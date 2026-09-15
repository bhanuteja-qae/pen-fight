# Policy-bot Wave 2 metrics

`match_harness.gd` writes the fixed-seed raw sample to
`game/prototypes/policy_bot/results/wave2_seeded_matches.json`. It runs six
two-shot, real-physics series: each persona against the `AutoFlick` debug
emitter, and each unordered persona pair. All shots route through
`TurnState.on_flick(impulse)` and `PenBody.apply_flick(direction, power,
contact_offset)`.

The results table below is populated from the checked-in raw artifact. Rates
are per launched flick. `mean_contact_offset` is mean absolute offset and
`spin_usage` means `abs(contact_offset) >= 0.5`. `settle_time_s` is time from
launch until the state machine leaves `IN_FLIGHT`, so it includes OOB
resolution and the eight-second backstop.

| Persona | shots | backstop_rate | no_impact_rate | oob_rate | mean impulse | mean abs contact | spin_usage | settle_time_s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| hitter | 3 | 0.0000 | 0.0000 | 0.0000 | 0.8900 | 0.2200 | 0.0000 | 2.5000 |
| spin | 3 | 0.0000 | 0.0000 | 0.3333 | 0.6533 | 0.8800 | 1.0000 | 1.9500 |
| edge | 3 | 0.0000 | 0.3333 | 0.6667 | 0.9400 | 0.0000 | 0.0000 | 1.4556 |

Per-series raw values (two alternating shots each) are retained so the mixed
match context is visible rather than hidden by the persona roll-up.

| Seed | Pairing | backstop | no-impact | OOB | impulse | abs contact | spin use | settle s |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 91001 | hitter vs AutoFlick | 0.0000 | 0.0000 | 0.5000 | 0.9296 | 0.4222 | 0.5000 | 1.4250 |
| 91002 | spin vs AutoFlick | 0.0000 | 0.0000 | 0.0000 | 0.5919 | 0.6437 | 0.5000 | 2.4500 |
| 91003 | edge vs AutoFlick | 0.0000 | 0.0000 | 0.5000 | 0.8519 | 0.1821 | 0.0000 | 1.5250 |
| 91004 | hitter vs spin | 0.0000 | 0.0000 | 0.5000 | 0.7850 | 0.5500 | 0.5000 | 1.5417 |
| 91005 | hitter vs edge | 0.0000 | 0.5000 | 0.5000 | 0.9150 | 0.1100 | 0.0000 | 1.4833 |
| 91006 | spin vs edge | 0.0000 | 0.0000 | 0.5000 | 0.7900 | 0.4400 | 0.5000 | 1.9333 |

Signature vectors, expected from the fixed authored candidate sets (the raw
metrics are the evidence that they survive the physics path):

| Persona | Signature vector |
|---|---|
| hitter | 0% spin usage, 0.22 mean contact offset, 0.89 impulse: direct centred hits |
| spin | 100% spin usage and 0.88 mean contact offset, with the lowest impulse (0.6533) |
| edge | highest impulse (0.94), centred contact (0.00), shortest settle time (1.4556 s) |

Working proxy thresholds are deliberately conservative rather than product
acceptance claims: backstop rate ≤ 0.10 (a completed flight should normally
resolve naturally), no-impact rate ≤ 0.35 (most committed flicks should create
an exchange), and no required OOB rate (OOB is tactical/contextual, not a
quality target). Hitter, spin, and edge all clear the backstop proxy (0.0000);
all also clear the no-impact proxy (0.0000, 0.0000, and 0.3333 respectively).
Their raw OOB rates are 0.0000, 0.3333, and 0.6667 respectively; these are
reported as context, not pass/fail thresholds.

These numbers show that a fixed policy can repeatedly author distinguishable
inputs and that those inputs produce bounded, measurable live-physics
exchanges. They do not show that exchanges are credible, fun, fair, or
human-readable: those remain human playtest judgments. Two shots per pairing
(three shots per policy persona) is intentionally a smoke-sized, deterministic
sample, not a balance study; the numbers also do not establish win rate,
tactical competence, or robustness across table layouts and player skill.
