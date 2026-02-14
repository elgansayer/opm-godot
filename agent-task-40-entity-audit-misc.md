# Agent Task 40: Entity Audit — info/light/misc/weapon/worldspawn

## Objective
Audit info_*, light_*, misc_*, weapon_*, and worldspawn entities. These are spawn points, ambient models, weapons on the ground, and global map settings.

## Files to Audit
- `code/fgame/g_spawn.cpp` — Master spawn table
- `code/fgame/misc.cpp` — misc_model, misc_gamemodel, misc_particle_effects
- `code/fgame/worldspawn.cpp` — worldspawn entity (gravity, ambient, etc.)
- `code/fgame/g_items.cpp` — Weapon/ammo/health pickups
- `code/fgame/player.cpp` — Player spawn at info_player_start

## Files to Create (EXCLUSIVE)
- `code/godot/godot_entity_audit.md` — Audit results documentation

## Entity Types to Verify

### info_* entities
- [ ] `info_player_start` — SP spawn point
- [ ] `info_player_deathmatch` — FFA DM spawn
- [ ] `info_player_allied` / `info_player_axis` — Team spawn points
- [ ] `info_player_intermission` — Camera position at end of match
- [ ] `info_teleport_destination` — Teleport target
- [ ] `info_null` / `info_notnull` — Target reference points

### light_* entities
- [ ] `light` — Point light (only used for lightmap compilation, no runtime)
- [ ] Verify lights don't spawn runtime entities (just lightmap data)

### misc_* entities
- [ ] `misc_model` — Static decorative model (not collideable)
- [ ] `misc_gamemodel` — Game model (can have animations, collision)
- [ ] `misc_particle_effects` — Particle emitter placement
- [ ] `misc_origin` — Reference origin point
- [ ] `misc_portal_surface` — Portal camera
- [ ] `misc_portal_camera` — Portal viewpoint

### weapon_* entities
- [ ] Weapon pickup entities (weapon_rifle, weapon_smg, etc.)
- [ ] Ammo pickups (ammo_rifle, ammo_smg, etc.)
- [ ] Health pickups (health_small, health_large)
- [ ] Item respawn timers (MP)
- [ ] Touch pickup logic

### worldspawn
- [ ] `worldspawn` entity — first entity in BSP, sets global keys
- [ ] `gravity` key → `sv_gravity` cvar
- [ ] `ambient` key → ambient light level
- [ ] `music` key → background music track
- [ ] `message` key → map name display
- [ ] `_color` / `ambient` / `gridsize` → lightgrid parameters

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 103-106: Entity Audit (info/light/misc/weapon/worldspawn) ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
