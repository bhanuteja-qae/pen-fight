**Resolved — measured ranges and rules.**

All levers are `RigidBody2D` runtime properties off Cobalt baseline (`mass 1.0`, `linear_damp 2.0`, `angular_damp 1.5`); one footprint. "Measured" = paired per-seed Δ vs Cobalt over 20 seeds exceeds the Wave-1 σ (travel 50.4 px, peak 128.4 px/s, spin 49.4°, OOB 0.179).

| Profile | Lever | Final range | Measured effect | Margin |
|---|---|---|---|---|
| Cobalt/Control | — | fixed baseline | reference | — |
| Graphite/Anchor | `mass` | **1.4–1.8** | travel −123…−200 px, peak −319…−496 px/s | 2.4–4.0σ |
| Ivory/Glide | `linear_damp` | **1.0–1.5** | travel +207…+102 px; self-OOB +0.575/+0.225 | 4.1σ/2.0σ |
| Amber/Spin | `angular_damp` | **0.5** (0.5–0.75) | spin +56.7° | 1.15σ, 20/20 same sign |

Amber `1.0` measured +23.3° — inside noise, so excluded.

**Rules.** Classic equal-physics is the default; Pen Powers is opt-in and applies these ranges. Profiles lock at match start (no swaps). Both profiles are disclosed simultaneously before round 1. Mirror play is allowed and exactly symmetric (identical physics). Selection is closed/simultaneous, and no range Pareto-dominates on measured proxies, so no dominant counter-pick.

Evidence: [`DECISION.md`](./DECISION.md), [`SWEEPS.md`](./SWEEPS.md), `game/prototypes/pen_profiles/results/*.json`. Wave 3 independently reproduced the mass-1.4 arm byte-for-byte and recomputed all 25 SWEEPS.md signal-vs-noise calls (0 mismatches); no dominance found; grip input (`contact_offset`/`contact_impulse`) is identical across arms. Human feel and pen-vs-pen contact remain unjudged.
