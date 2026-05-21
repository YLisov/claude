---
name: onboarding-conductor
description: Run a structured onboarding dialogue to learn who the operator is and fill in USER.md. Invoke when operator says "let's do onboarding", "introduce yourself", "fill in my profile", or when USER.md still has the template placeholder.
---

# onboarding-conductor

Run a structured 5-minute dialogue, then update USER.md and save key facts to L2 auto-memory.

## When to use

- USER.md contains "Онбординг не проведён" (template placeholder).
- Operator says "let's do onboarding", "introduce yourself", "tell me about yourself".
- Start of a new deployment — agent has no context about the operator.

## Dialogue structure

Ask questions in natural conversational Russian. One topic at a time — don't dump a form.
After each answer, acknowledge and ask the next question. Total: ~5–7 exchanges.

### Questions (order matters)

1. **Role** — "Расскажи немного о себе — чем занимаешься? (разработка, дизайн, бизнес, исследования?)"
2. **Main use cases** — "Для чего планируешь использовать меня чаще всего?"
3. **Tech stack** — "С какими языками, фреймворками или инструментами работаешь регулярно?"
4. **External services** — "Есть ли сервисы или базы, с которыми буду работать? (GitHub, баз данных, облака?)"
5. **Communication style** — "Как предпочитаешь получать ответы — подробно с объяснениями, или коротко и по делу?"
6. **Autonomy preference** — "Когда я делаю что-то необратимое — спрашивать каждый раз или действовать самостоятельно там где это безопасно?"
7. **Anything else** — "Что ещё важно знать о тебе или о том, как ты хочешь чтобы я работал?"

## After the dialogue

1. **Draft USER.md** — fill in all sections with collected info. Show draft to operator.
2. **Wait for approval** — "Это правильно? Хочешь что-то изменить?"
3. **Apply** — after "да/ок/выглядит хорошо" — write to `~/.claude/USER.md`.
4. **Save L2 memories** — for each key fact, create a typed memory file:
   - Role/context → `type: user`
   - Communication prefs → `type: feedback`
   - Projects/services → `type: project` or `type: reference`
5. **Confirm** — "Онбординг завершён. USER.md обновлён."

## USER.md template to fill

```markdown
# Профиль владельца

## Базовое

- **Язык общения:** русский (если явно не попросили иначе).
- **Стиль ответов:** {direct/detailed based on preference}
- **Роль:** {role}

## Деятельность и задачи

{what they do, main use cases}

## Технический стек

{languages, frameworks, tools}

## Внешние сервисы и репозитории

{GitHub, DBs, cloud, etc.}

## Предпочтения в работе

- **Автономность:** {when to ask vs act}
- **Стиль ответов:** {preference}

## Приоритеты агента

- Экономия токенов: L4 Cognee вызывать только при необходимости.
- Автоматическое запоминание важных фактов между сессиями.
- {additional preferences from dialogue}
```

## Rules

- NEVER write to USER.md without showing the draft first.
- Keep answers — don't paraphrase away specific details the operator gave.
- If operator skips a question — leave that section minimal, don't invent.
- After writing USER.md — also update MEMORY.md index if new memory files were created.
