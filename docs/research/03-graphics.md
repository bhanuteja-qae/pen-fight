# Phase 3 Research — Graphics & Asset Strategy for Pen Fight

Scope: replace `draw_rect` placeholders with real pen sprites, table texture, shadows, sound, haptics. Solo/small dev, no art pipeline, no dedicated artist, Android target, Godot 4.x / GDScript.

**Note on verification**: `docs.godotengine.org` is blocked by this environment's egress proxy, so exact API/property names below are cross-checked against community docs mirrors, GitHub issues, and search snippets rather than fetched directly from the canonical docs page. They match current Godot 4 stable behavior as far as I could verify; double-check exact casing in the editor's Project Settings search box before committing to project.godot edits.

---

## 1. 2D vs 3D vs "2.5D"

The core question: a pen is a long thin cylinder that **rolls on its side and tumbles end-over-end**, not a flat disc. How much of that read has to be real, versus faked?

### Option A — Pure 2D sprites, top-down physics (RigidBody2D)

- **Physics**: `RigidBody2D` with a `CapsuleShape2D` or thin `RectangleShape2D`/`SegmentShape2D` collider, top-down (`gravity_scale = 0`, damping does the work of friction). This is exactly what the current placeholder code almost certainly already uses.
- **Tumble illusion**: Godot's 2D physics only gives you rotation about the Z axis (spin in the plane), not a true roll axis. A pen "rolling" on its long axis in real life doesn't have a 2D analogue — in 2D you fake it by swapping between a "side" sprite and a "tip-on" sprite based on speed/spin, or by playing a canned roll animation/spritesheet when velocity crosses a threshold, and by using an elongated capsule collider so the pen visually spins convincingly end over end when it flat-spins post-flick.
- **Performance**: cheapest possible option on Android. 2D physics step is far lighter than 3D; a handful of RigidBody2D pens is negligible CPU. Rendering is flat sprites, batches trivially, lowest overdraw, works on any GPU tier.
- **Art cost**: one (or a few) hand-drawn/painted pen sprites per pen "skin," viewed from directly above (and optionally a couple of extra frames for the roll-tumble illusion). This is very achievable without an artist — a top-down pen is a simple rounded rectangle with a metal clip and cap, well within reach of a non-artist doing careful vector work or using CC0 assets/AI-generated 2D art (see §3).
- **Physics tuning**: easiest to tune. 2D linear/angular damping, restitution, and friction map directly and predictably onto "how far does a flick travel," which is the actual gameplay lever. This is the same physics model turn-based flick games (paper football, Flick Soccer-style games) use.
- **Code reuse**: **100% of the existing 2D architecture survives** — turn manager, input/flick vector code, `RigidBody2D` bodies, collision layers, camera, UI. Only the draw layer changes (Sprite2D/AnimatedSprite2D replacing `draw_rect`), plus you likely add a `Node2D` "shadow sprite" child per pen. This is the only option that doesn't touch physics or gameplay code at all.

### Option B — 2D with pre-rendered sprite sheets baked from a 3D model ("2.5D")

- You'd model a pen once in Blender (or grab a CC0 pen/pencil model), rig no bones needed (it's rigid), and render an 8- or 16-direction rotation sheet, or even a full tumble animation loop, from an orthographic camera — this is the "Diablo/Donkey Kong Country" technique.
- **Physics**: still `RigidBody2D` underneath (top-down), same as Option A. The pre-rendered frames just replace hand-drawn art for direction/roll state. This gets you a much more convincing 3D-looking tumble (real specular highlights, real cast shadow baked into the sprite) while keeping 2D's simulation and performance.
- **Performance**: essentially identical to Option A at runtime — it's still flat textures and `RigidBody2D`. The cost moves entirely to build/authoring time (rendering the sheets) and a slightly larger texture atlas (many frames per pen skin vs. one).
- **Art cost**: highest one-time cost of the three to *set up* (you need a 3D pen model + a render pipeline + atlas packing), but it's a one-time pipeline; once built, adding new pen skins ("reskins"/cosmetics — a natural mobile-game monetization hook) is cheap because you just re-texture the same 3D model and re-render. This is the option most likely to look genuinely polished without ongoing artist time, because the render does the shading work for you.
- **Physics tuning**: same as Option A (still 2D). No extra tuning difficulty vs. A.
- **Code reuse**: same as Option A — 100% of gameplay/physics code untouched, only asset content changes. This makes it a **low-risk upgrade path from Option A**: ship A first, swap in pre-rendered sheets later if you want the visual bump, without touching physics.

### Option C — Real 3D (MeshInstance3D + RigidBody3D, orthographic or low-FOV camera)

