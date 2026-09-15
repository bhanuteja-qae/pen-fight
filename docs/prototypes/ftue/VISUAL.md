# VISUAL — FTUE menu visual direction (checkable)

Ticket **#12**, wayfinder **Wave 2**. Owner: the menu-visual agent.
Deliverable pair: this file (the rules) + [`visual/index.html`](visual/index.html)
(the spec sheet that renders them and self-checks them).

Scope: a cheap **visual prototype**. No GDScript, no autoloads, no binary art, no
network. `game/**`, `docs/prototypes/app-flow/**`, `docs/prototypes/ftue/mock/**`
and `docs/prototypes/ftue/FLOW-FTUE.md` are frozen and untouched. This file is
contract deliverable 6; `visual/index.html` is deliverable 5.

Every rule is stated so a script can decide pass/fail. "Check:" gives the
mechanical test. Numbers in §5/§10/§11 are **measured by that script**, not
intended. If an implementer's change makes a measured number here wrong, the
number here is what gets updated — never the test.

---

## 1. What this extends (do not reinvent)

| Source | Taken from it |
|---|---|
| `docs/prototypes/app-flow/mock/index.html` | the `:root` token block (verbatim), the paper page (`--rule-pitch` ruling, red margin rule, punched holes), `.device` phone shell, button/pill/toggle shapes, page-title sizing |
| `assets/design/mockups/menu.html`, `settings.html`, `pen.html` | desk palette, pen-chip construction (brass cone + barrel gradient + clip), menu item rhythm |
| `assets/design/aim-ui.html`, `assets/design/table-view.html`, `assets/design/pen-sheet.html` | the desk surface + cream-on-desk ink for anything drawn on the desk rather than on paper |
| `game/scripts/settings_screen.gd` | production settings sheet metrics: labels 21 px, values 19 px right-aligned, pill 64×30 / knob ⌀22, BACK 150×52 @22 px, text column `RULE_X0..RULE_X1` = 24..512, title 44 px |
| `game/docs/turn_gate.md`, `game/scripts/turn_gate.gd` | the prompt-fit rule (`SIDE_MARGIN` 32, step the font down 2 px from 44 to a floor of 18, autowrap as safety net) |
| `docs/prototypes/pen-profiles/DECISION.md` | the four pen identities (Control / Anchor / Glide / Spin), one lever each, and each one's cost |

Where the frozen app-flow enum has no screen for an FTUE beat, §7 maps the beat
onto an existing enum member instead of inventing one.

---

## 2. Surfaces and the scale rule

**Reference surface (the design surface): 300 px of content width.**
Derived, not asserted: the app-flow mock's `.device` is `width:min(390px,94vw)`
with `padding:12px` → 366 px pane; its `.page` has `padding:30px 22px 90px 44px`
→ 366 − 44 − 22 = **300 px**. The spec sheet reproduces that geometry (device 386
incl. its own 10 px shell, page padding 44/22) and measures **300 px** at both
required viewports.

**Every other surface scales from it.** For a surface whose text column is `w`,
its scale factor is `k = w / 300`.

- Production settings sheet: `k = 488 / 300 = 1.6267` (`RULE_X0` = 24, `RULE_X1` = 512).

**RULE S-1 — minimum type on any surface is `11 × k` px.**
Check: `floor = 11 * k`; for the settings sheet `floor = 17.89 px`; its declared
sizes 21 (label row), 19 (value), 22 (BACK) must be `>= floor` — measured: all
three PASS.
```
python3 -c "k=488/300; f=11*k; print('k=%.4f floor=%.2f'%(k,f)); print([(s, s>=f) for s in (21,19,22)])"
```

**RULE S-2 — the scale factor is declared per surface**, never guessed. Every menu
surface carries `data-surface-scale` = the authored scale versus the 300 px
reference, and it must be **`>= 1.000`** (author at the reference or larger; the
*rendered* width is a separate measurement, e.g. a narrow window clamps it to
176 px / ratio 0.587 and that is reported, not failed). A production surface names
its text column width here (settings sheet: 488 px → `k = 1.6267`).
Check: every `[data-surface-scale]` parses and is `>= 1.0`, and the count of
declaring surfaces equals the count of panes. Measured: **8 of 8 surfaces, PASS**
(rendered content width 300 px, ratio 1.000, at both required viewports).

**RULE S-3 — two surface families only.**
(a) **paper** — menus/notebook sheet: `--paper-bg #f4efe2`, `--rule-line` ruling,
`--rule-margin` red rule, punched holes, `--ink #22304d` text;
(b) **desk** — the table and anything drawn over it: the 3-stop wood gradient
(`--desk-1..3`) with cream ink. Crossing from paper to desk is a state change
(menu → playing), never decoration.
Check: the split is enforced by RULE P-5 (no paper ink on the desk surface) and
RULE P-6 (every desk text node carries a darkened backer).
Measured: `P-5 0 leaks`, `P-6 152 of 152 desk text nodes backed`.

---

## 3. Type scale (tier table)

Sizes are px on the **300 px reference surface** (`11 × k` on a scaled surface).

