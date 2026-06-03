# Article-style time-domain extended-source FWI driver for JUDI.
#
# This script keeps the ES-FWI call close to Guo et al. (2024): first verify the
# least-squares extended-source workflow, then enable optional envelope/custom
# misfits only after the L2 workflow is stable.
#
# Key fixes compared with the failing script:
#   * IC="as" is used. ES-FWI is enabled by `extended_source=true`, not by
#     `IC="fwi"`.
#   * the default modeling type is constant-density slowness, matching the
#     equations in the article more closely than variable-density bulk mode.
#   * custom envelope misfit is disabled by default because equations 11--16
#     estimate the source extension from the L2 data residual.

using Distributed

const SCRIPT_DIR = @__DIR__
const DIR_LOGS = joinpath(SCRIPT_DIR, "logs")
mkpath(DIR_LOGS)
cd(DIR_LOGS)

include(joinpath(SCRIPT_DIR, "extended_source_fwi.jl"))
using .ExtendedSourceFWI

# ----------------------------- Parallel setup -----------------------------
const LOCAL_WORKERS = parse(Int, get(ENV, "JUDI_LOCAL_WORKERS", "1"))
if LOCAL_WORKERS > 0 && nworkers() < LOCAL_WORKERS
    addprocs(LOCAL_WORKERS - nworkers() + 1)
end

@sync for p in workers()
    @async remotecall_fetch(() -> myid(), p)
end
println("All workers alive")

@everywhere begin
    const N_GPU = parse(Int, get(ENV, "JUDI_NGPU", "1"))
    ENV["CUDA_VISIBLE_DEVICES"] = string((myid() - 1) % N_GPU)
    println("Process ID: ", myid(), "\tCUDA_VISIBLE_DEVICES: ", ENV["CUDA_VISIBLE_DEVICES"])
end

@everywhere using Statistics, Random, LinearAlgebra, Interpolations, DelimitedFiles
@everywhere using JUDI, SlimOptim, HDF5, SegyIO, Plots, ImageFiltering, Zygote
@everywhere using JUDI.FFTW

@everywhere include(joinpath($SCRIPT_DIR, "extended_source_fwi.jl"))
@everywhere using .ExtendedSourceFWI

# ----------------------------- User settings ------------------------------
const CFG = ESFWIRunConfig(modeling_type=get(ENV, "JUDI_MODELING_TYPE", "slowness"),
                           free_surface=parse(Bool, get(ENV, "JUDI_FREE_SURFACE", "false")),
                           limit_m=true,
                           buffer_size=parse(Float32, get(ENV, "JUDI_BUFFER_SIZE", "1000")),
                           nb=parse(Int, get(ENV, "JUDI_NB", "40")),
                           space_order=parse(Int, get(ENV, "JUDI_SPACE_ORDER", "16")),
                           ic="as",
                           hessian_mode=get(ENV, "JUDI_ES_HESSIAN", "scalar"),
                           mu=parse(Float32, get(ENV, "JUDI_ES_MU", "1e-3")),
                           filter_eps=parse(Float32, get(ENV, "JUDI_ES_FILTER_EPS", "1e-3")),
                           use_custom_misfit=parse(Bool, get(ENV, "JUDI_USE_CUSTOM_MISFIT", "false")))

const SIGNAL_TYPE = get(ENV, "JUDI_SIGNAL_TYPE", "ormsby")
const RICKER_FRQ = parse(Float32, get(ENV, "JUDI_RICKER_FRQ_KHZ", "0.008"))
const ORMSBY = (0.0f0, 0.002f0, 0.050f0, 0.075f0)  # kHz

const FRQ0 = parse(Float32, get(ENV, "JUDI_FRQ0_KHZ", "0.0"))
const FRQ1 = parse(Float32, get(ENV, "JUDI_FRQ1_KHZ", "0.005"))
const SEABED = parse(Float32, get(ENV, "JUDI_SEABED_KM", "0.01"))

