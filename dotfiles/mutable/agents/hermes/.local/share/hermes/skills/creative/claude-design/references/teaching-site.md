# Educational Variant: Tutorial → Interactive Teaching Site

Companion reference for the "Educational Variant" section of `claude-design/SKILL.md`. Read this before building any tutorial-to-website conversion.

## When this reference applies

Trigger phrases: "重新制作为网页", "做成互动教程", "适合初学者", "加上名词解释", "turn this into a website", "make it interactive", "适合教学场景", "面向初学者".

Source material shape: long-form instructional content. Chapter / day / lesson structure, code blocks, technical terms beginners wouldn't know, often in Chinese but works in any language.

## Architecture pattern (proven)

Use a **structured content data + section renderer + named interactive components + glossary system** separation. Single-page app, vanilla JS or React, no build step unless user wants it.

```
project/
├── index.html              # shell: topbar, sidebar, main, glossary panel, modal
├── styles.css              # theme variables + all component styles (dark/light dual)
├── data/
│   ├── content.js          # DAYS = [{id, title, theme, sections: [{type, ...}]}]
│   └── glossary.js         # Glossary = { 'term-key': {name, body} }
└── js/
    ├── storage.js          # localStorage wrapper (progress, theme)
    ├── components.js       # 7 reusable interactive components
    ├── app.js              # renderDays(), renderSection(), search, hotkeys
    └── (no build, no bundler)
```

### Section type taxonomy

Define a small union type for section content. Render each type with a switch in `renderSection()`. Keep it finite so users can mix-and-match.

| type | shape | purpose |
|---|---|---|
| `intro` | `{ theme }` | one card per day with "today's goal" |
| `p` | `{ html }` | paragraph with inline HTML + glossary spans |
| `h2`/`h3` | `{ text }` | headings |
| `tip`/`warn`/`good`/`info` | `{ title, body }` | 4-card palette for advice, warnings, wins, info |
| `code` | `{ lang, code }` | syntax-highlighted code block |
| `steps` | `{ items: [{title, desc}] }` | numbered step list |
| `fold` | `{ summary, body }` | collapsible `<details>` |
| `link-grid` | `{ items: [{title, url, desc}] }` | external resource cards |
| `component` | `{ id }` | mount point for a named interactive component |

Add new types by extending the switch. Don't try to make sections "smart enough" to figure out their type — explicit is fine.

### Named interactive components

Each component is a pair: `html()` returns HTML, `bind(root)` attaches event handlers. Components live in `js/components.js` and are registered in a `Components.map`.

The seven that cover ~90% of teaching needs:

1. **Keyboard visualizer** — click keys to reveal Emacs/Vim/IDE keybindings
2. **Cursor / movement demo** — buttons that animate a caret in a textarea-like div
3. **Mini REPL** — embedded parser + evaluator for the language being taught (Elisp, Python, SQL, regex...)
4. **Macro expansion animator** — split view showing "source" → "expanded" with arrow
5. **State machine** — drag/click items through TODO → STARTED → DONE etc.
6. **Mode switcher** — Normal/Insert/Visual/Emacs keybindings gated on current mode
7. **Node graph (Canvas)** — animated canvas with hover-to-highlight connections

When a component can be done in pure HTML + a few event handlers, do that. Reach for Canvas only when DOM count would explode (graphs, particle effects).

## Glossary tooltip system

The single most important feature for "面向初学者". Every term a beginner wouldn't know gets a tooltip on hover/click. Implementation:

```html
<span class="g-term" data-term="emacs">Emacs</span>
```

```js
document.addEventListener('mouseover', e => {
  const t = e.target.closest('.g-term');
  if (!t) return;
  showTooltip(t);
});
```

Glossary data:

```js
window.Glossary = {
  "emacs": { name: "Emacs", body: "一个可扩展的文本编辑器..." },
  "buffer": { name: "Buffer（缓冲区）", body: "..." }
};
```

Required features:

- hover triggers tooltip
- click pins tooltip (close on outside click)
- a side panel (`glossaryPanel`) lists all terms, searchable, alphabetical
- all terms declared in `glossary.js` even if not yet referenced — easy to wire up later

