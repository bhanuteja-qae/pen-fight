# Pen Fight — Market & Competitive Research

**Research method / tooling limitation (read first):** All data below comes from `WebSearch` snippet results. `WebFetch` was blocked by the sandbox's egress proxy for every relevant domain tested (`play.google.com`, `appbrain.com`, `apptopia.com`, `apkpure.com`, `apkcombo.com`, `softonic.com`, `aptoide.com`, `similarweb.com`, `appgrooves.com`, `en.wikipedia.org`, `reddit.com`, `fueler.io`) — this is a network-egress restriction in the current sandbox, not a source-quality choice. So none of the figures below were read directly off a live Play Store page or a raw review list; they are Google's AI-synthesized summaries of indexed pages (Play Store listings, AppBrain/AppGrooves/Apptopia cache pages, blog writeups). Numbers are internally consistent across repeated queries but **could not be independently cross-checked against the primary page**, so treat every install/rating figure as **directionally indicative, not audited**. This is flagged again inline as "(search-snippet sourced, unverified)."

---

## 1. Existing pen-fight / pen-duel games on Google Play

| Title | Developer | Installs | Rating | Reviews | Dimension | Modes | Monetization |
|---|---|---|---|---|---|---|---|
| Pen Fight HD – Online Multiplay | Ulka Games (`com.ulkagames.penfight`) | ~67,600+ (AppGrooves, search-snippet sourced) | 3.3★ | 349 | 2D | Offline + "online multiplayer", vs CPU | Free, ad-supported (no IAP mentioned) |
| Pen Fight: Local Multiplayer | Backspace Games (`com.backspacegames.penfight`) | Not verified (one search-synthesized answer said "50 thousand+"; unverified) | Not verified | Not verified | 2D | Local Wi-Fi multiplayer, AI bots, power-ups | Free; has "powers"/unlockable pens+arenas, daily rewards, live-ops style — IAP/ad structure not confirmed |
| Pen Fight 3D | GameGanesh (`com.GameGanesh.PenFight3D`) | Not verified | Not verified | Not verified | 3D (block-like pens) | 1v1, vs AI | Not confirmed |
| The PenFight Original OG | Empty Glass Studio (`com.emptyglassstudio.thepenfightog`) | Not verified | Not verified | Not verified | 2D, minimalist | 2-player same-device only, "no powers, no upgrades" | Not confirmed |
| Pen Fight (Workshop pack) | `com.penfight.game` | Not verified | Not verified | Not verified | 2D | 100 built-in levels incl. "Workshop pack" (76–100), single-player vs level hazards, not just PvP | Not confirmed |
| Pencil Fight: 1v1 Flick Game | Manthan (`com.pencilfight.manthan`) | Not verified | Not verified | Not verified | 2D | 1v1 local, Solo Practice, Survival (3 lives vs AI), Tournament (best-of-5), Ghost (replay), Chaos | Ad-supported; cosmetic pencil/desk skins unlocked via rewarded video |
| Pen Fight: Flick Battle (iOS) | Furlan Paolo / Alessio Furlan | N/A (App Store) | Not verified | Not verified | 2D | 1v1, coin wagering vs rivals | Free + one-time "remove ads" IAP |
| Pen Fight Game: Class Champion (iOS) | Akshat Jagga | N/A (App Store) | Not verified | Not verified | 2D | Not detailed | Not confirmed |
| Pen Fight (older, discontinued) | Anupam Chakravorty | 100,000+ (unpublished Dec 2023, last updated 2012) | 4.26★ | ~2,200 | 2D | — | Historical reference only, not a live competitor |
| Pen Fight (older, discontinued) | MGames ICTD | 1,000,000+ (unpublished Dec 2021) | 3.44★ | ~11,000 | 2D | — | Historical reference only, not a live competitor — but shows the *category itself* once reached 1M+ installs |