const PRESTK_DIR = get(ENV, "JUDI_PRESTK_DIR", joinpath(SCRIPT_DIR, "..", "DATA", "shots_ormsby_0.0-0.002-0.05-0.075Hz_1000.0ms_UNDER_fs"))
const PRESTK_FILE = get(ENV, "JUDI_PRESTK_FILE", "shot")
const MODEL_FILE = get(ENV, "JUDI_MODEL_FILE", joinpath(SCRIPT_DIR, "..", "DATA", "model_il892_1m_smooth.h5"))
const DIR_OUT = get(ENV, "JUDI_DIR_OUT", joinpath(SCRIPT_DIR, "..", "DATA", "es_fwi_spg_$(CFG.modeling_type)", "$(FRQ0)Hz_$(FRQ1)Hz_nb$(CFG.nb)_$(CFG.hessian_mode)"))
const MODEL_FILE_OUT = "model"
mkpath(DIR_OUT)

const SEGY_DEPTH_KEY_SRC = get(ENV, "JUDI_SEGY_DEPTH_KEY_SRC", "SourceSurfaceElevation")
const SEGY_DEPTH_KEY_REC = get(ENV, "JUDI_SEGY_DEPTH_KEY_REC", "RecGroupElevation")

# ----------------------------- Local helpers ------------------------------
function save_data(x, z, data; pltfile, title, colormap=:viridis, clim=nothing,
                   h5file=nothing, h5openflag="w", h5varname="data")
    plt = heatmap(x, z, data; yflip=true, title=title, color=colormap, clim=clim)
    savefig(plt, pltfile * ".png")
    if h5file !== nothing
        h5open(h5file, h5openflag) do fid
            haskey(fid, h5varname) && delete_object(fid, h5varname)
            write(fid, h5varname, data)
        end
    end
end

function save_fhistory(fhistory; h5file, h5openflag="r+", h5varname="fhistory")
    h5open(h5file, h5openflag) do fid
        haskey(fid, h5varname) && delete_object(fid, h5varname)
        write(fid, h5varname, fhistory)
    end
end

# ------------------------------ Data/model --------------------------------
container = segy_scan(PRESTK_DIR, PRESTK_FILE,
                      ["SourceX", "SourceY", "GroupX", "GroupY",
                       "RecGroupElevation", "SourceSurfaceElevation", "dt"])
d_obs = judiVector(container; segy_depth_key=SEGY_DEPTH_KEY_REC)
src_geometry = Geometry(container; key="source", segy_depth_key=SEGY_DEPTH_KEY_SRC)

fid = h5open(MODEL_FILE, "r")
n = Tuple(Int64(i) for i in read(fid, "n"))
d = Tuple(Float32(i) for i in read(fid, "d"))
o = Tuple(Float32(i) for i in read(fid, "o"))
m0 = Float32.(read(fid, "m"))
close(fid)

const VMIN = parse(Float32, get(ENV, "JUDI_VMIN", "0.8"))
const VMAX = parse(Float32, get(ENV, "JUDI_VMAX", "7.0"))
const MMIN = (1f0 / VMAX)^2
const MMAX = (1f0 / VMIN)^2
m0 .= clamp.(m0, MMIN, MMAX)

const DENSE_FACTOR = parse(Float32, get(ENV, "JUDI_DENSE_FACTOR", "1.0"))
if DENSE_FACTOR != 1f0
    i_dense = 1f0:1f0/DENSE_FACTOR:size(m0, 1)
    j_dense = 1f0:1f0/DENSE_FACTOR:size(m0, 2)
    global m0 = interpolate(m0, BSpline(Linear()))(i_dense, j_dense)
    global n = size(m0)
    global d = Tuple(Float32(di / DENSE_FACTOR) for di in d)
end

if CFG.modeling_type == "slowness"
    model0 = Model(n, d, o, m0, nb=CFG.nb)
elseif CFG.modeling_type == "bulk"
    rho0 = rho_from_slowness(m0)
    model0 = Model(n, d, o, m0, rho=rho0, nb=CFG.nb)
else
    error("Unknown JUDI_MODELING_TYPE=$(CFG.modeling_type). Use slowness or bulk.")
