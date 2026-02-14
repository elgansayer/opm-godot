# Agent Task 41: Entity Audit — path/script/animate Families

## Objective
Audit path_*, script_*, and animate_* entity families. These control NPC routes, scripted scene objects, and animated decorations.

## Files to Audit
- `code/fgame/navigate.cpp` — Path nodes
- `code/fgame/simpleactor.cpp` — Scriptable actors
- `code/fgame/animate.cpp` / `code/fgame/animate.h` — Animated entities
- `code/fgame/scriptmodel.cpp` — Script-controlled models
- `code/fgame/scriptslave.cpp` — Script slave entities (movers driven by scripts)

## Files to Create (EXCLUSIVE)
- `code/godot/godot_path_entity_audit.md` — Audit results documentation

## Entity Types to Verify

### path_* entities
- [ ] `path_corner` — Waypoint for func_train/NPC paths
- [ ] `path_node` — Navigation node for AI pathfinding
- [ ] `path_*` chain following via `target` key
- [ ] Speed/wait at each node
- [ ] Spline interpolation between nodes (if supported)

### script_* entities
- [ ] `script_origin` — Invisible scripted entity (positional reference)
- [ ] `script_model` — Model entity controlled by scripts
- [ ] `script_object` — Generic scripted object
- [ ] `script_camera` — Scripted camera (cutscenes) [overlap with Agent 37, just verify class exists]
- [ ] Script attachment: entity `thread` key → script fire on spawn

### animate_* entities  
- [ ] Animated scene objects (decorative animated models)
- [ ] Animation playback from TIKI definitions
- [ ] Loop vs one-shot animation modes
- [ ] Animation event callbacks during playback

### Script slave pattern
- [ ] `ScriptSlave` base class — entity that moves/rotates based on script commands
- [ ] `moveto`, `rotateto`, `speed` script commands
- [ ] Brush model movement (doors/lifts driven by scripts rather than entity logic)
- [ ] Sound triggers during movement

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 107-110: path/script/animate Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
