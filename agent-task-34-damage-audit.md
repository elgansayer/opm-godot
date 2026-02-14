# Agent Task 34: Hit Detection & Damage System Audit

## Objective
Audit hit detection (hitscan traces, radius damage, location-based damage) and the damage pipeline to verify correctness under the Godot GDExtension build.

## Files to Audit
- `code/fgame/g_combat.cpp` — Damage pipeline, `G_Damage()`, `G_RadiusDamage()`
- `code/fgame/sentient.cpp` — Health, armour, death logic
- `code/fgame/player.cpp` — Player damage reception
- `code/fgame/weaputils.cpp` — Weapon trace functions
- `code/fgame/g_utils.cpp` — `G_Trace()`, trace utilities

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_damage.h` — Damage system accessor (if needed)

## Audit Checklist

### 1. Hitscan traces
- [ ] `G_Trace()` calls `gi.trace()` — verify function pointer is valid
- [ ] Trace results: entity hit, surface flags, contents
- [ ] Bullet traces: `G_FireBullet()` or equivalent

### 2. Radius damage
- [ ] `G_RadiusDamage()`: explosion AOE damage
- [ ] Distance falloff calculation
- [ ] Line-of-sight check (traces to each potential target)
- [ ] Self-damage from own explosions

### 3. Location-based damage
- [ ] `G_LocationDamage()`: MOHAA's hitzone system (head, torso, limbs)
- [ ] Damage multipliers per location
- [ ] Armour reduction per location

### 4. Damage types
- [ ] `MOD_*` (means of death) types all defined
- [ ] Per-MOD behaviour (bullet, explosion, melee, falling, drowning, etc.)
- [ ] `T_Damage()` / `G_Damage()` pipeline: attacker → victim → damage → death

### 5. Death handling
- [ ] Entity death: `Killed()` callback
- [ ] Player death: death animation, respawn timer, score update
- [ ] NPC death: ragdoll/animation, item drops
- [ ] Obituary (kill feed) notification

### 6. #ifdef checks
- [ ] Verify `gi.trace()` and `gi.pointcontents()` function pointers are set
- [ ] Check for any DEDICATED-only damage code that might be skipped

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 88: Hit Detection & Damage Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
