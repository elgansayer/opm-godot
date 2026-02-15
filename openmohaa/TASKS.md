
## Phase 136: Weapon Effects (Muzzle Flash & Shell Casings) ✅
Implemented muzzle flash and shell casing ejection visual effects triggered by weapon firing events.

- [x] **Task 136.1:** Build Configuration: Added `HAS_WEAPON_EFFECTS_MODULE`, `HAS_VFX_MODULE` to `SConstruct` (and others for parity).
- [x] **Task 136.2:** Created `godot_weapon_effects.cpp/.h` with `Godot_MuzzleFlash_Spawn`, `Godot_ShellCasing_Eject`, `Init`, `Update`, `Cleanup`.
- [x] **Task 136.3:** Added `extern "C"` wrappers for engine interoperability.
- [x] **Task 136.4:** Exposed hooks via `refexport_t` in `tr_public.h` and `godot_renderer.c`.
- [x] **Task 136.5:** Exposed hooks via `clientGameImport_t` in `cg_public.h` and `cl_cgame.cpp`.
- [x] **Task 136.6:** Hooked `VM_ANIM_FIRE` and `VM_ANIM_FIRE_SECONDARY` in `cg_viewmodelanim.c` to trigger effects.
- [x] **Task 136.7:** Integrated into `MoHAARunner.cpp` lifecycle.

### Key technical details (Phase 136):
- Muzzle flash spawned at view origin + offset (20 forward, 4 right, -2 down).
- Shell casing ejected with velocity (120 right, 60 up) relative to view axis.
- Shell type determined by weapon class (Rifle/MG/Heavy = Type 1, Pistol/SMG = Type 0).
- Effects system manages its own sprite/mesh pools and updates via `_process(delta)`.

### Files modified (Phase 136):
- `openmohaa/SConstruct`
- `openmohaa/code/godot/MoHAARunner.cpp`
- `openmohaa/code/godot/godot_weapon_effects.cpp/.h`
- `openmohaa/code/renderercommon/tr_public.h`
- `openmohaa/code/godot/godot_renderer.c`
- `openmohaa/code/cgame/cg_public.h`
- `openmohaa/code/client/cl_cgame.cpp`
- `openmohaa/code/cgame/cg_viewmodelanim.c`
