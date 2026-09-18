# Web / Tauri / Electron / HTML

## Setup

```bash
cp ~/.claude/skills/henri-ui/assets/motion.css <projekt>/src/styles/motion.css
```

Enthält alle Tokens als CSS-Variablen, exakte Spring-Kurven (`--spring-*` als
`linear()` + passende `--spring-*-dur`), fertige Klassen `.ui-control`, `.ui-menu`,
`.ui-popover` und den Reduce-Motion-Fallback.

Spring in CSS immer als Paar verwenden:

```css
transition: transform var(--spring-smooth-dur) var(--spring-smooth);
```

## Regeln

- **Transitions statt `@keyframes`** für Zustände (hover, open, selected) — Transitions
  laufen beim Unterbrechen vom aktuellen Wert weiter, Keyframes springen.
- Menüs/Popover bleiben im DOM und werden über `[data-open]` gesteuert, nie
  per `display: none` / bedingtem Rendern sofort entfernt. In React/Svelte/Vue für
  bedingtes Rendern eine Exit-Animation nutzen (`AnimatePresence`, `transition:`-
  Direktive, `<Transition>`).
- Nur `transform` und `opacity` animieren; Höhen über `grid-template-rows: 0fr → 1fr`
  oder `interpolate-size: allow-keywords` + `height: auto`, Inhalt mit `overflow: clip`.
- `will-change` nur während der Animation setzen, nicht permanent.
- Scrollen: `overscroll-behavior: contain`, `scroll-behavior: smooth` für
  programmgesteuertes Scrollen.

## JavaScript-Springs (Motion / framer-motion)

Wenn ein JS-Framework im Spiel ist, `motion` (motion.dev) nutzen, mit genau diesen Werten
(`damping = 2·ζ·√stiffness`, Masse 1):

```js
export const spring = {
  smooth: { type: "spring", stiffness: 322, damping: 35.9, mass: 1 },
  snappy: { type: "spring", stiffness: 247, damping: 26.7, mass: 1 },
  gentle: { type: "spring", stiffness: 158, damping: 25.1, mass: 1 },
  bouncy: { type: "spring", stiffness: 195, damping: 20.9, mass: 1 },
};
export const dur = { instant: 0.09, fast: 0.16, base: 0.24, slow: 0.38, slower: 0.52 };
export const ease = {
  out: [0.22, 1, 0.36, 1],
  inOut: [0.45, 0, 0.15, 1],
  exit: [0.4, 0, 0.7, 0.2],
};
```

Menü mit Motion:

```jsx
<AnimatePresence>
  {open && (
    <motion.div
      style={{ transformOrigin: "top center" }}
      initial={{ opacity: 0, scale: 0.96, y: -4 }}
      animate={{ opacity: 1, scale: 1, y: 0, transition: { ...spring.smooth, opacity: { duration: dur.base, ease: ease.out } } }}
      exit={{ opacity: 0, scale: 0.98, transition: { duration: dur.base * 0.7, ease: ease.exit } }}
    />
  )}
</AnimatePresence>
```

Gleitendes Highlight / Tabs: `layoutId="highlight"` mit `transition={spring.smooth}`.
Listen: `layout` + `AnimatePresence`, Stagger 15 ms, max. 10 Einträge.

## Farben aus dem Omarchy-Theme

In Tauri/Electron beim Start `~/.local/state/omarchy/current/theme/colors.toml` lesen
und als CSS-Variablen (`--accent`, `--bg`, `--fg`, `--muted`, `--selection`) auf `:root`
setzen; Datei beobachten → live umschalten. `mode` bestimmt `color-scheme: light|dark`.
Reine Web-Seiten ohne Dateizugriff: gleiche Variablennamen, Werte aus
`prefers-color-scheme`.

## Material

```css
.ui-surface {
  background: color-mix(in srgb, var(--bg) 85%, transparent);
  backdrop-filter: blur(24px) saturate(1.6);
  border: var(--hairline);
  border-radius: var(--radius-popover);
  box-shadow: var(--shadow-popover);
}
```
