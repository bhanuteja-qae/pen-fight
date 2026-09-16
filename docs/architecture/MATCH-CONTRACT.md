# Match contract — frozen decision for issue #6

**Status:** Frozen architecture decision. This document defines the target contract; it does not claim that the migration has been implemented.

**Decision base:** repository commit `5a3c78d7cd145dbd6a834b4b00d0732e1a140d65`, `docs/design/multiplayer-audit.md`, issue #6 and its draft discussion, and the accepted decisions from the app-flow, pen-profile, and policy-bot prototypes. Where the draft discussion offered alternatives, this document records the frozen choice rather than treating the draft as accepted wholesale.

## Purpose and boundaries

A game session constructs one validated `MatchConfig` at match start. That immutable snapshot identifies the two participants and every match-scoped choice needed by runtime orchestration. Human input, the `AutoFlick` harness, and any future production bot express a flick as the same `ShotCommand` and submit it through one atomic session boundary: `Main._submit_shot`.

This decision deliberately does **not** move participant, controller, pen-selection, seed, or persistence concerns into `TurnState`:

- `TurnState` remains the existing pure-logic state machine and keeps its current constructor and public behavior.
- `red` and `blue` remain internal slot IDs. They are not identities, display names, controllers, or UI copy.
- `PenBody` remains the only layer that converts normalized shot power into physical impulse using `MAX_IMPULSE`.
- Persistence schema and legacy-key migration belong to issue #7. `MatchConfig` is a per-match snapshot, not a save-file model.
- The policy bot under `game/prototypes/policy_bot/` is prototype evidence, not a shipped production bot. Production promotion and Rival selection remain deferred through issue #10.

## Frozen plain-data shapes

These are plain data values. They must not extend `Node`, access the scene tree, apply physics, read or write persistence, or contain producer-specific behavior.

```gdscript
Participant {
    slot: String             # "red" | "blue"; internal only
    kind: String             # "local_player" | "rival"
    display_name: String     # non-empty player-facing identity
    controller: String       # "human" | "bot"
    pen_model: String        # "amber" | "cobalt" | "graphite" | "ivory"
    pen_profile: String      # effective profile for this match
    bot_profile: String      # "" for human; production registry ID for bot
}

MatchConfig {
    mode: String                     # "hot_seat" | "solo"
    ruleset: String                  # "classic" | "pen_powers"
    best_of: int                     # 1 | 3 | 5 | 7
    seed: int                        # effective nonzero match seed
    participants: Array[Participant] # exactly two; red then blue
}

ShotCommand {
    slot: String             # "red" | "blue"
    direction: Vector2       # finite unit vector
    power: float             # finite, inclusive 0.0..1.0
    contact_offset: float    # finite, inclusive -1.0..1.0
    source: String           # "human" | "bot" | "harness"
}
```

The concrete implementation may use typed `RefCounted` value classes or equivalent dictionaries, but the field names, meanings, ranges, and validation below are frozen. These values are data carriers, not services.

### `Participant` invariants

1. A config contains exactly one `red` participant and one `blue` participant, in that order. Slot order is an internal adapter for the existing `TurnState.new(["red", "blue"], ...)` contract; gameplay and UI code should resolve participants by slot rather than treating array position as identity.
2. `display_name.strip_edges()` must be non-empty. Player-facing prompts, HUD, results, and accessibility text render this value, never the slot ID.
3. V1 pairings are strict:
   - `local_player` uses controller `human` and `bot_profile == ""`.
   - `rival` uses controller `bot` and a non-empty, registered production bot-profile ID.
4. `hot_seat` contains two local-player/human participants. `solo` contains exactly one local-player/human participant and one rival/bot participant; either participant may occupy either internal slot.
5. `pen_model` is one of the four fixed model IDs.
6. `pen_profile` is the **effective**, already-resolved profile for the whole match:
   - `classic`: both participants use `control`, regardless of model.
   - `pen_powers`: `cobalt -> control`, `graphite -> anchor`, `ivory -> glide`, and `amber -> spin`.
   Profiles are locked at match start. No round, rematch, input source, or bot policy may change them inside the snapshot.
