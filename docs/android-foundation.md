# Android Export Foundation (Phase 0.75) — verified 2026-09-13

Everything here is **engine-verified on this box**, not doc-sourced. The full
pipeline produced a signed release AAB: `build/pen-fight-release.aab` (51 MB).

## Decisions (documented earlier, now baked in)

| Item | Value | Why |
|---|---|---|
| `applicationId` | `com.penfight.game` | Lowercase reverse-DNS (docs §3.3: immutable after first Play publish, malformed IDs fail silently at install not export). **Chosen by Bhanu.** |
| Version name / code | `0.1.0` / `1` | Bump per release. |
| ABIs | arm64-v8a + armeabi-v7a | Both present in the AAB (verified: `base/lib/<abi>/libgodot_android.so`). |
| Rendering | `gl_compatibility` + ETC2/ASTC on | Spec §3 `[FIXED]` — Android export fails without ETC2/ASTC import set. |
| Keystores | debug (auto) + release (self-signed, 2048 RSA) | Release key: `build/secrets/penfight-release.keystore` (gitignored). **Lose it = can't update the app.** Back it up off-box before first publish. |

## Toolchain on this box

- Godot 4.7.2-stable Linux (pinned binary)
- JDK 17 (`/usr/lib/jvm/java-17-openjdk-amd64`)
- Android SDK at `/home/ubuntu/android-sdk`: platform-35, build-tools 35.0.0, platform-tools
- Export templates at `~/.local/share/godot/export_templates/4.7.2.stable/`
- Godot editor settings (`~/.config/godot/editor_settings-4.7.tres`):
  - `export/android/android_sdk_path=/home/ubuntu/android-sdk`
  - `export/android/java_sdk_path=/usr/lib/jvm/java-17-openjdk-amd64`
  - `export/android/debug_keystore=/home/ubuntu/.android/debug.keystore`

## How to rebuild (headless, exact commands)

```bash
cd ~/pen-fight/game
# Debug AAB (signs with debug keystore)
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --export-debug "Android" ../build/pen-fight-debug.aab
# Release AAB (signs with the release keystore)
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --export-release "Android" ../build/pen-fight-release.aab
```

`export_presets.cfg` lives in `game/` but is **gitignored** (holds plaintext
keystore passwords — docs §3.3). If it's missing, regenerate from this repo's
pattern or the editor (Export → Android). The preset name must be exactly
"Android".

## Gotchas hit (all solved, all verified)

1. **Export templates must sit at the version dir root** — the tpz extracts a
   `templates/` subdir; move contents up to `.../4.7.2.stable/`.
2. **Gradle template needs `res://android/build/` layout** — extract
   `android_source.zip` to `game/android/build/` exactly (engine defaults
   `gradle_build_directory` to `res://android/build`).
3. **`.build_version` marker** — the engine reads `game/android/.build_version`
   (hidden file, content `4.7.2.stable`) to verify the template version. Missing
   it yields "no version info for it exists". Adding `version.txt` does NOT help.
4. **`.gdignore` in `game/android/build/`** — without it the Godot importer
   scans the template and writes `.import` sidecars next to `.webp` resources;
   Gradle's resource merger then fails ("file name must end with .xml or .png").
   Fix: add `.gdignore`, delete stray `*.import`, reimport.
5. **ETC2/ASTC must be set BEFORE any art import** — toggling it later forces a
   full `.godot/` wipe + double reimport (docs §3.3; reproduced).
6. **`~` does NOT expand in `export_presets.cfg` keystore paths** — use absolute.
7. **Target path must match preset format** — AAB preset (`export_format=1`)
   requires `--export-debug ... .aab`, not `.apk`.
8. **Project icon required** — Android export refuses ("No project icon
   specified") until `config/icon` is set; created `game/icon.svg`.

## Secrets (never commit)

- `game/export_presets.cfg` — plaintext keystore passwords
- `build/secrets/penfight-release.keystore` — release signing key
- Backup plan before Play publish: keystore password + file off-box (e.g. user's
 1Password), report AI risk of losing Play Console keys.