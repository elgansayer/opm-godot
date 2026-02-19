# Next-Gen Rendering CVars (OpenMOHAA Godot Port)

This document lists all next-gen rendering CVars, what they do, and recommended values.

## Quick profiles

- `set r_ng_profile -1` = custom/manual mode (no preset auto-apply)
- `set r_ng_profile 0` = stock OpenMOHAA look
- `set r_ng_profile 1` = stable next-gen (anti-flicker safe)
- `set r_ng_profile 2` = ultra next-gen (maximum depth and effects)

## Master mode and stability

- `r_ng_master` (0/1, default 1)
  - Master switch for next-gen pipeline.
  - `0` forces stock-like rendering path.

- `r_ng_antiflicker` (0/1, default 1)
  - Enables anti-flicker guardrails.
  - When enabled, unstable passes are constrained unless explicitly allowed.

- `r_ng_allow_risky` (0/1, default 0)
  - Allows risky cinematic passes (SSR/SSIL/LUT/reflection probe dynamic updates) while anti-flicker is enabled.
  - Set to `1` only if you accept possible visual instability.

## PBR and material depth

- `r_ng_pbr` (0/1, default 1)
  - Enables/disables PBR material enhancement.

- `r_ng_pbr_proc_normals` (0/1, default 1)
  - Enables fallback procedural normal map generation when no authored normal exists.

- `r_ng_pbr_wet` (0/1, default 1)
  - Enables wet-surface heuristics (stronger specular/lower roughness on wet-like materials).

- `r_ng_material_depth` (0/1, default 1)
  - Enables extra depth shaping for materials (normal/spec/roughness tuning).

- `r_ng_material_overdrive` (0/1, default 0)
  - Aggressive “overdrive” material depth mode.
  - Pushes stronger normal relief and shinier micro highlights.

- `r_ng_material_normal_scale` (float, default 1.35)
  - Base normal strength multiplier before overdrive.
  - Useful range: `0.8`–`3.0`.

- `r_ng_material_roughness_mul` (float, default 1.0)
  - Multiplies roughness globally.
  - Lower values = glossier surface response.

- `r_ng_material_specular_mul` (float, default 1.0)
  - Multiplies specular globally.

- `r_ng_material_metallic_mul` (float, default 1.0)
  - Multiplies metallic contribution on metallic-marked surfaces.

## Dynamic lights and shadows

- `r_ng_dynlights` (0/1, default 1)
  - Enables dynamic light node updates.

- `r_ng_dynlight_shadows` (0/1, default 1)
  - Enables dynamic-light shadow casting for hero lights.

- `r_ng_dlight_shadow_max` (int, default 1)
  - Max number of dynamic lights allowed to cast shadows at once.
  - Lower values reduce flicker and cost.

- `r_ng_shadow_blobs` (0/1, default 1)
  - Enables projected blob shadows from RF_SHADOW entities.

- `r_ng_sunlight` (0/1, default 1)
  - Enables directional sunlight energy.

- `r_ng_sun_shadows` (0/1, default 1)
  - Enables directional sunlight shadows.

- `r_ng_sun_energy` (float, default 0.8)
  - Sun light energy multiplier.

## Tone, ambient, and post processing

- `r_ng_tonemap_exposure` (float, default 1.0)
  - Filmic tonemap exposure.

- `r_ng_tonemap_white` (float, default 4.0)
  - Filmic tonemap white point.

- `r_ng_ambient_energy` (float, default 0.55)
  - Ambient light energy.

- `r_ng_ssao` (0/1, default 1)
  - Screen-space ambient occlusion.

- `r_ng_ssil` (0/1, default 0)
  - Screen-space indirect lighting.

- `r_ng_ssr` (0/1, default 0)
  - Screen-space reflections.

- `r_ng_glow` (0/1, default 1)
  - Bloom/glow.

- `r_ng_volfog` (0/1, default 1)
  - Volumetric fog.

- `r_ng_volfog_reprojection` (0/1, default 1)
  - Volumetric fog temporal reprojection toggle.

- `r_ng_volfog_reprojection_amount` (float, default 0.90)
  - Volumetric fog reprojection accumulation amount.
  - Useful range: `0.70`–`0.98`.

- `r_ng_fog` (0/1, default 1)
  - Distance/depth fog.

- `r_ng_colorgrade` (0/1, default 1)
  - Color adjustment pipeline toggle.

- `r_ng_lut` (0/1, default 0)
  - LUT-based colour correction.

## Reflection probe controls

- `r_ng_refprobe` (0/1, default 0)
  - Enables local reflection probe.

- `r_ng_refprobe_update` (0/1, default 0)
  - Reflection probe update mode.
  - `0` = update once (stable)
  - `1` = update always (higher dynamism, higher flicker risk)

## Model visual enhancements

- `r_ng_rim_light` (0/1, default 1)
  - Fresnel rim lighting on lit surfaces.
  - Adds edge highlighting that makes low-poly model silhouettes pop.

- `r_ng_rim_light_amount` (float, default 0.35)
  - Rim light intensity. Higher = stronger edge glow.
  - Useful range: `0.1`–`0.8`.
  - Profile 1 (stable): `0.35`, Profile 2 (ultra): `0.5`.

## Recommended command blocks

### Stock OpenMOHAA look

```cfg
set r_ng_profile 0
```

### Stable next-gen (recommended)

```cfg
set r_ng_profile 1
```

### Ultra next-gen (maximum depth/effects)

```cfg
set r_ng_profile 2
```

### Manual custom mode example

```cfg
set r_ng_profile -1
set r_ng_master 1
set r_ng_antiflicker 1
set r_ng_allow_risky 0
set r_ng_material_depth 1
set r_ng_material_overdrive 1
set r_ng_material_normal_scale 2.2
set r_ng_material_specular_mul 1.4
set r_ng_material_roughness_mul 0.75
set r_ng_ssao 1
set r_ng_ssil 0
set r_ng_ssr 0
set r_ng_refprobe 0
```