- **Physics**: `RigidBody3D` with a `CylinderShape3D` collider gives a genuinely correct tumble — real 6-DOF rotation, real rolling friction on the barrel, no faking needed. This is the only option where the tumble is *actually* physically simulated rather than approximated.
- **Performance**: 3D physics (Jolt in Godot 4.4+, or the built-in Godot Physics) is heavier per-body than 2D, though for 2 pens it's not going to be the bottleneck by itself. The real mobile cost is the **renderer**: even a simple 3D scene pulls in the 3D pipeline (depth prepass, shadow maps if you want real shadows, MSAA/FXAA, more expensive lighting) which has meaningfully higher baseline GPU cost than the 2D (Canvas) renderer on low-end Android GPUs (Mali-G52/Adreno 610 class chips common in budget 2024 phones). Use `Compatibility` (GLES3/Forward Mobile) rendering method, orthographic camera to avoid perspective distortion issues with a desk viewed from above, and bake or fake shadows (see §5) rather than real-time 3D shadow maps, which are the single most expensive thing you could turn on here.
- **Art cost**: needs an actual 3D pen model (low-poly, a cylinder + a cone tip + a clip + a cap — genuinely simple geometry, gettable for free from Quaternius/Poly Haven-adjacent sources or buildable in an hour in Blender by a non-artist) **and** a table/desk material, **and** basic 3D lighting setup. Total modeling effort for a pen is actually *lower* than good 2D pixel art of a pen from multiple angles — cylinders are the easiest possible 3D primitive — but you now also own a texturing (UV unwrap + material) step you didn't have in 2D.
- **Physics tuning**: harder. 3D rigid body tumbling has more emergent, less scriptable behavior — getting a "satisfying" flick (not too floaty, not stopping dead, rolling to a natural rest without infinite micro-jitter) takes more iteration in 3D than 2D because there are more degrees of freedom to fight (sleep thresholds, angular damping per axis, contact/friction solver quality). Godot's default physics solver historically has had known issues with small/thin colliders jittering — a pen-shaped cylinder is exactly the shape most likely to hit that.
- **Code reuse**: **worst of the three.** Every physics-touching line (flick impulse application, turn-end detection via `sleeping`/velocity thresholds, collision layer setup, any raycasts for aiming) has to be rewritten against 3D APIs. UI/turn-manager/score logic can mostly stay, but input needs a 2D-screen-tap-to-3D-world raycast (`Camera3D.project_ray_origin`/`project_ray_normal`) instead of direct 2D coordinates. This is close to a rewrite of the physics layer, not a reskin.

### Comparison table

| | 2D sprites (A) | Pre-rendered 3D→2D sheets (B) | Real 3D (C) |
|---|---|---|---|
| Runtime perf (low-end Android) | Best | Best (same as A) | Worst — 3D pipeline overhead |
| Tumble realism | Faked/approximated | Looks real (baked), still 2D physics | Actually real |
| Art cost to start | Low | Medium (needs 3D→render pipeline) | Medium (simple geometry, but new texturing skillset) |
| Art cost per new skin | Low-medium | Low (retexture + re-render) | Low (retexture) |
| Physics tuning difficulty | Easy | Easy (same as A) | Hard |
| Existing 2D code reuse | ~100% | ~100% | Physics/input layer largely rewritten |
| Risk of visible jank (thin-collider jitter, tunneling) | Low | Low | Higher |

### Recommendation

**Ship Option A (pure 2D, `RigidBody2D`, hand-drawn/sourced top-down pen sprites) for Phase 3.** It is the only option that costs zero rewrite of physics/turn logic already built, it is the cheapest to make convincing without an artist (a pen viewed from directly above is a simple, forgiving shape to draw or source), and it has the lowest, most predictable performance floor on cheap Android hardware, which matters more for a mobile physics-flick game than marginal visual fidelity. Treat **Option B as the natural next step** if the game gets traction and you want a "premium" visual pass or cosmetic pen skins later — it's a pure content swap on top of the same physics, not a rewrite. Only reach for Option C if true 3D tumble becomes a core selling point of the game (e.g., a "spin the pen" fidget-toy angle where the third dimension is the point); for a turn-based flick-battle game, 3D buys realism the player mostly won't consciously notice while costing real engineering time and GPU headroom on budget devices.

