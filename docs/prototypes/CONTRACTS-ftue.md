# CONTRACTS — ftue prototype (first-minute FTUE + menu visual direction)

**Wayfinder ticket:** *Prototype the first-minute FTUE and menu visual direction* (issue #12)
**Pinned before Wave 1. Any interface change requires orchestrator approval.**
Repo `~/pen-fight` @ `main` · offline only · no production behavior changes.

## Ground rules (all agents)

- **Own exactly the files listed for your wave. Never edit a file you do not own.** Do NOT edit
  `game/scripts/*`, `game/scenes/*`, `game/tests/*` (production), `project.godot`, or anything under
  another ticket's prototype dir (`docs/prototypes/app-flow/`, `game/prototypes/app_flow/`,
  `pen-profiles/`, `policy-bot/` are all frozen).
- Read first: `AGENTS.md`, `CONTEXT.md`, `docs/prototypes/CONTRACTS-app-flow.md`,
  `docs/prototypes/app-flow/FLOW.md`, `docs/design/design-pillars.md`, and the ticket body (#12).
- Serialize every Godot invocation behind `flock /tmp/pf-godot.lock -c '...'` (siblings share a
  2-core box).
- **Do NOT commit, do NOT push, do NOT run the full test suite.** Print raw gate output at the end.
- Cheap artifacts only: no new autoloads, no scene edits, no binary assets, no network.

## Ground truth from the repo (read; never modify)

- The app flow (ticket #5, closed) is the layer this prototype sits on: `Screen { BOOT, HOME, MODE,
  PENS, SETTINGS, CONFIRM_LEAVE, PLAYING }`. **`docs/prototypes/ftue/mock/index.html` must keep the
  same enum names and the same guard semantics** as `docs/prototypes/app-flow/mock/index.html` — if
  the FTUE mock and the app-flow mock disagree about an existing edge, the app-flow mock wins.
- **Game Mode and Ruleset are different axes** (`CONTEXT.md`): Hot Seat / Solo is the mode; Classic /
  Pen Powers is the ruleset. The FTUE must not present them as one list of "modes".
- **Pen Powers tradeoffs are fixed, visible, per-model** (`CONTEXT.md`: Pen Profile has an explicit
  strength and cost). No hidden stats, no numeric stat page — the tradeoff is stated in words on the
  pen itself.
- Turn input is already "grab the pen, pull back, release" (`AimInput`): the slingshot drag is the
  real gesture. The FTUE teaches *that*, inline.
- **Prompt/label fit rule (from commit `4573676`):** text fits a computed viewport width — never a
  hardcoded 44 px, never an assumption of 1280. `window/stretch/aspect = keep_height`, so a tall
  phone's logical width is well under 1280.
- Rival Circuit progression (ticket #10) is **not decided**. Rival choice may render an ordered list
  of three rivals, but lock/unlock state must come from an injected callback, never from hardcoded
  progression rules.
- Test convention: `extends SceneTree`, `static func run_tests() -> bool`, `func _init()` calls
  `quit(0 if ok else 1)`, success line `"<name>: ALL PASS"`. Verdict lines must contain the literal
  `PASS` (a `PAS OK` typo made one suite invisible to a `grep PASS` gate).

## Deliverables & ownership

### Wave 1 — owner: Agent A (interaction)

1. **NEW** `game/prototypes/ftue/ftue_flow.gd` — pure-logic first-minute beat sequence. No nodes, no
   scene deps, no timers of its own (the host feeds `tick(delta)`).

   ```gdscript
   enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }
   signal beat_changed(from: Beat, to: Beat)
   var beat: Beat                                  # read-only for consumers

   func start_first_minute(mode: String, ruleset: String) -> void
   func on_drag_started() -> void     # the inline teach dies the instant the player grabs
   func on_first_shot_committed() -> void
   func on_tradeoff_acknowledged() -> void
   func skip() -> void                # one-tap escape from any teach beat
   func tick(delta: float) -> void    # auto-advance/idle-timeout only, never blocks input
   func visible_cue() -> String       # "" when nothing should be shown
   ```

   Invariants (must be test-enforced):
   - `start_first_minute("hot_seat", ...)` never enters `RIVAL_CHOICE`; `"solo"` may.
   - A teach beat can never block a legal flick: `on_drag_started()` clears the teach immediately,
     from any beat, and never re-arms within the same player turn.
   - No beat other than `PLAY` may be active once `on_first_shot_committed()` has fired.
   - `TRADEOFF` appears only when `ruleset == "pen_powers"`.
   - Launch-to-first-flick budget: **≤ 3 taps** from `BOOT` to a live AIM turn, and no beat may be
     required to complete before the player can drag.

2. **NEW** `game/prototypes/ftue/ftue_flow_test.gd` — headless test, prints `ftue_flow_test: ALL PASS`.
   Covers: mode×ruleset matrix, teach-cancel-on-drag from every beat, tap budget, double-flick,
   `skip()` from every beat, tick advance without input.

3. **NEW** `docs/prototypes/ftue/mock/index.html` — single-file click-through of the first minute,
   extending the app-flow mock's `AppFlow` port (copy its structure; same Screen names/guards). Must
   include the inline grab/pull/release teach, the first-shot cue, mode select, rival choice, and the
   Pen Powers tradeoff surface. **Every screen must be reachable directly as `#<SCREEN>` or
   `#<SCREEN>@<beat>`** so it can be captured without clicking, and at 1280×720 and at a portrait
   viewport (720×1280) with no horizontal overflow.

4. **NEW** `docs/prototypes/ftue/FLOW-FTUE.md` — beat sequence, tap budget, what is on screen at t=0
   / t=5s / t=15s, the loading-feedback call (real work only, no fake delay — cite the app-flow
   finding), and the "what we deliberately did not build" list. Cites Wave-1 evidence.

### Wave 2 — owner: Agent B (visual direction)

5. **NEW** `docs/prototypes/ftue/visual/index.html` — one file showing the menu screens side by side
   as a spec sheet (START/HOME, mode select, pens, pen tradeoff, rival choice, settings row style,
   first-shot cue, loading), using the classroom-table identity already established in
   `assets/design/mockups/*.html` and `assets/design/render.sh`.
6. **NEW** `docs/prototypes/ftue/VISUAL.md` — the visual system as rules a later implementer follows:
   type scale, spacing/paper/desk tokens, how the tradeoff is stated in words, the prompt-fit rule,
   and one-line rationale per screen. Each rule must be checkable ("no text below N px", "prompt
   width ≤ viewport − 2×32"), not a mood adjective.

## Gates (paste raw output of each)

```bash
cd ~/pen-fight/game
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 240 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow_test.gd'
flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 120 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow.gd'   # must exit 0 with no script errors
# screenshots (chromium binary: /home/ubuntu/.cache/ms-playwright/chromium-1234/chrome-linux/chrome)
#   chrome --headless --disable-gpu --window-size=1280,720 --screenshot=<out>.png "file://<abs>/index.html#HOME"
#   repeat with --window-size=720,1280  -> assert no horizontal overflow
```

## Non-goals

No gameplay logic, no match instantiation, no production file edits, no autoloads, no network, no
build/export work, no new art assets (HTML/CSS/markdown only), no Rival Circuit progression rules.
