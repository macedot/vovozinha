<h1 align="center">Vovozinha</h1>

<p align="center"><strong>Offline 10-page bedtime storybooks on iPhone — on-device AI only</strong></p>

<p align="center">
  <img src="https://img.shields.io/github/license/macedot/vovozinha?color=blue" alt="License" />
  <img src="https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white" alt="iOS 18+" />
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/SwiftUI-5-F05138?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/device-physical%20iPhone-important" alt="Physical iPhone" />
  <img src="https://img.shields.io/badge/AI-on--device%20MLX%20%2B%20Core%20ML-blueviolet" alt="On-device MLX + Core ML" />
</p>

---

**Vovozinha** turns a short idea — and optionally a photo — into an illustrated 10-page bedtime book for kids (~ages 5–9). A parent or caregiver (**18+**) types 10–20 words; the phone writes the story with an on-device LLM and draws each page with on-device Stable Diffusion. The network is used only to **download the two model packs once** from `vovo.kraftek.cloud`. After that, generation is fully offline.

> **The iOS Simulator is not supported.** Build, run, and test on a **physical iPhone**.

## Features

- **Story from a short seed** — 10–20 words → title, summary, **exactly 10 paragraphs** (no static / template stories)
- **Optional photo** — a vision pass captions people, objects, and places; those elements are woven into the story. The photo is **never** used as an img2img base
- **On-device Qwen** — [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) via MLX; CDN zip + SHA-256 sidecar; Import from Files as fallback
- **On-device pictures** — Core ML SD 1.5 (`AnimeImg2Img-SD15`); **txt2img** per page, kids-locked style + negative prompt
- **Text first** — the 10 pages appear as soon as the story exists; pictures fill in one by one (cover first, then 2…10)
- **pt-BR / en-US / es-ES** — UI, story, and prompts from Markdown on disk; language bar, default = system
- **Privacy-first** — no accounts, no cloud generation, no cloud TTS; packs stay in private Application Support

## Quick Start

```bash
git clone https://github.com/macedot/vovozinha.git
cd vovozinha
git checkout multi

# Sibling MLX checkouts (../mlx-swift + ../mlx-swift-lm)
./scripts/setup_mlx_local.sh

# Physical iPhone, wired, Developer Mode on
export DEVELOPER_DIR=/Applications/Xcode-beta.app
./scripts/deploy.sh
```

`deploy.sh` builds the **Vovozinha** scheme, installs it on the connected iPhone, and launches it. First launch: download (or Import) the **story model**, then the **picture pack**, over Wi-Fi.

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
| Seed length    | 10–20 words | Parent-typed story idea |
| Languages      | system → pt-BR / en-US / es-ES | Language bar; prompts follow the UI language |
| Story model    | `Qwen3.5-4B-MLX-4bit` | ~3 GB zip from the CDN; ~2.4 GB resident |
| Picture pack   | `AnimeImg2Img-SD15` | ~2 GB zip; SD 1.5 Core ML (chunked UNet + VAE) |
| CDN            | `vovo.kraftek.cloud` | Only network host; SHA-256 sidecar on every download |
| Pages          | exactly 10 | Parse failures are errors — never padded with template text |
| Page art       | txt2img, 512×512 | 25 steps, CFG 6, DPM-Solver; per-page seed from a stable story-id hash |
| Photo          | optional | Caption only; never the diffusion starting image |
| Memory floor   | 900 MB free | Core ML pipeline refuses to load below this |

### Model packs

| Pack | URL | On device |
| ---- | --- | --------- |
| Qwen 4-bit MLX | `https://vovo.kraftek.cloud/qwen/Qwen3.5-4B-MLX-4bit.zip` (+ `.sha256`) | `Library/Application Support/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` |
| Anime SD 1.5   | `https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip` (+ `.sha256`) | `Library/Application Support/Vovozinha/ImagePack/Resources/` |

Manual **Import** (zip or folder) is the no-checksum fallback. Rebuild the zips with `./scripts/package_qwen35_4b_mlx_zip.sh` and `./scripts/package_anime_img2img_mlpackage.sh` (outputs under gitignored `build/`).

## Development

### Prerequisites

- macOS with **Xcode 27 beta** at `/Applications/Xcode-beta.app`
- iOS **18.0+**, iPhone only (no Catalyst, no Simulator)
- Apple Developer Team for device installs
- Sibling checkouts next to this repo:
  - `../mlx-swift` — Prism fork (`./scripts/setup_mlx_local.sh`)
  - `../mlx-swift-lm` — tagged 3.31.4, patched to path-depend on that mlx-swift
  - `../ml-stable-diffusion` — Apple 1.1.1 (vendors BPETokenizer; no transformers 0.1.8 clash)

The Xcode project is generated from `project.yml` (XcodeGen). `deploy.sh` / `test.sh` regenerate it if `Vovozinha.xcodeproj` is missing.

```bash
xcodegen generate
```