end

x = collect((o[1]:d[1]:o[1] + (n[1]-1)*d[1]) ./ 1000f0)
z = collect((o[2]:d[2]:o[2] + (n[2]-1)*d[2]) ./ 1000f0)
seabed_ind = [findfirst(zz -> zz > SEABED, z) for _ in eachindex(x)]

@info "modeling_type=$(CFG.modeling_type), n=$(n), d=$(d), o=$(o)"
@info "article_es_fwi=true, cfg=$(CFG)"

# ------------------------------ Wavelet -----------------------------------
function build_wavelet(src_geometry)
    nt = src_geometry.nt[1]
    if SIGNAL_TYPE == "ricker"
        return ricker_wavelet(src_geometry.t[1], src_geometry.dt[1], RICKER_FRQ)
    elseif SIGNAL_TYPE == "ormsby"
        w = Matrix{Float32}(undef, nt, 1)
        f1, f2, f3, f4 = ORMSBY
        w[:, 1] = ormsby_wavelet(dt=src_geometry.dt[1]/1000f0,
                                  t=src_geometry.t[1]/1000f0,
                                  f1=f1*1000f0, f2=f2*1000f0,
                                  f3=f3*1000f0, f4=f4*1000f0)
        return w
    else
        error("Unknown JUDI_SIGNAL_TYPE=$(SIGNAL_TYPE). Use ormsby or ricker.")
    end
end

wavelet = build_wavelet(src_geometry)
fs = 1000f0 / src_geometry.dt[1]
responsetype = FRQ0 == 0 ? Lowpass(FRQ1*1000f0; fs=fs) :
               isinf(FRQ1) ? Highpass(FRQ0*1000f0; fs=fs) :
               Bandpass(FRQ0*1000f0, FRQ1*1000f0; fs=fs)
wavelet[:, 1] = filt(digitalfilter(responsetype, Butterworth(5)), wavelet[:, 1])
q = judiVector(src_geometry, wavelet)

# -------------------------- Preconditioners/options ------------------------
Ml_ref = judiDataMute(q.geometry, d_obs.geometry, vp=8000, t0=0.3f0,
                      mode=:reflection, taperwidth=20)
Ml_tur = judiDataMute(q.geometry, d_obs.geometry, vp=500, t0=-0.1f0,
                      mode=:turning, taperwidth=20)
Ml_freq = judiFilter(d_obs.geometry, FRQ0*1000f0, FRQ1*1000f0)

mminArr = fill(MMIN, size(model0))
mmaxArr = fill(MMAX, size(model0))
model0.m .= clamp.(model0.m, mminArr, mmaxArr)

jopt = safe_judi_options(JUDI, CFG)
es_options = ESFWIOptions(; mu=CFG.mu,
                           hessian_mode=CFG.hessian_mode,
                           filter_eps=CFG.filter_eps)

Dm = judiDepthScaling(model0)
Il = inv(judiIllumination(model0))

# -------------------- Optional non-L2 misfit, off by default ---------------
@everywhere n2(x) = x / norm(x, 2)
@everywhere function Hilbert(x)
    n = size(x, 1)
    σ = sign.(-n/2+1:n/2)
    return imag(ifft(fftshift(σ .* fftshift(fft(x, 1), 1), 1), 1))
end
@everywhere HLoss(dsyn, dobs) = sum(abs2.((dsyn - dobs) .+ 1im .* Hilbert(dsyn - dobs)))
@everywhere function envelope(dsyn, dobs)
    ϕ = HLoss(n2(dsyn), n2(dobs))
    g = Zygote.gradient(xs -> HLoss(n2(xs), n2(dobs)), dsyn)
    return ϕ, real.(g[1])
end

