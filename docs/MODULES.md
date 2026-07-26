# Multi-module architecture

Vovozinha is composed of **feature libraries** + a thin **host app**. Each feature has a **DEBUG harness app** (app + lib) so you can develop and accept behavior in isolation.

## Layout

```
Packages/
  VovoUI/                 # shared theme + screen chrome (all apps look the same)
  StoryPromptKit/         # first feature: seed prompt → story draft
Apps/
  Vovozinha/              # product host — wires feature libs
  StoryPromptDebug/       # DEBUG-only harness for StoryPromptKit
Legacy/
  VovozinhaLegacy/        # previous full app (run scheme VovozinhaLegacy)
```

## Schemes

| Scheme | What it runs |
|--------|----------------|
| **Vovozinha** | New host app (Story Prompt feature) |
| **StoryPromptDebug** | StoryPromptKit alone |
| **VovozinhaLegacy** | Old monolithic app (for reference / migration) |

## Feature pattern (app + lib)

1. **Lib** (`Packages/<Feature>Kit`): models, protocols, pure generation, `*FeatureView`.
2. **Debug app** (`Apps/<Feature>Debug`): `@main` that only shows the feature view with `VovoUI` chrome.
3. **Host** (`Apps/Vovozinha`): imports kits and composes them into the product flow.

## Story Prompt (current feature)

- Input: free-form **story seed** (base of the story).
- Constraint: **10–20 words** (inclusive).
- Output: title, summary, **10 scene paragraphs** (offline generator for now; swap `StoryFromPromptGenerating` later for FM).

## Adding the next feature

1. `Packages/NewFeatureKit` + tests  
2. `Apps/NewFeatureDebug` target + scheme  
3. Host app navigates to / embeds `NewFeatureView`  
4. Keep UI via `VovoUI.VovoScreen` / buttons / colors  