### Local development

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
./scripts/deploy.sh
```

Override the phone with `IPHONE_UDID=…` if needed. Bundle id: `app.vovozinha.Vovozinha`. The host is a thin `NavigationStack` around `StorybookFeatureView`.

### Testing

Package tests run on the Mac with **mocks only** (no live model, no Simulator app run):

```bash
swift test --package-path Packages/StorybookKit
swift test --package-path Packages/StoryPromptKit
swift test --package-path Packages/PhotoDescribeKit
swift test --package-path Packages/ImageGenKit
```

Live inference is validated on a **physical iPhone** after both packs are installed (`./scripts/deploy.sh`). `./scripts/test.sh` is the inas-style `xcodebuild test` on the connected device; the host scheme has no XCTest target yet, so the package suites above are the tests that run today.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ iPhone (physical)                                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ SwiftUI                                               │  │
│  │  LanguageBar  ·  dual pack gate  ·  seed + photo      │  │
│  │  StorybookFeatureView  →  10-page reader              │  │
│  └────────────────────────────┬──────────────────────────┘  │
│                               │                             │
│  ┌────────────────────────────▼──────────────────────────┐  │
│  │ SeedPipeline                                          │  │
│  │  [1] PhotoDescribing (VLM, optional)                  │  │
│  │  [2] StoryFromPromptGenerating (Qwen / MLX)           │  │
│  │  [3] pageTextsReady  ← story is shown here            │  │
│  │  [4] IllustrationPromptGenerating (or paragraph fallback)│
│  │  [---] MemorySequencer releases MLX                   │  │
│  │  [5] ImageGenerating txt2img, one page at a time      │  │
│  └────────────────────────────┬──────────────────────────┘  │
│                               │                             │
│  Qwen 4-bit  ·  Core ML SD1.5  ·  never resident together   │
└─────────────────────────────────────────────────────────────┘
```

**How it works:**

1. **Gate** — both packs must be present (Download from `vovo.kraftek.cloud` with SHA-256 verify, or Import)
2. **Caption** — if a photo was picked, Qwen-as-VLM writes a short element list (people → objects → place)
3. **Story** — Qwen writes `TITLE:` / `SUMMARY:` / 10 paragraphs in the UI language; caption elements are woven in. One automatic retry on parse failure. Never fabricates paragraphs
4. **Reader** — texts are published immediately so a later picture-prompt miss cannot hide the book
5. **Scene prompts** — a second LLM pass asks for a `CHARACTER:` lock plus 10 English scene lines. If that parse fails, each page uses the paragraph itself
6. **Handoff** — drop MLX (`MLX.Memory.clearCache()`), wait, load Core ML only if ≥ 900 MB is free
7. **Pictures** — txt2img, cover first then 2…10, one at a time. CLIP prompt is scene + short character lock + kids style prefix; locked negative (no photoreal, nsfw, violence, text). A failed page does not drop the story
8. **Files** — `Documents/Vovozinha/Stories/<storyID>/page-N.png` (parent-visible). Packs stay out of Documents

```
Apps/Vovozinha/          thin host (StorybookFeatureView)
Packages/VovoUI/         theme, chrome, language bar, Markdown L10n
Packages/StoryPromptKit/ seed, Qwen MLX session, model store
Packages/PhotoDescribeKit/ photo → caption (VLM, same Qwen pack)
Packages/ImageGenKit/    Core ML SD txt2img / img2img, image pack store
Packages/StorybookKit/   SeedPipeline, reader UI, story file store
scripts/                 deploy, test, mlx setup, packagers
project.yml              XcodeGen → Vovozinha.xcodeproj
```

Story text loads Qwen through the **LLM** factory (drops unused `vision_tower` weights). Photo describe uses the **VLM** factory (keeps vision). Image gen uses a local `ml-stable-diffusion` 1.1.1 checkout so it can share the graph with transformers 1.x.

## Privacy

- **No cloud inference** — network is pack download from `vovo.kraftek.cloud` only
- **No Hugging Face / third-party download path** in the app
- **Model packs** live in Application Support (backup-excluded, never Files → On My iPhone)
- **Stories / page PNGs** live under `Documents/Vovozinha/Stories/`
- **Photos** stay on-device; used for a caption, not uploaded, not remixed as the page image
- **Kids-safe imagery** — locked negative prompt scaffold; SafetyChecker is stripped from the pack
- **Increased memory entitlement** — `com.apple.developer.kernel.increased-memory-limit` for the ~2.4 GB Qwen resident set
- No accounts, no required analytics, no cloud TTS

## License

Vovozinha is licensed under the [GNU Affero General Public License v3.0](LICENSE).

MLX / mlx-swift retain their upstream licenses. **Qwen3.5-4B** MLX community weights are **Apache-2.0**, independent of this repo’s AGPL-3.0. Apple [ml-stable-diffusion](https://github.com/apple/ml-stable-diffusion) remains under its own license.
