# pen-profiles — Wave-3 decision (Wayfinder ticket #8)

Independent verification of the Wave-1/2 measurements, then the final ranges and rules.
Every Godot run below was serialized behind `flock /tmp/pf-godot.lock`; no production file,
scene, test, or another ticket's artifact was touched.

## Ticket question (verbatim)

> Can the existing four equal-size pen models support four readable, non-dominant gameplay identities while preserving risk-symmetric flicks and grip-position skill?
>
> Prototype Cobalt/Control (current baseline), Graphite/Anchor (mass lever), Ivory/Glide (linear-damping lever), and Amber/Spin (angular-damping lever). Choose measured ranges only after repeated sweeps exceed physics noise. Decide the final rules for Classic equal-physics default versus optional Pen Powers mode, profile locking, disclosure, mirror play, and counter-pick fairness.

## Answer

Rules, not discussion. All three new profiles change **only** `RigidBody2D` runtime properties
off the shipped Cobalt baseline (`mass 1.0`, `linear_damp 2.0`, `angular_damp 1.5`); one
footprint, no size change. "Measured" means the paired per-seed delta vs Cobalt (`arm − baseline`
over the same 20 seeds) exceeds the matching Wave-1 metric σ.

| Profile | Lever | Final value / range | Measured effect (paired Δ vs Cobalt, same seeds) | Floor σ | Margin |
|---|---|---|---|---|---|
| Cobalt / Control | — | fixed `mass 1.0, linear_damp 2.0, angular_damp 1.5` | reference | — | — |
| Graphite / Anchor | `mass` | **1.4 – 1.8** (default 1.4) | travel −123 (1.4) … −200 (1.8) px; launch peak −319 … −496 px/s; spin −51° at 1.8 | 50.4 / 128.4 / 49.4 | travel 2.4–4.0σ, peak 2.5–3.9σ, spin 1.03σ |
| Ivory / Glide | `linear_damp` | **1.0 – 1.5** (default 1.5) | travel +207 (1.0) … +102 (1.5) px; self-OOB +0.575 (1.0) / +0.225 (1.5) | 50.4 / 0.179 | travel 4.1σ / 2.0σ; OOB 3.2σ / 1.26σ* |
| Amber / Spin | `angular_damp` | **0.5** (usable 0.5–0.75; do not reach 1.0) | spin +56.7° at 0.5 | 49.4 | 1.15σ, same sign on 20/20 seeds |

\* the 1.5 OOB call is above the floor but not all-same-sign; treat 1.0 as the firm glide, 1.5 as the safe interior.

- **Classic equal-physics default vs optional Pen Powers.** Rule: Classic is the default mode; all pens run Cobalt physics. Pen Powers is an explicit opt-in local toggle; when it is off, no profile lever is applied.
- **Profile locking.** Rule: each player's profile is chosen before round 1 and locked for the whole match; no mid-round, between-round, or rematch swap.
- **Disclosure.** Rule: both profiles are revealed simultaneously before the first flick, together with the selected profile's lever and measured tradeoff. No hidden profile information.
- **Mirror play.** Rule: mirror (both players the same profile) is allowed. A mirror is exactly symmetric because both pens run identical physics; outcomes differ only by each player's own inputs. Cobalt-vs-Cobalt is the default.
- **Counter-pick fairness.** Rule: selection is closed and simultaneous, then locked, so no player can see the opponent's pick and counter it. Within the measured self-metrics, no final range Pareto-dominates another — every strong range buys its benefit with a measured cost (Anchor/Glide trade reach against self-OOB; Spin trades spin against nothing measured, but its benefit is the weakest signal), so there is no dominant pick. Counter-pick balance in pen-vs-pen contact is **not** established (see open risks).

Amber `angular_damp 1.0` was swept in Wave 3 and gives only +23.3° spin, inside the 49.4° floor:
it is indistinguishable from Cobalt and is therefore **excluded** from the readable range.

## Evidence