Additional adjacent/indie entries found (lower relevance, noted for completeness): "Pen Battle" (Sayanosoft, last updated 2019, low activity), "Stick Arena – Pen Fight," "Imad Pen vs Pen," a CodeCanyon-sold "Pen Fight 3D real-time multiplayer HTML5" template (i.e., the mechanic is now sold as a white-label asset), and several browser (non-Play-Store) versions: **penfight.xyz**, **penfight.net**, **penfight.org**, **y8.com/games/pen_fight_html5**, **learninggames247.com**.

**Notable pattern:** two prior "Pen Fight" apps on Play crossed 100K and 1M installs respectively but were both **unpublished by Google** (Dec 2023 and Dec 2021) — consistent with either low-effort/policy-violating hyper-casual shovelware getting delisted, or abandonment by small devs, not necessarily a demand problem. Cannot confirm the delisting reason.

**Confidence: Low-medium.** Titles, developers, and feature descriptions are corroborated across multiple independent search results (high confidence they exist and are described accurately). Install counts and star ratings are single-source, snippet-derived, and could not be verified against a live page — treat as approximate at best.

---

## 2. Adjacent comparables — what successful flick/physics games do differently

| Game | Publisher | Scale (verified where possible) | Structure |
|---|---|---|---|
| Carrom Pool: Disc Game | Miniclip | **640M+ lifetime downloads**, ~6.5M downloads/30-days, 4.44★ from **7.8M ratings**, #1 in Sports category (search-snippet sourced from SensorTower/AppBrain/Similarweb aggregation, not independently verified) | Real-money-free PvP matchmaking (online, skill-based), seasonal **battle pass** ("Carrom Pass"), coins/gems soft+hard currency, cosmetic board/disc skins, clubs/social features, tournaments, daily login rewards |

Search results for India/US/Pakistan monthly estimates (single-source, unverified precision): ~5M downloads/$90K revenue (India), ~6M/$100K (US), ~5M/$100K (Pakistan) for a recent 30-day window — illustrates the game monetizes across *all* tiers, not just Tier-1, but Tier-1 CPMs likely drive a disproportionate revenue share despite similar download volume.

Could not retrieve specific comparable data for 8 Ball Pool, Golf Battle, Flick Kick Football, or Bottle Flip within tool constraints (WebFetch blocked; WebSearch queries returned only generic monetization-blog content, not game-specific figures) — **not verified, omitted rather than guessed.**

**What Carrom Pool does that pen-fight clones do not, based on available descriptions:**
- **Real online PvP with matchmaking**, not just hot-seat/local — this is the core retention loop (always someone to play against, ELO-style progression).
- **Seasonal content cadence** (battle pass, "Carrom Pass") giving a recurring reason to return, versus the pen-fight titles which appear to be static single-purchase-of-content experiences (e.g., "100 levels" ships once, no live-ops seen mentioned in any listing).
- **Soft+hard currency economy** driving cosmetic monetization (boards/discs) beyond ads — none of the pen-fight titles mention gems/currency; monetization described for them is ads (+ occasional rewarded video for cosmetics, e.g., Pencil Fight) rather than a full economy.
- **Social layer** (clubs, friend challenges, leaderboards) — one Ulka Games review theme explicitly asked for "friend battle options," suggesting this gap is felt by real users of the existing pen-fight app.
- **Production polish** — Miniclip-tier art direction, sound, and juice vs. the visibly template/low-budget presentation implied by titles being resold as CodeCanyon source templates.

**Confidence: Medium** on Carrom Pool's scale (numbers repeated consistently across SensorTower/AppBrain/Similarweb-sourced snippets), **low** on the qualitative "what they do differently" claims (inferred from store descriptions, not gameplay testing or dev postmortems).

---

## 3. User review themes for existing pen-fight games

Direct review text could not be scraped (Play Store and AppGrooves both blocked to WebFetch). What follows are **paraphrased themes**, sourced from search-engine-synthesized summaries of AppGrooves' review aggregation for **Pen Fight HD – Online Multiplay (Ulka Games)**, the one title with enough indexed review content to surface themes:

