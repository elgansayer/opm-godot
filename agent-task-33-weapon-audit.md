# Agent Task 33: Weapon Mechanics Audit

## Objective
Audit weapon fire/reload/switch/drop/pickup mechanics to verify they work correctly under the Godot GDExtension build. Check spread, recoil, falloff, melee, and weapon script execution.

## Scope
CODE AUDIT — read and verify. Fix only `#ifdef GODOT_GDEXTENSION` compile issues.

## Files to Audit
- `code/fgame/weapon.h` / `code/fgame/weapon.cpp` — Base weapon class
- `code/fgame/weapturret.cpp` — Turret weapons
- `code/fgame/weaputils.cpp` — Weapon utility functions
- `code/fgame/player.cpp` — Player weapon handling
- `code/fgame/g_items.cpp` — Item pickup
- `code/script/` — Script commands that affect weapons

## Files to Create (EXCLUSIVE — only if accessor needed)
- `code/godot/godot_game_weapons.h` — Weapon state accessors (if needed)

## Audit Checklist

### 1. Fire mechanics
- [ ] `Weapon::Fire()` traces/projectile spawning
- [ ] Hitscan: `G_Trace()` from muzzle along aim direction
- [ ] Projectile: `G_LaunchProjectile()` — entity spawned with velocity
- [ ] Spread: per-weapon spread values from TIKI weapon files
- [ ] Recoil: view punch after firing

### 2. Reload
- [ ] `Weapon::ReloadWeapon()` — animation + ammo transfer
- [ ] Reload cancel (switching weapons during reload)
- [ ] Auto-reload when empty

### 3. Weapon switching
- [ ] `Player::useWeapon()` — weapon switch logic
- [ ] Weapon holster/draw animation times
- [ ] Number keys + mouse wheel selection

### 4. Melee
- [ ] Melee attack: short-range trace
- [ ] Melee damage calculation
- [ ] Bayonet/butt-stroke variants

### 5. Weapon scripts
- [ ] `.tik` weapon files load correctly (TIKI parser)
- [ ] Weapon-specific script events fire correctly
- [ ] Ammo types and limits from script definitions

### 6. Known issues to check
- [ ] `gi.Malloc` / `gi.Free` used in weapon code → may need safe wrappers during shutdown
- [ ] `G_Trace` function pointer valid in Godot build
- [ ] Weapon entity classnames registered in class system

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 87: Weapon Mechanics Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any code/godot/ files owned by other agents
