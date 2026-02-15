# Agent Task 62: Full UI/Menu/HUD Parity (MOHAA ↔ Godot GDExtension)

## Mission
Implement and verify **complete menu/UI/HUD parity** so this port behaves as a 1:1 replacement for OpenMoHAA for all user-facing GUI flows.

You must deliver working behaviour for all items below, not partial scaffolding.

---

## User-required outcomes (must all pass)
1. Main menu works.
2. All menus function end-to-end.
3. All GUI systems function end-to-end.
4. All HUD functions render and update correctly.
5. After spawning in-game, team/weapon select menus appear and function.
6. Pressing `ESC` in-game opens the in-game menu correctly.
7. All `.urc` UI resources are supported and functioning (user wrote `.ucr`; confirm `.urc` runtime paths).
8. `pushmenu` and `showmenu` commands work reliably from console and from Godot wrapper methods.

---

## Mandatory read-before-code
Read these files first:
- `.github/copilot-instructions.md`
- `openmohaa/AGENTS.md`
- `openmohaa/TASKS.md` (read to end)

Then trace upstream UI paths in:
- `openmohaa/code/client/cl_ui.cpp`
- `openmohaa/code/client/cl_keys.cpp`
- `openmohaa/code/client/cl_scrn.cpp`
- `openmohaa/code/uilib/**`
- `openmohaa/code/godot/MoHAARunner.cpp`
- `openmohaa/code/godot/godot_ui_system.cpp`
- `openmohaa/code/godot/godot_ui_input.cpp`
- `openmohaa/code/godot/godot_client_accessors.cpp`
- `openmohaa/code/godot/godot_renderer.c`

---

## Constraints you must follow
- Keep upstream mergeability.
- Any engine-file changes must be under `#ifdef GODOT_GDEXTENSION` guards.
- Use C accessor pattern when bridging engine/client state into godot-cpp translation units.
- No raw `malloc/free` in new C++ code.
- British English in comments/docs.
- No workarounds that bypass engine UI architecture.

---

## Implementation plan (execute in order)

### Step 1 — Audit and reproduce UI/menu failures
Create a short fault list with concrete repro steps for:
- Main menu open/close.
- ESC in-game menu open.
- Team/weapon select visibility and input.
- Console + chat overlays.
- `pushmenu`, `showmenu`, `togglemenu`, `popmenu` command behaviour.
- HUD draw correctness during gameplay vs menu/loading.
- `.urc` load failures/missing assets (if any).

### Step 2 — Fix command and state routing parity
Ensure wrapper/API behaviour matches upstream command contracts exactly:
- `pushmenu <name>`
- `showmenu <name> [force 0/1]`
- `togglemenu <name>`
- `popmenu <restore_cvars 0/1>`

Verify Godot methods map 1:1 to valid engine command formats.

### Step 3 — Fix input routing parity
Ensure proper routing by key catcher state:
- `KEYCATCH_GAME` gameplay input.
- `KEYCATCH_UI` menu input.
- `KEYCATCH_CONSOLE` console input.
- `KEYCATCH_MESSAGE` chat input.
- `KEYCATCH_CGAME` cgame special handling.

ESC behaviour requirements:
- In-game + no modal overlay -> opens pause/in-game menu.
- In menu -> backs out/close according to upstream behaviour.
- In console/chat -> follows upstream key handling (no duplicate handling on Godot side).

### Step 4 — Fix menu and HUD rendering layering
Validate and correct draw-order/layering for:
- Backgrounds/loading screens.
- Menu widgets.
- Console overlay.
- HUD elements (crosshair, health, ammo, compass, scoreboard, centre-print).

Ensure menu backgrounds do not incorrectly obscure gameplay when they should not.

### Step 5 — Team/weapon selection flows
Ensure these menus appear and are interactive after spawn events:
- Team selection (Allies/Axis/Auto/Spectator)
- Weapon selection

If event trigger is missing, trace from cgame/client path and implement correct bridge/state handling.

### Step 6 — `.urc` coverage verification
Confirm `.urc` files load through VFS and menu manager.
Produce a list of loaded menu resources and unresolved resources.
Fix any path/case/command integration issue preventing proper `.urc` usage.

### Step 7 — Build and validate
Run:

```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

Build must pass cleanly.

### Step 8 — Document
Append a new phase entry to `openmohaa/TASKS.md` with:
- Phase number
- What was fixed
- Files changed
- Upstream functions traced
- Remaining gaps

---

## Acceptance checklist (must all be true)
- [ ] Main menu opens and is interactive.
- [ ] ESC opens in-game menu while playing.
- [ ] Team/weapon selection appears and accepts input after spawn.
- [ ] Console overlay input and rendering both work.
- [ ] Chat/message mode input works.
- [ ] HUD renders correctly in active gameplay.
- [ ] `pushmenu` works from console and Godot wrapper.
- [ ] `showmenu` works from console and Godot wrapper.
- [ ] `.urc` resources load and drive menus correctly.
- [ ] No regression in gameplay input when menus are closed.
- [ ] Build passes.

---

## Final report format (required)

```markdown
## Status
FIXED: <one-line summary>
NEXT PRIORITY: <one most important remaining gap>
REMAINING GAPS: <count>
```