Target ≥ 50 terms for a 21-day course. Less than 30 means beginners will hit unknowns.

## Progress persistence

Every chapter has a "mark complete" button. localStorage Set, JSON-serialized:

```js
const KEY = 'me21-completed';
const completed = new Set(JSON.parse(localStorage.getItem(KEY) || '[]'));
```

Show progress in topbar (`X / 21`) + colored bar. Sidebar items show a green check when complete. This is the single feature that converts "visiting the site" into "taking the course".

## Search

Index every section's title + body + tag at startup. Live search on `Ctrl+K`. On match, smooth-scroll to section and flash-highlight.

## Keyboard shortcuts

- `Ctrl+K` → focus search
- `G` → open glossary panel
- `T` → toggle theme
- `Esc` → close panels

Bind shortcuts at `document` level, ignore when target is `<input>` / `<textarea>` / `[contenteditable]`.

## Dual theme (dark + light)

CSS variables on `:root` and `[data-theme="light"]`. `T` button + system `prefers-color-scheme` fallback. Default to dark for technical / dev audiences, light for general.

## Responsive

Breakpoint at 900px. Below it: hide sidebar, show hamburger. Below 560px: hide brand text, simplify keyboard visualizer. Mobile hit targets ≥ 44px.

---

## JS pitfalls (these bit this session, will bite you too)

### 1. Template strings vs backtick code blocks