| tier | px | weight | colour | minimum | used for |
|---|---|---|---|---|---|
| `t0` page title | 26 | 700 | `--ink` | **26** | one per page: "Pen Fight", "Game Mode", "Pens", "Ruleset", "Settings" |
| `t1` item | 18 | 700 | `--ink` | **18** | mode / pen / rival names, option names |
| `t2` action | 17 | 700 | `--ink`, or cream on ink | **17** | buttons, setting-row labels, loading-stage names |
| `cue` | 15 | 700 | `#eaf2ff` on the desk | **15** | the first-shot cue chips (grab / pull / release) |
| `t3` statement | 14 | 400 | `--ink-soft #4a5a78` | **14** | tradeoff Strength/Cost lines, rival habits, rule lines |
| `t4b` value | 13 | 400 | `--ink-soft` | **13** | right-aligned setting values, tags |
| `t4` mono note | 12 | 400 | `--muted-2 #8b97a8` | **12** | flavor / last-played / mono notes |
| `t5` eyebrow | 11 | 400 mono | `--muted #6b7a90` | **11** | page eyebrows, tags, stage labels, `letter-spacing:2.2px` |

**RULE T-1 — absolute floor: no menu text below 11 px** (reference surface;
`11 × k` on a scaled surface, RULE S-1).
Check: for every element with a direct non-empty text node,
`parseFloat(getComputedStyle(el).fontSize) >= 11`; the sheet prints the measured
minimum and the element it came from. Measured: **min 11 px at `P.t5`, floor 11 px
→ PASS**.

**RULE T-2 — per-tier minimum.** `data-tier="<t>"` must render `>=` that tier's
size. A tier may be used larger than the table on a scaled surface, never smaller.
Check: per-tier census. Measured at every viewport:
`t0(26)=7 t1(18)=15 t2(17)=13 cue(15)=5 t3(14)=15 t4b(13)=3 t4(12)=6 t5(11)=30`.

**RULE T-3 — never shrink type to fit.** No `transform: scale()`, no `zoom`, no
size below a tier minimum. The sanctioned fit mechanisms are the turn-gate 2 px
step-down (RULE F-6) and re-authoring the line (RULE F-4). Rationale: a scaled
label keeps its layout box, so the hit target and the glyphs disagree.
Check: for every element owning a text node, the computed `transform` matrix's
scale magnitude `sqrt(a²+b²)` / `sqrt(c²+d²)` must be `1 ± 0.001` and `zoom`
must be `1` (rotation is exempt — only the scale magnitude is measured, which is
why the sheet's rotated decorations do not trip it). Measured: **0 offenders → PASS**.

**RULE T-4 — measure the painted element.** Read `font-size` off the element that
owns the text node; never infer a tier from a class name.
Check: the `TYPE` census walks the elements that own a text node (the hidden
measurement probes are excluded) and takes the **minimum** rendered size.
Measured: `min rendered font-size=11px at P.t5  global floor=11px :: PASS`.

---

## 4. Spacing, paper and desk tokens

Tokens are byte-identical to the app-flow mock's `:root` (extend, don't fork):

```
--room-bg    #241f1a
--desk-1     #b8925f    --desk-2 #a07a4d   --desk-3 #8a6740
--desk-border #e6c496
--paper-bg   #f4efe2
--rule-line  #a9bdd4    --rule-margin #d9707f
--ink        #22304d    --ink-soft  #4a5a78  --muted #6b7a90  --muted-2 #8b97a8
--cream      #f4efe2
--p1         #5b8ce0    --p1-deep   #3f6cc4
--p2         #f0a23c    --p2-deep   #d9861f
--font-ui    "Liberation Sans","DejaVu Sans",sans-serif
--font-mono  "DejaVu Sans Mono",monospace
```

Spacing scale — **only these six values**: `--s1..--s8` = `4 / 8 / 12 / 16 / 24 / 32`.

**RULE P-1 — page gutter is 32 px per side** (matches `SIDE_MARGIN` in
`turn_gate.gd`), so effective content width = viewport − 64.
Check: `getComputedStyle(document.body).paddingLeft/Right === "32px"`. Measured:
`left=32px right=32px → PASS`.

**RULE P-2 — no menu page scrolls horizontally.** Vertical scrolling is fine.
Check: `document.documentElement.scrollWidth <= window.innerWidth`.
Measured: `1280/1280`, `720/720`, `360/360` → **overflow 0 px** at all three.

**RULE P-3 — never hide overflow to pass a gate.** `overflow:hidden` on
`html`/`body` is forbidden in menu surfaces: it converts "clipped text" into
"silently passing check". Clip only where a shape requires it (the phone `.pane`),
and then rely on RULES F-5/P-6, which are independent of the clip. This is not
theoretical — §11's negative control shows a blown-out prompt passing the
document-level test (FIT-1 PASS 0 px while the prompt is 2158.9 px wide).
Check: computed `overflow` of `document.documentElement` and `document.body` must
match neither `hidden` nor `clip`. Measured: `html=visible body=visible → PASS`.

**RULE P-4 — ruling pitch.** The paper ruling pitch is a real custom property
`--rule-pitch` that the gradient consumes; it must be **`>= 28 px`** (2× the `t3`
size) on any page carrying a wrappable `t3` statement, so a two-line statement
never straddles two rules. Pages with only single-line text may use less (the
production settings sheet keeps 27 px).
Check: read `--rule-pitch` from each `.page` and compare. Measured: `33px → PASS`.

