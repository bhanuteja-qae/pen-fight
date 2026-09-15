## Resolution: home / mode / pens / settings / Back flow

**Answer:** 7 screens — `BOOT, HOME, MODE, PENS, SETTINGS, CONFIRM_LEAVE, PLAYING` — with one
pure-logic module (`AppFlow`) owning all Back behavior. HOME fans out to MODE/PENS/SETTINGS; Back
from any of them returns to HOME. `start_match(mode)` (MODE → PLAYING) is the only place a Game
Session is requested; `end_match()`/`confirm_leave()` are the only two places it's torn down. Back
from a live match never exits directly — it always routes through `CONFIRM_LEAVE`, which overlays
the still-mounted match rather than replacing it, so nothing is live behind a menu and nothing is
torn down before the player actually confirms.

**Loading-view verdict:** no manufactured delay. `boot_complete()` is synchronous (no timer, no
counter); the mock proves it by construction — a tap-gated cover, not a spinner. Any future BOOT
screen needs to be backed by real upstream async work (asset/save loads), never a fabricated wait.

**Verification:** re-ran `app_flow_test.gd` clean this session — `app_flow_test: ALL PASS`. Wrote
an independent adversarial driver (not part of the deliverables) covering Back at every screen,
double-Back (including 6x repeated Back from a live match, which safely toggles
`PLAYING ⇄ CONFIRM_LEAVE` forever), start/end_match misuse, settings/mode-switch attempts from
`PLAYING`, and a negative sweep confirming `gameplay_start_requested` never escapes a menu state —
29/29 checks pass. The mock's JS state machine is a verified line-for-line port of the GDScript one. The orchestrator re-ran the adversarial driver at integration: 29 checks, 0 failures.

**Open risks (need a human, not more logic tests):** real device Back-gesture feel;
whether the "match visible behind the leave dialog" affordance reads clearly to players; in-match
settings/pause UX, which is explicitly host-owned and undesigned here; and an actual click-through
of the mock in a browser (only statically verified in this sandbox, no browser available).

Full evidence and rejected alternatives: `docs/prototypes/app-flow/DECISION.md`. Artifacts:
`game/prototypes/app_flow/app_flow.gd`, `app_flow_test.gd`, `docs/prototypes/app-flow/mock/index.html`,
`docs/prototypes/app-flow/FLOW.md`.