- **Praise:** "very addicting," fun for quick sessions with classmates when bored; simple pick-up-and-play value is repeatedly the positive anchor.
- **Complaint / feature request:** users ask for **better multiplayer modes and a "friend battle" option** — i.e., the existing "online multiplayer" claim is perceived as weak or matchmaking-only, and players want to challenge a specific friend directly (a private-room / invite-link feature).
- Rating context: 3.3★ from 349 reviews is a mediocre score for a casual game category where 4.0+ is typical for anything with real polish — consistent with "good core hook, weak execution" rather than "concept doesn't work."

For all other titles (Backspace Games, GameGanesh, Empty Glass Studio, `com.penfight.game`, Pencil Fight), targeted searches for review complaint language ("too many ads," "controls unresponsive," "physics broken," "laggy") returned **no indexed review text** — only store-description content. This is a genuine data gap, not an absence of complaints; it likely reflects low review volume (most of these apps look like small-studio releases with review counts probably in the low hundreds or fewer) that Google hasn't surfaced richly in search snippets.

**What can be said with more confidence, inferred from feature comparisons rather than direct quotes:** the pattern across the category is (a) simple/no-frills apps get praised for capturing the nostalgia hook but criticized for shallow multiplayer, and (b) the more feature-rich app (Backspace Games, with power-ups/arenas/daily rewards) is the most recently active/updated ("various bug fixes and performance improvements" in its latest changelog), suggesting active iteration is happening in at least one competitor.

**Confidence: Low.** This section is the weakest in the report — genuine review text was not accessible under current tool constraints. Recommend a manual pass (a human downloading 2-3 of these APKs/store pages directly) before treating any specific complaint as validated.

---

## 4. Market size / demand signals

Concrete, corroborated signals:

- **A browser-based "Pen Fight" clone (penfight.xyz) by a Bangalore-based indie founder (Rinkesh Gorasia) reportedly logged 6,000+ matches in its first 24 hours** after launch and generated organic virality on Instagram Reels and X (multiple independent posts found: `@game_rushh`, `@viral.naman`, `@abhaytechai`, `@rinks__g`) — this is the single strongest, most recent demand signal, though the 6,000-match figure is single-source (a Fueler.io blog writeup) and unverified against any analytics dashboard.
- **At least 5 separate browser-based pen-fight clones exist concurrently** (penfight.xyz, penfight.net, penfight.org, y8.com/games/pen_fight_html5, learninggames247.com/physics-games/pen-fight), plus a CodeCanyon-sold HTML5 template — indicating multiple independent developers are converging on this idea right now, a sign of a live trend rather than a one-off.
- **Two new iOS entrants (Pen Fight: Flick Battle, Pen Fight Game: Class Champion) both appear to be very recent releases** (their App Store numeric IDs, 680166xxxx and 680329xxxx, are in a range Apple was issuing in 2025), meaning fresh competitive entry into this niche is happening within the last ~1 year, concurrent with this project.
- **A USC Digital Folklore Archives page documents "Pen Fight" as a real, named schoolyard game** — corroborates the cultural/nostalgia basis for the concept independent of app-store activity, and situates it as most associated with Indian schools (source explicitly references Mumbai schools).
- **Historical Play Store precedent:** one now-delisted pen-fight app reached 1,000,000+ installs (MGames ICTD) and another reached 100,000+ (Anupam Chakravorty) — evidence the *ceiling* for this niche on Android has reached 6-7 figure installs before, even from unpolished apps, though both are now gone from the store (cannot confirm why).
- **Could not verify:** Google Trends search volume for "pen fight game" (no direct trends.google.com access; broader 2025 "Year in Search India" roundups do not list it among top trends, meaning it is not a mass-market breakout term, more likely a smaller/niche-but-real search volume). No YouTube view-count data could be obtained (YouTube Shorts references exist — e.g., "Play PEN Fight Online" — but view counts were not retrievable via search snippets). No Reddit thread discussion volume could be quantified (Reddit itself was unreachable via WebFetch; WebSearch surfaced no dedicated pen-fight subreddit threads, only the same blog/social coverage already cited).

