<h1 align="center">Vovozinha</h1>

<p align="center"><strong>Offline-first kids bedtime stories on iPhone — on-device AI only</strong></p>

<p align="center">
  <img src="https://img.shields.io/github/license/macedot/vovozinha?color=blue" alt="License" />
  <img src="https://img.shields.io/badge/iOS-18%2B-lightgrey" alt="iOS 18+" />
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6" />
  <img src="https://img.shields.io/badge/device-iPhone%2015%2B%20physical-important" alt="Physical iPhone" />
  <img src="https://img.shields.io/badge/AI-on--device%20MLX-blueviolet" alt="On-device MLX" />
</p>

---

**Vovozinha** is an offline-first iOS app for children’s bedtime stories (~ages 3–8). Parents and caregivers (**18+**) write a short seed; the phone generates a title, summary, and **exactly 10 scenes** with an on-device LLM. The network is used only to **download the model pack once**; after that, generation works fully offline.

> **The iOS Simulator is not supported.**  
> Build, run, and validate story / photo features on a **physical iPhone**, or install a development `.ipa` (Xcode, Apple Configurator, or AltStore).

Development happens on branch **`multi`**: feature kits + DEBUG harness apps + a thin host. See [`docs/MODULES.md`](docs/MODULES.md) and [`AGENTS.md`](AGENTS.md).

| | |
|--|--|
| **Content** | Kids ~3–8 |
| **Who uses the app** | Parents / caregivers **18+** |
| **Devices** | **iPhone 15+** (physical) |
| **AI** | **Strictly on-device** (no cloud generation / TTS) |
| **Languages** | **pt-BR / en-US / es-ES** (language bar; default = system) |
| **Model** | [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) (~3 GB pack) |

## Features

- **Story from a short seed** — 10–20 words → title, summary, **10 paragraphs** (no static / template stories)
- **On-device MLX** — Qwen3.5 4-bit; CDN zip + SHA-256 check; Import from Files as fallback
- **Photo describe (DEBUG)** — pick a photo → short caption (persons → objects → scene) via the same pack as a VLM
- **Modular kits** — develop one feature at a time with dedicated DEBUG schemes
- **pt-BR / en-US / es-ES** — UI and prompts from Markdown on disk
- **Privacy-first** — no accounts, no required analytics, models stay in private Application Support

## Quick Start

### Requirements

| Item | Value |
|------|--------|
| macOS | Recent (Xcode 27 beta OK) |
| Xcode | **Xcode 27 beta** at `/Applications/Xcode-beta.app` |
| Deployment | iOS **18.0+**, iPhone only |
| MLX checkouts | Sibling repos via `./scripts/setup_mlx_local.sh` |
| Run target | **Physical device** (or sideload `.ipa`) |

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

git clone https://github.com/macedot/vovozinha.git
cd vovozinha
git checkout multi

# One-time: local mlx-swift + mlx-swift-lm (Prism) next to this repo
./scripts/setup_mlx_local.sh
# If Metal tools are missing on Xcode beta:
xcodebuild -downloadComponent MetalToolchain

open Vovozinha.xcodeproj
```

In Xcode: select a **physical iPhone**, pick a scheme (see below), Run.

## Schemes — build only what you need

One Xcode project, several **schemes**. Use a DEBUG harness when you want to exercise a single feature without the full host.

| Scheme | What it is | Bundle ID | When to use |
|--------|------------|-----------|-------------|
| **Vovozinha** | Product host (Story Prompt) | `app.vovozinha.Vovozinha` | Day-to-day product / IPA for parents |
| **StoryPromptDebug** | Story Prompt kit alone | `app.vovozinha.StoryPromptDebug` | Iterate on seed → story only |
| **PhotoDescribeDebug** | Photo Describe kit alone | `app.vovozinha.PhotoDescribeDebug` | Iterate on photo → caption (VLM) |
| **VovozinhaLegacy** | Old monolith (reference) | legacy | Migration / comparison only |

Always set `DEVELOPER_DIR` first. Prefer `generic/platform=iOS` for CLI builds (device/IPA); do **not** use the Simulator destination.

### Host app

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /path/to/vovozinha

xcodebuild -scheme Vovozinha -destination 'generic/platform=iOS' -configuration Debug build
```