**RULE P-5 — paper ink is never drawn on the desk** (and cream is never drawn on
paper). Desk text uses the desk's cream tokens; paper text uses the `--ink*`
tokens.
Check: no element with a direct text node inside `.deskpane` may compute to any
of `rgb(34,48,77) / rgb(74,90,120) / rgb(107,122,144) / rgb(139,151,168)`.
Measured: **PASS 0**.

**RULE P-6 — text on the desk-wood gradient needs a darkened backer of
`alpha >= 0.40`** (`rgba(20,16,12,a)`, `a >= 0.40`), because the desk is a *light*
brown gradient. Raw cream `#f6ecd6` on it measures **2.45:1** (desk top) to
**3.32:1** (desk mid) — below 4.5:1. The backer at `a = 0.42` composites to
`rgb(115,91,60)` / `rgb(101,77,50)` / `rgb(88,66,42)` across the gradient and
brings `#fbf5e8` to **5.87 / 7.26 / 8.68:1**, and the cue chips at `a = 0.78` to
**11.93 / 12.89 / 13.62:1**. Paper is opaque, so paper text is exempt.
Check: for every element with a direct text node inside `.card` or `.deskpane`,
walk up until the first non-transparent `background-color` or the gradient; if the
surface is the gradient, the accumulated alpha must be `>= 0.40`, else if the
surface is opaque (alpha 1) it passes.
Measured: **152 desk text nodes, all backed → PASS**.
```
python3 -c "
l=lambda c:(c/255)/12.92 if c/255<=0.03928 else (((c/255)+0.055)/1.055)**2.4
def L(p):r,g,b=p;return .2126*l(r)+.7152*l(g)+.0722*l(b)
r=lambda a,b:(max(L(a),L(b))+.05)/(min(L(a),L(b))+.05)
print('raw cream on desk mid : %.2f:1'%r((246,236,214),(160,122,77)))
print('backed cream (a=.42)  : %.2f:1'%r((251,245,232),(101,77,50)))
print('backed cue   (a=.78)  : %.2f:1'%r((234,242,255),( 99,120, 62)))"
```

---

## 5. Prompt fit (the rule the repo already paid for)

Background: commit `4573676` — the match-over prompt rendered **1276 px on a
1280 px viewport** and was clipped at both edges. The fix introduced
`SIDE_MARGIN` 32 px per side, a 2 px step-down from 44 to a floor of 18, and
autowrap as a safety net.

**RULE F-1 — the budget is computed, never assumed.** For a viewport of logical
width `W`, the prompt budget is `W − 2×32 = W − 64`, and no rendered prompt box
may exceed it.
Check: `document.scrollWidth <= window.innerWidth`, plus per-element box fit.

**RULE F-2 — never assume 1280.** `game/project.godot` sets
`window/size/viewport_width=1280`, `viewport_height=720`,
`stretch/mode=canvas_items`, `aspect=keep_height`. With `keep_height` the
**logical height is always 720** and the logical width is
`720 × (window_width / window_height)`:

| physical window | logical viewport | prompt budget (W−64) |
|---|---|---|
| 1280×720 | 1280×720 | 1216 px |
| 720×1280 | 405×720 | 341 px |
| 1080×2340 (tall phone) | 332×720 | **268 px** ← the design floor |

Author against **268 px**. 1280 is one case of many. The spec sheet's own
`innerWidth` is used as the budget basis for its checks, which is conservative:
the real game computes the budget from the logical viewport
(`root.get_visible_rect().size.x`).
Check: the sheet never hardcodes a width — it writes the computed budget to
`<body data-budget>` at run time. Measured: `data-budget=1216` (1280 viewport),
`656` (720), `296` (360) — i.e. `innerWidth − 64` each time.

