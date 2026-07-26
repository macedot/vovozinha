# Vovozinha — agent notes

## Product
- Offline **kids bedtime stories** (~3–8); parents/caregivers **18+**.
- **No cloud AI** for generation.
- Floor: **iPhone 15+**.

## Architecture (branch `multi`)
- **Host app** `Apps/Vovozinha` composes feature kits.
- **Feature kits** under `Packages/*Kit` (logic + UI surface).
- **DEBUG harness apps** under `Apps/*Debug` instantiate one kit alone.
- **Shared look** via `Packages/VovoUI` (theme + `VovoScreen` template).
- **Legacy** full product lives in `Legacy/VovozinhaLegacy` (scheme **VovozinhaLegacy**).

See `docs/MODULES.md`.

## Current feature: Story Prompt
- Seed text **10–20 words** → story draft (title, summary, 10 paragraphs).
- Protocol `StoryFromPromptGenerating`; default offline generator for bootstrap.
- **Languages:** pt-BR / en-US / es-ES via `VovoUI` (`LanguageStore`, `LanguageBar`, `VovoL10n`). UI + offline story body follow selection; language is stored on `StoryDraft.language`.

## Build
```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -scheme Vovozinha -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme StoryPromptDebug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Code norms
- Prefer small, focused diffs.
- New product work goes in **kits + host**, not Legacy.
- Kids-safety and offline-first rules still apply when wiring real LLMs.
- **Narration / packs** remain legacy until ported as kits.