| Claim | Artifact | How verified (Wave 3) | Result |
|---|---|---|---|
| Determinism: identical config → identical JSON | `game/prototypes/pen_profiles/results/mass_1p40.json`; `.scratch/repro_mass1p4_{a,b}.json` | Re-ran the mass-1.4 arm (20 seeds × 4 shots, `flock`, `timeout 600`) twice, then `diff` | Raw diff shows only the `arm` label (`repro_a` vs `repro_b`); `diff` ignoring it is empty; both also byte-equal to the Wave-2 arm ignoring the label |
| Wave-1 noise floor σ | `game/prototypes/pen_profiles/README.md`; `user://pen_profiles_noise_floor.json` | Re-read the stats block from the JSON | travel 50.3841, peak 128.3509, settle 0.3245, spin 49.4046, dispersion 12.5460, OOB 0.1791 — matches the README exactly |
| SWEEPS.md signal-vs-noise calls | `docs/prototypes/pen-profiles/SWEEPS.md`; `results/*.json` | Recomputed **all** paired per-seed deltas from the raw JSON against the floor σ (independent script, no Wave-2 code) | 25/25 cited calls hold; **0 mismatches** |
| Mass lever | `results/mass_0p80/1p00/1p40/1p80.json` | Paired recompute | 1.4 & 1.8 exceed σ on travel and peak; 1.8 also on spin; 1.4 does **not** move settle/dispersion/OOB |
| Linear-damp lever | `results/linear_damp_1p0/2p0/3p0/4p0.json` | Paired recompute | 1.0/3.0/4.0 exceed σ on travel and settle; it is the only lever that decisively moves OOB (1.0 → +0.575, 76 %) |
| Angular-damp lever | `results/angular_damp_0p5/1p5/3p0/5p0.json` | Paired recompute | 0.5 (+56.7°) and 5.0 (−71.2°) exceed σ on spin; 3.0 (−45.0°) does **not** (floor 49.4°) |
| `profile_name` is inert | `results/mass_1p00.json`, `linear_damp_2p0.json`, `angular_damp_1p5.json` | Compared `shots` and `aggregate` arrays to baseline | byte-identical; only the `profile_name` label differs. SWEEPS.md's "shots arrays are identical" holds |
| Duplicate arm | `results/mass_0p80.json` vs `results/graphite_anchor_mass0.8.json` | Compared `runs` | identical physics; only the arm tag differs (as Wave 2 said) |
| Grip-position skill preserved | `results/*.json` | Compared every shot's `dir_deg`, `power`, `contact_offset`, `contact_impulse` across all arms | identical in every arm; `contact_impulse` is profile-invariant. No dedicated `contact_offset` arm exists (see open risks) |
| No dominance on measured proxies | `results/*.json` + Wave-3 arms | Compared travel / self-OOB / dispersion | No arm is safer AND further AND tighter than Cobalt; every gain has a measured cost |
| Interior `linear_damp 1.5` | `.scratch/wave3_linear_damp_1p5.json` | Wave-3 sweep, 20 seeds × 4 shots | travel +102.3 px (measured), OOB +0.225 (measured); settle/dispersion inside noise |
| Interior `angular_damp 1.0` | `.scratch/wave3_angular_damp_1p0.json` | Wave-3 sweep, 20 seeds × 4 shots | spin +23.3° — **inside** the 49.4° floor, so not a readable identity |

## Options considered and why rejected

- **Cosmetic-only profiles** — rejected: no measured physics identity, so "readable" is unsupported.
- **Four settings from one lever (e.g. four masses)** — rejected: collapses the identity space and leaves `mass` as the only launch-speed lever.
- **Pen size / footprint differences** — rejected by contract (single V1 footprint).
- **Extreme sampled points as identities** — `mass 0.8` (self-OOB 37.5 %), `linear_damp 4.0` (travel −230 px, no slide), `angular_damp 5.0` (spin −71° with no other axis), `angular_damp 3.0` (unproven, −45.0° < 49.4° σ) — rejected: unstable, unproven, or too costly in reach.
- **Wave-2's first-cut Amber range 0.5–1.0** — rejected upper half: Wave 3 measured `angular_damp 1.0` at +23.3° spin, inside noise. The readable spin value is ~0.5.
- **Balancing via pen-vs-pen contact** — rejected / out of scope: no two-pen rig exists in this contract.

## Open risks / what only human play can judge

- **Readability, fun, and whether the identities feel distinct** — no human has played any range; the rig measures displacement, not feel.
- **Pen-vs-pen contact is unmeasured.** Counter-pick balance and defensive dominance are only argued for self-metrics; none of the ranges is evidence about collisions.
- **Anchor as a defensive pick.** `mass 1.4–1.8` is the safest, slowest range; if real play rewards anchoring/denying, it could dominate defensively — unmeasurable in the single-pen rig.
- **Linear-damp OOB/settle coupling.** At `linear_damp 1.0`, OOB censoring inflates the settle paired sd (0.782 > σ 0.3245); read that as "when shots end", not a clean settle law.
- **Endpoint-only ranges.** Only the range ends were swept; interior points interpolate. `linear_damp 1.5` was added in Wave 3; `mass 1.6` and `angular_damp 0.75` remain unswept.
- **Amber is the weakest signal** (1.15σ). Pair it with a strong visual spin cue, or accept that it may read as subtle.
- **No touch/Android input model.** The launch lane and shot ranges are a documented measurement choice, not a human input model.

## Artifacts

- `docs/prototypes/CONTRACTS-pen-profiles.md` — binding interface.
- `game/prototypes/pen_profiles/README.md` — Wave-1 harness + measured noise floor.
- `docs/prototypes/pen-profiles/SWEEPS.md` — Wave-2 sweeps and signal-vs-noise calls.
- `game/prototypes/pen_profiles/results/*.json` — Wave-2 raw sweep evidence (committed).
- Wave-3 verification, uncommitted scratch under `game/prototypes/pen_profiles/.scratch/`:
  `repro_mass1p4_a.json`, `repro_mass1p4_b.json`, `wave3_linear_damp_1p5.json`,
  `wave3_angular_damp_1p0.json`, `wave3_verify.py`, `wave3_verify.out`.
- `docs/prototypes/pen-profiles/DECISION.md` (this file), `docs/prototypes/pen-profiles/RESOLUTION-COMMENT.md`.
