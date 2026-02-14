# Agent Task 38: Entity Audit — trigger_* Family

## Objective
Audit all `trigger_*` entity types to verify they compile, spawn correctly, and execute their logic under the Godot GDExtension build.

## Files to Audit
- `code/fgame/trigger.cpp` / `code/fgame/trigger.h` — Trigger entity classes
- `code/fgame/g_spawn.cpp` — Spawn table (trigger classnames → C++ classes)

## Files to Create (EXCLUSIVE)
- `code/godot/godot_trigger_audit.md` — Audit results documentation (placed in code/godot/ for proximity)

## Trigger Types to Verify

### Core triggers
- [ ] `trigger_multiple` — fires repeatedly when touched
- [ ] `trigger_once` — fires once then removes itself
- [ ] `trigger_relay` — fires targets when triggered (no touch)
- [ ] `trigger_use` — fired by player USE key
- [ ] `trigger_hurt` — applies damage to entities inside
- [ ] `trigger_push` — pushes entities (jump pads)
- [ ] `trigger_teleport` — teleports to `info_teleport_destination`

### MOHAA-specific triggers
- [ ] `trigger_changelevel` — level transition (single-player)
- [ ] `trigger_exit` — mission exit trigger
- [ ] `trigger_music` — change music state
- [ ] `trigger_camerause` — activate camera
- [ ] `trigger_vehicle` — vehicle entry/exit
- [ ] `trigger_objective` — objective completion
- [ ] `trigger_save` — autosave point

## Verification Steps

### 1. Class registration
For each trigger type, verify:
- `CLASS_DECLARATION(Trigger, trigger_xxx, ...)` exists in trigger.cpp
- Classname appears in spawn table (`g_spawn.cpp` or class system)
- Constructor initialises all fields

### 2. Entity keys
Verify common keys are parsed:
- `targetname` — entity name
- `target` — what to fire
- `delay` — delay before firing
- `count` — fire limit
- `message` — display text
- `dmg` — damage amount (trigger_hurt)
- `speed` — push speed (trigger_push)

### 3. Touch/Use logic
- `trigger_multiple::Touch()` — collision detection
- Trigger bounds from brush model or explicit `mins`/`maxs`
- Cooldown timer between activations
- Target firing: `G_UseTargets()` or `trigger->activator`

### 4. Compile check
Each trigger class should compile without errors. If any use functions only available with specific `#ifdef` guards, document the issue.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 101: trigger_* Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Files in `code/godot/` owned by other agents