7. The current repository has no production bot-profile registry. Therefore the contract can represent `solo`, but current production code must not pretend it can build a valid solo config. The prototype persona IDs and `PolicyBot.commit()` are not production registration.

### `MatchConfig` construction and immutability

A single builder/factory validates all fields, deep-copies the two participants, resolves the seed, and only then publishes the snapshot. On validation failure, match creation fails as a whole; it must not silently substitute a participant, slot, mode, ruleset, model, profile, or bot profile.

`seed` is match-scoped and has these exact semantics:

- A nonzero requested seed becomes the effective `MatchConfig.seed` unchanged.
- A requested seed of `0` means “generate an effective seed.” Construction must choose a nonzero integer, store that nonzero value in `MatchConfig.seed`, and log the effective value once with the match-start diagnostic.
- Consumers seed match-scoped software randomness from the effective value: bot judgment noise, `AutoFlick`/harness random choices, and any future randomized match setup.
- The seed does not claim to make Godot physics bit-deterministic; current physics can vary between runs.
- The snapshot never contains `0`, so downstream consumers have no separate “random seed” branch.

After construction, no field or nested participant may change. Settings edits and persistent-state updates affect a later match, not the active snapshot. Implementations must not expose a mutable participant array or mutable participant references. A rematch creates a new snapshot, even if every value happens to match the prior one.

Issue #7 decides which source values are durable, how legacy keys migrate, and whether/how the effective seed is persisted. Issue #6 requires runtime logging of the effective seed but does not add `last_match.cfg`, mutate `settings.cfg`, or otherwise choose persistence policy.

## `ShotCommand` semantics

`ShotCommand` records intent in the same units for every producer:

- `direction` is normalized launch direction, separate from magnitude.
- `power` is normalized input power, not a physical impulse and never pre-scaled by `1600`.
- `contact_offset` is a first-class physics input: signed grip position along half the pen length (`-1` tip, `0` center, `+1` cap). It is not a human-only gesture detail. Bots and harnesses may choose `0.0`, but may not omit the field.
- `source` identifies where the command came from for diagnostics and analytics. It is **attribution, not authority**: it cannot bypass locks, grant a turn, select a different participant, alter validation, or change physics. In this offline in-process design it is not an authentication credential. A recognized source value is required, but acceptance is decided by session state and `slot`, not by comparing `source` with `Participant.controller`.

### Boundary validation and rejection

`Main._submit_shot(cmd: ShotCommand) -> bool` is the only runtime/session-orchestration consumer. It validates the complete operation before mutating `TurnState` or a pen. Validation is performed in this order, though all failures have the same no-op result:

1. An active game session and immutable `MatchConfig` exist.
2. `cmd` and every required field exist and have the declared type.
3. `slot` is exactly `red` or `blue` and resolves to one participant and one live `PenBody` in the active session.
4. `source` is exactly `human`, `bot`, or `harness`.
5. `direction` is finite, nonzero, and unit length within `DIRECTION_EPSILON = 0.001` (`abs(direction.length() - 1.0) <= 0.001`). Producers normalize before construction; the boundary does not repair a malformed direction.
6. `power` is finite and in inclusive range `0.0..1.0`. The boundary rejects rather than clamps.
7. `contact_offset` is finite and in inclusive range `-1.0..1.0`. The boundary rejects rather than clamps.
8. `TurnState` is in `PHASE_AIM`, `cmd.slot == turn_state.current_player()`, and shot intake is open: no handoff/round-over gate, settings or blocking modal, input lock, ended match, or teardown is active.
9. The resolved pen is the active pen for `cmd.slot` and is ready to receive exactly one flick.