**RULE F-3 — a single-line prompt must measure within the budget.** An element
marked `data-nowrap` is authored as **one line**; its unwrapped text width must be
`<= W − 64` at every tested viewport.
Check: measure the text in a hidden, identically-styled probe
(`white-space: nowrap`) and compare with `innerWidth − 64`.
Measured: widest `data-nowrap` text = **295.4 px against a 296 px budget at
innerWidth 360** (the binding case); 656 px budget at 720; 1216 px at 1280 —
PASS at all three. Of 56 prompts, 33 are `data-nowrap`. The widest prompt string
of any kind is **616.1 px** ("Each pen runs its own profile. The strength and the
cost are printed on the pen, before the first flick.") — it is *not* `data-nowrap`;
it is a wrappable statement, see F-4.

Risk: the 360 px case passes by **0.6 px**. Adding one character to any
`data-nowrap` string fails this gate on a small window — by design; shrink the
copy (RULE F-4), never the budget.

**RULE F-4 — a statement that cannot fit is authored as multiple lines, never
shrunk.** On a surface at or above the 300 px reference, an element marked
`data-oneline` must render on **exactly one line**, and its measured text width
must be `<= the surface's content width`. Below the reference the rule is
**not enforced** — the line wraps instead (never clips, never shrinks below the
floor).
Check: line count from `scrollHeight / line-height`, plus the probe width against
the measured content width. Measured at 1280×720 and 720×1280: **13 of 13
one-line prompts render on 1 line**, widest **295.4 px vs 300 px** content width
("GRAB THE PEN - PULL BACK - LET GO" — the `Beat.TEACH` cue). At 360×640 the
surface is 176 px (ratio 0.587), the rule is out of scope, and 10 prompts wrap —
reported, not failed. Two prompts had to be shortened to reach 11/11 before the
real cue strings landed (§11 item 2); the count is now 13 and the cue was moved
from a padded chip to a full-width bar to hold its single line (§11 item 6).

**RULE F-5 — the load-bearing gates.** FIT-1 (`document.scrollWidth`) and
"element `scrollWidth` vs `clientWidth`" are **necessary but not sufficient**: a
prompt that blows out inside a clipped `.pane` passes both — measured, §11. The
gates that actually decide prompt copy are the measured-text gates F-3/F-4 and
the geometry gate F-7.

**RULE F-6 — prompt copy changes are visual-system changes.** If copy must grow,
either split it into explicit lines (the match-over precedent) or step the size
down in 2 px increments to a floor of **13 px** (turn-gate pattern: 44 → 18 in
2 px steps; menus: 15 → 13 in 2 px steps). Never below RULE T-1's floor.
Check: nothing in the sheet is painted below its tier minimum (`T-3`/`TYPE`
lines) and the tier census shows the floor tiers in use. Measured: `0 offenders`,
`min rendered font-size=11px`.

**RULE F-7 — nothing leaves its pane.** Every descendant's
`getBoundingClientRect()` must sit inside its `.pane`'s border box (±0.5 px).
Check: per-descendant rect comparison against the pane rect.
Measured: **0 spill across 8 panes** at all three viewports. This gate caught a
decorative punched hole hanging 1 px below a 392 px page — fixed by moving the
holes to 70 / 210 / 350 px.

**RULE F-8 — a panel that contains a prompt is a pane, and panes are counted.**
An empty or collapsed shape is a defect; the sheet reports `panes=8` and
`pens=9 with a non-zero box`.
Check: every `.pane` counted, every identity shape with a non-zero bounding box
(`SHAPES` line). Measured: `panes=8 (no pane clips its content) :: PASS`,
`pens=9 with non-zero box :: PASS`.

---

## 6. How the tradeoff is stated in words

Pillars in play: *Visible Physics* (no hidden numbers) and *Legible Identity*
(the game names the pen on the table). `CONTEXT.md`: "no numeric stat page — the
tradeoff is stated in words on the pen itself". `DECISION.md` fixes the four
identities, one lever each.

**RULE W-1 — exactly two lines per pen: `Strength.` then `Cost.`** Both are `t3`
statements, both use `data-oneline` (RULE F-4), and the pen's name sits on the
same row as its lever word.

| pen | lever | Strength. | Cost. |
|---|---|---|---|
| Cobalt | CONTROL | straight, balanced, repeatable. | Nothing added: no reach, no spin. |
| Graphite | ANCHOR | Heavy. Holds its line, barely turns. | Reach: it lands short of Cobalt. |
| Ivory | GLIDE | Keeps sliding when others stop. | It can slide itself off the table. |
| Amber | SPIN | Carries spin further than any pen. | Its edge is the least proven one. |

Check: for every `#card-TRADEOFF .power` block, exactly **two** `.wl` lines exist,
the first text node starts with the literal word `Strength.` and the second with
`Cost.` — a third line, a missing line or a renamed label fails.
Measured: `pens=4 :: PASS no hidden stats`.

**RULE W-2 — nothing numeric, ever, on the tradeoff surface.** No digits-as-stats,
no bars, no percentages, no units, no ratings, no "×1.2".
Check: zero `[0-9]` characters in any `t3`/`t4b` text node inside
`#card-TRADEOFF`. Measured: **PASS 0 of 10**.

**RULE W-3 — vocabulary split.** The two rulesets are named **`Classic`** and
**`Pen Powers`**, are presented as a **Ruleset**, and are never called a "mode".
The Game Mode screen's own text must not name either ruleset; the Ruleset screen's
text must not contain the word "mode".
Check: regex over the *screen* text only (`.pane` text — card captions, sheet
notes and rationales are documentation chrome and are excluded).
Measured: **PASS**. Building this check caught a real leak: the Game Mode screen's
footnote said "Classic / Pen Powers is the Ruleset and lives on its own page" —
moved off the screen into the sheet note.

**RULE W-4 — Classic is the default and normalizes every pen to one profile**,
stated on the option row: "Every pen runs the same physics." Under Classic the pen
is cosmetic identity and the pen card says so, in words:
"In Classic they all run the same physics" (the pen card's own sentence — the
sheet never uses the word "cosmetic", which would be a stat word in disguise).
Check: the exact sentences above must be present as text in `#card-TRADEOFF` and
in the pen card respectively.
Measured: `PASS | PASS`.

**RULE W-5 — Pen Powers shows all four pens' Strength + Cost before the first
flick**, in one place, with the Ruleset choice: no progressive disclosure, no
hover-to-reveal, no page to hunt for.
Check: `#card-TRADEOFF` holds exactly 4 `.power` blocks, 8 `.wl` lines total, and
names both `Classic` and `Pen Powers`.
Measured: `options=2 pens=4 word-lines=8 :: PASS`.

**RULE W-6 — both players' picks are visible on the pen surface itself** (tags
`P1 · EQUIPPED` / `P2`), and a mirror pick (both pens the same) is legal and
renders with no error and no warning.
Check: `#card-PENS` carries `>= 4` `.tag` elements whose text includes both `P1`
and `P2`, and the pane states in words that a mirror is legal.
Measured: `tags=4 [P1 · EQUIPPED P2 OPEN OPEN] :: PASS`.

