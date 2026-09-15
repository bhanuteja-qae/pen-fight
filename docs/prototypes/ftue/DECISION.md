# DECISION.md — ftue prototype (Wave 3, wayfinder ticket #12)

Ticket resolution for *"Prototype the first-minute FTUE and menu visual direction"* (issue #12),
written after re-running every gate on the on-disk artifacts of Waves 1 and 2 and reconciling the one
real divergence between them (the rival placeholder names).

## Ticket question (verbatim)

> Prototype the first-minute FTUE and menu visual direction

as pinned in `docs/prototypes/CONTRACTS-ftue.md:3` (**Wayfinder ticket:** *Prototype the first-minute
FTUE and menu visual direction* (issue #12)). `gh` is not installed in this offline sandbox and the
contract is explicitly offline-only, so this quotes the contract's pinned wording rather than the live
GitHub issue body. Flagged under Open risks.

Two honest notes about the contract as Wave 3 found it:

- `CONTRACTS-ftue.md` spells out **Wave 1** (deliverables 1–4) and **Wave 2** (deliverables 5–6), then a
  `## Gates` block and a `## Non-goals` block. It pins **no Wave-3 section and no Wave-3 resolution
  criteria** — unlike `CONTRACTS-app-flow.md`, which pinned app-flow's. The Wave-3 job (independently
  verify both waves, fix the divergence, decide what carries forward) came from the orchestrator's
  handoff, and that is what this document answers.
- Deliverable 6 of Wave 2 is `docs/prototypes/ftue/VISUAL.md`, which this ticket's frozen-file list
  puts out of reach for Wave 3. Its §12.1 still names the old placeholder rivals; see *Open risks*.

## Answer

**Proceed — both waves stand, with two corrections and a named set of unanswered questions.** The
first minute is a **non-gating teaching layer over an already-live AIM turn**, and the menu visual
direction is a **two-family paper/desk system with a mechanically measured type scale**. Nothing in the
prototype needs to be thrown away or simplified, and nothing in it is ready to be called
human-verified.

**1. The first-minute FTUE is five beats over a live turn, and no beat can ever gate a flick.**

`enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }` (pinned order), driven by one
node-free pure-logic module (`game/prototypes/ftue/ftue_flow.gd`, `extends MainLoop` — the only base
class that satisfies the pinned smoke gate *and* creates no Window/scene tree). The host feeds
`tick(delta)`; the module owns no timer and no rendering decision.

| Mode | Ruleset | Beat order before a flick (idle relaxes only `TEACH`/`RIVAL_CHOICE`; `FIRST_SHOT` and `TRADEOFF` are sticky) |
|---|---|---|
| `hot_seat` | `classic` | `TEACH → FIRST_SHOT → PLAY` |
| `hot_seat` | `pen_powers` | `TRADEOFF → TEACH → FIRST_SHOT → PLAY` |
| `solo` | `classic` | `RIVAL_CHOICE → TEACH → FIRST_SHOT → PLAY` |
| `solo` | `pen_powers` | `RIVAL_CHOICE → TRADEOFF → TEACH → FIRST_SHOT → PLAY` |

The load-bearing property is not the order, it is the **non-gating** property: `on_drag_started()`
clears the beat from *any* beat, in the same frame, and the beat can never re-arm within the player's
turn — so the teach is a layer the player can ignore by simply playing. `skip()` means two different
things on purpose: on a teach beat it cancels the rest of the minute; on a pre-flick card it dismisses
that card. Launch to a live AIM turn costs ≤ 3 host taps and the FTUE's own required cost is 0.

**2. The visual direction is the paper/desk system in `VISUAL.md`, stated as rules a script decides.**
One page of it is reproduced below; the binding version is the file.

**3. The rival placeholder-name divergence is resolved to one set: `CHALK`, `INK RED`, `VELLUM`.**
Detail in its own section below. The mock already used that set; the visual sheet used
`Nib` / `Blotter` / `Understudy`. The visual sheet was renamed on three text nodes and nothing else;
it still prints `ALL CHECKS PASS` at all three viewports, and at exactly the same numbers.

## The visual direction in one page

*(Summary of `docs/prototypes/ftue/VISUAL.md` and the sheet that renders and self-checks it. Every
number here was measured by that sheet's own checker, not asserted.)*

- **Two surface families, and crossing between them is a state change, never decoration.**
  **paper** = menus/notebook sheet (`--paper-bg #f4efe2`, ruling, red margin rule, punched holes,
  `--ink #22304d`); **desk** = the table and anything drawn over it (3-stop wood gradient with cream
  ink). Tokens are byte-identical to the app-flow mock's `:root` — extend, never fork.
- **Reference surface: 300 px of content width**, derived not asserted (device `386 − 20` shell
  `− 66` page padding). Every other surface declares `data-surface-scale >= 1.000` and scales by
  `k = w / 300`; the production settings sheet is `k = 488/300 = 1.6267`. Rendered width is reported,
  not failed (a narrow window clamps it, e.g. ratio 0.537 at 360 px).
- **Type is eight tiers with an absolute floor: `t0` 26 / `t1` 18 / `t2` 17 / `cue` 15 / `t3` 14 /
  `t4b` 13 / `t4` 12 / `t5` 11 px**, floor `11 × k` on a scaled surface. **Never shrink type to fit** —
  no `transform: scale()`, no `zoom`; the only sanctioned fit mechanisms are the turn-gate 2 px
  step-down and re-authoring the line. Reason: a scaled label keeps its layout box, so the hit target
  and the glyphs disagree.
- **Fit: gutter 32 px per side** (matches `SIDE_MARGIN` in `turn_gate.gd`), so the prompt budget is
  `viewport − 64`; no horizontal scroll on a menu page; and **never `overflow:hidden` on `html`/`body`**
  to pass a fit gate — §11.2 records the negative control where a blown-out 2158.9 px prompt passed the
  document-level test.
- **Desk legibility is arithmetic, not taste.** Raw cream `#f6ecd6` on the wood gradient measures
  **2.45–3.32:1** — below 4.5:1 — so every desk text node carries a darkened backer `rgba(20,16,12,a)`
  with `a >= 0.40`: at `a = 0.42` that is **5.87 / 7.26 / 8.68:1**, and the cue chips at `a = 0.78` are
  **11.93 / 12.89 / 13.62:1**. Paper ink is never drawn on the desk, and cream is never drawn on paper.
- **Content rules that outlive the prototype.** The Pen Powers tradeoff is stated **in words**
  (`Strength.` then `Cost.`, two lines per pen, no digits, no hidden stats, no numeric stat page); the
  cue voice is uppercase ASCII ≤ 48 chars (`MAX_CUE_CHARS`); the rival list is ordered, exactly three
  rows, with lock state as an **injected callback** and no progression rule encoded in the visual layer.
- **The sheet is the gate.** Its readout prints one line per rule id; VISUAL.md §11.3 records nine real
  defects those checks caught during construction (a hole 1 px past a page edge, two wrapped Strength
  lines, 2.45:1 cream on the desk, a cue that wrapped inside a padded chip at 295.4 px…) and that the
  checks were never relaxed to pass.

## Evidence

| Claim | Artifact | How verified (Wave 3) | Result |
|---|---|---|---|
| Beat logic and every pinned invariant hold | `game/prototypes/ftue/ftue_flow.gd`, `ftue_flow_test.gd` | Re-ran the pinned Godot gate, `flock`-serialized, on the on-disk files | `ftue_flow_test: ALL PASS` — 2500 interaction sequences over 4 mode × ruleset combos, exit 0 |
| The module loads as a script with no nodes/timers | `ftue_flow.gd` | Re-ran the pinned second gate (`--script res://prototypes/ftue/ftue_flow.gd`) | `ftue_flow load smoke OK (beat=PLAY, cue=)`, exit 0 |
| The mock is a faithful port, not a re-implementation | `docs/prototypes/ftue/mock/index.html` | Its in-page `#selftest`, read from `--dump-dom` | `FTUE SELFTEST: PASS (9129 checks, 2500 interaction sequences over 4 mode x ruleset combos)` — the same 2500 as the GDScript gate |
| Hash routes land on the requested screen **and** beat | `mock/index.html` (`#debug-cur`, `#debug-hash`) | `--dump-dom` at 1280x720 `#PLAYING@TEACH` and 720x1280 `#MODE@RIVAL_CHOICE` | `screen: PLAYING \| beat: TEACH` and `screen: MODE \| beat: RIVAL_CHOICE`, both reporting `replayed through the real API` |
| No horizontal overflow in the mock at the pinned sizes | `mock/index.html` (`#viewport-probe`) | headless chromium at 1280x720 and 720x1280 | `horizontalOverflowPx=0` at both; widest element right edge exactly equals the window edge |
| The visual rules are mechanically true, not aspirational | `docs/prototypes/ftue/visual/index.html` | Its own in-page checker via `--dump-dom` at 1280x720, 720x1280 and a true 360x640 | `ALL CHECKS PASS` at all three; widest nowrap prompt 295.4 px vs budgets 1216 / 656 / 296 px |
| Absolute type floor | `visual/index.html` (TYPE census) | Read the census line | `min rendered font-size=11px at P.t5  global floor=11px :: PASS` |
| Neither HTML file reaches outside itself | both HTML files | `grep` for `src=`, `href=`, `@import`, `<link`, `url(http`, `https://` | **0 matches in both** (no external stylesheet, script, font, image or CDN) |
| The rival placeholder set is now single | `mock/index.html:911-913`; `visual/index.html:412,420,428` | `grep` both trees for both name sets; rendered `#rival-list` read from the DOM | In the two rendered artifacts only `CHALK` / `INK RED` / `VELLUM` remain; the old set survives only in frozen `VISUAL.md:637` and in this document's own record of the divergence |
| The rename fits, with room to spare | `visual/index.html` | Measured `#card-RIVAL .rname` text at the sheet's own declared font stack (bold 18 px, `--font-ui`) in the same browser | `CHALK` 63.00 px, `INK RED` 74.02 px, `VELLUM` 74.00 px — vs the set it replaced: `Nib` 29.00, `Blotter` 58.00, `Understudy` 100.02 px. Widest rival name **100.02 → 74.02 px**, inside the 300 px reference surface |
| The rename did not touch the binding constraint | `visual/index.html` | `data-widest-nowrap` + `FIT-2` before/after; `t1` tier census | widest nowrap prompt still exactly **295.4 px** (the 33-char cue) at all three viewports; `t1(18px)=15` unchanged; `R-1` and `R-3` PASS |
| Ticket wording | `docs/prototypes/CONTRACTS-ftue.md:3` | Could **not** verify against the live GitHub issue (`gh` absent, offline sandbox) | Used the contract's pinned quote instead |

Raw gate output (re-run this session, on the files now on disk, `flock`-serialized):

```
$ cd ~/pen-fight/game && flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 300 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow_test.gd'
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ftue_flow: load smoke OK (beat=RIVAL_CHOICE, cue=PICK YOUR RIVAL)
ftue_flow_test: exhaustive walk cross-checked 2500 interaction sequences over 4 mode x ruleset combos
ftue_flow_test: ALL PASS
EXIT=0

$ cd ~/pen-fight/game && flock /tmp/pf-godot.lock -c 'DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 120 ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://prototypes/ftue/ftue_flow.gd'
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ftue_flow: load smoke OK (beat=PLAY, cue=)
EXIT=0
```

```
$ chrome-headless-shell --no-sandbox --disable-gpu --window-size=1280,720 --virtual-time-budget=3000 \
    --dump-dom "file:///home/ubuntu/pen-fight/docs/prototypes/ftue/mock/index.html#PLAYING@TEACH"   # (grep of the dumped DOM)
id="debug-cur">screen: PLAYING | beat: TEACH | cue: GRAB THE PEN - PULL BACK - LET GO
id="debug-hash">hash route: #PLAYING@TEACH -> screen PLAYING, beat TEACH (replayed through the real API)
id="selftest">FTUE SELFTEST: PASS (9129 checks, 2500 interaction sequences over 4 mode x ruleset combos)
id="viewport-probe">viewport probe: 1280x720 | documentElement.scrollWidth=1265 | body.scrollWidth=1265 | max scrollWidth=1265 | innerWidth=1280 | horizontalOverflowPx=0 | widest element right edge=1265.0px (.room)

$ chrome-headless-shell --window-size=720,1280 ... "...#MODE@RIVAL_CHOICE"
id="debug-cur">screen: MODE | beat: RIVAL_CHOICE | cue: PICK YOUR RIVAL
id="debug-hash">hash route: #MODE@RIVAL_CHOICE -> screen MODE, beat RIVAL_CHOICE (replayed through the real API)
id="selftest">FTUE SELFTEST: PASS (9129 checks, 2500 interaction sequences over 4 mode x ruleset combos)
id="viewport-probe">viewport probe: 720x1280 | documentElement.scrollWidth=720 | body.scrollWidth=720 | max scrollWidth=720 | innerWidth=720 | horizontalOverflowPx=0 | widest element right edge=720.0px (.room)
<div class="rival-name">1. CHALK</div>
<div class="rival-name">2. INK RED</div>
<div class="rival-name">3. VELLUM</div>
id="rival-provenance">lock state injected by the host stub — real rules are Rival Circuit (ticket #10), out of scope for Wave 1
```

Visual sheet, `--dump-dom` of `#readout` (full readout at the pinned reference size; at 720x1280 and
360x640 the other 35 lines are byte-identical and only the four size-dependent ones move):

```
=== SPEC-SHEET SELF-CHECK — FTUE menu visual direction (ticket #12, Wave 2) ===        @ 1280x720
viewport      innerWidth=1280 innerHeight=720 dpr=1
FIT-1  document.scrollWidth=1265 vs innerWidth=1280 -> overflow=0px :: PASS no horizontal overflow
prompts       count=56 (data-nowrap=33)
FIT-1b box-fit inside every prompt element :: PASS 0 of 56 spill their box
FIT-2  budget=innerWidth-2*32=1216px  widest-nowrap-prompt=295.4px :: PASS
widest prompt (single line, unwrapped) = 616.1px  text="Each pen runs its own profile. The strength and the cost are printed on the pen, before the first flick."
FIT-1c clippers=8 hiding content=0 :: PASS nothing clipped by overflow:hidden/clip
F-8   panes=8 (nothing clipped by overflow:hidden/clip) :: PASS
surface       measured page content width=300px (device 386 - 20 shell - 66 page padding)  declared reference=300px  ratio=1.000
FIT-4  one-line prompts marked data-oneline=13  surface>=reference=true -> PASS all 13 render on 1 line
FIT-4b widest one-line prompt text=295.4px vs surface content width=300px :: text="GRAB THE PEN - PULL BACK - LET GO"
FIT-1d descendants inside their pane's box :: PASS 0 spill
SHAPES pens=9 (identity shapes) with non-zero box :: PASS
TYPE   min rendered font-size=11px at P.t5  global floor=11px :: PASS
TYPE   tier counts t0(26px)=7 t1(18px)=15 t2(17px)=13 cue(15px)=5 t3(14px)=15 t4b(13px)=3 t4(12px)=6 t5(11px)=30
SCALE  production settings sheet text column=488px on a 300px reference -> k=1.6267  type floor=17.89px
SCALE  production label 21px PASS | value 19px PASS | back label 22px PASS  (settings_screen.gd:15-18, :255, :260, :292)
S-2   surfaces declaring data-surface-scale >= 1.000 :: 8 found :: PASS
R-1   rival list li.rival=3 with ordinal marks=3 (ordered, exactly three) :: PASS
R-3   locked rows keep t1 name at 18px (2 locked) :: PASS
V-4   cue voice: uppercase / ASCII / <=48 chars (MAX_CUE_CHARS) :: 2 cue strings, longest=33 chars, violations=0 :: PASS
P-1   page gutter (body padding) left=32px right=32px  SIDE_MARGIN=32px :: PASS
P-4   --rule-pitch (33px) >= 28px on every page carrying a wrappable t3 :: PASS
P-5   paper-ink text on the desk surface :: PASS 0
P-6   desk-gradient text on a backer alpha>=0.40 : 152 nodes :: PASS
W-2   digits in the tradeoff pane's t3/t4b text :: PASS 0 of 10
W-3   vocabulary split, screen text only (mode pane <-> ruleset pane) :: PASS
SC-1  primary actions per pane <= 1 :: PASS
L-2   loading stages=3 name real work (>=2 words, none banned) :: PASS
T-3   text elements shrunk by transform/zoom :: 0 offenders :: PASS scale=1 zoom=1 (rotations exempt: scale magnitude measured)
P-3   no overflow:hidden/clip on html/body :: html=visible body=visible :: PASS
L-3   percentage-driven bars without data-total :: 0 (bars=0, data-total=0) :: PASS
W-1   two word-lines per pen (Strength. then Cost.) :: pens=4 :: PASS no hidden stats
W-4   Classic default states 'Every pen runs the same physics.' :: PASS | pen card states 'In Classic they all run the same physics' :: PASS
W-5   Classic + Pen Powers and all four pens on one screen :: options=2 pens=4 word-lines=8 :: PASS
W-6   P1/P2 tags on the pen surface, mirror pick legal :: tags=4 [P1 · EQUIPPED P2 OPEN OPEN] :: PASS
SC-2  menu panes with a t0 title and a control :: 7 of 7 :: PASS | desk pane cues=5 :: PASS
=== ALL CHECKS PASS @ 1280x720 ===

--- the four lines that differ from the run above -------------------------------------------
  @ 720x1280 : viewport innerWidth=720 innerHeight=1280 | FIT-1 scrollWidth=705 vs 720 -> overflow=0px :: PASS
               FIT-2 budget=656px  widest-nowrap-prompt=295.4px :: PASS
  @ 360x640  : viewport innerWidth=360 innerHeight=640 | FIT-1 scrollWidth=345 vs 360 -> overflow=0px :: PASS
               FIT-2 budget=296px  widest-nowrap-prompt=295.4px :: PASS        <-- 0.6 px of margin
               surface ratio=0.537  FIT-4 NOT ENFORCED below the 300px reference surface; wrapped=10
=== ALL CHECKS PASS @ 720x1280 ===
=== ALL CHECKS PASS @ 360x640 ===
```

## Invariants that are test-enforced, and how

Each row is enforced in **two** places — the GDScript test and the mock's 2500-sequence walk — which is
the reason the divergence in this wave was worth chasing: the two ports agree on the state machine but
were never gated against each other (see Open risks).

| Contract invariant | Module test | Also enforced by |
|---|---|---|
| `"hot_seat"` never enters `RIVAL_CHOICE` | `_test_exhaustive_interaction_walk` (4 combos × 5⁴ sequences) + `_test_mode_ruleset_matrix_chains` | mock selftest, same walk |
| A teach beat can never block a legal flick | `_test_teach_dies_on_drag_from_every_beat` | mock: pointer-down never reads `beat`; the card is pointer-transparent (measured: `pointer-events:none` on `#beat-shell`, arena still receives the grab) |
| … and never re-arms in the same player turn | `_test_teach_never_rearms_after_drag` (300 s of ticks after the grab) | mock selftest |
| Only `PLAY` may remain after `on_first_shot_committed()` | `_test_only_play_after_first_shot_committed` (a second commit is a strict no-op) | mock selftest |
| `TRADEOFF` only when `ruleset == "pen_powers"` | `_test_resolution_defaults_are_strict`, `_test_exhaustive_interaction_walk` | mock selftest |
| ≤ 3 taps `BOOT` → live AIM, and no beat is *required* | `_test_tap_budget_boot_to_live_aim` | mock: host-tap ledger in the debug panel (`host taps: 3 / 3 budget \| FTUE taps required: 0`) |
| Beat changes only ever go where the matrix allows | `_test_beat_changed_edges_are_legal` | — |
| Pure logic: no nodes, no scenes, no own timers | `_test_no_nodes_or_timers_in_source` (source scan; first `extends` must be `MainLoop`) | gate 2 runs the file itself |
| Cue text can always fit a computed viewport width | `_test_cue_text_fits` (≤ 48 chars, uppercase, ASCII, trimmed) | visual sheet RULE V-4 (uppercase/ASCII/≤48 on the rendered cue strings) |
| Prompts fit, type never shrinks, nothing is hidden to pass | — (logic layer's proxy is the 48-char cap) | visual sheet FIT-1/FIT-1b/FIT-2/FIT-1c/T-3/P-3, measured at three viewports |

## Options considered and why rejected

- **Wave 3 rewriting the beat module to add a `on_turn_forfeited()` hook.** Rejected: nothing has needed
  it, the player who never flicked is still correctly being taught the first flick, and adding a hook
  for an unobserved layer invents an interface to solve a problem no one has measured (FLOW-FTUE.md
  §10.3). The host-side hand-off is the cheaper fix if playtest says otherwise.
- **Making the 4 s dwell configurable / longer.** Rejected for now: it is a judgement call with no
  measurement behind it either way; exposing it as a tunable before anyone has played it adds a knob
  that nothing can set well. It is named as the first number a playtest should move.
- **Keeping two rival placeholder sets (one per wave) because "the names are placeholders anyway".**
  Rejected: two placeholder sets for one list is not a placeholder decision, it is an undocumented
  divergence — the visual sheet is the artifact a later implementer copies from, and ticket #10 would
  have had to guess which set was canonical. The mock's set wins because it is consistent with the pen
  models being named for desk materials and colours (amber, cobalt, graphite, ivory).
- **Renaming to `Nib`/`Blotter`/`Understudy` instead (the visual sheet's set), i.e. adopting the
  larger artifact's wording.** Rejected: the mock's set is the one the *interaction* prototype renders
  in `#rival-list` with ids (`chalk`/`inkred`/`vellum`), it matches the desk-materials naming family,
  and — measured — it is also the **narrower** set (widest name 74.02 px vs 100.02 px), so adopting it
  strictly relaxes the fit constraint rather than tightening it.
- **Adding a mechanical mock↔GDScript parity gate in Wave 3.** Rejected *as scope*, kept as an open
  risk: it is a new artifact and a new contract interface, not a Wave-3 correction, and the divergence
  it would have caught (names, not logic) was found by reading the two files. Recorded so the
  implementation ticket can decide.
- **Re-authoring the 33-char cue to buy margin at 360 px.** Rejected: the cue is the real teaching line,
  it is already inside budget at 295.4 px / 296 px, and the sheet records that the *element* was
  changed (padded chip → full-width bar) rather than the rule when this same constraint bit before.
  Shortening copy to buy margin silently deletes the margin signal; it stays a named risk instead.
- **Claiming the visual direction is "verified" because the checker says PASS.** Rejected: the checks
  are geometry and tokens, not perception. No human or vision model has looked at a rendered page, and
  §11 of VISUAL.md is explicit that RULES F-7/P-6 are stand-ins for "it looks right".

## The rival placeholder divergence (resolved)

Wave 1 and Wave 2 each needed placeholder rivals and independently invented a set:

| Artifact | Wave | Set before | Set now |
|---|---|---|---|
| `docs/prototypes/ftue/mock/index.html:911-913` | 1 | `CHALK`, `INK RED`, `VELLUM` | *(unchanged)* |
| `docs/prototypes/ftue/visual/index.html:412,420,428` | 2 | `Nib`, `Blotter`, `Understudy` | `CHALK`, `INK RED`, `VELLUM` |

**Resolution: adopt the mock's set.** It is consistent with the pen models being named for materials
and colours, and it is the narrower set (74.02 px vs 100.02 px widest name at bold 18 px). The change is
three text nodes — `git diff --stat` is `1 file changed, 3 insertions(+), 3 deletions(-)` — and the
placeholder labelling is intact in both files: the sheet keeps `data-placeholder="rival-name"` on all
three name spans, and the mock keeps its injected-callback stub, its `provenance` string, and the
`rival-provenance` line rendered from it (`lock state injected by the host stub — real rules are Rival
Circuit (ticket #10), out of scope for Wave 1`).

**Both sets remain stand-ins.** Ticket #10 owns the real Rival Circuit names and unlock rules; nothing
here decides them, and neither artifact encodes a progression rule. The one residue this wave could not
reach — `VISUAL.md:637`, which named `Nib` / `Blotter` / `Understudy` as the sheet's placeholders — was
corrected by the orchestrator in the same commit as this decision (frozen-file rule: only the
orchestrator may edit it). All three documents and both artifacts now carry the one set. No check in
either file reads that sentence, so nothing regressed either way.

## Explicit non-answers — what this ticket did not decide, and who owns it

1. **Rival Circuit names and unlock rules** → ticket #10. The three names above are placeholders, and
   lock/unlock state is an injected callback by contract. `RIVAL_CHOICE` exists, is ordered, and is
   Solo-only; nothing else about the Circuit is decided.
2. **Which Pen Powers values ship and how the tradeoff is authored** → `pen-profiles/DECISION.md`
   owns the numbers (Graphite/Anchor `mass` 1.4–1.8, Ivory/Glide `linear_damp` 1.0–1.5, Amber/Spin
   `angular_damp` 0.5) and the rules. This ticket owns only the **format** in which the tradeoff is
   shown: two word-lines per pen, Strength then Cost, no digits in the tradeoff text (RULE W-2).
3. **Where the beat card renders in a real build** → implementation. The mock anchors the card over
   whatever screen is current (with a desk-specific anchor when the desk is up) so every screenshot
   route is meaningful; a real build wants the desk-only anchor as the *only* path, because a beat
   always implies a live turn (FLOW-FTUE.md §10.2).
4. **Whether the 15 s no-input forfeit and the beat layer need an explicit hand-off** → implementation
   decision, not decided here. There is deliberately no forfeit API in the module.
5. **Cue copy voice vs the cue cap.** The cues are terse uppercase imperatives. If the copy voice warms
   up, the 48-char cap and the uppercase/ASCII invariant (module `_test_cue_text_fits`, sheet RULE V-4)
   must be re-decided **together with** the cap, in that order (FLOW-FTUE.md §10.1).
6. **The loading surface.** The visual sheet renders three loading stages that name real work, but the
   app-flow verdict stands: a manufactured delay is not justified anywhere in this flow, and the
   first-minute beat must never be repurposed as a loading view. Any future BOOT duration needs genuine
   upstream async work behind it.
7. **Not built, and still not built:** production behavior of any kind (nothing here is wired into
   `main.gd`; `game/scripts/*`, `game/scenes/*`, `game/tests/*` and `project.godot` are untouched),
   in-match settings/pause UX (host-owned), settings persistence, analytics, a second player's
   separate FTUE, touch/Android input, mobile build or export path, and any numeric stat page.
8. **Wave-3 resolution criteria for this ticket.** `CONTRACTS-ftue.md` pins none (see above), so this
   document answers the ticket question plus the contract's own gate block; it does not claim to answer
   acceptance criteria that were never written down.

## Open risks / what only a human playtest or a later ticket can settle

- **The 360 px margin is 0.6 px.** At 360x640 the fit budget is `360 − 64 = 296 px` and the widest nowrap
  prompt measures **295.4 px**. That is the system's tightest constraint, it is real (measured, not
  estimated), and it means a one-character widening of the `GRAB THE PEN - PULL BACK - LET GO` cue, or a
  different UI font on the target device, breaks the fit gate at that size. Related and equally
  unmeasured: at 360 px the surface ratio drops to **0.537**, so RULE FIT-4 is *not enforced* below the
  300 px reference surface and **10 of 13 one-line prompts wrap**. Wrapping is not clipping and no gate
  fails — but "the first-minute cue is a single line on a small phone" is not established.
- **The mock and the module are two hand-written ports of one state machine, and nothing gates them
  against each other.** The mock's JS was written by copying the GDScript structure; the two agree
  today (both walk the same 2500 sequences, both report the same PASS), but that agreement is
  *coincidence of authorship*, not a diff, a codegen step, or a parity test. Nothing fails when one side
  gains a transition the other lacks. This is the same class of defect as the rival-name divergence
  Wave 3 just fixed — and in that case the divergence was in data a human had to notice.
- **`IDLE_ADVANCE_SECONDS = 4.0` is unmeasured.** It is a judgement call: long enough not to fire
  mid-thought, short enough to keep the first minute moving for a reading player. No player has been
  timed. It is the single number here a playtest would move first, and it is entangled with risk below.
- **The 15 s idle forfeit already in the game is not observed by the beat module** (`FORFEIT_TIMEOUT:
  float = 15.0`, `game/scripts/main.gd:87`; rule restated at `turn_state.gd:52`). The module has no
  forfeit API on purpose, so a player who never flicks leaves the beat sitting at `FIRST_SHOT` into the
  next turn, and how a host's forfeit gate *looks* with a teach card underneath it has never been
  composed, let alone seen. 4 s < 15 s is a deliberate ordering, not a proof that the two layers read
  well together.
- **The beat layer has never been composed with a live match.** The desk in the mock reproduces the
  *input* (grab / pull back / release, 30 px cancel, 160 px cap) and not the physics. No GDScript in this
  ticket touches gameplay, no match is instantiated, and the beat module has never run inside the real
  game loop. Everything asserted about "a live AIM turn" is asserted about a prototype of one.
- **No human has judged the look.** The orchestrator did run a vision pass over three rendered screens
  (720×1280 `#PLAYING@TEACH`, `#MODE@RIVAL_CHOICE`, `#PLAYING@TRADEOFF`) and the card text read back
  correctly in all three (`GRAB THE PEN - PULL BACK - LET GO`, `PICK YOUR RIVAL`, `PEN POWERS - READ YOUR
  PEN'S TRADEOFF`), so the cards are legible at phone size. Beyond that, both HTML artifacts were
  verified by geometry, computed style and grep in a headless browser, and VISUAL.md §11.3 is explicit
  that its geometric rules stand in for "it looks right". Readability at a glance, feel, and whether the
  paper→desk transition reads as a state change are still unjudged by a human.
- **The production surfaces are still hand-checks, not rendered screens.** RULE S-1's scale comparison
  reads *declared* sizes in `game/scripts/settings_screen.gd` (labels 21 px, values 19 px, BACK 22 px
  against a floor of 17.89 px). No production menu has been rendered and measured against this type
  scale.
- **No touch/Android input path and no device Back-gesture feel.** The pinned sizes are a measurement
  choice (1280x720, 720x1280, 360x640 in a desktop headless browser), not a device matrix. 360x640 is a
  true window but still desktop chromium, not a phone.
- **The mock's own clock is paused by default.** Screenshots are deterministic because nothing advances
  unless a reviewer opts into `?live=1` (or the `L` key). A time-based beat therefore has never been
  watched running — the reviewer starts the clock deliberately.
- **The verbatim GitHub issue #12 body was not independently fetched** (`gh` not installed, offline
  sandbox). The ticket wording above is the contract's pinned quote, which the contract states was
  fixed before Wave 1 started.

## Artifacts

- `game/prototypes/ftue/ftue_flow.gd` — Wave 1, the pure-logic beat sequence (node-free; see its header
  for why `MainLoop` is the only base class that satisfies the pinned smoke gate)
- `game/prototypes/ftue/ftue_flow_test.gd` — Wave 1, the headless gate test (prints `ftue_flow_test: ALL PASS`)
- `docs/prototypes/ftue/mock/index.html` — Wave 1, single-file click-through; hash-routable `#<SCREEN>` /
  `#<SCREEN>@<beat>`
- `docs/prototypes/ftue/FLOW-FTUE.md` — Wave 1, beat sequence, tap budget, t=0/5/15 s, loading call,
  what was deliberately not built
- `docs/prototypes/ftue/VISUAL.md` — Wave 2, the visual system as checkable rules (deliverable 6)
- `docs/prototypes/ftue/visual/index.html` — Wave 2, the spec sheet that renders and self-checks those
  rules (deliverable 5)
- `docs/prototypes/CONTRACTS-ftue.md` — the pinned ticket contract
- `docs/prototypes/ftue/DECISION.md` — this document
- `docs/prototypes/ftue/RESOLUTION-COMMENT.md` — the issue-comment draft
