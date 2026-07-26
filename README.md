# Vovozinha

Offline-first **children’s bedtime stories** for iOS.

**Branch `multi`:** modular architecture — feature kits + DEBUG harness apps + thin host.  
See [`docs/MODULES.md`](docs/MODULES.md).

Legacy monolithic app: scheme **VovozinhaLegacy**.

| | |
|--|--|
| **Content** | Kids ~3–8 |
| **Who uses the app** | Parents / caregivers **18+** |
| **Devices** | **iPhone 15+** |
| **AI** | **Strictly on-device** (no cloud generation) |
| **Languages** | **pt-BR / en-US / es-ES** (language bar; default = system) |
| **This phase** | Stories + **offline procedural page art** (neural pack later) |

## Story generation (this phase)

- **Body text:** local **LLM only** — Apple **Foundation Models** when available.
- **No** pre-written / template story body in the product path.
- **10 pages** = one continuous chronological story split into 10 paragraphs.
- Target **~280 words** total (band ~150–480); **3–5 short sentences per page** with sensory scene detail.
- **Kids content filter** with rewrite retries until pass.
- **Graphics:** on-device art per page — **Core ML Stable Diffusion pack** when installed (text2img + img2img continuity), else **procedural** fallback. Install: `./scripts/download_sd_pack.sh` (see `docs/IMAGE_PACK.md`).

### Who can generate today

| Device / OS | Stories |
|-------------|---------|
| **iOS 26+** with **Apple Intelligence** (typically Pro-class / A17+) | **Yes** — Foundation Models |
| **iPhone 15 / 15 Plus (A16)** | **Not yet** — needs optional **local LLM pack** (stub; coming later) |
| Older / no FM assets | No — clear in-app message; no template fallback |
| Simulator | Usually no FM path; UI works |

## Dev requirements

| Item | Value |
|------|--------|
| macOS | Beta ok |
| Xcode | **Xcode 27 beta** (`/Applications/Xcode-beta.app`) |
| Deployment | iOS **18.0+**, iPhone only |
| Simulator | iOS 27 (e.g. iPhone 17) for UI |

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
open /Users/thiago/Projects/vovozinha/Vovozinha.xcodeproj
```

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thiago/Projects/vovozinha
xcodebuild -scheme Vovozinha -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

## App flow

1. **18+** age gate  
2. Language bar (system / PT / EN / ES)  
3. **Quick create** — description + optional photo; rest randomized  
4. **Custom create** — full form (world, lesson, age, style, idea)  
5. **Generate** — character → on-device LLM story → library  
6. **Reader** — swipe text pages, TTS in story language, parent read-aloud, text PDF  
7. **Library** offline  

## Architecture (summary)

- SwiftUI + SwiftData  
- Protocols: `CharacterAnalyzing`, `StoryPlanning`, `Illustrating`  
- Product planner: `FoundationModelsStoryPlanner` or `UnavailableLLMStoryPlanner`  
- Scene beat labels: `StorySceneTags` (not a story body source)  
- Illustrator: scene-aware **procedural** art; swap-in for local neural pack later  


See `docs/SPIKE.md` and `AGENTS.md`.

## Install a development `.ipa` (physical device)

On branch **`multi`**, the **Vovozinha** host is the story-generation app  
(`app.vovozinha.Vovozinha`). You can archive a **development-signed** IPA for devices on the Apple Developer team. This is **not** an App Store / TestFlight build.

### Build the IPA (CLI)

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thiago/Projects/vovozinha

# exportOptions (development)
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
Window → Devices and Simulators → select the phone → under Installed Apps, **+** → choose `Vovozinha.ipa`.  
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
3. Tap **Create story** — on-device / offline path produces title, summary, and **10 scenes**.  
4. Scroll to read the full draft.

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
