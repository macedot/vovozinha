# Vovozinha — agent notes

## Project overview
- Offline-first **kids bedtime stories** iOS app. Content for kids ~3–8; the app's users are parents/caregivers **18+** (there is an age gate).
- **No cloud AI for generation** — all inference is on-device. The network is used only to *download model assets once*; after that the app is fully offline.
- Devices: **physical iPhone 15+ only** (iOS Simulator is **not supported**). Deployment target **iOS 18.0+**, iPhone only.
- Languages **pt-BR / en-US / es-ES** (default = system language).
- License: AGPL-3.0. Development happens on branch `multi`.

## Repository layout (modular architecture, branch `multi`)
```
Packages/
  VovoUI/                 # shared theme + screen chrome + localization (SwiftPM)
  StoryPromptKit/         # feature kit: seed prompt → story draft (SwiftPM)
Apps/
  Vovozinha/              # product host app — thin, composes feature kits
  StoryPromptDebug/       # DEBUG-only harness app running StoryPromptKit alone
  VovozinhaUITests/       # XCUITest UI tests for the host app
Legacy/
  VovozinhaLegacy/        # previous full monolithic product (kept for reference/migration)
VovozinhaTests/           # STALE — see "Testing" below
docs/                     # MODULES.md (architecture), SPIKE.md (AI stack), IMAGE_PACK.md (art pack)
scripts/download_sd_pack.sh  # optional Core ML Stable Diffusion art pack installer
```

- **Feature pattern (app + lib):** logic + UI surface live in a kit under `Packages/<Feature>Kit` (models, protocols, generators, `<Feature>FeatureView`); a harness app under `Apps/<Feature>Debug` shows that one feature with `VovoUI` chrome; the host `Apps/Vovozinha` imports kits and composes them. See `docs/MODULES.md`.
- **VovoUI** provides `VovoTheme`, `VovoScreen`, `LanguageBar`, `LanguageStore`, `AppLanguage`, `VovoL10n`, and `MarkdownTextCatalog` (loads `## key` sections with `{{placeholders}}` from Markdown files).
- Stack: **SwiftUI + SwiftData**, **Swift 6** (`swift-tools-version: 6.0`). SPM packages target iOS 18 / macOS 14.

## Current feature: Story Prompt
- Input: free-form **story seed**, **10–20 words** (validated by `StorySeedPrompt`).
- Output: `StoryDraft` = title, summary, **exactly 10 paragraphs**, with the story language pinned on `StoryDraft.language`.
- Feature boundary protocol: `StoryFromPromptGenerating`. **No static / template story generation.**
  - `DeviceStoryGenerator` — **default**. Model missing → `modelNotInstalled`; inference/parse failure → error. Never invents a story body.
  - `MLXBonsaiStoryGenerator` — on-device LLM via **MLX** + **prism-ml/Bonsai-27B-mlx-1bit** (~5.13 GB pack). Runtime: Prism `mlx-swift` (1-bit) + `mlx-swift-lm` @ 3.31.4. Parses `TITLE:` / `SUMMARY:` + **exactly 10** blank-line-separated paragraphs; fewer than 10 → failure. Sampling: temperature 0.7 / topK 20 / topP 0.95 / maxTokens 1024.
  - **Model install:** automatic download from `https://files.kraftek.dev/bonsai/Bonsai-27B-mlx-1bit.zip` into `Documents/Vovozinha/Models/Bonsai-27B-mlx-1bit/`. Fallback: open Hugging Face model page + user **Import** zip or folder from Files/Downloads.
  - **Status:** Bonsai **did not meet quality on device tests** — expect another backend swap. Stable seams + checklist: `docs/ON_DEVICE_LLM.md`.
- **Markdown on disk** (edit, rebuild):
  - UI: `Packages/VovoUI/Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md`
  - Story prompts: `Packages/StoryPromptKit/.../Resources/Prompts/litert.<lang>.md` (description placeholders must be filled — `StoryPromptTemplate`).

## Build & test
Requires **Xcode 27 beta** (`/Applications/Xcode-beta.app`); always set `DEVELOPER_DIR` first.

