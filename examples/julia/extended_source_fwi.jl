module ExtendedSourceFWI

export ESFWIRunConfig,
       safe_judi_options,
       rho_from_slowness,
       ormsby_wavelet,
       l2_misfit,
       scalar_matching_weight,
       wiener1d_matching_filter,
       apply_wiener1d_matching_filter,
       gabor2d_matching_filter,
       apply_gabor2d_matching_filter,
       fwi_objective_es_article

using FFTW
using LinearAlgebra
using Statistics

"""
    ESFWIRunConfig(; kwargs...)

Runtime switches for the article-style extended-source FWI workflow.

The important default is `ic="as"`. In JUDI, `IC="fwi"` selects a special
imaging-condition branch and can make Devito receive an unexpected runtime
symbol such as `v=v(time, x, y)`. ES-FWI itself is enabled by passing
`extended_source=true` to `fwi_objective`, not by setting `IC="fwi"`.
"""
Base.@kwdef struct ESFWIRunConfig
    modeling_type::String = "slowness"
    free_surface::Bool = false
    limit_m::Bool = true
    buffer_size::Float32 = 1000f0
    nb::Int = 40
    space_order::Int = 16
    ic::String = "as"
    hessian_mode::String = "scalar"
    mu::Float32 = 1f-3
    filter_eps::Float32 = 1f-3
    use_custom_misfit::Bool = false
end

rho_from_slowness(m) = 0.23f0 .* (sqrt.(1f0 ./ m) .* 1000f0) .^ 0.25f0

"""
    safe_judi_options(JUDI, cfg::ESFWIRunConfig)

Create a `JUDI.Options` object with the ES-FWI-safe imaging condition.
"""
function safe_judi_options(JUDI, cfg::ESFWIRunConfig)
    cfg.ic == "fwi" && error("Use IC=\"as\" for ES-FWI. `extended_source=true` enables ES-FWI; IC=\"fwi\" selects a different JUDI imaging-condition branch.")
    return JUDI.Options(IC=cfg.ic,
                        limit_m=cfg.limit_m,
                        buffer_size=cfg.buffer_size,
                        optimal_checkpointing=false,
                        free_surface=cfg.free_surface,
                        space_order=cfg.space_order)
end

"""
    ormsby_wavelet(; dt, t, f1, f2, f3, f4)

Build a zero-phase Ormsby wavelet. `dt` and `t` are in seconds; frequencies
are in Hz. This intentionally does not depend on JUDI so it can be tested
locally.
"""
function ormsby_wavelet(; dt, t, f1, f2, f3, f4)
    nt = Int(round(t / dt)) + 1
    nf = div(nt, 2) + 1
    freqs = Float32.((0:nf-1) ./ (nt * dt))
    amp = zeros(Float32, nf)
    for (i, f) in pairs(freqs)
        amp[i] = f < f1 ? 0f0 :
                 f < f2 ? Float32((f - f1) / max(f2 - f1, eps(Float32))) :
                 f <= f3 ? 1f0 :
                 f < f4 ? Float32((f4 - f) / max(f4 - f3, eps(Float32))) : 0f0
    end
    w = real(irfft(ComplexF32.(amp), nt))
    return Float32.(circshift(w, div(nt, 2)))
end

"""
    l2_misfit(dsyn, dobs)

Plain least-squares residual objective and gradient. This is the residual
assumed by the derivation of equations 11--16 in Guo et al. (2024): the source
extension is estimated from `δd = d_obs - S(m)b` before weighting by the inverse
data-domain Hessian approximation.
"""
function l2_misfit(dsyn, dobs)
    r = dsyn - dobs
    return 0.5f0 * sum(abs2, r), r
end

"""
    scalar_matching_weight(dblur, dobs_residual; eps_scale=1f-12)

Scalar-fitting approximation to `H_d^{-1}` from equation 29. `dblur` is
`H_d δd` and `dobs_residual` is `δd`. Returns `γ` such that `γ*dblur` best fits
`δd` in least-squares sense.
"""
function scalar_matching_weight(dblur::AbstractArray, dobs_residual::AbstractArray; eps_scale=1f-12)
    den = real(dot(vec(dblur), vec(dblur)))
    den <= eps_scale && return 0f0
    return real(dot(vec(dblur), vec(dobs_residual))) / den
end

"""
    wiener1d_matching_filter(dblur, dobs_residual; eps_fraction=0.002f0)

Trace-by-trace stationary Wiener matching filter from equations 30--31.
Input arrays are `(nt, nr)`. The returned complex spectrum can be applied to a
residual gather with `apply_wiener1d_matching_filter` to approximate
`δd_d = H_d^{-1} δd`.
"""
function wiener1d_matching_filter(dblur::AbstractMatrix, dobs_residual::AbstractMatrix; eps_fraction=0.002f0)
    size(dblur) == size(dobs_residual) || throw(DimensionMismatch("dblur and dobs_residual must have the same size"))
    nt, nr = size(dblur)
    filt = Matrix{ComplexF32}(undef, nt, nr)
    for ir in 1:nr
        b = fft(Float32.(dblur[:, ir]))
        d = fft(Float32.(dobs_residual[:, ir]))
        denom = abs2.(b)
        epsv = Float32(eps_fraction) * max(maximum(denom), eps(Float32))
        filt[:, ir] .= d .* conj.(b) ./ (denom .+ epsv)
    end
    return filt
