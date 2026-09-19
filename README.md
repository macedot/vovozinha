<h1 align="center">Vovozinha</h1>

<p align="center"><strong>Offline 10-page bedtime storybooks on iPhone — on-device AI only</strong></p>

<p align="center">
  <img src="https://img.shields.io/github/license/macedot/vovozinha?color=blue" alt="License" />
  <img src="https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white" alt="iOS 18+" />
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/SwiftUI-5-F05138?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/device-physical%20iPhone-important" alt="Physical iPhone" />
  <img src="https://img.shields.io/badge/AI-on--device%20MLX-blueviolet" alt="On-device MLX" />
</p>

---

**Vovozinha** turns a short description into a 10-page bedtime book for kids (~ages 5–9). A parent or caregiver (**18+**) types 10–20 words; the phone writes the story with an on-device LLM. The network is used only to **download the model pack once** from `vovo.kraftek.cloud`. After that, generation is fully offline.

> **The iOS Simulator is not supported.** Build, run, and test on a **physical iPhone**.

## Features

- **Story from a required description** — 10–20 words → title, summary, **exactly 10 paragraphs** (no static / template stories)
- **On-device Qwen** — [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) via MLX; CDN zip + SHA-256 sidecar; Import from Files as fallback
- **Text reader** — swipeable 10-page reader, no pictures
- **pt-BR / en-US / es-ES** — UI, story, and prompts from Markdown on disk; language bar, default = system
- **Privacy-first** — no accounts, no cloud generation; the model pack stays in private Application Support

## Quick Start

```bash
git clone https://github.com/macedot/vovozinha.git
cd vovozinha
git checkout v1

# Sibling MLX checkouts (../mlx-swift + ../mlx-swift-lm)
./scripts/setup_mlx_local.sh

# Physical iPhone, wired, Developer Mode on
export DEVELOPER_DIR=/Applications/Xcode-beta.app
./scripts/deploy.sh
```

`deploy.sh` builds the **Vovozinha** scheme, installs it on the connected iPhone, and launches it. First launch: download (or Import) the **story model** over Wi-Fi.

### From Xcode

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# If Metal tools are missing on Xcode beta:
xcodebuild -downloadComponent MetalToolchain

open Vovozinha.xcodeproj
```

Select a **physical iPhone**, scheme **Vovozinha**, Run. Team `FTS4YLJNG3` (or your own — change `DEVELOPMENT_TEAM` in `project.yml` and regenerate).

## Configuration

| Setting        | Default | Description |
| -------------- | ------- | ----------- |
| Description    | 10–20 words | Required parent-typed story idea; Create stays disabled without it |
| Languages      | system → pt-BR / en-US / es-ES | Language bar; prompts follow the UI language |
| Story model    | `Qwen3.5-4B-MLX-4bit` | ~3 GB zip from the CDN; ~2.4 GB resident |
| CDN            | `vovo.kraftek.cloud` | Only network host; SHA-256 sidecar on every download |
| Pages          | exactly 10 | Parse failures are errors — never padded with template text |

### Model pack

| Pack | URL | On device |
| ---- | --- | --------- |
| Qwen 4-bit MLX | `https://vovo.kraftek.cloud/qwen/Qwen3.5-4B-MLX-4bit.zip` (+ `.sha256`) | `Library/Application Support/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` |

Manual **Import** (zip or folder) is the no-checksum fallback. Rebuild the zip with `./scripts/package_qwen35_4b_mlx_zip.sh` (output under gitignored `build/`).

## Development

### Prerequisites

- macOS with **Xcode 27 beta** at `/Applications/Xcode-beta.app`
- iOS **18.0+**, iPhone only (no Catalyst, no Simulator)
- Apple Developer Team for device installs
- Sibling checkouts next to this repo:
  - `../mlx-swift` — Prism fork (`./scripts/setup_mlx_local.sh`)
  - `../mlx-swift-lm` — tagged 3.31.4, patched to path-depend on that mlx-swift

The Xcode project is generated from `project.yml` (XcodeGen). `deploy.sh` / `test.sh` regenerate it if `Vovozinha.xcodeproj` is missing.

```bash
xcodegen generate
```

### Local development

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
IPHONE_UDID=YOUR_DEVICE_UDID ./scripts/deploy.sh
```

`IPHONE_UDID` is required and must identify the connected physical iPhone. Bundle id: `app.vovozinha.Vovozinha`. The host is a thin `NavigationStack` around `StorybookFeatureView`.

### Testing

Package tests run on the Mac with **mocks only** (no live model, no Simulator app run):

```bash
swift test --package-path Packages/StorybookKit
swift test --package-path Packages/StoryPromptKit
```

Live inference is validated on a **physical iPhone** after the model pack is installed (`./scripts/deploy.sh`). `./scripts/test.sh` is the inas-style `xcodebuild test` on the connected device; the host scheme has no XCTest target yet, so the package suites above are the tests that run today.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ iPhone (physical)                                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ SwiftUI                                               │  │
│  │  LanguageBar  ·  model gate  ·  description field     │  │
│  │  StorybookFeatureView  →  10-page reader              │  │
│  └────────────────────────────┬──────────────────────────┘  │
│                               │                             │
│  ┌────────────────────────────▼──────────────────────────┐  │
│  │ SeedPipeline                                          │  │
│  │  [1] StoryFromPromptGenerating (Qwen / MLX)           │  │
│  │  [2] pageTextsReady  ← story is shown here            │  │
│  └────────────────────────────┬──────────────────────────┘  │
│                               │                             │
│  Qwen 4-bit · never a static or template story            │
└─────────────────────────────────────────────────────────────┘
```

**How it works:**

1. **Gate** — the model pack must be present (Download from `vovo.kraftek.cloud` with SHA-256 verify, or Import)
2. **Describe** — the parent types the story description (10–20 words, required; Create is disabled until it validates)
3. **Story** — Qwen writes `TITLE:` / `SUMMARY:` / 10 paragraphs in the UI language. One automatic retry on parse failure. Never fabricates paragraphs
4. **Reader** — the 10 text pages open in a swipeable reader
5. **History** — the books icon opens saved storybooks; metadata is stored locally in `Documents/Vovozinha/Stories/history.json`, with reopen and delete actions

```
Apps/Vovozinha/          thin host (StorybookFeatureView)
Packages/VovoUI/         theme, chrome, language bar, Markdown L10n
Packages/StoryPromptKit/ seed, Qwen MLX session, model store
Packages/StorybookKit/   SeedPipeline, reader UI, story file store
scripts/                 deploy, test, mlx setup, packagers
project.yml              XcodeGen → Vovozinha.xcodeproj
```

Story text loads Qwen through the **LLM** factory (drops unused `vision_tower` weights).

## Privacy

- **No cloud inference** — network is pack download from `vovo.kraftek.cloud` only
- **No Hugging Face / third-party download path** in the app
- **Model pack** lives in Application Support (backup-excluded, never Files → On My iPhone)
- **Story history metadata** stays in `Documents/Vovozinha/Stories/history.json`
- **Increased memory entitlement** — `com.apple.developer.kernel.increased-memory-limit` for the ~2.4 GB Qwen resident set
- No accounts, no required analytics, no cloud TTS

## License

Vovozinha is licensed under the [GNU Affero General Public License v3.0](LICENSE).

MLX / mlx-swift retain their upstream licenses. **Qwen3.5-4B** MLX community weights are **Apache-2.0**, independent of this repo’s AGPL-3.0.
