# Story generation prompts (Markdown)

User-edited **LLM instructions** for the on-device **Qwen3.5 MLX** path. These are **not** static story bodies.

## Files

| File | Language |
|------|----------|
| `story.en-US.md` | English (US) |
| `story.pt-BR.md` | Português (Brasil) |
| `story.es-ES.md` | Español (España) |

## Placeholders

Parent story description replaces:

| Token | Language |
|-------|----------|
| `[INSERT STORY DESCRIPTION HERE]` | en-US |
| `[INSERIR A DESCRIÇÃO DA HISTÓRIA AQUI]` | pt-BR |
| `[INSERTAR LA DESCRIPCIÓN DE LA HISTORIA AQUÍ]` | es-ES |

Also: `{{seed}}`, `{{idea}}`, `{{description}}`.

`StoryPromptTemplate` / `MLXStoryGenerator` perform substitution. **Never leave INSERT tokens unreplaced.**

## Product rule

There is **no** offline / template story generator. Without a working on-device model, generation **fails**.
