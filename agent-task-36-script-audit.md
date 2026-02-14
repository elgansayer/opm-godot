# Agent Task 36: Script Engine (Morfuse) Audit

## Objective
Audit the Morfuse script system — verify `.scr` script loading, compilation, thread/wait/event execution, and built-in commands work correctly under the Godot GDExtension build.

## Files to Audit
- `code/script/scriptmaster.cpp` — ScriptMaster: thread management
- `code/script/scriptcompiler.cpp` — Script compiler
- `code/script/scriptvm.cpp` — Script VM execution
- `code/script/scriptvariable.cpp` — Script variables
- `code/script/scriptthread.cpp` — Thread class
- `code/script/scriptevent.cpp` — Event system
- `code/fgame/g_spawn.cpp` — Entity script attachment
- `code/fgame/level.cpp` — Level script execution

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_script.c` — Script engine state accessor
- `code/godot/godot_game_script.h` — Accessor declarations

## Accessor Functions
```c
int Godot_Script_GetThreadCount(void);     // active script threads
int Godot_Script_IsCompilerReady(void);    // compiler initialized
int Godot_Script_GetLastError(char *buf, int size); // last script error
```

## Audit Checklist

### 1. Script loading
- [ ] `.scr` files load via `gi.FS_ReadFile()` — VFS path resolution works
- [ ] Script compiler produces valid bytecode
- [ ] Compiled scripts cached correctly

### 2. Thread management
- [ ] `thread <function>` creates a new script thread
- [ ] `waitthread <function>` blocks caller until child completes
- [ ] `waittill <event>` suspends thread until event fires
- [ ] Thread cleanup on map change / entity removal

### 3. Event system
- [ ] `waittill animdone` — waits for animation to complete
- [ ] `waittill trigger` — waits for trigger activation
- [ ] `waittill damaged` — waits for entity to take damage
- [ ] Custom events: `trigger <event_name>` / `waittill <event_name>`

### 4. Built-in commands
- [ ] `exec <script>` — execute another script
- [ ] `goto <label>` — jump within script
- [ ] `print <string>` — console output
- [ ] `wait <seconds>` — timed delay
- [ ] `waitframe` — wait one server frame
- [ ] `spawn <classname>` — create entity
- [ ] `remove` — delete entity
- [ ] `huddraw_*` — HUD drawing commands
- [ ] `setsize`, `link`, `origin`, `angles` — entity manipulation

### 5. Timer accuracy
- [ ] `wait 1.0` actually waits 1 second (±1 frame at sv_fps)
- [ ] `waitframe` waits exactly 1 server frame (50ms at sv_fps 20)
- [ ] Scheduled events fire at correct time

### 6. Memory safety
- [ ] ScriptMaster destructor uses `gi_Malloc_Safe` / `gi_Free_Safe` wrappers
- [ ] Thread pool cleanup doesn't crash during shutdown
- [ ] `Z_MarkShutdown()` protects against post-shutdown allocations

### 7. Known issues
- [ ] `mem_blockalloc.cpp` and `mem_tempalloc.cpp` already have safe wrappers — verify they still compile
- [ ] `lightclass.cpp` safe wrapper — verify

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 95: Script Engine Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
