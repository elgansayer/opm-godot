# Agent Task 43: Inventory & Item Pickup Audit

## Objective
Audit the inventory and item system: health/ammo/grenade pickups, item entities, inventory limits, stacking, and entity touch triggers.

## Files to Audit
- `code/fgame/g_items.cpp` — Item registration and pickup logic
- `code/fgame/inventoryitem.cpp` — InventoryItem class
- `code/fgame/health.cpp` — Health pickup entities
- `code/fgame/ammo.cpp` — Ammo pickup entities
- `code/fgame/equipment.cpp` — Equipment items
- `code/fgame/player.cpp` — Player inventory methods

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_items.h` — Item state accessor (if needed)

## Audit Checklist

### 1. Item entity classes
- [ ] All item classes registered in spawn table
- [ ] CLASS_DECLARATION macros present for each item type
- [ ] Constructor sets model, bounds, pickup type

### 2. Pickup logic
- [ ] Touch trigger: player walks over item → `ItemPickup()` called
- [ ] Pickup conditions: not full, correct team, alive
- [ ] Pickup sound played
- [ ] Item removed or set to respawn timer (MP)
- [ ] Pickup notification (HUD message)

### 3. Inventory limits
- [ ] Health: max 100 (or 200 with super health)
- [ ] Ammo: per-weapon limits from weapon TIKI definitions
- [ ] Grenade limits
- [ ] Equipment slots

### 4. Item respawn (MP)
- [ ] `g_itemrespawntime` cvar
- [ ] Item becomes invisible during respawn wait
- [ ] Item re-appears with spawn effect

### 5. Weapon pickups
- [ ] Player receives weapon + initial ammo
- [ ] Duplicate weapon pickup → only adds ammo
- [ ] Weapon slot management

### 6. #ifdef checks
- [ ] `gi.Malloc`/`gi.Free` in item code — safe for Godot?
- [ ] Item entity think functions scheduled correctly

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 99: Inventory & Items Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
