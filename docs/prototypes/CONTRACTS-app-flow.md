# CONTRACTS — app-flow prototype

**Wayfinder ticket:** *Prototype the home, mode, pens, settings, and Back flow* (issue #5)
**Pinned before Wave 1. Any interface change requires orchestrator approval.**
Repo `~/pen-fight` @ `main` · Godot 4.7.2 headless · offline only · no production behavior changes.

## Ground rules (all agents)

- **Own exactly the files listed for your wave. Never edit a file you do not own.** Do NOT edit
  `game/scripts/*`, `game/scenes/*`, `game/tests/*` (production), `project.godot`, or anything under
  another ticket's prototype dir.
- Read first: `AGENTS.md`, `CONTEXT.md`, `docs/adr/0001-separate-application-flow-from-game-sessions.md`,
  and the ticket body (GitHub issue #5).
- Serialize every Godot invocation behind `flock /tmp/pf-godot.lock -c '...'` (siblings share the box).
- **Do NOT commit, do NOT push, do NOT run the full test suite.** Print raw gate output at the end.
- Prototypes are cheap decision artifacts: no new autoloads, no scene edits, no assets, no network.

## Deliverables & ownership

### Wave 1 — owner: Claude Code (Sonnet)

1. **NEW** `game/prototypes/app_flow/app_flow.gd` — pure-logic navigation state machine.

   ```gdscript
   enum Screen { BOOT, HOME, MODE, PENS, SETTINGS, CONFIRM_LEAVE, PLAYING }
   signal screen_changed(from: Screen, to: Screen)
   signal gameplay_start_requested(mode: String)   # emitted ONLY when screen transitions INTO PLAYING
   signal gameplay_stop_requested()                # emitted ONLY when leaving PLAYING
   var screen: Screen                              # read-only for consumers

   func open_mode_select() -> void
   func open_pens() -> void
   func open_settings() -> void
   func confirm_leave() -> void      # CONFIRM_LEAVE -> HOME
   func cancel_leave() -> void       # CONFIRM_LEAVE -> PLAYING
   func start_match(mode: String) -> void   # MODE -> PLAYING (emits gameplay_start_requested)
   func end_match() -> void                 # PLAYING -> HOME (emits gameplay_stop_requested)
   func handle_back() -> bool               # true = consumed; false = host quits the app
   ```

   Invariants (must be test-enforced):
   - `gameplay_start_requested` fires only on a transition *into* PLAYING; nothing in this module
     instantiates scenes/nodes.
   - `handle_back()` from PLAYING → CONFIRM_LEAVE (never straight out); from HOME → `false` (not consumed).
   - Back from MODE/PENS/SETTINGS → HOME. Back in CONFIRM_LEAVE → cancel (back to PLAYING).
   - Settings entry from PLAYING is not allowed (suspend semantics live with the host).

2. **NEW** `game/prototypes/app_flow/app_flow_test.gd` — headless test, no autoloads, no scene deps.
   Must print `app_flow_test: ALL PASS` (repo convention) and cover: full transition table, both
   invariants, Back from every screen, double-Back, leave-confirm cancel path.

### Wave 2 — owner: Claude Code (Sonnet)

3. **NEW** `docs/prototypes/app-flow/mock/index.html` — single-file click-through
   (boot → home → mode → pens → settings → confirm-leave → home), zero external deps, classroom
   identity consistent with `assets/design/mockups/*`.
4. **NEW** `docs/prototypes/app-flow/FLOW.md` — flow map + Back table + the loading-view finding
   (real work feedback vs fake delay), citing Wave-1 evidence.

### Wave 3 — owner: Claude Code (Sonnet)

5. **NEW** `docs/prototypes/app-flow/DECISION.md` — ticket resolution: the smallest flow that
   satisfies START/PENS/SETTINGS clarity, Pass & Play + Solo without restructuring, correct Back
   ownership, no live match behind a menu; evidence table; open risks.
6. **NEW** `docs/prototypes/app-flow/RESOLUTION-COMMENT.md` — the issue-comment draft (orchestrator posts it).

## Gates (paste raw output of each)

```bash
cd ~/pen-fight/game
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --quit --import .'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 240 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/app_flow/app_flow_test.gd'
```

## Non-goals

No gameplay logic, no match instantiation, no production file edits, no autoloads, no network,
no build/export work.