Sources: [RigidBody2D docs (4.4)](https://docs.godotengine.org/en/4.4/classes/class_rigidbody2d.html), [RigidBody2D physics body comparison](https://uhiyama-lab.com/en/notes/godot/physics-body-comparison/)

---

## 2. Asset loading in Godot 4 — the "preloaded model" question

### `preload()`

- Resolves **at parse time** (when the script is compiled), and the argument **must be a string literal** starting with `res://` — it cannot be a variable or built from string concatenation. The resource is baked into the script as a constant and is available immediately when the script loads, with zero runtime call cost.
- Best for: small, always-needed resources referenced by a fixed path — a pen's base texture, a shared shader, a `Theme` resource, a sound the game always needs. If you `preload()` a dozen small pen-sprite PNGs and a couple of SFX at the top of an autoload/singleton script, they load once during that script's own instantiation (effectively at project start for an autoload) and are available for the rest of the game's life with no further I/O.
- **Danger**: preloading large or many resources (big textures, whole scenes, long audio) directly in a script that's instantiated often (e.g., a scene that gets created every turn) reloads/reallocates on every instantiation unless it's a true singleton — and preloading *everything* into one autoload bloats startup time and resident memory even for content the player may never reach in that session (e.g., cosmetic pen skins they haven't unlocked).

```gdscript
# Good preload use: small, always-needed, fixed path.
const PEN_DEFAULT_TEX := preload("res://art/pens/pen_default.png")
const SFX_FLICK := preload("res://audio/sfx/flick.ogg")
```

### `load()`

- A regular function call, evaluated **at runtime**, so the path can be a variable (`load(path_var)`). It reads from disk or returns the cached copy if that resource is already loaded elsewhere (Godot's `ResourceCache` dedupes by path).
- Because it runs synchronously on the calling thread, `load()` on a large resource (a big scene, a big texture) that hasn't been loaded yet **will block that frame and can cause a visible hitch** — this is exactly the "mid-turn hitch" the prompt is asking to avoid. Use `load()` freely for small things or things you know are already warm in cache; avoid it for big one-shot loads triggered by gameplay events (e.g., loading a new pen-skin texture the instant the player selects it mid-match).

```gdscript
# Fine for a small, already-preloaded-elsewhere resource, or picked dynamically:
var skin_path := "res://art/pens/pen_%s.png" % skin_id
var tex: Texture2D = load(skin_path)  # OK if small / infrequent
```

### `ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` / `load_threaded_get()`

- The correct tool for anything non-trivial: it kicks the actual disk read + import decode onto a background thread while the main thread keeps rendering, and you poll (or check once per frame) until it's done, then pull the finished resource with no blocking.

```gdscript
# Loading screen / splash controller
var _pending_paths: Array[String] = [
    "res://art/pens/pen_default.png",
    "res://art/table/table_felt.png",
    "res://art/fx/shadow_soft.png",
    "res://audio/sfx/flick.ogg",
    "res://audio/sfx/collision.ogg",
]
var _loaded: Dictionary = {}

func _ready() -> void:
    for path in _pending_paths:
        ResourceLoader.load_threaded_request(path)
    set_process(true)

func _process(_delta: float) -> void:
    var all_done := true
    for path in _pending_paths:
        if _loaded.has(path):
            continue
        var status := ResourceLoader.load_threaded_get_status(path)
        match status:
            ResourceLoader.THREAD_LOAD_LOADED:
                _loaded[path] = ResourceLoader.load_threaded_get(path)
            ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
                push_error("Failed to load: %s" % path)
                _loaded[path] = null # don't block forever on a bad path
            ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                all_done = false
    if all_done:
        set_process(false)
        _on_all_loaded()

func _on_all_loaded() -> void:
    get_tree().change_scene_to_packed(_loaded["res://match/match.tscn"])
```

Notes verified against current usage patterns: `load_threaded_get_status()` must be polled from the main thread — if nothing ever calls it, the load can appear stuck "in progress" indefinitely, so drive it from `_process()` or a repeating `Timer`, not a one-shot check. `load_threaded_request()` also accepts an optional `type_hint` and `use_sub_threads` argument in current Godot 4 — pass the hint (e.g. `"PackedScene"`) when loading `.tscn` to avoid ambiguity.

### `PackedScene` instantiation cost

- Loading a `PackedScene` (via any of the above) only deserializes the scene resource into memory — it does **not** create a live node tree yet. The actual cost happens at `.instantiate()`, which allocates the node tree, runs `_init`/`_ready` for every node, and hooks up signals. For a scene with many nodes (a whole pen with sprite + collider + shadow + particle emitter + audio player), `instantiate()` several times per second (e.g., spawning a fresh pen scene every turn) is a real, measurable cost on low-end devices — each call touches the allocator and runs GDScript setup code for every child node.

### Object pooling for repeated instances

Since Pen Fight most likely only ever needs exactly 2 pens (not spawning/despawning dozens), pooling is lower-priority than it would be for, say, a bullet-hell game — but it still matters for anything spawned repeatedly and short-lived: hit-effect particles, collision-sound one-shots, trail-of-dust sprites, "score popup" UI. Pattern:

```gdscript
# Simple pool for a repeatedly-spawned effect (e.g. collision spark).
class_name EffectPool
extends Node

@export var effect_scene: PackedScene
@export var pool_size: int = 8

var _pool: Array[Node2D] = []

func _ready() -> void:
    for i in pool_size:
        var inst: Node2D = effect_scene.instantiate()
        inst.visible = false
        inst.set_process(false)
        add_child(inst)
        _pool.append(inst)

func spawn(pos: Vector2) -> void:
    for inst in _pool:
        if not inst.visible:
            inst.global_position = pos
            inst.visible = true
            inst.set_process(true)
            inst.restart() # e.g. a method on your effect scene that resets & plays
            return
    # pool exhausted: either grow it or drop the request silently
```

For the two pens themselves, don't pool at all — just keep them as permanent nodes in the match scene and reset their `position`/`rotation`/`linear_velocity`/`angular_velocity` between turns/rounds instead of freeing and re-instantiating.

### Preloading during a splash/loading screen so no hitch happens mid-turn

Concrete recipe for this game:
1. On app start, show a lightweight splash `Control` scene (its own tiny scene, loaded synchronously since it must be near-instant).
2. From the splash script, threaded-load every asset the *match* scene will need: both pen sprite atlases (including any skins the player owns), the table texture, shadow sprite/texture, all SFX the match can trigger, and the match `PackedScene` itself.
3. Poll to completion (as above), then either `add_child()` a pre-instantiated match scene or `change_scene_to_packed()` with the already-loaded `PackedScene` — instantiating from an already-loaded `PackedScene` is comparatively cheap (parse cost is gone; only node-tree construction remains) so it won't hitch mid-swipe.
4. Anything *not* needed for the very first match (extra cosmetic skins beyond the equipped one, alternate table themes) should be threaded-loaded lazily in the background *after* the first match is playable, or loaded on-demand when the player opens a skin-select menu (with its own tiny loading spinner), never loaded synchronously during active gameplay.

Sources: [Dynamic Loading and Resource Management in Godot](https://uhiyama-lab.com/en/notes/godot/dynamic-loading-resource-management/), [ResourceLoader In Godot - Complete Guide](https://gamedevacademy.org/resourceloader-in-godot-complete-guide/), [Godot GitHub issue on load_threaded_get_status polling](https://github.com/godotengine/godot/issues/95470)

---

## 3. Where to get art without an artist

| Source | License | Commercial use + Play Store | Attribution required? | Notes |
|---|---|---|---|---|
| **Kenney.nl** | CC0 (public domain) | Yes, unrestricted | No (credit appreciated, not required) | Best first stop. Huge library incl. top-down/UI kits; “Kenney” himself has publicly confirmed no attribution/permission/donation requirement, commercial yes, remix yes. |
| **OpenGameArt.org (OGA)** | Mixed per-asset: CC0, CC-BY, CC-BY-SA, GPL, OGA-BY | Yes for all of the above, **but check the exact license on every individual asset** | CC-BY / CC-BY-SA / OGA-BY: **yes, required** (credit screen or credits file). CC0: no. | CC-BY-SA is "viral" for derivative *art* (if you edit and redistribute the art itself under SA, the modified art must stay CC-BY-SA) — this is not a problem for using it as-is inside a closed-source game binary, but avoid it if you plan to build a public asset pack from edits. |
| **itch.io asset packs** | Mixed: free CC0/royalty-free, and paid "commercial license" packs with pack-specific terms | Depends per pack — many explicitly say "royalty free," some have "no redistribution of raw asset files" clauses | Varies — read the pack's own license.txt; itch does not enforce a site-wide license | Treat every itch pack as its own contract; the good ones ship a plain-English `LICENSE.txt` in the download. |
| **Poly Haven** | CC0 | Yes, unrestricted, no attribution needed | No | Mainly HDRIs/3D materials/3D models — most useful if you go the pre-rendered-sprite-sheet (Option B) or real-3D (Option C) route for table wood/desk textures, not for 2D pen sprites directly. |
| **Quaternius** | CC0 | Yes, unrestricted, no attribution needed | No | Free low-poly 3D model packs (characters, props). Directly useful if pursuing Option B/C for a pen-like 3D prop base mesh; note some *newer/premium* Quaternius packs are paid — check per-pack, the free legacy packs are CC0. |
| **Google Fonts** | SIL Open Font License (~99%) or Apache 2.0 (rest) | Yes, commercial and Play Store fine, can bundle the font file in the app | Yes for OFL fonts if you *redistribute the font file* (you must include the license text with it; some fonts also want in-app/credits attribution) — but you cannot sell the font file standalone | Fine for UI/score text. Bundle the `.ttf`/`.otf` + its `OFL.txt` under `res://` for an offline build; don't rely on a live Google Fonts CDN fetch in a mobile app. |
| **Paid marketplaces** (Unity Asset Store 2D packs usable in Godot as raw images, itch.io paid packs, Gumroad, CodeAndWeb, GraphicRiver/Envato) | Per-marketplace EULA | Usually yes for one commercial title per license seat, but **read the specific EULA** — some (e.g. certain Envato "regular license" tiers) cap unit sales/impressions or forbid resale of the asset itself | Rarely required, but check | Reasonable option for a table/wood-texture pack or SFX pack if the free sources don't have the exact look you want; budget $5–$30 per pack is common and often faster than hunting free sources. |

### License traps to flag explicitly

- **CC-BY-NC ("NonCommercial")**: common on OpenGameArt and itch — **cannot** be used in a Play Store game the moment there's any monetization angle (ads, IAP, or even a paid app), and Google Play distribution itself is arguably commercial distribution even for a free ad-free app depending on interpretation — **avoid NC-licensed assets entirely** for this project rather than relying on ambiguous interpretation.
- **"Free for personal use" / "free for non-commercial use"**: functionally the same trap as NC, common on freebie font sites and some texture sites (not Google Fonts). Any asset page that says this is a **hard no** for a distributed Android game, regardless of whether the game itself is free.
- **CC-BY-SA "share-alike"**: safe to *use* unmodified inside a closed-source commercial game (you're not re-licensing your whole game, just crediting and not relicensing the *asset*), but if you materially edit/remix the art and later want to redistribute that edited art as your own separate asset pack, the edited version must also be CC-BY-SA — don't let this creep into "we can't ship the app" panic, it doesn't block shipping a game that merely *contains* the asset, just credit it.
- **Unity Asset Store EULA quirks**: some Unity Asset Store packages' standard EULA restricts use to Unity-integrated projects or via specific redistribution clauses that may not cleanly cover dropping raw PNGs into a Godot project — read the specific package's EULA before importing Unity-store art into Godot; don't assume "it's just PNG files" makes the EULA irrelevant.
- **Font "desktop use only" licenses**: outside Google Fonts, many free-looking fonts on sites like dafont.com are personal-use-only unless marked otherwise per-font — Google Fonts specifically avoids this problem because every font listed there has been vetted as OFL/Apache, so prefer it as your font source for this project rather than a general "free fonts" site.

### AI-generated art for sprites/textures

- **Practicality**: for this project's needs — a flat, simple, top-down pen sprite; a tileable desk/wood/felt texture; simple particle textures (dust, scuff mark) — current-generation image models are genuinely usable, especially for **tileable textures** (wood grain, felt, cork) where seams and exact silhouette don't need pixel-perfect control, and for **concept/reference** to then trace/simplify by hand into a clean top-down asset. It's less reliable for a *precise, game-ready, alpha-cut, top-down sprite at a specific canvas size* — you'll almost always need manual cleanup (background removal, exact silhouette, consistent orientation/scale across pen skins) in a tool like Krita/GIMP/Photopea afterward.
- **Copyright caveat (US)**: purely AI-generated output, with no meaningful human creative modification, is **not independently copyrightable** under current US Copyright Office guidance — this doesn't stop you from *using* it in a commercial game, but it means you may not be able to stop someone else from using the *same or very similar* AI output, and if you want your specific art defensible as your own IP, you need enough human authorship (compositing, hand-editing, arranging elements, color grading) layered on top to claim it. For a solo dev without an artist, this is usually an acceptable risk — most competitors won't bother re-generating and re-editing your exact composited result — but it's worth knowing you're not getting the same protection you'd get from wholly hand-drawn art.
- **Play Store policy**: as of 2025–2026, Google Play does **not** ban AI-generated art in your app's actual content by itself, but requires that AI-generation features (if the *player* can generate content in-app) not produce harmful/deceptive/impersonating output and be disclosed where relevant; static, pre-baked AI-generated sprites/textures you made during development and shipped as fixed assets are not treated differently from any other art asset for policy purposes — the disclosure requirements target apps that expose AI generation *as a feature* to end users, and apps with sexual/exploitative or impersonation content regardless of how it was made. If targeting the EU, note the EU AI Act's Article 50 transparency rule (in force from August 2026) requires marking synthetic images/audio/video as AI-generated in machine-readable form for certain deployer categories — check current guidance closer to your EU launch, this is a live regulatory area.
- **Practical recommendation for this project**: use AI generation for **texture references and desk/table backgrounds** (tileable, forgiving of imperfection) and for rapid **concept iteration** on pen skins, but hand-finish (crop, clean alpha, palette-match, resize to your atlas grid) everything that ships as a game sprite. Combine with CC0 sources (Kenney/Poly Haven) as your primary art backbone and use AI only to fill specific gaps (a themed pen skin, a seasonal table texture) rather than as the whole pipeline.

Sources: [Kenney license (X/Twitter)](https://x.com/KenneyNL/status/1939336549684183078), [OpenGameArt: Licensing a game](https://opengameart.org/forumtopic/licensing-a-game), [Poly Haven license](https://polyhaven.com/license), [Quaternius CC0](https://x.com/quaternius/status/1559299393177747456), [Google Fonts FAQ](https://developers.google.com/fonts/faq), [Google Play AI-Generated Content policy](https://support.google.com/googleplay/android-developer/answer/14094294?hl=en), [AI Game Assets: Copyright, Contracts & Platform Rules](https://blog.promise.legal/ai-generated-game-assets-legal-guide/), [itch.io commercial-license/royalty-free tag](https://itch.io/game-assets/tag-commercial-license/tag-royalty-free)

---

## 4. Texture and import settings that matter on Android

| Setting | Recommendation for this game | Why |
|---|---|---|
| **VRAM compression** | Enable `rendering/textures/vram_compression/import_etc2_astc` (Project Settings → Rendering → Textures → VRAM Compression) | Godot 4 uses this single toggle to import mobile-compressed formats: **ETC2** for Android GLES3/Vulkan-mobile baseline, **ASTC** where supported. ETC2 is mandatory-supported on GLES 3.0, i.e. effectively every Android device since ~2013, making it the safe floor; ASTC gives better quality/size on devices that support it. Godot picks the right one per export target when this is on. |
| **ETC2 vs ASTC** | Let Godot's mobile export preset handle the choice (don't hand-roll per-texture format unless you hit a specific device issue) | ASTC gives visibly better quality at equal or smaller memory footprint on hardware that supports it (most Android GPUs from the last ~6-7 years); ETC2 is the universal fallback. Both are lossy VRAM-resident compressed formats, decoded by the GPU directly (never fully decompressed in RAM), which is what actually saves memory vs. an uncompressed or PNG-lossless import. |
| **Lossless vs Lossy (Import → Compress Mode)** | `VRAM Compressed` for anything on-screen every frame (pen sprites, table texture, shadow blob); `Lossless` only for crisp UI icons/text where banding would be visible and the image is small | `Lossy`/`Lossless` in the Godot importer are CPU-side compressed-in-RAM-then-decompressed-to-VRAM-uncompressed formats (good for disk size, **not** for GPU memory) — they do **not** save GPU VRAM the way `VRAM Compressed` does. For gameplay sprites that live in VRAM every frame, VRAM Compressed is the one that actually reduces the memory Android has to keep resident. |
| **Mipmaps on 2D** | Off (default) for most 2D sprites that are always shown near their native size (pen, table); On only if a sprite is ever scaled down substantially (e.g. a zoomed-out overview or a minimap-style UI) | Mipmaps cost ~33% extra texture memory and are only useful to reduce shimmering/aliasing when a texture is minified; a 2D game that mostly renders sprites near 1:1 scale gets no benefit and pure memory cost from enabling them everywhere. |
| **Filtering** | `Linear` (Godot 4 default `rendering/textures/canvas_textures/default_texture_filter`) for the pen/table/shadow art if it's painted/photographic-style; switch to `Nearest` per-texture (or project-wide if going full pixel-art) only if the visual direction is deliberately pixel art | Nearest on non-pixel-art content produces jagged edges on rotation (and the pen rotates constantly during a flick), so unless committing to a pixel-art style, keep Linear. If it *is* pixel art, use Nearest everywhere plus integer `content_scale_factor` to avoid shimmering on rotation — pixel-art pens spinning with linear filtering look blurry/muddy. |
| **Texture atlases / `AtlasTexture`** | Pack the pen sprite(s), shadow sprite, and small FX into one shared atlas via Godot's `SpriteFrames`/`AtlasTexture` workflow or an external tool (TexturePacker + its Godot importer plugin) | Sprites sharing one texture *and* one material batch into a single draw call; splitting each sprite into its own file multiplies draw calls (each texture switch flushes the batch) — for a scene with only 2 pens + table + shadows this isn't yet a bottleneck, but establishing the atlas habit now avoids draw-call growth later (particle effects, multiple pen skins on screen in a menu, etc). Keep all sprites in one atlas on the **same compression/filter settings** — mixed settings within an atlas force Godot to break the batch anyway, cancelling the benefit. |
| **Power-of-two sizing** | Not strictly required by Godot 4's renderer (unlike old GLES1/fixed-function eras) but still good practice for atlas packers and predictable compression block alignment | ETC2/ASTC compress in fixed block sizes (4×4 etc.); non-PoT/non-block-aligned dimensions can waste padding. Size the finished atlas to a round number (512, 1024) rather than an odd size like 900×613. |
| **Max texture size on low-end devices** | Cap individual gameplay textures at **1024×1024**; only go to 2048×2048 for something like a full detailed table background if it truly needs that much distinct detail (it usually won't at typical phone screen sizes) | A pen sprite and its shadow don't need more than a few hundred px on the long axis at any realistic phone resolution; oversizing wastes VRAM for zero visible gain and risks hitting driver quirks around very large single textures on cheap Android SoCs. |
| **APK/AAB size impact** | Ship as Android App Bundle (AAB), let Play deliver per-device compressed texture format where applicable; keep total imported-texture footprint modest (a handful of MB, not tens) for a game this visually simple | Installed size is commonly a multiple of the raw APK size after decompression on-device — keep source art small and let VRAM compression do the heavy lifting rather than shipping huge uncompressed masters. |

Sources: [Godot texture compression discussion](https://forum.godotengine.org/t/the-effect-of-etc2-atsc-compression/87984), [ETC2/ASTC VRAM compression proposal](https://github.com/godotengine/godot-proposals/issues/7119), [Texture Atlases for Mobile Games (Godot/Cocos)](https://ilovesprites.com/blog/texture-atlas-mobile-godot-cocos-guide), [Reducing Draw Calls with Texture Atlases](https://ilovesprites.com/blog/reducing-draw-calls-texture-atlases), [Godot 4 Mobile Optimization: Android & iOS](https://gtstu.com/godot-4-optimize-android-ios/)

---

## 5. Making a flat 2D scene look "polished" cheaply

| Technique | How | Cost on low-end Android GPU |
|---|---|---|
| **Drop shadow via offset sprite** | A second, darker/alpha-reduced copy of the pen sprite (or a simple soft blob texture) drawn under the pen, offset a few px and slightly scaled, `z_index` below the pen | **Very low.** Just one extra `Sprite2D` draw call per pen, no lighting system involved. This is the recommended default for this game. |
| **Light2D + real-time shadows (`shadow_enabled`)** | `PointLight2D`/`DirectionalLight2D` above the scene with occluders (`LightOccluder2D`) on the pens | **High.** Community reports show FPS dropping meaningfully (e.g., to ~50fps on a mid-range phone) with as few as 2 dynamic-shadow lights; mobile shadow rendering is disproportionately expensive vs. desktop. **Avoid for this game** — the fake offset-sprite shadow reads just as well for a top-down desk scene and costs almost nothing. |
| **Baked/static shadow** | Pre-paint a soft shadow shape directly into a shadow texture asset, positioned once (or per pen orientation frame if using Option B) | **Very low** — it's just another sprite draw, no lighting math at all. Best "shadow that looks hand-crafted" option if you want more shaping than a generic blob allows. |
| **CanvasModulate for mood** | One `CanvasModulate` node tinting the whole scene (e.g. warm desk-lamp tint, or a "match point" dramatic tint) | **Negligible** — it's a full-screen color multiply, effectively free. Great cheap win for atmosphere/state changes (e.g., tint shifts on final round). |
| **Vignette** | A full-screen `ColorRect` with a small radial-gradient shader, or a pre-baked semi-transparent PNG overlay with dark corners | **Low** — one extra full-screen quad; a static PNG overlay is essentially free, a shader-computed vignette is one cheap fragment shader over one quad, still negligible on any 2024 Android GPU. |
| **Normal maps on the pen sprite** | Assign a normal map to `Sprite2D.normal_texture` / use `NORMAL_MAP` in a CanvasItem shader, lit by a `PointLight2D` | **Medium**, and only pays off if you also have a moving/dynamic light to react to — without a light, a normal map does nothing visible. Given the Light2D cost concerns above, this is **not recommended** unless you keep it to a single cheap, non-shadow-casting light; otherwise it's cost for no payoff. |
| **CanvasItem shader for gloss/highlight on the barrel** | A small fragment shader adding a fixed or slowly-panning specular highlight streak along the pen's long axis (fake rim-light, doesn't need real lighting data) | **Low** — a single extra shader pass on a small sprite is cheap; this is a good "looks 3D-ish without being 3D" trick specifically suited to a shiny plastic/metal pen barrel. Recommended as a genuinely high value-for-cost item. |
| **Particles for dust/scuff** | `GPUParticles2D` for a brief dust puff on collision/landing, or a static scuff decal sprite left behind | **Low-medium** — a short-lived, small, low-count particle burst (dozens of particles, sub-second lifetime) is cheap; avoid continuous/looping particle systems running the whole match, and cap particle counts hard for budget devices. |
| **Table felt/wood tiling texture** | One small (e.g. 256×256–512×512) tileable texture repeated via a `TextureRect`/`Sprite2D` with `texture_repeat` region, or `NinePatchRect`/`Polygon2D` UV-tiled | **Very low** — one texture, one draw call, tiling costs nothing extra at runtime versus a single large baked background, and tiling one small texture is far cheaper on APK size and memory than one giant painted table background. |
| **Depth cues (fake AO under pen ends, slight perspective on table edge art, subtle size falloff)** | Hand-authored in the static table art / shadow shaping, not a runtime system | **Free at runtime** — this is purely an authoring-time trick (paint it into the assets), not a shader/system, so it costs nothing in the frame budget at all. |

**Bottom line for this game**: offset/baked shadow sprites + `CanvasModulate` + a cheap vignette + a tiling table texture + a small gloss shader on the pen barrel gets most of the "polished" read for close to zero GPU cost. Skip real-time `Light2D` shadows entirely on a low-end Android target — it's the one item on this list with a real, measured performance cost for a middling visual payoff on this specific scene (a top-down desk doesn't need dynamic lighting to read as lit).

Sources: [2D lights and shadows docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html), [Why is Light2D on Android so slow? (Godot Forums)](https://godotforums.org/d/18553-why-is-light2d-on-android-so-slow), [Light2D + normal map performance thread](https://forum.godotengine.org/t/perfomance-issues-using-light2d-with-normal-maps/7096), [Lighting with 2D normal maps (GDQuest)](https://www.gdquest.com/tutorial/godot/2d/lighting-with-normal-maps/)

---

## 6. Resolution and scaling

Godot 4 project settings live under `display/window/*`; the equivalent runtime API is on the root `Window` (via `get_window()` / `get_tree().root`) as `content_scale_mode`, `content_scale_aspect`, `content_scale_size`, `content_scale_factor`.

**Recommended settings for this game:**

| Project setting | Value | Reasoning |
|---|---|---|
| `display/window/size/viewport_width` / `viewport_height` | e.g. `1080 x 1920` (portrait) — pick a real reference device resolution, not an arbitrary small number, since this is painted/vector-ish 2D art, not pixel art | Sets your authoring canvas; UI and layout math is easiest to reason about in a resolution you can picture. If the game is portrait-only, design in portrait; if it supports rotation, pick whichever orientation is primary. |
| `display/window/stretch/mode` | `canvas_items` | Renders 2D content at whatever the actual output resolution is (so sprites/text stay crisp at any device DPI) while treating your base size as the reference for layout — the right choice for non-pixel-art 2D on a platform with huge resolution variance like Android. (`viewport` mode instead renders at a fixed low internal resolution and upscales — the better choice only if you commit to a pixel-art style with `Nearest` filtering, which is not what's recommended in §4 for a painted-look pen game.) |
| `display/window/stretch/aspect` | `expand` | With `expand`, extra width/height beyond your base aspect ratio is simply given to the game instead of adding black bars (`keep`) or stretching/distorting content (`ignore`). This is the right behavior across the real spread of Android aspect ratios you named — a 4:3 tablet and a 21:9 phone should both show *more table*, not the same table letterboxed or squashed. |
| Base aspect / viewport choice | Design your base resolution close to a common **mid** aspect ratio (e.g. ~9:19.5, a common tall-phone ratio) and build the play-space (table) as a shape that can lose or gain margin at the edges gracefully | Since `expand` reveals more of the scene on wider/narrower devices, the table/background art needs enough bleed/extendable tiling at the edges (see §5 tiling texture) that a 4:3 tablet doesn't reveal a hard edge where the art runs out, and a 21:9 phone doesn't crop essential play area (the two pens and the whole table must remain visible at the *narrowest* realistic aspect ratio your device matrix includes). |
| `content_scale_factor` (Window property, exposed as a stretch scale setting) | `1.0` (leave default) unless you deliberately want to globally over/under-sample | This is a manual multiplier on top of the aspect-mode math — mainly useful for supersampling UI crispness or deliberately downscaling for performance headroom on very weak devices; not needed as a baseline setting here. |
| UI vs playfield scaling | Put the **HUD/UI** (turn indicator, score, buttons) in a `CanvasLayer` with its own `Control` tree sized against safe-area-aware anchors (percentage anchors, not fixed pixel offsets), separate from the **playfield** `Node2D` tree that scales via the project's `canvas_items`+`expand` stretch settings | UI needs to respect notches/rounded corners/gesture-nav bars (safe area) and stay legible at a fixed relative size regardless of how much extra table the `expand` aspect mode reveals, while the playfield (table, pens, shadows) should be the thing that gains/loses visible margin on aspect changes — conflating the two makes buttons drift toward screen edges/cutouts on unusual aspect ratios. Android's Godot export template also exposes `display/window/handheld/orientation` — set explicitly to `portrait` (or `landscape`, matching this game's actual mode) rather than leaving `sensor`, to avoid unwanted device auto-rotation mid-flick gesture. |

Verified via search snippets (stretch mode names `canvas_items`/`viewport`, aspect option names `ignore`/`keep`/`keep_width`/`keep_height`/`expand`) against community Godot 4 references; recommend confirming exact property text in the editor's Project Settings search since the canonical docs page was unreachable from this environment.

Sources: [Godot Android form-factor guide (Android Developers)](https://developer.android.com/games/engines/godot/godot-formfactor), [multiple_resolutions.rst (godot-docs repo)](https://github.com/godotengine/godot-docs/blob/master/tutorials/rendering/multiple_resolutions.rst), [Display Scaling in Godot 4 (Chickensoft)](https://chickensoft.games/blog/display-scaling)

---

## 7. Render budget (estimates)

All figures below are **estimates**, order-of-magnitude guidance for a "2024-era low-end Android phone" (entry-level Mali-G52/Adreno 610-class SoC, 3–4GB RAM class device) — validate with the in-editor profiler and `adb shell dumpsys gfxinfo` / Android GPU profiling tools on an actual low-end test device before trusting these numbers for shipping decisions.

- **Total frame budget for 60 FPS**: ~16.6 ms/frame. A commonly cited rough split for mobile is ~8–10 ms CPU-side, ~8–10 ms GPU-side, leaving a couple ms of headroom for OS/thermal jitter — the two overlap/pipeline rather than strictly summing, but neither side should regularly approach the full 16.6 ms alone.
- **Draw calls**: general community guidance for mobile 2D put "hundreds of draw calls per frame" as the danger zone where CPU dispatch overhead alone risks blowing the frame budget on weak devices. This scene (2 pens + 2 shadows + table background + a handful of UI elements + occasional short particle burst) should realistically be on the order of **single digits to a few dozen draw calls** — trivially inside budget, assuming the atlas/batching guidance in §4 is followed (mixed textures/materials per sprite would be the main way to accidentally blow this up).
- **Texture memory**: keep-under guidance from general mobile optimization sources suggests **~100MB VRAM as a low-end-safe ceiling**, ~200–300MB for average-tier hardware. This scene's actual texture budget (a small pen atlas, a small table tile, a shadow blob, a UI atlas, maybe some particle textures) should realistically total **low single-digit MB** after ETC2/ASTC compression — nowhere near the ceiling, meaning there's comfortable headroom to add pen skins, seasonal tables, or extra polish without texture memory becoming a real constraint for this specific game.
- **Physics**: 2 `RigidBody2D` bodies with simple capsule/rectangle colliders is negligible CPU cost relative to the 16.6 ms budget — this is not where risk lives for this game. (This changes if Option C/real-3D is chosen — see §1's perf caveats.)
- **Where the real risk actually is for this game**: not raw draw-call count or texture memory (both comfortably small for a 2-object scene), but **avoiding accidental added cost** — real-time `Light2D` shadows (§5), an uncapped/looping particle system, or a naive full-screen shader (heavy vignette/post-process running every frame at full native resolution on a big phone screen) are the plausible ways a scene this simple could still miss 60fps on weak hardware. Budget deliberately for **one** cheap full-screen effect (vignette or `CanvasModulate`) rather than stacking several, and treat any particle system as strictly a short-lived one-shot, not a continuous system.

Sources: [Frame Budget Calculator / mobile frame budget guidance](https://gamedevcheatsheet.com/frame-budget), [Mobile game performance pitfalls](https://blog.gamebench.net/mobile-game-performance-pitfalls), [Reducing Draw Calls with Texture Atlases](https://ilovesprites.com/blog/reducing-draw-calls-texture-atlases), [Optimizing Godot for Mobile — A Field Guide](https://slicker.me/godot/mobile-optimization.html)

---

## Summary of concrete recommendations

1. **Stay in 2D** (`RigidBody2D`, capsule/rect collider) for the pens — zero rewrite of existing physics/turn code, cheapest on low-end Android, and a top-down pen is an easy shape to source or draw without an artist. Treat pre-rendered 3D→2D sprite sheets as a future upgrade path on the *same* physics, not a rewrite; reserve true 3D (`RigidBody3D`) only if real tumble physics becomes a core selling point.
2. Build a small splash/loading screen that `ResourceLoader.load_threaded_request()`s every asset the first match needs (pen atlas, table texture, shadow art, SFX, the match scene itself), polls to completion, then hands off — never `load()` a big asset synchronously mid-gameplay. Use `preload()` only for small always-needed constants. Don't bother pooling the 2 pens themselves; do pool short-lived one-shot effects if/when they're added.
3. Primary art sources: **Kenney.nl** (CC0, no strings) and **Poly Haven/Quaternius** (CC0, useful if 3D route is ever taken) as the backbone; **OpenGameArt** and **itch.io** packs per-asset-license-checked (avoid anything CC-BY-NC or "personal use only" — hard blockers for Play Store); **Google Fonts** (OFL) for UI text, bundled offline with its license file. AI-generation is fine for tileable textures/backgrounds and concept work but hand-finish anything that ships as a game sprite, and know that pure-AI output isn't independently copyrightable under current US guidance.
4. Import settings: enable ETC2/ASTC VRAM compression project-wide, use `VRAM Compressed` (not Lossless/Lossy) for gameplay sprites, mipmaps off unless something is minified, `Linear` filtering (this is a painted-look game, not pixel art), pack sprites into one shared atlas with consistent compression/filter settings, cap individual textures at 1024×1024 (2048 only if truly needed).
5. Fake shadows via an offset/baked sprite (not real-time `Light2D` shadows, which measurably hurt mobile FPS for little payoff on a top-down desk scene); layer in `CanvasModulate`, a cheap vignette, a tiling felt/wood table texture, and a small gloss `CanvasItem` shader on the pen barrel — all near-zero cost and together do most of the "polish" work.
6. Project settings: `display/window/stretch/mode = canvas_items`, `display/window/stretch/aspect = expand`, base viewport sized to a common tall-phone ratio, `content_scale_factor` left at 1.0, UI in its own safe-area-aware `CanvasLayer` separate from the `expand`-scaled playfield, orientation locked explicitly rather than left on `sensor`.
7. This scene's actual render cost (2 pens, table, shadows, minimal UI) is comfortably inside a 16.6ms/60fps budget on 2024-era low-end Android by a wide margin on both draw calls and texture memory (all figures estimates) — the realistic risk isn't the base scene, it's *adding* an expensive extra (real-time 2D lighting/shadows, a continuous particle system, a heavy full-screen shader) on top of it, so budget deliberately for at most one cheap full-screen effect and keep particles strictly one-shot.