Any failed check returns `false`, emits one diagnostic warning containing the rejection reason plus `slot` and `source` when available, and otherwise performs a hard no-op: no `TurnState.on_flick`, no `PenBody.apply_flick`, no haptics/audio, no aim-overlay clear, and no partial bookkeeping. Values are not clamped, normalized, redirected to the other slot, retried, or queued for a later turn.

After all checks pass, the boundary performs one synchronous commit:

```gdscript
turn_state.on_flick(cmd.direction * cmd.power)
pen.apply_flick(cmd.direction, cmd.power, cmd.contact_offset)
# accepted-shot feedback follows the successful commit
```

It then returns `true`. `TurnState` records exactly `direction * power` in its existing `_last_impulse`; there is **no `1600` scaling in `Main` or `TurnState`**. `PenBody.apply_flick` alone performs `direction * power * MAX_IMPULSE` (`MAX_IMPULSE == 1600.0` at the decision base). A second submission loses the race deterministically because the first accepted command moves `TurnState` out of `AIM`; the second is rejected without touching physics.

The order above preserves the existing rule that committed Flick physics is authoritative while preventing a malformed command from advancing state without a pen impulse. Feedback is downstream of acceptance and cannot authorize or alter the shot.

## Producer adapters

All producers stop at `ShotCommand`; none calls `TurnState.on_flick` or `PenBody.apply_flick` as part of runtime/session orchestration.

### Human

`AimInput` keeps gesture ownership. Its existing release math already produces a normalized direction, `0..1` power, and `-1..1` contact offset. `Main._on_flick_ready` becomes a thin adapter that builds:

```gdscript
ShotCommand(slot = active_slot,
            direction = direction,
            power = power,
            contact_offset = contact_offset,
            source = "human")
```

and immediately returns `_submit_shot(cmd)`. It contains no second phase/slot/physics path.

### `AutoFlick` harness

`AutoFlick` remains a debug/test harness, not a production bot. Its scheduling and seeded random-choice helpers may remain, but at fire time it builds or emits a complete `ShotCommand` with `source = "harness"`. Its legacy full-vector payload is split as follows: for nonzero intent, `direction = intent.normalized()` and `power = intent.length()`; an out-of-range or zero-direction result is rejected by the same command validation rather than receiving a special harness rule.

`Main._on_auto_flick_requested` and its duplicated state/pen application logic are removed in the final migration. The harness connects to the same `_submit_shot` boundary as human input.

### Future production bot

There is no shipped production bot today. The `PolicyBot` implementation under `game/prototypes/` remains a prototype and its direct `PenBody.apply_flick` call is not evidence of production integration. If issue #10 promotes a bot policy, the production adapter must convert the chosen candidate into a `ShotCommand` with `source = "bot"` and submit it through `_submit_shot`; it receives no direct physics API and no source-based bypass.

## Exact migration plan

The implementation change that follows this decision must land the following sequence as one coherent migration, without a period where two runtime shot paths are authoritative:

1. Add the three plain-data types plus one `MatchConfig` builder/validator. Keep them free of scene, physics, settings-store, and persistence dependencies.
2. At game-session start, build one config from already-loaded inputs. For the current hot-seat product, adapt existing state exactly as follows: `mode = "hot_seat"`, `ruleset = "classic"`, `best_of = SettingsStore.match_length`, requested seed `0` unless explicitly supplied; for each slot, set `display_name = Main._display_name(slot)` and select `pen_model` from `SettingsStore.pen_red` or `SettingsStore.pen_blue`; make both participants `local_player`/`human` with effective profile `control` and `bot_profile = ""`.
3. Store the validated config as the active match snapshot. Derive display names, model assignment, effective profiles, and best-of target from it for the life of that match. Continue to instantiate `TurnState` with only `Array[String](["red", "blue"])`, timeout, and table rect; do not change `turn_state.gd`.
4. Add `Main._submit_shot` with the validation and atomic commit rules above. Resolve the active pen and every rejection condition before calling either downstream method.
5. Change the human callback into a `ShotCommand(source = "human")` adapter. Move accepted-shot haptics, audio, and overlay clearing after the successful `_submit_shot` commit.
6. Change `AutoFlick` to produce `ShotCommand(source = "harness")`; connect it to `_submit_shot`. Remove `_on_auto_flick_requested` and every duplicated runtime call to `TurnState.on_flick`/`PenBody.apply_flick` in `Main`/`AutoFlick` orchestration.
7. Leave `PolicyBot` under `game/prototypes/` unchanged as prototype evidence until issue #10 owns production promotion. Do not advertise Solo bot play as shipped merely because the config shape reserves it.
8. Do not rename or migrate `SettingsStore` keys in this change. They are inputs to the snapshot adapter only. Issue #7 owns durable domains, invalid-ID fallback, and migration of `pen_red`, `pen_blue`, `matches_won_red`, and `matches_won_blue`.
9. Add contract tests for config validation/immutability, seed resolution, every command rejection class, one accepted commit, duplicate submission, and producer parity. Update integration tests to route human and `AutoFlick` commands through `_submit_shot`.