When the source markdown contains Elisp / Lisp / Rust code that itself uses backticks (``, ` ``) for quoting, those backticks close the JS template string early.

**Wrong**:
```js
{ type: "code", lang: "elisp", code: `
;; \` 是 backquote
(setq some-list '(2 3))
\`(1 ,@some-list 4)
` }
```

**Fix options** (pick one):

a. Use plain double-quoted strings, escape internal `"` and `\n`:
   ```js
   { type: "code", lang: "elisp", code: "(+ 1 1)\n(message \"hi\")" }
   ```
   Then in render time, replace `\n` → `\n` (newline char). This is the most robust for big content data.

b. Switch to `<template>` tag in HTML and read `.textContent` at runtime — backticks inside `<template>` are literal.

c. Build a build step that pre-processes content (overkill unless 50+ files).

### 2. Real newlines vs `\n` literal in JS strings

`"a\nb"` is two chars with a real newline (JS escape). `"a\\nb"` is four chars: `a`, `\`, `n`, `b`. If you wrote `"a\nb"` and the file shows `\n` in the browser, your `\n` is not being processed as a newline — usually because the source string is the literal four-character `\n` (single backslash + n) that JS did NOT parse as an escape (e.g. you wrapped in a function that escaped `\`).

**Fix**: always test with `node -c file.js` for syntax + run a quick `console.log(s.length)` after parse to confirm `\n` was interpreted as one char.

### 3. Cross-line double-quoted strings are illegal

```js
const s = "line1
line2";  // SyntaxError
```

Inside JS string literals, real newlines are not allowed — only `\n` escape. If you have multi-line text in a content data file, either use template literals (backticks) or escape the newlines as `\n`.

### 4. Object keys with reserved words / special chars

`{ type: "code", code: \`...\` }` — when code block content contains `{` or `}`, the parser is fine, but if it contains `${...}` inside a template string, that's interpolation. Avoid template strings for code blocks.

### 5. JSON.stringify of nested arrays shows as "1,2,3" not "(1 2 3)"

Elisp-style list pretty-printer: walk the array, recurse, output `(a b c)`. Don't trust `JSON.stringify`.

### 6. localStorage Set serialization

`Set` is not natively JSON-serializable. Use `JSON.stringify([...set])` and back with `new Set(JSON.parse(...))`. Always wrap in try/catch.

---

## Mini REPL design (when embedding an evaluator)

For Elisp / Lisp / Python / SQL — anything with parseable grammar — embed a parser + evaluator. The teaching site does not need full spec coverage; ~20 builtins + defun + defmacro + let + quote is plenty.

Skeleton:

```js
const env = { '+': (a,b) => a+b, 't': true, 'nil': false, ... };
const tokenize = src => /* split on parens, strings, atoms */;
const parse = tokens => /* recursive descent on ( ... ) */;
const eval = (expr, env) => {
  if (typeof expr === 'number') return expr;
  if (Array.isArray(expr)) {
    switch (expr[0]) {
      case 'quote': return expr[1];
      case 'setq':  env[expr[1]] = eval(expr[2], env); return env[expr[1]];
      case 'defun': env[expr[1]] = (...args) => { /* local scope */ }; return `<fn ${expr[1]}>`;
      case 'let':   /* bind pairs, then eval body in local env */;
      case 'if':    return eval(expr[1], env) ? eval(expr[2], env) : eval(expr[3], env);
      default: {
        const fn = env[expr[0]];
        if (!fn) throw new Error(`Unknown: ${expr[0]}`);
        return fn(...expr.slice(1).map(e => eval(e, env)));
      }
    }
  }
  return expr; // symbol lookup
};
```

UI:
- monospace editor at bottom
- "output" panel above
- `Ctrl+Enter` to run
- pretty-print: `(a b c)` not `[a,b,c]`, `t`/`nil` not `true`/`false`, strings quoted

---

## Canvas node graph (for knowledge-graph / Roam-style viz)

```js
const nodes = [{id, title, x, y, r, link: [otherIds]}];
const draw = () => {
  ctx.clearRect(0,0,w,h);
  // lines first (so they sit under nodes)
  nodes.forEach(n => n.link.forEach(t => {
    const m = map[t]; if (!m) return;
    const active = n.id===activeId || m.id===activeId;
    ctx.strokeStyle = active ? 'rgba(124,92,255,0.7)' : 'rgba(120,120,140,0.18)';
    ctx.beginPath(); ctx.moveTo(n.x, n.y); ctx.lineTo(m.x, m.y); ctx.stroke();
  }));
  // nodes on top
  nodes.forEach(n => {
    const active = n.id===activeId;
    ctx.fillStyle = active ? '#7c5cff' : '#3b3949';
    ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI*2); ctx.fill();
    ctx.fillStyle = active ? '#fff' : '#b9b6c8';
    ctx.fillText(n.title, n.x, n.y - n.r - 6);
  });
};
```

Use `devicePixelRatio` for crispness on retina. `requestAnimationFrame` loop. Stop loop when tab hidden (`document.hidden`).

Click on left list items → set `activeId` → redraw. No need for hit-testing on canvas — list is the picker.

---

## Evil-style mode-switching pad

When teaching Vim/Evil/anything mode-based, give a contenteditable div with a `keydown` handler that:

- tracks current mode in a state variable
- in `Insert` mode, lets keys through normally (browser default inserts)
- in `Normal` mode, swallows all printable keys (preventDefault), only listens to mode-switch keys (`i`, `v`, `Esc`, `R`, `C-z`)
- shows current mode in a colored bar above the pad

This is the smallest possible interactive demo of modal editing. Beginners get it within 2 minutes.

---

## Verification checklist

Before declaring done:

- [ ] `node -c data/content.js` — content parses
- [ ] `node -c js/components.js` — components parse
- [ ] open in browser via local HTTP server (`python3 -m http.server`)
- [ ] check browser console — zero errors / zero 404s
- [ ] all `data-term` keys in HTML exist in `Glossary` (no broken tooltips)
- [ ] click each "mark complete" button → progress updates → reload page → still marked
- [ ] `Ctrl+K` search returns expected hits
- [ ] `T` toggles theme, persists across reload
- [ ] mobile width (375px) — sidebar collapses, no horizontal scroll
- [ ] all REPL examples run without error
- [ ] all interactive components render and respond to clicks

---

## Scope guidance (when to push back on the user)

If the user asks for "just put the markdown on a webpage", clarify scope:

- "Pretty HTML with syntax-highlighted code blocks" — small, ~30 min, single file
- "Interactive site with REPL, glossary, progress" — full SPA, 3-6 hours, multi-file
- "Multi-page with auth, quizzes, certificate" — that's a real product, not a one-off

Don't oversell. Ask before delivering the wrong thing.