**Geography:** All demand signals found are **India-centric** — the founder of the viral browser clone is Bangalore-based, the cultural documentation ties the game to Mumbai schools, and hypercasual-genre India install share is independently known to be large (~23% of hypercasual installs are India-sourced per one industry report, not pen-fight-specific). No evidence of meaningful demand outside South Asia; the iOS entrants' developer names/regions were not identifiable as India-based, so some spread beyond India cannot be ruled out but isn't confirmed either.

**Confidence: Medium** on "a real, currently-active, India-centered nostalgia trend exists and multiple builders are entering it right now" (corroborated by concurrent independent launches across web and both app stores). **Low** on any actual size number (no search volume, no aggregate DAU/MAU, no ad-spend data found) — there is no way to state whether this is a "thousands of engaged users" niche or a "hundreds of thousands" niche with current tools.

---

## 5. Differentiation opportunity — is this crowded or underserved?

**Bluntly: it is a crowded-at-the-low-end, underserved-at-the-top niche.** The evidence supports both halves of that claim:

- **Crowded at the bottom:** At minimum 8-10 distinct Play Store apps, 2 iOS apps, 5+ browser clones, and a resellable HTML5 template all exist for essentially the same core mechanic, with more entering within the last year. A generic "flick your pen, knock theirs off, 2D, hot-seat" app with no further differentiation has many near-identical existing options and would need to out-market, not out-build, them.
- **Underserved at the top:** None of the discovered competitors show evidence of: (a) real online PvP matchmaking (most explicitly advertise "local"/"same device"/"same Wi-Fi" only, or vague "online multiplayer" that a reviewer explicitly called weak), (b) a live-ops content cadence (seasons, events) — everything found ships as a static level pack or arena set, (c) high production polish — nothing in the descriptions or template-resale evidence suggests Miniclip-tier art/juice, (d) social/friend-challenge features, which is the literal, verbatim, user-requested gap surfaced in the one review-theme dataset available (Ulka Games' reviewers asking for "friend battle options").
- The project's own current scope (2D, hot-seat only, interstitials + remove-ads IAP, later skins) is **squarely aimed at the crowded low end**, not the underserved top. This is not necessarily wrong — a hot-seat "played on the bus/in class in real life" app has genuine authenticity to the original social game that a matchmade-online version loses — but it means the realistic ceiling looks more like "Ulka Games' ~70K installs at 3.3★" than "Carrom Pool's hundreds of millions," unless execution quality (physics feel, art, juice, ASO) is clearly a tier above the existing 8-10 competitors.
- The single most actionable, cheaply-added differentiator suggested directly by the evidence: **an invite-link / "challenge a friend remotely" mode** (async or simple online relay) sitting on top of the existing hot-seat core — this doesn't require full server-authoritative PvP/matchmaking infrastructure, directly answers the one concrete review complaint found in the dataset, and is not clearly present in any competitor's description.

**Confidence: Medium.** The "crowded" half is high-confidence (directly counted, corroborated titles). The "underserved at the top" and "recommended differentiator" conclusions are reasoned inferences from store descriptions and one review-theme, not from hands-on competitive testing or a larger review corpus — a deeper pass (actually installing 3-4 competitor apps) would sharpen this.

---

## 6. Monetization benchmarks for this category

All figures below are **industry-wide benchmarks from monetization/ad-tech blogs (Tenjin, Appodeal/industry reports, MAF/Mistplay, various)**, not pen-fight-specific — no pen-fight title's actual revenue or eCPM could be found. Treat every number as an industry-average estimate to plan against, not a guarantee.

**Interstitial eCPM (2024-2025 aggregate benchmark data):**
- General interstitial eCPM range cited: **$0.50–$1.50** on the low end up to **$4.80** average, with **Tier-1 publishers reaching $6–$12** for high-performing inventory.
- Regional blended eCPM (2024, all ad formats): ~**$6.50 North America**, ~**$5.00 Europe**, ~**$4.50 Asia-Pacific**. India specifically was not broken out; as a lower-ARPU APAC market, actual India interstitial eCPM is very likely **well below the $4.50 APAC blend** — commonly discussed industry wisdom (not directly sourced here) places India interstitial eCPM in roughly the **$0.30–$1.50** range depending on ad network and fill quality, materially below Tier-1. **Mark this India-specific range as an estimate, not a sourced figure** — could not find a citation with India-specific interstitial eCPM data.
- For context on audience mix: hypercasual games as a genre skew ~23% of installs from India vs. ~7% from the US (one industry report, genre-wide not pen-fight-specific) — meaning a pen-fight app with a heavily India-weighted audience should plan revenue-per-install materially below a US/Tier-1-weighted comparable, purely from eCPM geography, independent of engagement quality.

**ARPDAU benchmarks (genre-wide, 2025 industry blog aggregation):**
- **Hypercasual:** ~$0.02–$0.05 (2-5 cents) average; one source cites $0.10-0.12 for a higher-performing band; D90 ad revenue/user cited at $0.22 in one report.
- **Casual (ads-only):** ~$0.01–$0.05.
- **Casual (IAP-leaning):** ~$0.10–$0.25.
- **Hybridcasual games (ads + stronger IAP/meta layer):** need to target $0.50–$1.00+ to be considered healthy.
- A hot-seat, no-online-PvP-infrastructure pen-fight app is architecturally closer to "casual/ads-only," so **$0.01–$0.05 ARPDAU is the realistic planning band**, with India-weighted traffic likely at the low end of even that range given the eCPM discount noted above.

**"Remove ads" IAP conversion:**
- General mobile-game payer conversion benchmark: **2-5% considered healthy**, sub-1% signals a problem; broader all-app-type average is 2-3% and mobile games specifically often land lower than that blended figure.
- **No benchmark specific to a single, one-time "remove ads" non-consumable purchase (as opposed to overall IAP/payer conversion) was found.** Industry commentary generically describes "remove ads" as a standard non-consumable category but did not surface a percentage. **Recommend treating 1-3% of engaged/returning users as a planning estimate for a remove-ads-only IAP in a casual, India-weighted, ad-supported game — this is an inference from the adjacent 2-5% overall payer-conversion benchmark, not a sourced remove-ads-specific number.**

**Confidence: Medium** on the general industry-wide benchmark ranges (multiple corroborating blog/report sources, consistent numbers). **Low** on anything India-specific or pen-fight-specific (no direct source found; explicitly flagged as extrapolation above).

---

## Bottom line for planning

- Expect ARPDAU in the **$0.01–$0.05** range unless a live-ops/social layer is added to justify hybridcasual-tier monetization.
- Expect interstitial eCPM well below Tier-1 blended averages given a likely India-heavy audience — budget UA and break-even math around **sub-$1.50, plausibly sub-$1** eCPM, not the $4.80+ headline averages.
- The category has a real, current, India-centered demand signal (viral browser clone, multiple concurrent 2025-launched entrants) but **no verified size number** — do not plan against an assumed TAM without further validation (e.g., actually installing top competitors and tracking their rank-history via a paid tool like SensorTower/data.ai, which this research pass could not access).
- The most credible, evidence-backed differentiation lever is a lightweight "challenge a friend remotely" feature layered on the existing hot-seat core, since it directly answers the one concrete, sourced user complaint found (Ulka Games reviewers wanting friend-battle options) without requiring full server-authoritative online PvP.
