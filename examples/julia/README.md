# Julia ES-FWI example

This directory contains an article-style extended-source FWI helper and SPG
driver for JUDI-based inversions.

The main operational fix is that ES-FWI is enabled with
`extended_source=true`; `IC="fwi"` is intentionally avoided because it selects a
JUDI imaging-condition branch that can pass an unexpected `v(time, x, y)`
runtime argument to Devito. Use `IC="as"` for this workflow.

Start with the default constant-density/L2 setup:

```bash
julia examples/julia/fwi_es_spg_article.jl
```

Then re-enable more complex options one at a time, for example:

```bash
JUDI_FREE_SURFACE=true julia examples/julia/fwi_es_spg_article.jl
JUDI_MODELING_TYPE=bulk julia examples/julia/fwi_es_spg_article.jl
JUDI_USE_CUSTOM_MISFIT=true julia examples/julia/fwi_es_spg_article.jl
```