### Story generation only (DEBUG)

```bash
xcodebuild -scheme StoryPromptDebug -destination 'generic/platform=iOS' -configuration Debug build
```

Same model gate and `StoryPromptFeatureView` as the host; nav title `StoryPrompt · Debug`.

### Photo describe only (DEBUG)

```bash
xcodebuild -scheme PhotoDescribeDebug -destination 'generic/platform=iOS' -configuration Debug build
```

PhotosPicker → on-device VLM caption. Uses the **same** Qwen pack as Story Prompt (loaded with vision weights). Not composed into the host yet.

### Legacy reference app

```bash
xcodebuild -scheme VovozinhaLegacy -destination 'generic/platform=iOS' -configuration Debug build
```

### Unit tests (Mac — no device / no live model)

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

cd Packages/StoryPromptKit && swift test
cd Packages/PhotoDescribeKit && swift test
```

Mocks only. Live MLX inference is validated on a **physical iPhone** after the model pack is installed.

## App flow

### Host / StoryPromptDebug

1. Language bar (system / PT / EN / ES)  
2. First launch: install the **~3 GB** model (Download, or HF page + Import)  
3. Enter a short **story description** (10–20 words)  
4. **Create story** → title, summary, **10 scenes**  

If the model is missing or inference fails → **error** (never a fabricated story).

### PhotoDescribeDebug

1. Install the same model pack if needed  
2. **Choose photo** (stays on device)  
3. **Describe photo** → short paragraph (people, then objects, then scene)

## Architecture

```
Packages/
  VovoUI/              shared theme, chrome, L10n
  StoryPromptKit/      seed → StoryDraft + MLX text path + model store
  PhotoDescribeKit/    photo → caption (VLM); depends on StoryPromptKit for the pack store
Apps/
  Vovozinha/           thin host
  StoryPromptDebug/    Story kit harness
  PhotoDescribeDebug/  Photo kit harness
Legacy/
  VovozinhaLegacy/     previous monolith
```

| Piece | Role |
|-------|------|
| `StoryFromPromptGenerating` | Feature boundary: seed → draft |
| `DeviceStoryGenerator` | Production story entry (pack required) |
| `OnDeviceMLXModelStore` | Application Support pack, CDN + SHA-256, Import |
| `PhotoDescribing` / `DevicePhotoDescriber` | Photo → caption (VLM factory) |
| Markdown under `Resources/` | UI strings + LLM/VLM prompts (edit & rebuild) |

Details: [`docs/MODULES.md`](docs/MODULES.md), [`docs/ON_DEVICE_LLM.md`](docs/ON_DEVICE_LLM.md).

### Model pack

| | |
|--|--|
| **CDN zip** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip` |
| **Checksum** | `…zip.sha256` (verified on host download) |
| **On device** | `Library/Application Support/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` |
| **Rebuild zip** | `./scripts/package_qwen35_4b_mlx_zip.sh` → `build/` (gitignored) |

Story text prefers the **LLM** factory (drops unused vision weights). Photo describe uses the **VLM** factory (keeps vision).

## Install a development `.ipa` on a physical iPhone

There is no App Store / TestFlight pipeline in this repo. You archive a **development-signed** IPA and install it yourself. Free-Apple-ID sideloads (e.g. via AltStore) typically expire about **every 7 days**.

Requires: Xcode signed into an Apple ID on team **FTS4YLJNG3** (or your own team — change `DEVELOPMENT_TEAM` / `teamID`), and a valid **Apple Development** certificate. The device must be allowed for that team’s development provisioning.

### 1. Build the IPA (CLI)

