---
name: present
description: Turn markdown, JSON, CSV, or prose into a beautiful self-contained HTML file. Invoke when operator says "present this", "make a report", "visualise this", "create an HTML page", "make a slide deck", or wants a shareable document.
---

# present

Given markdown, JSON, CSV, or plain prose, generate a polished self-contained
HTML file (inline CSS, no external dependencies) and save it to `~/projects/`.

## When to use

- "Present this", "make a report", "visualise", "create an HTML page".
- A subagent produced a long markdown output the operator wants to read comfortably.
- Data (JSON/CSV) needs a human-readable presentation.
- A slide-deck style document is needed.

## Workflow

1. **Understand content** — what type? (report, slides, dashboard, doc)
2. **Choose layout**:
   - `report` — clean single-column, like a readable article
   - `slides` — sectioned full-screen slides (CSS scroll-snap)
   - `dashboard` — grid layout for data/metrics
3. **Generate HTML** — self-contained, with inline `<style>` block:
   - System font stack (no Google Fonts)
   - Dark/light mode via `@media (prefers-color-scheme: dark)`
   - Responsive, readable at 768px+
   - Code blocks with syntax-highlighted background
4. **Save** — write to `~/projects/<descriptive-name>.html`
5. **Report** — tell operator the full path.

## HTML template skeleton

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
  <style>
    :root { --bg: #fff; --fg: #1a1a1a; --accent: #2563eb; --muted: #6b7280; }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #0f172a; --fg: #e2e8f0; --accent: #60a5fa; --muted: #94a3b8; }
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--fg); font: 1rem/1.7 system-ui, sans-serif;
           max-width: 860px; margin: 0 auto; padding: 2rem 1.5rem; }
    h1 { font-size: 2rem; margin-bottom: 0.5rem; }
    h2 { font-size: 1.4rem; margin: 2rem 0 0.75rem; border-bottom: 1px solid var(--muted); padding-bottom: 0.3rem; }
    h3 { font-size: 1.1rem; margin: 1.5rem 0 0.5rem; color: var(--accent); }
    p { margin-bottom: 1rem; }
    code { background: rgba(128,128,128,0.15); padding: 0.1em 0.4em; border-radius: 3px; font-size: 0.9em; }
    pre { background: rgba(128,128,128,0.1); padding: 1rem; border-radius: 6px; overflow-x: auto; margin-bottom: 1rem; }
    pre code { background: none; padding: 0; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; }
    th, td { padding: 0.5rem 1rem; text-align: left; border-bottom: 1px solid rgba(128,128,128,0.2); }
    th { font-weight: 600; color: var(--accent); }
    ul, ol { padding-left: 1.5rem; margin-bottom: 1rem; }
    blockquote { border-left: 3px solid var(--accent); padding-left: 1rem; color: var(--muted); margin-bottom: 1rem; }
    .meta { color: var(--muted); font-size: 0.85rem; margin-bottom: 2rem; }
  </style>
</head>
<body>
  {content}
</body>
</html>
```

## Rules

- NO external URLs (fonts, CDNs, images) — fully self-contained.
- File name: lowercase, hyphenated, descriptive (e.g., `q1-sales-report.html`).
- Default save path: `~/projects/`. Ask if operator wants a different location.
- For slides layout: use `<section>` tags with `scroll-snap-type: y mandatory` on body.
- Always confirm the file was written: print the absolute path.
