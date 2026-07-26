# Story generation prompts (Markdown)

User-edited **generation instructions** for each language. Do not rewrite these files from code.

## Files

Two generator backends, each with one file per language:

| File | Backend | Language |
|------|---------|----------|
| `offline.en-US.md` | Offline deterministic (fallback) | English (US) |
| `offline.pt-BR.md` | Offline deterministic (fallback) | Português (Brasil) |
| `offline.es-ES.md` | Offline deterministic (fallback) | Español (España) |
| `litert.en-US.md` | LiteRT-LM (on-device LLM, primary when model present) | English (US) |
| `litert.pt-BR.md` | LiteRT-LM | Português (Brasil) |
| `litert.es-ES.md` | LiteRT-LM | Español (España) |

The `litert.*` templates tell the model to emit a strict `TITLE:` / `SUMMARY:` header
followed by 10 blank-line-separated paragraphs. `LiteRTLMStoryGenerator` parses that.

## Placeholders (required)

The short story description from the UI replaces these tokens at runtime:

| Token | Language |
|-------|----------|
| `[INSERT STORY DESCRIPTION HERE]` | en-US |
| `[INSERIR A DESCRIÇÃO DA HISTÓRIA AQUI]` | pt-BR |
| `[INSERTAR LA DESCRIPCIÓN DE LA HISTORIA AQUÍ]` | es-ES |

Also supported: `{{seed}}`, `{{idea}}`, `{{description}}`.

`OfflineStoryFromPromptGenerator.filledGenerationPrompt` (and the LiteRT-LM generator's
equivalent) perform the substitution. **Never leave INSERT tokens unreplaced.**

## Edit workflow

1. Edit the `.md` prompt for the language you care about.
2. Keep one clear insert token for the parent’s few-word description.
3. Rebuild — SPM copies `Resources/` into the package bundle.