# ----------------------------- Optimization --------------------------------
const NITERATIONS = parse(Int, get(ENV, "JUDI_NITERATIONS", "30"))
const SHOT_FROM = parse(Int, get(ENV, "JUDI_SHOT_FROM", "1"))
const SHOT_STEP = parse(Int, get(ENV, "JUDI_SHOT_STEP", "4"))
const SHOT_TO = parse(Int, get(ENV, "JUDI_SHOT_TO", string(d_obs.nsrc)))
const MUTE_REFLECTIONS = parse(Bool, get(ENV, "JUDI_MUTE_REFLECTIONS", "false"))
const MUTE_TURNING = parse(Bool, get(ENV, "JUDI_MUTE_TURNING", "false"))

count = Ref(0)
fhistory = Float32[]

function objective_function(m_update_vec)
    count[] += 1
    m_update = reshape(m_update_vec, size(model0))
    m_update .= clamp.(m_update, mminArr, mmaxArr)

    model0.m .= Float32.(m_update)
    if CFG.modeling_type == "bulk"
        model0.rho .= Float32.(reshape(rho_from_slowness(model0.m), size(model0)))
    end

    indsrc = SHOT_FROM:SHOT_STEP:SHOT_TO
    data_precon = MUTE_REFLECTIONS ? Ml_tur[indsrc] * Ml_freq[indsrc] :
                  MUTE_TURNING ? Ml_ref[indsrc] * Ml_freq[indsrc] :
                  Ml_freq[indsrc]

    fval, gradient = fwi_objective_es_article(JUDI, model0, q[indsrc], d_obs[indsrc];
                                              cfg=CFG,
                                              options=jopt,
                                              es_options=es_options,
                                              data_precon=data_precon,
                                              misfit=CFG.use_custom_misfit ? envelope : nothing)

    gradient = reshape(Dm * Il * gradient, size(model0))
    push!(fhistory, Float32(fval[]))

    println("iteration: ", count[], "\tfval: ", fval[], "\tnorm: ", norm(gradient))

    h5path = joinpath(DIR_OUT, MODEL_FILE_OUT * " " * string(count[]) * ".h5")
    save_data(x, z, adjoint(reshape(model0.m.data, size(model0)));
              pltfile=joinpath(DIR_OUT, "ES-FWI slowness $(count[])") ,
              title="ES-FWI slowness^2 $(CFG.modeling_type): $(FRQ0*1000)-$(FRQ1*1000)Hz, iter $(count[])",
              colormap=cgrad(:Spectral, rev=true),
              h5file=h5path, h5openflag="w", h5varname="m")
    save_data(x, z, sqrt.(1f0 ./ adjoint(reshape(model0.m.data, size(model0))));
              pltfile=joinpath(DIR_OUT, "ES-FWI velocity $(count[])") ,
              title="ES-FWI velocity $(CFG.modeling_type): $(FRQ0*1000)-$(FRQ1*1000)Hz, iter $(count[])",
              colormap=cgrad(:Spectral, rev=true),
              h5file=h5path, h5openflag="r+", h5varname="v")
    save_data(x, z, adjoint(reshape(gradient.data, size(model0)));
              pltfile=joinpath(DIR_OUT, "ES-FWI gradient $(count[])") ,
              title="ES-FWI gradient $(CFG.modeling_type): $(FRQ0*1000)-$(FRQ1*1000)Hz, iter $(count[])",
              clim=(-maximum(abs, gradient.data)/5f0, maximum(abs, gradient.data)/5f0),
              colormap=:bluesreds,
              h5file=h5path, h5openflag="r+", h5varname="grad")
    save_fhistory(fhistory; h5file=h5path, h5openflag="r+", h5varname="fhistory")

    return fval[], gradient
end

proj(x) = reshape(median([vec(mminArr) vec(x) vec(mmaxArr)]; dims=2), size(model0))

@info "STARTED ARTICLE-STYLE ES-FWI COMPUTATIONS"
spgopt = spg_options(verbose=3,
                     maxIter=NITERATIONS,
                     memory=3,
                     suffDec=1f-3,
                     iniStep=1f0,
                     maxLinesearchIter=12,
                     useSpectral=true,
                     feasibleInit=true)
sol = spg(objective_function, model0.m.data, proj, spgopt)

for p in workers()
    rmprocs(p)
end
