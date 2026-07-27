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
- Feature boundary protocol: `StoryFromPromptGenerating` (`Packages/StoryPromptKit/Sources/StoryPromptKit/StoryFromPromptGenerating.swift`). Implementations:
  - `OfflineFirstStoryGenerator` — **the default used by both apps**. On a **physical device**: no model on disk → offline; model present → LiteRT-LM, falling back to offline on any inference error (never throws for LLM failures).
  - `LiteRTLMStoryGenerator` — on-device LLM via **LiteRT-LM** (Gemma 3n E2B int4, local path checkout `../../../LiteRT-LM` at v0.13.1 — see the setup note below; the Swift API is "Early Preview"). The ~3.66 GB `.litertlm` model is downloaded once from Hugging Face by `LiteRTLMModelStore` into `Documents/Vovozinha/Models/`. Parses a strict `TITLE:` / `SUMMARY:` header + 10 blank-line-separated paragraphs; a reply with **fewer than 10 paragraphs fails parsing** so the composite falls back (never pads empty scenes). Inference samples with temperature 0.9 / topK 40 / topP 0.95 and a **random seed per generation** (the engine default seed 0 is deterministic — same prompt would repeat verbatim). **Physical iPhone only** (Metal `.gpu` backend).
  - `OfflineStoryFromPromptGenerator` — template-based fallback, always available. **Analyzes the seed** (per-language stopword/common-verb filtering → up to 3 key elements) and **randomly picks 1 of 3 copy variants per narrative beat** (10 beats × en/pt/es), weaving the elements through the story — the same seed yields a fresh story each time; the full seed text appears verbatim exactly once (spark paragraph). Variant selection is injectable (`init(pickVariant:)`) so tests stay deterministic.
- **Static text lives in Markdown on disk** (edit files, rebuild; never rewrite these from code):
  - UI strings: `Packages/VovoUI/Sources/VovoUI/Resources/Strings/{en-US,pt-BR,es-ES}.md`
  - Generation prompts: `Packages/StoryPromptKit/Sources/StoryPromptKit/Resources/Prompts/{offline,litert}.<lang>.md` — each contains a parent-description placeholder (`[INSERT STORY DESCRIPTION HERE]` and pt/es equivalents, plus `{{seed}}`/`{{idea}}`/`{{description}}`) that **must never be left unreplaced** (enforced by `replaceDescriptionPlaceholders` / `containsUnresolvedDescriptionPlaceholder`).

## Build & test
Requires **Xcode 27 beta** (`/Applications/Xcode-beta.app`); always set `DEVELOPER_DIR` first.

> **One-time setup — LiteRT-LM local checkout (required to build).** `StoryPromptKit` depends on LiteRT-LM as a **local path package** (`../../../LiteRT-LM`) because the upstream repo is currently unresolvable via SPM/Xcode — see [google-ai-edge/LiteRT-LM#2407](https://github.com/google-ai-edge/LiteRT-LM/issues/2407): (a) v0.14.0+ pins checksums that don't match its release binaries, and (b) SPM clones to a bare mirror and runs `git lfs pull` against it, but the `prebuilt/*` LFS objects only exist on the GitHub remote, not the mirror. Set it up once:
> ```bash
> git clone -b v0.13.1 https://github.com/google-ai-edge/LiteRT-LM.git /Users/thiago/Projects/LiteRT-LM
> cd /Users/thiago/Projects/LiteRT-LM && git lfs install --local && git lfs pull
> ```
> Do **not** move the checkout inside the vovozinha repo (it'd pollute git status); keep it as a sibling. The `Package.swift` documents this too.

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
- **StoryPromptKitTests** (`Packages/StoryPromptKit/Tests/StoryPromptKitTests/`): XCTest, run with `swift test` from `Packages/StoryPromptKit`. Covers seed validation, the offline generator in all three languages (randomness injected via `init(pickVariant:)`), prompt-placeholder substitution, and the LiteRT-LM layer (`LiteRTLMTests.swift`) with injected mock sessions — **never hit the network or a real model in tests** (inject a mock `LiteRTLMEngineSessioning` / point `LiteRTLMModelStore` at a temp dir). Live LiteRT-LM inference only runs on a **physical device** after the model download.
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
