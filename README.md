# Vovozinha

Offline-first **children’s bedtime stories** for iOS.

> **WARNING: This project does NOT support the iOS Simulator.**  
> Develop, run, and test story generation on a **physical iPhone** (or install a development `.ipa`).  
> Simulator usage is unsupported and will not provide a working product experience.

**Branch `multi`:** modular architecture — feature kits + DEBUG harness apps + thin host.  
See [`docs/MODULES.md`](docs/MODULES.md).

Legacy monolithic app: scheme **VovozinhaLegacy** (reference only).

| | |
|--|--|
| **Content** | Kids ~3–8 |
| **Who uses the app** | Parents / caregivers **18+** |
| **Devices** | **iPhone 15+** (physical device) |
| **AI** | **Strictly on-device** (no cloud generation) |
| **Languages** | **pt-BR / en-US / es-ES** (language bar; default = system) |
| **This phase** | Story description → **on-device LiteRT-LM only** (10 scenes) |

## Story generation (this phase)

- Short **story description** (about **10–20 words**).
- **On-device LiteRT-LM only** (Gemma model must be installed on the device).
- **No static / template story generation.** If the model is missing or inference fails, creation **fails** with an error.
- Output: title, summary, **exactly 10 scene paragraphs**.
- Languages: **pt-BR / en-US / es-ES**.
- **No cloud AI** for generation.

### Who can generate today

| Device | Stories |
|--------|---------|
| **Physical iPhone 15+** with LiteRT-LM model downloaded | **Yes** — on-device LLM |
| Model not installed / inference fails | **No** — error (no fake story) |
| **iOS Simulator** | **Not supported** |

## Dev requirements

| Item | Value |
|------|--------|
| macOS | Beta ok |
| Xcode | **Xcode 27 beta** (`/Applications/Xcode-beta.app`) |
| Deployment | iOS **18.0+**, iPhone only |
| Run target | **Physical device** only |

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
open /Users/thiago/Projects/vovozinha/Vovozinha.xcodeproj
```

Build for a connected device (replace the destination id with yours):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thiago/Projects/vovozinha
xcodebuild -scheme Vovozinha -destination 'generic/platform=iOS' -configuration Debug build
```

Unit tests for the kit (macOS host, no device required):

```bash
cd Packages/StoryPromptKit && swift test
```

## App flow (multi host)

1. Language bar (system / PT / EN / ES)  
2. Enter a short **story description** (10–20 words)  
3. **Create story** — requires on-device LiteRT-LM model  
4. Scroll to read title, summary, and 10 scenes  

## Architecture (summary)

- Host: `Apps/Vovozinha` + kits `Packages/StoryPromptKit`, `Packages/VovoUI`  
- Protocol: `StoryFromPromptGenerating`  
- Default: `DeviceStoryGenerator` → **LiteRT-LM only** (no static body)  
- UI strings + LLM prompt files: Markdown under package `Resources/`  

See `docs/MODULES.md` and `AGENTS.md`.

## Install a development `.ipa` (physical device)

On branch **`multi`**, the **Vovozinha** host is the story-generation app  
(`app.vovozinha.Vovozinha`). You can archive a **development-signed** IPA for devices on the Apple Developer team. This is **not** an App Store / TestFlight build.

### Build the IPA (CLI)

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thiago/Projects/vovozinha

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
  -scheme Vovozinha \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Vovozinha.xcarchive \
  DEVELOPMENT_TEAM=FTS4YLJNG3 \
  CODE_SIGN_STYLE=Automatic

xcodebuild -exportArchive \
  -archivePath build/Vovozinha.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist build/exportOptions-development.plist
```

Artifact (gitignored): `build/ipa/Vovozinha.ipa`.

Requires Xcode signed in with an Apple ID on team **FTS4YLJNG3**, and a valid **Apple Development** certificate. App Store / Ad Hoc export needs a Distribution certificate (not covered here).

### Install on an iPhone

**1. Xcode**  
Window → **Devices** → select the phone → under Installed Apps, **+** → choose `Vovozinha.ipa`.  
Then on the phone: **Settings → General → VPN & Device Management** → trust the developer.

**2. Apple Configurator**  
Connect the device → Add → Apps → select the `.ipa`.

**3. AltStore / AltServer** ([altstore.io](https://altstore.io))  
Useful for sideloading without App Store Connect on a personal device:

1. Install **AltServer** on Mac/PC and **AltStore** on the iPhone (same network / cable as in their docs).  
2. In AltStore: **My Apps → +** → pick `Vovozinha.ipa`.  
3. Enable **Developer Mode** on the device when iOS asks (iOS 16+).

Caveats:

- Free-Apple-ID sideloads typically expire about **every 7 days** and must be **refreshed** via AltStore while AltServer is reachable.  
- Sideloading has a small app slot limit.  
- A **team development IPA** still has to match provisioning (device registered to the team / signing identity). AltStore cannot turn an arbitrary binary into a permanent App Store install.  
- Prefer the official [AltStore](https://altstore.io) setup guide for Wi‑Fi/wire details.

### Using the story-generation app

1. Pick language (**PT / EN / ES**) on the language bar.  
2. Type a short **story description** (about **10–20 words**).  
3. **Model install (first time):**  
   - Tap **Download model** — automatic fetch from [files.kraftek.dev](https://files.kraftek.dev/gemma4/gemma-4-E4B-it.litertlm) (**Wi‑Fi**, ~3.5 GB).  
   - If that fails: **Open backup download page** (Hugging Face) → save to **Downloads** → **Import from Files**.  
   - Declining leaves story creation unavailable until the model is installed.  
4. After the model is ready, enter a description and tap **Create story**.  
5. Scroll to read title, summary, and **10 scenes** (model output only).

### Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Untrusted Developer | Trust the cert under VPN & Device Management |
| Install fails | Device UDID not on the development profile; wrong team |
| AltStore refresh fails | Start AltServer, same Apple ID, refresh from AltStore on the phone |

## Privacy

Photos and stories stay under `Documents/Vovozinha/`. No account, no required analytics, **no cloud generation or cloud TTS**. Optional downloads (voice/model packs) only install files; synthesis stays on-device.

## License

GNU Affero General Public License v3.0 (AGPL-3.0). See [LICENSE](LICENSE).
