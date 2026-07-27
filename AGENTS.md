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
  - `LiteRTLMStoryGenerator` — on-device LLM via **LiteRT-LM** (Gemma 4 E4B weights as `gemma-4-E4B-it.litertlm`). Runtime checkout `../../../LiteRT-LM` at v0.13.1. Parses `TITLE:` / `SUMMARY:` + **exactly 10** blank-line-separated paragraphs; fewer than 10 → failure. Sampling: temperature 0.9 / topK 40 / topP 0.95 / random seed per generation.
  - **Model install:** automatic download from `https://files.kraftek.dev/gemma4/gemma-4-E4B-it.litertlm` into `Documents/Vovozinha/Models/`. Fallback: open Hugging Face model page + user **Import** from Files/Downloads.
- **Markdown on disk** (edit, rebuild):
  - UI: `Packages/VovoUI/Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md`
  - LiteRT prompts only: `Packages/StoryPromptKit/.../Resources/Prompts/litert.<lang>.md` (description placeholders must be filled — `StoryPromptTemplate`).

## Build & test
Requires **Xcode 27 beta** (`/Applications/Xcode-beta.app`); always set `DEVELOPER_DIR` first.

> **One-time setup — LiteRT-LM local checkout (required to build).** `StoryPromptKit` depends on LiteRT-LM as a **local path package** (`../../../LiteRT-LM` → sibling of the vovozinha folder under `Projects/`) because remote SPM resolution is flaky ([google-ai-edge/LiteRT-LM#2407](https://github.com/google-ai-edge/LiteRT-LM/issues/2407)). Set it up once:
> ```bash
> git clone -b v0.13.1 https://github.com/google-ai-edge/LiteRT-LM.git /Users/thiago/Projects/LiteRT-LM
> cd /Users/thiago/Projects/LiteRT-LM && git lfs install --local && git lfs pull
> # XCFrameworks (CLiteRTLM) — required; without them Xcode reports "No XCFramework found":
> ./scripts/setup_litert_xcframeworks.sh   # from the vovozinha repo
> # or manually unzip v0.13.0 CLiteRTLM*.xcframework.zip into LiteRT-LM/.xcframeworks/
> ```
> Do **not** move the checkout inside the vovozinha repo. After adding frameworks: Xcode → Packages → Reset Package Caches, then clean build.

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
- **StoryPromptKitTests**: seed validation, litert prompt placeholder injection, LiteRT parse/normalize, `DeviceStoryGenerator` throws without model; LiteRT tests use mock sessions only. Live inference only on a **physical device** after model download.
- **VovozinhaUITests** (`Apps/VovozinhaUITests/`): optional XCUITest harness for the host app (seed → story flow, language bar). Accessibility identifiers: `storySeedField`, `createStoryButton`, `storyResult`, `language.en/pt/es`. Prefer validating story generation on a physical device.
- **VovozinhaTests** (`VovozinhaTests/`): **stale**. The target still exists in the project but is wired into no scheme's test action, and its sources test legacy-domain types (`DeviceProfile`, `KidsSafetyFilter`, `FoundationModelsStoryPlanner`, …) that are not part of the thin host target. Treat as legacy reference, not a suite to run; port or delete when touching it.

## Code norms
- Prefer small, focused diffs. New product work goes in **kits + host**, never in `Legacy/`.
- Match the surrounding style: `Sendable` value types, dependency injection via protocol + initializer defaults, doc comments on public API.
- Kids-safety and offline-first rules are hard constraints: no cloud generation, no cloud TTS, no accounts, no required analytics. User data stays under `Documents/Vovozinha/`.
- Pin a story's language on `StoryDraft.language`; UI and offline story body follow the `LanguageStore` selection.
- Parent-facing copy must stay parent-friendly — no model codenames (e.g. "VAEEncoder", "Core ML") in UI strings; those belong in docs/dev tooling only.
- Narration / image packs remain legacy-only until ported as kits. Optional neural art pack: `./scripts/download_sd_pack.sh` (see `docs/IMAGE_PACK.md`); procedural art is the fallback. The Legacy target links `apple/ml-stable-diffusion` (`StableDiffusion` product) for that pack.
- **Licensing — LiteRT-LM:** the runtime is **Apache-2.0** (compatible with AGPL-3.0; keep LICENSE/NOTICE attribution). The **Gemma model weights are under Google's separate Gemma Terms of Use** — bundling/downloading them means accepting those terms, independent of this repo's AGPL-3.0 license.
- `.gitignore` excludes `.cache/`, `**/.build/`, model bundles (`*.mlmodel`, `*.mlpackage`, `/Models/`). `.pbx_ids.json` is a local agent/helper file, also ignored.
