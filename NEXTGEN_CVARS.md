# Next-Gen Rendering CVars (OpenMOHAA Godot Port)

All defaults are set to maximum quality (ultra). Use profiles or individual cvars to lower settings.

## Quick profiles

- `set r_ng_profile -1` = custom/manual mode (no preset auto-apply)
- `set r_ng_profile 0` = stock OpenMOHAA look
- `set r_ng_profile 1` = stable next-gen
- `set r_ng_profile 2` = ultra next-gen (maximum depth and effects)

## PBR and material depth

- `r_ng_pbr` (0/1, default 1) — Enables PBR material enhancement.
- `r_ng_pbr_proc_normals` (0/1, default 1) — Procedural normal map fallback.
- `r_ng_pbr_wet` (0/1, default 1) — Wet-surface heuristics.
- `r_ng_material_depth` (0/1, default 1) — Extra depth shaping for materials.
- `r_ng_material_overdrive` (0/1, default 0) — Aggressive overdrive depth mode.
- `r_ng_material_normal_scale` (float, default 1.35) — Normal strength multiplier. Range: 0.8–3.0.
- `r_ng_material_roughness_mul` (float, default 1.0) — Global roughness multiplier.
- `r_ng_material_specular_mul` (float, default 1.0) — Global specular multiplier.
- `r_ng_material_metallic_mul` (float, default 1.0) — Global metallic multiplier.

## Dynamic lights and shadows

- `r_ng_dynlights` (0/1, default 1) — Dynamic light node updates.
- `r_ng_dynlight_shadows` (0/1, default 1) — Dynamic-light shadow casting.
- `r_ng_dlight_shadow_max` (int, default 1) — Max shadow-casting dynamic lights. Range: 0–8.
- `r_ng_shadow_blobs` (0/1, default 1) — Projected blob shadows from RF_SHADOW entities.
- `r_ng_sunlight` (0/1, default 1) — Directional sunlight energy.
- `r_ng_sun_shadows` (0/1, default 1) — Directional sunlight shadows.
- `r_ng_sun_energy` (float, default 0.15) — Sun light energy multiplier.

## Tone, ambient, and post processing

- `r_ng_tonemap_exposure` (float, default 1.0) — Filmic tonemap exposure.
- `r_ng_tonemap_white` (float, default 4.0) — Filmic tonemap white point.
- `r_ng_ambient_energy` (float, default 0.85) — Ambient light energy.
- `r_ng_ssao` (0/1, default 1) — Screen-space ambient occlusion.
- `r_ng_glow` (0/1, default 1) — Bloom/glow.
- `r_ng_volfog` (0/1, default 1) — Volumetric fog.
- `r_ng_volfog_reprojection` (0/1, default 1) — Volumetric fog temporal reprojection.
- `r_ng_volfog_reprojection_amount` (float, default 0.90) — Reprojection amount. Range: 0.70–0.98.
- `r_ng_fog` (0/1, default 1) — Distance/depth fog.
- `r_ng_colorgrade` (0/1, default 1) — Colour adjustment pipeline.
- `r_ng_lut` (0/1, default 0) — LUT-based colour correction.

## Reflection probe controls

- `r_ng_refprobe` (0/1, default 0) — Local reflection probe.
- `r_ng_refprobe_update` (0/1, default 0) — Probe update mode: 0=once, 1=always.

## Model visual enhancements

- `r_ng_rim_light` (0/1, default 1) — Fresnel rim lighting on lit surfaces.
- `r_ng_rim_light_amount` (float, default 0.35) — Rim light intensity. Range: 0.1–0.8.

## Removed cvars (no longer functional)

- `r_ng_master` — was a master switch; all features are now always active
- `r_ng_antiflicker` — was a guardrail for SSIL/SSR; no longer needed
- `r_ng_allow_risky` — was an override for the guardrail; no longer needed
- `r_ng_ssil` — removed (Godot 4.x temporal accumulation causes green flash)
- `r_ng_ssr` — removed (Godot 4.x temporal accumulation causes green flash)

## Recommended command blocks

### Stock look
```cfg
set r_ng_profile 0
```

### Stable next-gen
```cfg
set r_ng_profile 1
```

### Ultra next-gen
```cfg
set r_ng_profile 2
```

### Manual custom example
```cfg
set r_ng_profile -1
set r_ng_material_depth 1
set r_ng_material_overdrive 1
set r_ng_material_normal_scale 2.2
set r_ng_material_specular_mul 1.4
set r_ng_material_roughness_mul 0.75
set r_ng_ssao 1
set r_ng_refprobe 0
```