---

## 7. Screens: must-contain, one-line rationale, enum mapping

**Mapping (reconciled against `FLOW-FTUE.md`, which landed mid-build).**
`docs/prototypes/ftue/FLOW-FTUE.md` now exists and declares
`enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }` — a **beat** axis
separate from the app-flow `Screen` axis (`FLOW-FTUE.md:24`). So the beats are
cited as `Beat.*`, the menus as `Screen.*`, and the panes inherit both vocabularies
without inventing enum members. Nothing in this file edits that one.

| # | pane (spec sheet) | parent enum / beat | must contain | rationale (one line) |
|---|---|---|---|---|
| 1 | HOME / START | `Screen.HOME` | title `t0`, eyebrow `t5`, exactly **one** primary button (`t2`, ink-filled), at most two outline buttons, mono flavor line | The desk is one decision deep, so the page offers one primary action. |
| 2 | Game Mode | `Screen.MODE` (Game Mode axis) | two option cards: `Hot Seat` (two people, one device, hand it over every flick) and `Solo` (one human, the Rival Circuit, three rivals in order) | Game Mode and Ruleset are separate axes, so they get separate pages with separate vocabulary. |
| 3 | Pens | `Screen.PENS` | 2×2 pen cards, each: pen shape, name `t1`, state tag `t5` (`P1 · EQUIPPED`, `P2`, `AVAILABLE`), one `t3` line saying whether this is cosmetic | Pen Model is a visible identity, not a stat: same size and shape in both rulesets. |
| 4 | Ruleset / tradeoff | `Screen.MODE` → `Beat.TRADEOFF`; entered only when `ruleset == pen_powers` | `Classic` (default, one line of words) vs `Pen Powers`; under Pen Powers all four pens with Strength + Cost in words; one `t5` rule line banning numbers | The tradeoff is stated in words on the pen, because a stat page is the hidden-information defect the design bans. |
| 5 | Rival choice | Solo only → `Beat.RIVAL_CHOICE` (`FLOW-FTUE.md:32`) | `<ol>` of exactly **three** rivals: ordinal, name, one-line habit, lock chip; lock state read from the injected `rivalLocked(i)` callback | An ordered list is the contract: the path is a sequence, so it looks like a sequence. |
| 6 | Settings rows | `Screen.SETTINGS` | one row per setting: label `t2` left, control or right-aligned value `t4b`; rows: Sound, Haptics, Screen shake, Match length, `<P1>`'s pen, `<P2>`'s pen | Rows are one line each — label left, control or value right — so a setting is read without a sentence. |
| 7 | First-shot cue | over `Screen.PLAYING` → `Beat.TEACH` then `Beat.FIRST_SHOT` | the two real cue strings, verbatim from `FLOW-FTUE.md:30-31`, as full-width cue bars on the **desk** surface (`GRAB THE PEN - PULL BACK - LET GO`, then `FIRST FLICK - PULL BACK, LET GO`), the 3-step diagram chips (grab / pull back / let go), the live turn's persistent hint strip, and a `t3` rule line stating the cue dies on `on_drag_started()` and never re-arms this turn | The drag is the real gesture, so the cue names the three moves of that gesture and then removes itself. |
| 8 | Loading | `Screen.BOOT` | three stages in verb + object form (`Boot files`, `Read settings`, `Build the table`), one marked current; a `t3` rule line stating the screen is shown only while work is outstanding | Feedback is bound to real work; a fake delay is a lie the player pays for on every launch. |

**RULE SC-1 — one primary action per page.** At most one `.btn.primary` per pane.
Check: count per pane `<= 1`. Measured: **PASS** (0 panes over).

**RULE SC-2 — every pane is a real screen, not a fragment.** Each **menu** pane
carries a `t0` title and at least one control or value readout; the desk pane
(the play state) carries at least one cue element instead of a menu title.
Check: `.pane:not(.deskpane)` must each own a `[data-tier="t0"]` and an element
matching `.btn, .opt, .row, .stage, .pencard, .rival`; `.pane.deskpane` must own
`>= 1` `.cuebar`/`.cuechip`.
Measured: `7 of 7 :: PASS | desk pane cues=5 :: PASS` (8 panes total: 7 menus +
1 desk).

**RULE SC-3 — one-line, non-overlapping layout is asserted geometrically**:
RULES F-7 (inside the pane) and P-6 (legible on its surface) replace "looks fine".
A screenshot is evidence for a human, never the gate.

**RULE V-4 — cue voice (answers the open question at `FLOW-FTUE.md:249-251`).**
The visual system **keeps the terse uppercase voice** and **adopts the cap as a
rule**: a cue string is `<= 48` chars (`MAX_CUE_CHARS`), uppercase, ASCII-only
(`0x20-0x7E`), trimmed, with no doubled space — the same invariant the logic test
already asserts, so the cap is never re-decided after the fact. A cue string is
rendered in the `cue` tier (15 px bold) as a **full-width cue bar, not a padded
chip**: a 33-char cue measures 295.4 px, which fits the 300 px reference surface
only without horizontal padding (RULE F-4 is what caught the chip form).
Check: every `[data-cue]` satisfies length/uppercase/ASCII/trim, and `>= 2` cue
strings exist. Measured: **2 cue strings, longest 33 chars, 0 violations → PASS**.

