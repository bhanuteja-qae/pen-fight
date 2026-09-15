# pen-profiles — Wave-2 sweeps (mass / linear damping / angular damping)

Wayfinder ticket: *Prototype four readable pen profiles and fair hot-seat rules* (issue #8).
Harness: `game/prototypes/pen_profiles/profile_sweep.gd` (Wave-1 contract,
`docs/prototypes/CONTRACTS-pen-profiles.md`). Raw evidence:
`game/prototypes/pen_profiles/results/*.json`.

All arms here are **seed-paired**: the same 20 seeds `1..20` and the same 4 shots
per seed, so every profile sees the identical shot pattern. Only `RigidBody2D`
runtime properties (`mass`, `linear_damp`, `angular_damp`) change; no production
file, scene, geometry or size is touched.

## Method and yardstick

Each arm config is documented in its result file. The three levers move one
variable at a time off the shipped baseline (`mass 1.0`, `linear_damp 2.0`,
`angular_damp 1.5`):

| lever | profile label | varied | held at baseline |
|---|---|---|---|
| mass (graphite_anchor) | `graphite_anchor` | `mass` ∈ {0.8, 1.0, 1.4, 1.8} | lin 2.0, ang 1.5 |
| linear damping (ivory_glide) | `ivory_glide` | `linear_damp` ∈ {1.0, 2.0, 3.0, 4.0} | mass 1.0, ang 1.5 |
| angular damping (amber_spin) | `amber_spin` | `angular_damp` ∈ {0.5, 1.5, 3.0, 5.0} | mass 1.0, lin 2.0 |

The `profile_name` string is a **label only** — it selects no physics. It is
proven inert below.

**Noise floor (Wave-1, K=20 seeds, 4 shots).** Per-run metric level across the
seed set; sample stddev.

| metric | floor σ | floor mean |
|---|---:|---:|
| `travel_px` | 50.38 | 482.99 |
| `peak_speed` | 128.35 | 1115.39 |
| `settle_time_s` | 0.3245 | 2.3277 |
| `angular_travel_deg` | 49.40 | 129.50 |
| `dispersion_deg` | 12.55 | 38.89 |
| `self_oob_rate` | 0.1791 | 0.1875 |

`contact_impulse` has the same floor as `peak_speed` (128.35) and `timed_out_rate`
is 0 in the floor.

### How to read the paired comparisons

Because arms share seeds, the honest statistic is the **paired per-seed difference**
`arm − baseline`, whose mean cancels the seed sampling spread. Following the
Wave-1 rule, an effect is called **measured** only when
`|paired mean delta| > floor σ` for that metric; otherwise it is **within the
sampling floor**. `paired sd` and `all-same-sign` are shown as supporting
evidence (a small paired sd and a consistent sign mean the effect is reliable,
not luck).

### Control check (determinism)

The `mass 1.00`, `lin 2.0` and `ang 1.5` arms are physically identical to the
baseline but carry a different `profile_name`. Their per-shot rows are
**byte-identical** to `cobalt_control_baseline.json` (verified with `diff` on the
seeded `shots` arrays; every paired delta is exactly `+0.0000 ± 0.0000`). This
confirms (a) the harness is deterministic, and (b) `profile_name` changes no
physics. It also means three of the required ≥4-value lever points are the
baseline point itself.

## Lever 1 — mass (`graphite_anchor`)

Per-run mean over the 20 seeds:

| mass | travel_px | peak_speed | settle_s | ang_travel | dispersion | self_oob |
|---:|---:|---:|---:|---:|---:|---:|
| 0.80 | 567.47 | 1394.24 | 2.050 | 147.85 | 42.56 | 0.375 |
| **1.00 (baseline)** | **482.99** | **1115.39** | **2.328** | **129.50** | **38.89** | **0.188** |
| 1.40 | 359.97 | 796.71 | 2.465 | 98.89 | 38.12 | 0.050 |
| 1.80 | 282.94 | 619.66 | 2.415 | 78.42 | 38.19 | 0.013 |

Paired delta vs baseline (`✓` = exceeds floor σ):

| mass | metric | Δ mean | paired sd | same sign | floor σ | measured? |
|---:|---|---:|---:|:--:|---:|:--:|
| 0.80 | travel_px | **+84.48** | 23.01 | yes | 50.38 | ✓ |
| 0.80 | peak_speed | **+278.85** | 32.09 | yes | 128.35 | ✓ |
| 0.80 | settle_time_s | −0.278 | 0.292 | no | 0.3245 | no |
| 0.80 | angular_travel_deg | +18.34 | 7.53 | yes | 49.40 | no |
| 0.80 | dispersion_deg | +3.67 | 9.16 | no | 12.55 | no |
| 0.80 | self_oob_rate | **+0.1875** | 0.1791 | no | 0.1791 | marginal |
| 1.40 | travel_px | **−123.02** | 20.77 | yes | 50.38 | ✓ |
| 1.40 | peak_speed | **−318.68** | 36.67 | yes | 128.35 | ✓ |
| 1.40 | settle_time_s | +0.138 | 0.331 | no | 0.3245 | no |
| 1.40 | angular_travel_deg | −30.62 | 13.13 | yes | 49.40 | no |
| 1.40 | dispersion_deg | −0.77 | 12.11 | no | 12.55 | no |
| 1.40 | self_oob_rate | −0.1375 | 0.1898 | no | 0.1791 | no |
| 1.80 | travel_px | **−200.06** | 27.56 | yes | 50.38 | ✓ |
| 1.80 | peak_speed | **−495.73** | 57.04 | yes | 128.35 | ✓ |
| 1.80 | settle_time_s | +0.087 | 0.337 | no | 0.3245 | no |
| 1.80 | angular_travel_deg | **−51.08** | 20.02 | yes | 49.40 | ✓ (just) |
| 1.80 | dispersion_deg | −0.70 | 13.07 | no | 12.55 | no |
| 1.80 | self_oob_rate | −0.1750 | 0.1832 | no | 0.1791 | no |

**Call.** Mass is a strong, monotone lever on `peak_speed` (launch) and
`travel_px`: every tested non-baseline value exceeds the floor on both, with the
same-sign paired delta every seed. It does **not** move `settle_time_s` or
`dispersion_deg` beyond noise at any tested mass, and only `mass 1.8` nudges
`angular_travel_deg` past the floor. The `self_oob_rate` shifts at 0.8 are
marginal (Δ = floor σ exactly); treat OOB as "suggestive, not established".
`mass 1.00` is the baseline (zero delta by construction).

## Lever 2 — linear damping (`ivory_glide`)

Per-run mean over the 20 seeds:

| linear_damp | travel_px | peak_speed | settle_s | ang_travel | dispersion | self_oob |
|---:|---:|---:|---:|---:|---:|---:|
| 1.0 | 689.63 | 1115.39 | 1.993 | 115.34 | 39.71 | 0.762 |
| **2.0 (baseline)** | **482.99** | **1115.39** | **2.328** | **129.50** | **38.89** | **0.188** |
| 3.0 | 336.03 | 1115.39 | 1.822 | 135.15 | 38.81 | 0.062 |
| 4.0 | 253.05 | 1115.39 | 1.534 | 139.20 | 39.76 | 0.000 |

Paired delta vs baseline (`✓` = exceeds floor σ):

| lin | metric | Δ mean | paired sd | same sign | floor σ | measured? |
|---:|---|---:|---:|:--:|---:|:--:|
| 1.0 | travel_px | **+206.64** | 53.20 | yes | 50.38 | ✓ |
| 1.0 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 1.0 | settle_time_s | **−0.335** | 0.782 | no | 0.3245 | ✓ (censored) |
| 1.0 | angular_travel_deg | −14.16 | 12.93 | yes | 49.40 | no |
| 1.0 | dispersion_deg | +0.82 | 8.69 | no | 12.55 | no |
| 1.0 | self_oob_rate | **+0.5750** | 0.2702 | yes | 0.1791 | ✓ |
| 3.0 | travel_px | **−146.96** | 22.05 | yes | 50.38 | ✓ |
| 3.0 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 3.0 | settle_time_s | **−0.505** | 0.290 | no | 0.3245 | ✓ |
| 3.0 | angular_travel_deg | +5.64 | 7.50 | no | 49.40 | no |
| 3.0 | dispersion_deg | −0.09 | 6.33 | no | 12.55 | no |
| 3.0 | self_oob_rate | −0.1250 | 0.1721 | no | 0.1791 | no |
| 4.0 | travel_px | **−229.94** | 29.43 | yes | 50.38 | ✓ |
| 4.0 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 4.0 | settle_time_s | **−0.794** | 0.346 | yes | 0.3245 | ✓ |
| 4.0 | angular_travel_deg | +9.70 | 15.39 | no | 49.40 | no |
| 4.0 | dispersion_deg | +0.87 | 4.37 | no | 12.55 | no |
| 4.0 | self_oob_rate | **−0.1875** | 0.1791 | no | 0.1791 | marginal |

**Call.** Linear damping is a strong, monotone lever on `travel_px` and
`settle_time_s` — both exceed the floor at 1.0, 3.0 and 4.0. It is the **only**
lever that moves `self_oob_rate` decisively (1.0 → 76 % of shots leave the table;
4.0 → 0 %), though the 4.0 endpoint is marginal (Δ = floor σ). `peak_speed` is
**exactly invariant** (the launch impulse is applied before damping acts, and the
metric is the commanded peak). It does **not** move `angular_travel_deg` or
`dispersion_deg` beyond noise at any tested value. The `lin 1.0` settle-time
signal is real but **censored**: high OOB truncates flights, and the paired sd
(0.782) is larger than the floor σ — read it as "changes when shots end", not as
a clean settle law.

## Lever 3 — angular damping (`amber_spin`)

Per-run mean over the 20 seeds:

| angular_damp | travel_px | peak_speed | settle_s | ang_travel | dispersion | self_oob |
|---:|---:|---:|---:|---:|---:|---:|
| 0.5 | 473.84 | 1115.39 | 2.179 | 186.23 | 49.45 | 0.275 |
| **1.5 (baseline)** | **482.99** | **1115.39** | **2.328** | **129.50** | **38.89** | **0.188** |
| 3.0 | 475.78 | 1115.39 | 2.210 | 84.53 | 38.05 | 0.250 |
| 5.0 | 481.27 | 1115.39 | 2.262 | 58.30 | 31.88 | 0.250 |

Paired delta vs baseline (`✓` = exceeds floor σ):

| ang | metric | Δ mean | paired sd | same sign | floor σ | measured? |
|---:|---|---:|---:|:--:|---:|:--:|
| 0.5 | travel_px | −9.16 | 13.60 | no | 50.38 | no |
| 0.5 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 0.5 | settle_time_s | −0.149 | 0.264 | no | 0.3245 | no |
| 0.5 | angular_travel_deg | **+56.73** | 20.14 | yes | 49.40 | ✓ |
| 0.5 | dispersion_deg | +10.55 | 16.76 | no | 12.55 | no (just under) |
| 0.5 | self_oob_rate | +0.0875 | 0.1677 | no | 0.1791 | no |
| 3.0 | travel_px | −7.21 | 16.94 | no | 50.38 | no |
| 3.0 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 3.0 | settle_time_s | −0.118 | 0.292 | no | 0.3245 | no |
| 3.0 | angular_travel_deg | −44.98 | 17.81 | yes | 49.40 | no (just under) |
| 3.0 | dispersion_deg | −0.84 | 12.35 | no | 12.55 | no |
| 3.0 | self_oob_rate | +0.0625 | 0.1791 | no | 0.1791 | no |
| 5.0 | travel_px | −1.73 | 15.84 | no | 50.38 | no |
| 5.0 | peak_speed | +0.000 | 0.000 | — | 128.35 | no (invariant) |
| 5.0 | settle_time_s | −0.065 | 0.299 | no | 0.3245 | no |
| 5.0 | angular_travel_deg | **−71.20** | 26.86 | yes | 49.40 | ✓ |
| 5.0 | dispersion_deg | −7.01 | 16.54 | no | 12.55 | no |
| 5.0 | self_oob_rate | +0.0625 | 0.1791 | no | 0.1791 | no |

**Call.** Angular damping is a **single-axis** lever: it moves
`angular_travel_deg` (✓ at 0.5 and 5.0; 3.0 is just under the floor at 44.98) and
leaves `travel_px`, `settle_time_s`, `self_oob_rate` and `dispersion_deg` inside
the floor. `peak_speed` is exactly invariant. The `ang 3.0` and `ang 0.5`
under-threshold calls are honest "not established" results, not zeros. The
`ang 0.5` dispersion rise (+10.55 vs σ 12.55) is suggestive but inside noise.

## Headline summary

| lever / value | effect axis | vs noise floor | notes |
|---|---|---|---|
| mass 0.8 | travel ↑, peak_speed ↑ | measured | OOB roughly doubles (0.19→0.375), marginal |
| mass 1.4 | travel ↓, peak_speed ↓ | measured | OOB collapses to 5 % |
| mass 1.8 | travel ↓, peak_speed ↓, ang_travel ↓ | measured | OOB ~1 %, slowest mover |
| lin 1.0 | travel ↑, settle ↓, OOB ↑ | measured | 76 % OOB — control risk |
| lin 3.0 | travel ↓, settle ↓ | measured | no OOB |
| lin 4.0 | travel ↓, settle ↓, OOB ↓ | measured (OOB marginal) | shortest slide |
| ang 0.5 | angular_travel ↑ | measured | travel/settle/OOB unaffected |
| ang 3.0 | angular_travel ↓ | **not** measured (44.98 < 49.40) | direction right, size in noise |
| ang 5.0 | angular_travel ↓ | measured | flattest spin |
| any | dispersion_deg | **not measured** | no lever clears σ 12.55 |
| any | peak_speed under lin/ang | invariant (Δ=0) | only mass changes launch speed |

## First-cut candidate ranges (Wave-2 recommendation, not a Wave-3 decision)

Costs are stated in the same measured metrics; risks are things the single-pen
rig cannot see.

| profile | lever | first-cut range | rationale | cost / risk |
|---|---|---|---|---|
| `graphite_anchor` | `mass` | **1.4 – 1.8** | strongest signal, both endpoints exceed floor on travel & peak_speed; OOB falls to 1–5 % | costs launch speed (−319 to −496) so it is the clear "slow/stable" arm; risk of reading as strictly weaker at moving, and of being a dominant *defensive* pick if anchoring matters in contact play (rig has no pen-vs-pen) |
| `ivory_glide` | `linear_damp` | **1.0 – 1.5** | "glide" wants long run-out; 1.0 measured (+207 px travel) | 1.0 also measured 76 % self-OOB; the interior 1.5 is **untested** (only {1,2,3,4} sampled), so the low-end boundary is uncertain — 1.5–2.0 is the conservative fallback |
| `amber_spin` | `angular_damp` | **0.5 – 1.0** | only clean single-axis lever; 0.5 gives +57° spin with travel/settle/OOB inside noise | interior 1.0 untested; dispersion +10.6° at 0.5 is inside noise but trending; risk that more spin reads as less controllable / slower to settle in human play (rig shows settle flat) |

All three ranges intentionally avoid values whose effect did not clear the floor
(`lin 4.0` is a measured but extreme "no-slide" end; `ang 3.0` is unproven).
Every interior value between the sampled points is an interpolation that this
sweep did **not** test.

## What remains uncertain

- **Interior points are unmeasured.** Levers were sampled coarsely; e.g. no run
  exists at `linear_damp 1.5`, `angular_damp 1.0`, or `mass 1.1/1.6`. The
  candidate ranges above are boundaries, not validated settings.
- **OOB and settle near linear_damp 1.0 are coupled.** Censoring by OOB inflates
  the settle-time paired sd; the settle effect there is directional, not a clean
  curve.
- **Two marginal calls.** `self_oob_rate` deltas of exactly ±0.1875 vs σ 0.1791
  (mass 0.8 ↑, lin 4.0 ↓) are at the threshold; do not over-read them.
- **Single pen, no contact.** `contact_impulse` is the commanded input and is
  profile-invariant; `dispersion_deg` cannot capture collision deflection. A
  pen-vs-pen rig would be a new contract, so none of these ranges is evidence
  about how profiles interact or about counter-pick balance.
- **Feel is untested.** No human has played these values; the floor says how
  reproducible the rig is, not whether any range reads as fair or fun.
- **`graphite_anchor_mass0.8.json` is a duplicate** of `mass_0p80.json` (arm tag
  `mass_0.8` vs `mass_0p80`, same physics). Left in place; ignore it in analysis.