Replace **`Vovozinha`** with **`StoryPromptDebug`** or **`PhotoDescribeDebug`** to ship a single-feature harness instead of the host.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /path/to/vovozinha

SCHEME=Vovozinha          # or StoryPromptDebug / PhotoDescribeDebug
mkdir -p build

cat > build/exportOptions-development.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>FTS4YLJNG3</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>compileBitcode</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

xcodebuild archive \
  -project Vovozinha.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "build/${SCHEME}.xcarchive" \
  DEVELOPMENT_TEAM=FTS4YLJNG3 \
  CODE_SIGN_STYLE=Automatic

xcodebuild -exportArchive \
  -archivePath "build/${SCHEME}.xcarchive" \
  -exportPath build/ipa \
  -exportOptionsPlist build/exportOptions-development.plist
```

Artifact (gitignored): `build/ipa/<SchemeName>.ipa` (e.g. `build/ipa/Vovozinha.ipa`).

### 2. Install with AltStore (recommended for personal devices)

[AltStore](https://altstore.io) sideloads IPAs using your Apple ID, without App Store Connect. Pair **AltServer** (Mac or PC) with **AltStore** on the iPhone.

1. **Install AltServer** on your computer from [altstore.io](https://altstore.io) and keep it running when you install or refresh apps.  
2. **Install AltStore on the iPhone** (Mail plug-in / wire / Wi‑Fi — follow their current setup guide). Use the **same Apple ID** you will refresh with.  
3. On the iPhone (iOS 16+): enable **Developer Mode** if prompted (**Settings → Privacy & Security → Developer Mode**), then restart as directed.  
4. Copy `build/ipa/Vovozinha.ipa` (or the DEBUG IPA) onto the phone (Files, AirDrop, iCloud Drive, etc.).  
5. Open **AltStore → My Apps → +** → choose the `.ipa`.  
6. Wait for install; open the app. If iOS shows **Untrusted Developer**: **Settings → General → VPN & Device Management** → trust the certificate.  
7. **Refresh before expiry** (~7 days on a free Apple ID): open AltStore on the phone with AltServer reachable (same Wi‑Fi or USB as in their docs) → **My Apps** → refresh. Background refresh works when AltServer is available.

Caveats:

- Free accounts have a **small limit** on sideloaded apps.  
- A **team development IPA** must still match signing/provisioning (registered device / correct team). AltStore does not replace a Distribution profile or make an App Store install.  
- Prefer the official [AltStore](https://altstore.io) docs for cable vs Wi‑Fi and troubleshooting.

### 3. Install with Xcode

**Window → Devices and Simulators** → select the iPhone → **Installed Apps** → **+** → select the `.ipa`. Then trust the developer under **VPN & Device Management** if needed.

### 4. Install with Apple Configurator

Connect the device → **Add → Apps** → select the `.ipa`.

### Troubleshooting install

| Symptom | What to try |
|---------|-------------|
| Untrusted Developer | Trust the cert under **VPN & Device Management** |
| Install / launch fails | Device UDID not on the development profile; wrong team; rebuild with your `DEVELOPMENT_TEAM` |
| AltStore refresh fails | Start AltServer, same Apple ID, refresh from AltStore on the phone |
| App expires after ~7 days | Free-ID limit — refresh via AltStore or use a paid team / reinstall |
| “No profiles for bundle id” | Open the scheme once in Xcode with automatic signing so a profile is created |

## Privacy

- **Stories / exports** default under `Documents/Vovozinha/Exports/` (user can pick another folder).  
- **Model packs** stay in private Application Support (never Documents / Downloads).  
- Photos used in PhotoDescribe stay on-device.  
- No account, no required analytics, **no cloud generation or cloud TTS**.

## License

GNU Affero General Public License v3.0 (AGPL-3.0). See [LICENSE](LICENSE).

MLX / mlx-swift retain their upstream licenses. **Qwen3.5-4B** MLX community weights are **Apache-2.0**, independent of this repo’s AGPL-3.0.