## Acceptance and call-site scope

The implementation is complete only when evidence demonstrates all of the following:

- Valid hot-seat configs freeze two correctly mapped participants; invalid cross-field combinations fail construction rather than defaulting.
- Requested seed `0` yields and logs a nonzero effective seed; a supplied nonzero seed is preserved; the active snapshot never exposes `0`.
- Changing settings after match start does not mutate the active config.
- Human and `AutoFlick` submissions with the same slot/direction/power/contact values produce the same `TurnState.state().last_impulse` and the same arguments at `PenBody.apply_flick`.
- `TurnState.state().last_impulse == direction * power`; the physical pending impulse is scaled exactly once, inside `PenBody`, by `MAX_IMPULSE`.
- Every rejection is a hard no-op, including wrong slot, wrong phase, closed gate/modal, ended session, missing pen, malformed direction, out-of-range power/contact, unknown source, and duplicate submission.
- `turn_state.gd` remains pure and unchanged by the migration; it contains no Participant, mode, ruleset, display-name, controller, bot-profile, model, or persistence knowledge.
- Player-facing copy resolves `Participant.display_name`; internal slot IDs are not rendered as identities.
- Runtime/session orchestration has exactly one `TurnState.on_flick` call site and one `PenBody.apply_flick` call site, both inside `Main._submit_shot`.

The final call-site scan is intentionally scoped to **runtime/session orchestration** (`Main`, input adapters, harness adapters, and any future production bot adapter). Low-level unit tests, physics probes, and prototype rigs intentionally call `TurnState` or `PenBody` directly to isolate those components; those calls are allowed and must not be rewritten merely to satisfy a repository-wide grep count. In particular, the current prototype `PolicyBot.commit()` remains outside the production acceptance count until issue #10 promotes or replaces it.

## Grounding in the decision base

At `5a3c78d`:

- `AimInput._release` already emits normalized direction, normalized power, and contact offset (`game/scripts/aim_input.gd:199-208`).
- Human and automated paths duplicate orchestration and can drift (`game/scripts/main.gd:359-415`).
- `TurnState.on_flick` is pure logic and stores its input unchanged (`game/scripts/turn_state.gd:129-146`).
- `PenBody.apply_flick` owns `MAX_IMPULSE` scaling and torque-arm contact (`game/scripts/pen_body.gd:38-42,111-134`).
- `AutoFlick` currently emits a combined direction-times-power vector (`game/scripts/auto_flick.gd:22,62-101,127-133`).
- The current settings keys and best-of choices are `pen_red`, `pen_blue`, `match_length`, `matches_won_red`, and `matches_won_blue`, with lengths `[1,3,5,7]` (`game/scripts/settings_store.gd:23-41,85-110`). Their persistence redesign is issue #7, not this contract.
- `PolicyBot` exists only under `game/prototypes/` and commits directly to a pen (`game/prototypes/policy_bot/policy_bot.gd:82-84`); this contract does not relabel that prototype as shipped code.