> **One-time setup — Bonsai MLX local checkouts (required to build).** `StoryPromptKit` depends on **local path** packages for Prism 1-bit kernels:
> ```bash
> ./scripts/setup_bonsai_mlx.sh   # from the vovozinha repo
> # Clones siblings: ../mlx-swift (Prism @ prism) and ../mlx-swift-lm @ 3.31.4
> # (mlx-swift-lm is patched to path-depend on Prism mlx-swift; pinned so it matches ~0.31.1 APIs)
> xcodebuild -downloadComponent MetalToolchain   # once per Xcode beta if metal tool missing
> ```
> Do **not** move those checkouts inside the vovozinha repo. After setup: Xcode → Packages → Reset Package Caches, then clean build. Metal shaders require the Metal Toolchain.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Host app (physical device / generic iOS — not the Simulator)
xcodebuild -scheme Vovozinha -destination 'generic/platform=iOS' build

# Single kit in isolation (DEBUG harness)
xcodebuild -scheme StoryPromptDebug -destination 'generic/platform=iOS' build

# StoryPromptKit unit tests (macOS package tests; mocks only — no real model)
cd Packages/StoryPromptKit && swift test

# Legacy reference app
xcodebuild -scheme VovozinhaLegacy -destination 'generic/platform=iOS' build
```
Shared schemes (in `Vovozinha.xcodeproj/xcshareddata/xcschemes`): **Vovozinha** (host), **StoryPromptDebug** (kit harness), **VovozinhaLegacy** (old monolith). The `StoryPromptKit` scheme is auto-generated by Xcode from the package for running its unit tests.

## Testing
- **StoryPromptKitTests**: seed validation, prompt placeholder injection, Bonsai parse/normalize, `DeviceStoryGenerator` throws without model; MLX tests use mock sessions only. Live inference only on a **physical device** after model download.
- **VovozinhaUITests** (`Apps/VovozinhaUITests/`): optional XCUITest harness for the host app (seed → story flow, language bar). Accessibility identifiers: `storySeedField`, `createStoryButton`, `storyResult`, `language.en/pt/es`. Prefer validating story generation on a physical device.
- **VovozinhaTests** (`VovozinhaTests/`): **stale**. The target still exists in the project but is wired into no scheme's test action, and its sources test legacy-domain types (`DeviceProfile`, `KidsSafetyFilter`, `FoundationModelsStoryPlanner`, …) that are not part of the thin host target. Treat as legacy reference, not a suite to run; port or delete when touching it.

## Code norms
- Prefer small, focused diffs. New product work goes in **kits + host**, never in `Legacy/`.
- Match the surrounding style: `Sendable` value types, dependency injection via protocol + initializer defaults, doc comments on public API.
- Kids-safety and offline-first rules are hard constraints: no cloud generation, no cloud TTS, no accounts, no required analytics. User data stays under `Documents/Vovozinha/`.
- Pin a story's language on `StoryDraft.language`; UI and offline story body follow the `LanguageStore` selection.
- Parent-facing copy must stay parent-friendly — no model codenames (e.g. "VAEEncoder", "Core ML") in UI strings; those belong in docs/dev tooling only.
- Narration / image packs remain legacy-only until ported as kits. Optional neural art pack: `./scripts/download_sd_pack.sh` (see `docs/IMAGE_PACK.md`); procedural art is the fallback. The Legacy target links `apple/ml-stable-diffusion` (`StableDiffusion` product) for that pack.
- **Licensing — Bonsai / MLX:** MLX / mlx-swift are under their upstream licenses (typically Apache-2.0 / MIT — keep NOTICE attribution). **Bonsai-27B-mlx-1bit** weights are **Apache-2.0** (Prism ML). Independent of this repo's AGPL-3.0 license.
- `.gitignore` excludes `.cache/`, `**/.build/`, model bundles (`*.mlmodel`, `*.mlpackage`, `/Models/`). `.pbx_ids.json` is a local agent/helper file, also ignored.