end

function apply_wiener1d_matching_filter(filt::AbstractMatrix, residual::AbstractMatrix)
    size(filt) == size(residual) || throw(DimensionMismatch("filter and residual must have the same size"))
    nt, nr = size(residual)
    out = Matrix{Float32}(undef, nt, nr)
    for ir in 1:nr
        out[:, ir] .= real.(ifft(filt[:, ir] .* fft(Float32.(residual[:, ir]))))
    end
    return out
end

function _gaussian_window(n::Int, center::Int, sigma::Real)
    sigma <= 0 && throw(ArgumentError("sigma must be positive"))
    x = collect(1:n)
    w = exp.(-0.5f0 .* ((Float32.(x .- center) ./ Float32(sigma)).^2))
    s = sqrt(sum(abs2, w))
    return Float32.(w ./ max(s, eps(Float32)))
end

"""
    gabor2d_matching_filter(dblur, dobs_residual; sigma_t, sigma_r, step_t, step_r, eps_fraction=0.002f0)

Nonstationary 2D Gabor matching-filter approximation to `H_d^{-1}` inspired by
equations 34--35 and Appendix B. Arrays are `(nt, nr)`. The return value is a
NamedTuple containing window centers and local f-k filters. Apply it with
`apply_gabor2d_matching_filter`.

This implementation is intentionally conservative and pure Julia: it uses an
overlap-add inverse over Gaussian time/receiver windows, making it suitable for
precomputing weighted data residuals outside the Devito operator.
"""
function gabor2d_matching_filter(dblur::AbstractMatrix, dobs_residual::AbstractMatrix;
                                 sigma_t::Real,
                                 sigma_r::Real,
                                 step_t::Integer=max(1, round(Int, sigma_t)),
                                 step_r::Integer=max(1, round(Int, sigma_r)),
                                 eps_fraction=0.002f0)
    size(dblur) == size(dobs_residual) || throw(DimensionMismatch("dblur and dobs_residual must have the same size"))
    nt, nr = size(dblur)
    centers_t = collect(1:step_t:nt)
    centers_t[end] == nt || push!(centers_t, nt)
    centers_r = collect(1:step_r:nr)
    centers_r[end] == nr || push!(centers_r, nr)
    filters = Array{ComplexF32, 4}(undef, nt, nr, length(centers_t), length(centers_r))
    for (it, ct) in pairs(centers_t), (ir, cr) in pairs(centers_r)
        wt = _gaussian_window(nt, ct, sigma_t)
        wr = _gaussian_window(nr, cr, sigma_r)
        win = wt * transpose(wr)
        b = fft(Float32.(dblur) .* win)
        d = fft(Float32.(dobs_residual) .* win)
        denom = abs2.(b)
        epsv = Float32(eps_fraction) * max(maximum(denom), eps(Float32))
        filters[:, :, it, ir] .= d .* conj.(b) ./ (denom .+ epsv)
    end
    return (filters=filters, centers_t=centers_t, centers_r=centers_r,
            sigma_t=Float32(sigma_t), sigma_r=Float32(sigma_r), nt=nt, nr=nr)
end

function apply_gabor2d_matching_filter(gabor_filter, residual::AbstractMatrix)
    nt, nr = size(residual)
    gabor_filter.nt == nt && gabor_filter.nr == nr || throw(DimensionMismatch("filter and residual must have the same size"))
    out = zeros(Float32, nt, nr)
    normw = zeros(Float32, nt, nr)
    for (it, ct) in pairs(gabor_filter.centers_t), (ir, cr) in pairs(gabor_filter.centers_r)
        wt = _gaussian_window(nt, ct, gabor_filter.sigma_t)
        wr = _gaussian_window(nr, cr, gabor_filter.sigma_r)
        win = wt * transpose(wr)
        local = real.(ifft(gabor_filter.filters[:, :, it, ir] .* fft(Float32.(residual) .* win)))
        out .+= Float32.(local) .* win
        normw .+= win .^ 2
    end
    return out ./ max.(normw, eps(Float32))
end

"""
    fwi_objective_es_article(JUDI, model, q, dobs; cfg, options, es_options, kwargs...)

Thin, safe wrapper around JUDI's ES-FWI entry point. It enforces the article's
least-squares residual by default and enables ES-FWI through
`extended_source=true`. Pass `cfg.use_custom_misfit=true` and `misfit=...` only
after the L2 workflow is verified.
"""
function fwi_objective_es_article(JUDI, model, q, dobs; cfg::ESFWIRunConfig,
                                  options=safe_judi_options(JUDI, cfg),
                                  es_options=nothing,
                                  data_precon=nothing,
                                  misfit=nothing)
    cfg.ic == "fwi" && error("Refusing IC=\"fwi\": use IC=\"as\" for article-style ES-FWI.")
    kw = Dict{Symbol, Any}(:options => options,
                           :extended_source => true)
    data_precon !== nothing && (kw[:data_precon] = data_precon)
    es_options !== nothing && (kw[:es_options] = es_options)
    if cfg.use_custom_misfit
        misfit === nothing && error("cfg.use_custom_misfit=true requires a `misfit` function")
        kw[:misfit] = misfit
    end
    return JUDI.fwi_objective(model, q, dobs; kw...)
end

end # module