---

## 8. Rival lock state (owned by a callback, not by this design)

**RULE R-1 — the list is ordered and has exactly three entries.** Check:
`#card-RIVAL li.rival` length `=== 3`, each with an ordinal mark `.ord`.
Measured: **`li.rival=3` with `3` ordinal marks → PASS**.

**RULE R-2 — the lock state comes from an injected callback.** The menu reads
`rivalLocked(index) -> bool` (placeholder signature; the real one belongs to
ticket #10) and renders: unlocked → name + habit + `OPEN`; locked → dimmed row +
`LOCKED` chip + a reason line. This design **does not encode** unlock progression
rules, thresholds or win counts; the spec sheet hardcodes a demo array
`[false, true, true]` and says so on the pane.
Check: `#card-RIVAL` shows the callback signature and the demo array as code, and
both a locked and an unlocked row render (so the lock state is visibly
data-driven, not designed-in). Measured: `rivalLocked(index: int) -> bool`,
`demo values on this sheet: [false, true, true]`, 2 locked of 3 rows.

**RULE R-3 — a locked row is still readable.** Dimming is a colour change on the
row's ink (`opacity:.62` + a dashed border), never a font-size change: the row
keeps its `t1` name at 18 px and the reason line stays `>= t5` (11 px).
Check: every `li.rival.locked .rname` computes to `>= 18px`. Measured:
**2 locked rows, both at 18 px → PASS**; all rows also pass RULES T-1/T-2.

---

## 9. Loading (real work only)

**RULE L-1 — no fake delay.** Minimum display time is **0 frames**: the loading
screen is shown only while work is outstanding and disappears the frame the work
finishes. Check: no timer/animation-only state in the surface's spec; every stage
names real work (L-2).

**RULE L-2 — every stage names work: verb + object, `>=` 2 words, and none of
`Loading…` / `Please wait` / `Working…` / `Just a moment` / `Preparing…`.**
Check: each `.stage .sname` must have `>= 2` whitespace-separated words and must
not match `^(loading|please wait|working|just a moment|preparing)\b`; and there
must be `>= 2` stages. Measured: **3 stages, 0 banned → PASS**.

**RULE L-3 — no progress bar without a known total.** A determinate bar requires
a real total; otherwise show the stage list. Check: inside `#card-LOADING`, no
element whose `style` contains a `%` width unless it also carries `data-total`.
Measured: **0 bars, 0 `data-total`, 0 offenders → PASS** (the pane has no bar at
all: three stages, one marked current).

---

## 10. Gates — exact commands

Binaries (the path quoted in the ticket does not exist — the real dir is
`chrome-linux64`, **not** `chrome-linux`):

```
SHELL=/home/ubuntu/.cache/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-linux64/chrome-headless-shell
CHROME=/home/ubuntu/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome   # needs an explicit --headless
URL=file:///home/ubuntu/pen-fight/docs/prototypes/ftue/visual/index.html
```

Spec-sheet self-check — renders, executes every rule, prints every verdict.

**Pipe the DOM to a file, never through a pipe into a truncating reader.** The
readout plus the inlined CSS is ~59 KB; a harness that caps stdout near 50 KB will
hand you a DOM dump with the `</pre>` missing, and a naive extractor then reports
"no readout" for a page that passed. The commands below redirect to `/tmp` and read
the file back:

```
"$SHELL" --no-sandbox --disable-gpu --hide-scrollbars --virtual-time-budget=3000 \
  --window-size=1280,720 --dump-dom "$URL" > /tmp/pf-ftue-visual/dump-1280x720.html
python3 - <<'PY'
import html, re
d = open("/tmp/pf-ftue-visual/dump-1280x720.html", encoding="utf-8", errors="replace").read()
print(html.unescape(re.search(r'<pre class="readout"[^>]*>(.*?)</pre>', d, re.S).group(1)))
PY
```

`--dump-dom` alone (piped) is enough only if you want the one-attribute summary
below. Repeat the same pair for `--window-size=720,1280` and `--window-size=360,640`.

The sheet writes the verdict to `<body data-selfcheck="PASS|FAIL"
data-inner-width data-doc-width>`, so this also works as a one-line gate:

```
"$SHELL" ... --dump-dom "$URL" | grep -o 'data-selfcheck="[A-Z]*"'      # -> data-selfcheck="PASS"
```

Screenshots (written to `/tmp`, deliberately **not** in the repo — no binaries):

```
"$SHELL" ... --window-size=1280,720  --screenshot=/tmp/pf-ftue-visual/spec-1280x720.png  "$URL"
"$SHELL" ... --window-size=720,1280  --screenshot=/tmp/pf-ftue-visual/spec-720x1280.png  "$URL"
"$SHELL" ... --window-size=360,640   --screenshot=/tmp/pf-ftue-visual/spec-360x640.png   "$URL"
"$SHELL" ... --window-size=1280,4400 --screenshot=/tmp/pf-ftue-visual/spec-1280x4400-fullsheet.png "$URL"
```

---

## 11. Measured results

### 11.1 Positive runs — `ALL CHECKS PASS` at all three viewports

| viewport | innerWidth | `document.scrollWidth` | overflow | budget | widest nowrap | min font | one-line (F-4) | content width |
|---|---|---|---|---|---|---|---|---|
| 1280×720 | 1280 | 1280 | **0 px** | 1216 px | 295.4 px | 11 px | **13/13 on 1 line** | 300 px (ratio 1.000) |
| 720×1280 | 720 | 720 | **0 px** | 656 px | 295.4 px | 11 px | **13/13 on 1 line** | 300 px (ratio 1.000) |
| 360×640 | 360 | 360 | **0 px** | 296 px | 295.4 px | 11 px | out of scope, 10 wrapped | 176 px (ratio 0.587) |

Prompt census: `count=56 (data-nowrap=33)`, box-fit `0 of 56`. Panes `8`, 0 spill.
Pens `9`, none collapsed. Tier census `t0=7 t1=15 t2=13 cue=5 t3=15 t4b=3 t4=6
t5=30`. S-2 `8 surfaces` at scale `1.000`. R-1 `li.rival=3, ordinals=3`;
R-3 `2 locked rows at 18px`; V-4 `2 cues, longest 33`. P-1 `left=32px right=32px`, P-4
`33px`, P-5 `0 leaks`, P-6 `152 nodes, 0 bare`, W-2 `0 of 10`, W-3 PASS, SC-1 PASS,
L-2 `3 stages`, W-1 `pens=4`, W-4 `PASS | PASS`, W-5 `options=2 pens=4
word-lines=8`, W-6 `tags=4`, SC-2 `7 of 7 + desk cues=5`. SCALE `k=1.6267`,
floor `17.89 px`, production 21/19/22 all PASS. T-3 `0 offenders`, P-3
`html=visible body=visible`, L-3 `0 bars / 0 offenders`, FIT-1c `clippers=8,
hiding content=0`.
**33 named check lines**, of which **30 carry a `PASS` verdict** at 1280×720 and
720×1280 (the `FIT-4b`, `TYPE` tier-census and `SCALE` floor line are censuses
with no verdict) and **29 at 360×640**, where `FIT-4` reports
`NOT ENFORCED below the 300px reference surface; wrapped=10` by design. The
verdict line is `=== ALL CHECKS PASS @ 1280x720 ===`.

Screenshot bytes (re-taken against the final file, `--hide-scrollbars`):
`spec-1280x720.png` **407183**, `spec-720x1280.png` **493010**,
`spec-360x640.png` **139180**, `spec-1280x4400-fullsheet.png` **1354666** — all
four verify as PNG (`89 50 4E 47` magic).
(`assets/design/render.sh --out /tmp/pf-ftue-visual` reproduces these paths.)
Line counts: `index.html` **1018 lines / 60793 B** (frozen — re-measure after any edit).
`VISUAL.md` is prose and grows with each edit, so it is not gated.
Self-containment re-counted on the
final file: `http(s):// = 0`, `src= = 0`, `<link = 0`, `@import = 0`,
`url(` with a non-`data:` target `= 0`.

**Full Chrome cross-check** (different layout path, classical scrollbars visible,
`--headless=new`): 1280 → `innerWidth=1280 document.scrollWidth=1280` (**0 px**
horizontal overflow, verdict `ALL CHECKS PASS @ 1280x633`); 720 →
`720 / 720`, 0 px overflow, `ALL CHECKS PASS @ 720x1193`. Chrome's layout viewport
is 87 px shorter than the window in both cases (new-headless reserves that height),
which is why `assets/design/render.sh` prefers the headless shell.

### 11.2 Negative controls — the gates can fail

Two `/tmp` copies of the sheet, each with one injected defect.

**Control A — an over-wide authored prompt** (a 225-char string on a
`data-nowrap` line in the Ruleset pane; it wraps, because `data-nowrap` is an
authoring marker and carries no CSS):

| gate | positive run | control A |
|---|---|---|
| FIT-1 `document.scrollWidth` | PASS 0 px | **PASS 0 px** ← insufficient |
| FIT-1b element `scrollWidth` vs `clientWidth` | PASS 0 of 56 | **PASS 0 of 57** ← insufficient |
| FIT-1c clippers hiding content | PASS 8 clippers, 0 hiding | PASS 8 clippers, 0 hiding |
| FIT-2 measured nowrap text vs budget | PASS 295.4 ≤ 1216 | **FAIL 1380.7 > 1216** (and 1380.7 > 296 at 360) |
| W-1 two word-lines per pen | PASS `pens=4` | **FAIL `Cobalt:lines=3`** |
| verdict | `ALL CHECKS PASS` | `CHECKS FAILED` @ 1280 and @ 360 |

**Control B — text that is genuinely clipped** (same insertion point, this time
with an inline `white-space:nowrap`, so the layout really overflows):

| gate | positive run | control B |
|---|---|---|
| FIT-1 `document.scrollWidth` | PASS 0 px | **PASS 0 px** ← blind to clipping |
| FIT-1b element box-fit | PASS 0 of 56 | **FAIL 1 spill: `P.wl scrollW=1671 clientW=300`** |
| FIT-1c clippers hiding content | PASS `clippers=8 hiding content=0` | **FAIL 1: `pane(1715>366w,901>901h)`** |
| verdict | `ALL CHECKS PASS` | `CHECKS FAILED` |

Control B is the important one: `.pane{overflow:hidden}` (the frame's rounded
corners) silently hides 1349 px of content, `FIT-1` still reports `overflow=0px`,
and only the hardened `FIT-1c` sees it. That is why `FIT-1c` measures every
`overflow != visible` element's `scrollWidth`/`scrollHeight` against its client
box instead of trusting `document.scrollWidth`.

Reproduce:
```
python3 - <<'PY'
p = "/home/ubuntu/pen-fight/docs/prototypes/ftue/visual/index.html"
s = open(p).read()
a = '<p class="wl" data-tier="t3" data-prompt data-oneline><b>Cost.</b> Nothing added: no reach, no spin.</p>'
assert a in s
long = "Reach measured against the flick, the paper, the table and the entire desk " * 3
# Control A: wraps (no CSS), caught by the text-width probe
open("/tmp/pf-ftue-visual/negative-control.html","w").write(
  s.replace(a, '<p class="wl" data-tier="t3" data-prompt data-nowrap>' + long + '</p>\n' + a, 1))
# Control B: really overflows -> clipped by the .pane frame
open("/tmp/pf-ftue-visual/negative-clip.html","w").write(
  s.replace(a, a + '\n<p class="wl" style="white-space:nowrap" data-tier="t3" data-prompt>CLIP PROBE '
            + "over-wide unwrappable content " * 8 + '</p>', 1))
PY
"$SHELL" --no-sandbox --disable-gpu --hide-scrollbars --virtual-time-budget=4000 \
  --window-size=1280,720 --dump-dom file:///tmp/pf-ftue-visual/negative-clip.html > /tmp/out.html
```

### 11.3 Defects these gates caught while building the sheet

1. **F-7** — a decorative punched hole hung 1 px below a 392 px page (3 holes all
   past the bottom edge) → holes moved to 70 / 210 / 350 px.
2. **F-4** — two pen Strength lines wrapped at the 300 px design surface
   ("…Your flick is the flick.", "Light. Keeps sliding when others stop.") → copy
   shortened; 13/13 now one line.
3. **P-6** — multi-line cream text sat directly on the desk gradient at 2.45–3.32:1
   (the rationale lines, card notes, card heads, the cleared-cue line) → all given
   the `a = 0.42` backer; 5.87–8.68:1.
4. **W-3** — the Game Mode screen named the rulesets in its footnote → moved to the
   sheet note; the check now scopes to screen text only.
5. **P-5 / T-2** — the first-shot cue chips were 11 px mono (an eyebrow tier doing a
   cue's job) → promoted to the `cue` tier at 15 px bold; the tier census proves
   the tier is actually used (`cue(15)=5`).
6. **F-4, second pass** — after the cue strings were replaced with the real ones
   from `FLOW-FTUE.md`, the 33-char cue measured 295.4 px and **wrapped to two
   lines inside a padded chip** (295.4 + 20 px padding > 300 px surface) → the cue
   is now a full-width bar (no horizontal padding), 13/13 one line. The element
   changed; the rule did not.
7. **S-2 / R-1 / R-3 / V-4** were added as checks *after* `FLOW-FTUE.md` landed, so
   the two documents agree on the beat enum, the cue cap and the rival list shape:
   the reconciliation found no contradiction, and RULE V-4 is the written answer to
   that document's open question §10.1 (`FLOW-FTUE.md:249-251`).
8. **FIT-1c, hardened** — the first version of this gate compared `.pane`
   `scrollWidth` with `clientWidth`, but `.pane` was already `overflow:hidden` for
   its rounded corners, so it reported PASS on a page that was silently clipping
   1349 px of content (control B). It now walks **every** element whose computed
   overflow is not `visible` — `clippers=8` on the positive run, all eight being
   `.pane` frames that hide nothing — and fails if any of them hides content.
9. **F-6, W-4, W-5, W-6, SC-2 and the W-1 check** were added to close the
   doc-to-artifact loop: every rule that stated a "Check:" now has a matching line
   in the readout, and every readout line maps back to a rule id. The gates caught
   real copy defects twice (items 2 and 6) and a real false-negative gate once
   (item 8); they have never been relaxed to pass.

---

## 12. Assumptions and things this file does not decide

1. **Rival names** on the sheet (`CHALK`, `INK RED`, `VELLUM`) are placeholders
   for ticket #10's authored rivals, marked `data-placeholder="rival-name"`. The
   deliverable is the row format, not the names.
2. **Rival unlock rules** are not decided here (RULE R-2: a callback).
3. **Screen/beat enum membership** is *not* invented here: `docs/prototypes/ftue/
   FLOW-FTUE.md` (which landed while this was being built) declares
   `enum Beat { TEACH, FIRST_SHOT, RIVAL_CHOICE, TRADEOFF, PLAY }`, and §7 cites
   `Beat.*` for the beats and `Screen.*` for the menus. If that file renames a
   member, only the "parent" column changes — no visual rule moves.
4. **Prompt copy wording** is the visual system's format; the physics behind the
   words is `DECISION.md`'s. Rewordings are copy edits that still obey RULES
   F-3/F-4/F-6.
5. **A fourth pen colour** extends §6's table; the two-line Strength/Cost format
   and RULE W-2 do not change.
6. **Screenshots are not committed** — the sheet is reproducible from HTML alone.
7. **The sheet is the gate, not a person.** No automated visual review (vision
   model) was available when this was built, so RULES F-7/P-6 are the geometric
   and token stand-ins for "it looks right". If a human reviews the screenshots and
   finds a defect these gates missed, that defect becomes a new rule here.
