/* mdview — renderer + UI inside the web view.
 * Python calls MdView.render(payload) and friends; the page talks back via
 * window.webkit.messageHandlers.mdview (JSON strings). */
"use strict";
(() => {
  const NONCE = document.currentScript.nonce;
  const ASSETS = document.currentScript.src.replace(/\/[^/]*$/, "");
  const content = document.getElementById("content");
  const post = (type, data = {}) =>
    window.webkit?.messageHandlers?.mdview?.postMessage(JSON.stringify({ type, ...data }));
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const motionMs = (name, fallback) => {
    const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v.endsWith("ms") ? parseFloat(v) : v.endsWith("s") ? parseFloat(v) * 1000 : fallback;
  };

  // ------------------------------------------------------------ icons
  const svg = (d) => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
  const ICON = {
    list: svg('<path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>'),
    search: svg('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'),
    pencil: svg('<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>'),
    up: svg('<path d="m18 15-6-6-6 6"/>'),
    down: svg('<path d="m6 9 6 6 6-6"/>'),
    x: svg('<path d="M18 6 6 18M6 6l12 12"/>'),
    chevron: svg('<path d="m9 18 6-6-6-6"/>'),
    info: svg('<circle cx="12" cy="12" r="9.5"/><path d="M12 16v-4.5M12 8h.01"/>'),
    alert: svg('<circle cx="12" cy="12" r="9.5"/><path d="M12 7.5V12M12 16h.01"/>'),
    flame: svg('<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.4-.5-2-1-3-1.1-2.1-.2-4 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.2.4-2.3 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>'),
    check: svg('<path d="M20 6 9 17l-5-5"/>'),
    help: svg('<circle cx="12" cy="12" r="9.5"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>'),
    warn: svg('<path d="m21.7 18-8-14a2 2 0 0 0-3.5 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3Z"/><path d="M12 9v4M12 17h.01"/>'),
    zap: svg('<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>'),
    bug: svg('<rect x="8" y="6" width="8" height="14" rx="4"/><path d="M19 7l-3 2M5 7l3 2M19 13h-3M5 13h3M19 19l-3-2M5 19l3-2M12 20v-9M9.5 3.5 12 6l2.5-2.5"/>'),
    quote: svg('<path d="M10 11H6a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v6c0 2.5-1.5 4-4 5M19 11h-4a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v6c0 2.5-1.5 4-4 5"/>'),
    clip: svg('<rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>'),
    todo: svg('<circle cx="12" cy="12" r="9.5"/><path d="m8.5 12 2.5 2.5 4.5-5"/>'),
  };
  const CALLOUT_ALIAS = {
    summary: "abstract", tldr: "abstract", hint: "tip", check: "success", done: "success",
    help: "question", faq: "question", attention: "warning", caution: "danger",
    fail: "failure", missing: "failure", error: "danger", cite: "quote",
  };
  const CALLOUT_ICON = {
    note: ICON.pencil, info: ICON.info, todo: ICON.todo, abstract: ICON.clip, tip: ICON.flame,
    success: ICON.check, question: ICON.help, warning: ICON.warn, failure: ICON.x,
    danger: ICON.zap, bug: ICON.bug, example: ICON.list, quote: ICON.quote, important: ICON.alert,
  };

  // ------------------------------------------------------------ helpers
  const slugify = (s) => String(s).trim().toLowerCase()
    .replace(/<[^>]*>/g, "")
    .replace(/[^\p{L}\p{N}\s_-]/gu, "")
    .replace(/\s+/g, "-");
  const inlineText = (children = []) => children.map((c) => {
    if (c.type === "text" || c.type === "code_inline" || c.type === "math_inline") return c.content;
    if (c.type === "wikilink") return c.meta.alias || c.meta.target;
    if (c.type === "tag") return "#" + c.content;
    if (c.type === "emoji") return c.content;
    return "";
  }).join("");

  // ------------------------------------------------------------ markdown-it
  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: false });
  md.validateLink = (url) => !/^\s*(javascript|vbscript):/i.test(url);
  const plugin = (p) => { if (p) md.use(p.full || p.default || p); };
  [window.markdownitFootnote, window.markdownitDeflist, window.markdownitMark,
    window.markdownitSub, window.markdownitSup, window.markdownitAbbr,
    window.markdownitEmoji].forEach(plugin);
  md.linkify.set({ fuzzyLink: false });

  // --- math ($…$, $$…$$, ```math)
  const tex = (src, display) => {
    try {
      return katex.renderToString(src, { displayMode: display, throwOnError: false, strict: "ignore", output: "html" });
    } catch (e) {
      return `<code class="math-error">${esc(src)}</code>`;
    }
  };
  md.inline.ruler.before("escape", "math_inline", (state, silent) => {
    const s = state.src, pos = state.pos;
    if (s.charCodeAt(pos) !== 0x24) return false;
    const display = s.charCodeAt(pos + 1) === 0x24;
    const delim = display ? "$$" : "$";
    const start = pos + delim.length;
    if (!display) {
      const c = s.charCodeAt(start);
      if (Number.isNaN(c) || c === 0x20 || c === 0x09 || c === 0x0a || c === 0x24) return false;
    }
    let end = start;
    for (;;) {
      end = s.indexOf(delim, end);
      if (end === -1) return false;
      if (s.charCodeAt(end - 1) === 0x5c) { end += 1; continue; }
      if (!display) {
        const prev = s.charCodeAt(end - 1), next = s.charCodeAt(end + 1);
        if (prev === 0x20 || prev === 0x09 || prev === 0x0a) { end += 1; continue; }
        if (next >= 0x30 && next <= 0x39) { end += 1; continue; }
      }
      break;
    }
    if (end === start) return false;
    if (!silent) {
      const t = state.push("math_inline", "math", 0);
      t.content = s.slice(start, end);
      t.meta = { display };
    }
    state.pos = end + delim.length;
    return true;
  });
  md.block.ruler.before("fence", "math_block", (state, startLine, endLine, silent) => {
    const pos = state.bMarks[startLine] + state.tShift[startLine];
    const max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    if (pos + 2 > max || state.src.slice(pos, pos + 2) !== "$$") return false;
    const first = state.src.slice(pos + 2, max);
    let line = startLine, found = false;
    const lines = [];
    if (first.trim().length >= 2 && first.trim().endsWith("$$")) {
      lines.push(first.trim().slice(0, -2));
      found = true;
    } else {
      lines.push(first);
      for (line = startLine + 1; line < endLine; line++) {
        const p = state.bMarks[line] + state.tShift[line], m = state.eMarks[line];
        if (p < m && state.sCount[line] < state.blkIndent) break;
        const text = state.src.slice(p, m);
        if (text.trim().endsWith("$$")) { lines.push(text.trim().slice(0, -2)); found = true; break; }
        lines.push(text);
      }
    }
    if (!found) return false;
    if (silent) return true;
    const t = state.push("math_block", "math", 0);
    t.block = true;
    t.content = lines.join("\n");
    t.map = [startLine, line + 1];
    state.line = line + 1;
    return true;
  }, { alt: ["paragraph", "reference", "blockquote", "list"] });
  md.renderer.rules.math_inline = (t, i) => t[i].meta.display
    ? `<span class="math-display">${tex(t[i].content, true)}</span>`
    : tex(t[i].content, false);
  md.renderer.rules.math_block = (t, i) =>
    `<div class="math-block"${lineAttr(t[i])}>${tex(t[i].content, true)}</div>`;

  // --- wikilinks + embeds
  md.inline.ruler.before("link", "wikilink", (state, silent) => {
    const s = state.src;
    let pos = state.pos, embed = false;
    if (s.charCodeAt(pos) === 0x21 && s.startsWith("[[", pos + 1)) { embed = true; pos += 1; }
    else if (!s.startsWith("[[", pos)) return false;
    const end = s.indexOf("]]", pos + 2);
    if (end < 0) return false;
    const inner = s.slice(pos + 2, end);
    if (!inner.trim() || inner.includes("\n") || inner.includes("[[")) return false;
    if (!silent) {
      const bar = inner.indexOf("|");
      const t = state.push(embed ? "wiki_embed" : "wikilink", "", 0);
      t.meta = {
        target: (bar < 0 ? inner : inner.slice(0, bar)).trim(),
        alias: bar < 0 ? null : inner.slice(bar + 1).trim(),
      };
    }
    state.pos = end + 2;
    return true;
  });
  const wikiLabel = (target) => {
    const [file, ...rest] = target.split("#");
    const sub = rest.join("#").replace(/^\^/, "");
    const name = file.split("/").pop().replace(/\.md$/i, "");
    return name ? (sub ? `${name} › ${sub}` : name) : sub;
  };
  md.renderer.rules.wikilink = (t, i, _o, env) => {
    const { target, alias } = t[i].meta;
    const label = esc(alias || wikiLabel(target));
    if (target.startsWith("#")) return `<a class="wikilink" href="#${esc(target.slice(1))}">${label}</a>`;
    const ok = env.links && env.links[target];
    return `<a class="wikilink${ok ? "" : " unresolved"}" href="#" data-wiki="${esc(target)}">${label}</a>`;
  };
  const sectionOf = (text, sub) => {
    if (!sub) return text;
    const lines = text.split("\n");
    if (sub.startsWith("^")) {
      const id = sub.slice(1);
      const hit = lines.find((l) => l.trimEnd().endsWith("^" + id));
      return hit ? hit.replace(new RegExp(`\\s*\\^${id}\\s*$`), "") : text;
    }
    const want = slugify(sub);
    let start = -1, level = 0;
    for (let i = 0; i < lines.length; i++) {
      const m = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(lines[i]);
      if (!m) continue;
      if (start < 0 && slugify(m[2]) === want) { start = i; level = m[1].length; continue; }
      if (start >= 0 && m[1].length <= level) return lines.slice(start, i).join("\n");
    }
    return start >= 0 ? lines.slice(start).join("\n") : text;
  };
  md.renderer.rules.wiki_embed = (t, i, _o, env) => {
    const { target, alias } = t[i].meta;
    const info = env.links && env.links[target];
    if (!info) return `<span class="embed-missing">${esc(wikiLabel(target))}</span>`;
    const size = alias && /^(\d+)(?:x(\d+))?$/.exec(alias);
    const dims = size ? ` width="${size[1]}"${size[2] ? ` height="${size[2]}"` : ""}` : "";
    const url = esc(info.url);
    switch (info.kind) {
      case "image": return `<img class="embed" src="${url}" alt="${esc(size ? wikiLabel(target) : alias || wikiLabel(target))}"${dims}>`;
      case "audio": return `<audio controls src="${url}"></audio>`;
      case "video": return `<video controls src="${url}"${dims}></video>`;
      case "md": {
        if ((env.depth || 0) >= 2 || info.text == null) break;
        const sub = target.includes("#") ? target.slice(target.indexOf("#") + 1) : "";
        const body = sectionOf(stripFrontmatter(info.text).body, sub);
        const inner = md.render(stripComments(body), { links: env.links, depth: (env.depth || 0) + 1 });
        return `<div class="transclusion"><a class="transclusion-head wikilink" href="#" data-wiki="${esc(target)}">${esc(alias || wikiLabel(target))}</a>${inner}</div>`;
      }
    }
    return `<a class="wikilink file" href="#" data-wiki="${esc(target)}">${esc(alias || wikiLabel(target))}</a>`;
  };

  // --- #tags
  md.inline.ruler.after("wikilink", "tag", (state, silent) => {
    const s = state.src, pos = state.pos;
    if (s.charCodeAt(pos) !== 0x23) return false;
    if (pos > 0 && !/[\s(]/.test(s[pos - 1])) return false;
    const m = /^#([\p{L}\p{N}_\-/]+)/u.exec(s.slice(pos));
    if (!m || /^[\d/_-]+$/.test(m[1])) return false;
    if (!silent) state.push("tag", "", 0).content = m[1];
    state.pos += m[0].length;
    return true;
  });
  md.renderer.rules.tag = (t, i) => `<span class="tag">#${esc(t[i].content)}</span>`;

  // --- callouts (Obsidian + GitHub alerts)
  md.core.ruler.after("block", "callouts", (state) => {
    const toks = state.tokens;
    for (let i = 0; i < toks.length; i++) {
      const open = toks[i];
      if (open.type !== "blockquote_open") continue;
      const para = toks[i + 1], inl = toks[i + 2];
      if (!para || para.type !== "paragraph_open" || !inl || inl.type !== "inline") continue;
      const [head, ...restLines] = inl.content.split("\n");
      const m = /^\[!([\w-]+)\]([+-]?)\s*(.*)$/.exec(head.trim());
      if (!m) continue;
      const type = m[1].toLowerCase();
      const kind = CALLOUT_ALIAS[type] || (CALLOUT_ICON[type] ? type : "note");
      const fold = m[2];
      let depth = 0, j = i;
      for (; j < toks.length; j++) {
        if (toks[j].type === "blockquote_open") depth++;
        else if (toks[j].type === "blockquote_close" && --depth === 0) break;
      }
      const tag = fold ? "details" : "div";
      open.tag = toks[j].tag = tag;
      open.attrJoin("class", `callout callout-${kind}`);
      open.attrSet("data-callout", type);
      if (fold === "+") open.attrSet("open", "");
      const titleOpen = new state.Token("callout_title_open", fold ? "summary" : "div", 1);
      titleOpen.meta = { kind, fold: !!fold };
      const title = new state.Token("inline", "", 0);
      title.content = m[3] || type.charAt(0).toUpperCase() + type.slice(1);
      title.children = [];
      title.map = inl.map;
      const titleClose = new state.Token("callout_title_close", fold ? "summary" : "div", -1);
      titleClose.meta = titleOpen.meta;
      const bodyOpen = new state.Token("callout_body_open", "div", 1);
      const bodyClose = new state.Token("callout_body_close", "div", -1);
      toks.splice(j, 0, bodyClose);
      const rest = restLines.join("\n");
      if (rest.trim()) {
        inl.content = rest;
        if (inl.map) inl.map = [inl.map[0] + 1, inl.map[1]];
        if (para.map) para.map = [para.map[0] + 1, para.map[1]];
        toks.splice(i + 1, 0, titleOpen, title, titleClose, bodyOpen);
      } else {
        toks.splice(i + 1, 3, titleOpen, title, titleClose, bodyOpen);
      }
    }
  });
  md.renderer.rules.callout_title_open = (t, i) =>
    `<${t[i].tag} class="callout-title"><span class="callout-icon">${CALLOUT_ICON[t[i].meta.kind]}</span><span class="callout-title-text">`;
  md.renderer.rules.callout_title_close = (t, i) =>
    `</span>${t[i].meta.fold ? `<span class="callout-fold">${ICON.chevron}</span>` : ""}</${t[i].tag}>`;
  md.renderer.rules.callout_body_open = () => '<div class="callout-content">';
  md.renderer.rules.callout_body_close = () => "</div>";

  // --- task lists (clickable, written back to the file)
  md.core.ruler.after("inline", "tasks", (state) => {
    const toks = state.tokens, env = state.env;
    for (let i = 2; i < toks.length; i++) {
      const t = toks[i];
      if (t.type !== "inline" || toks[i - 1].type !== "paragraph_open" || toks[i - 2].type !== "list_item_open") continue;
      const m = /^\[([ xX/\-<>?!*])\](?=\s|$)/.exec(t.content);
      const first = t.children[0];
      if (!m || !first || first.type !== "text" || !first.content.startsWith(m[0])) continue;
      first.content = first.content.slice(m[0].length).replace(/^\s/, "");
      const ch = m[1];
      const cb = new state.Token("task_checkbox", "", 0);
      const line = toks[i - 1].map ? toks[i - 1].map[0] + (env.lineOffset || 0) : -1;
      cb.meta = { checked: ch !== " ", ch, line: env.depth ? -1 : line };
      t.children.unshift(cb);
      toks[i - 2].attrJoin("class", "task-item" + (ch !== " " ? " is-checked" : ""));
      if (!/[ xX]/.test(ch)) toks[i - 2].attrSet("data-task", ch);
      for (let k = i - 3; k >= 0; k--) {
        if (toks[k].type === "bullet_list_open" || toks[k].type === "ordered_list_open") {
          if (toks[k].level === toks[i - 2].level - 1) { toks[k].attrJoin("class", "contains-task-list"); break; }
        }
      }
    }
  });
  md.renderer.rules.task_checkbox = (t, i) => {
    const { checked, line } = t[i].meta;
    return `<input type="checkbox" class="task"${checked ? " checked" : ""}${line < 0 ? " disabled" : ` data-line="${line}"`}>`;
  };

  // --- heading ids + outline, source lines for scroll anchoring
  md.core.ruler.push("anchors", (state) => {
    const env = state.env;
    const slugs = env.slugs || (env.slugs = new Map());
    for (let i = 0; i < state.tokens.length; i++) {
      const t = state.tokens[i];
      const block = t.nesting === 1 || (t.nesting === 0 && t.block && t.type !== "inline");
      if (t.map && block && !env.depth) t.attrSet("data-line", t.map[0] + (env.lineOffset || 0));
      if (t.type !== "heading_open") continue;
      const text = inlineText(state.tokens[i + 1].children);
      let slug = slugify(text) || "abschnitt";
      const n = slugs.get(slug) || 0;
      slugs.set(slug, n + 1);
      if (n) slug += "-" + n;
      if (env.depth) continue;
      t.attrSet("id", slug);
      env.outline?.push({ level: Number(t.tag.slice(1)), text, slug });
    }
  });
  const lineAttr = (t) => (t.map && t.attrGet && t.attrGet("data-line") != null ? ` data-line="${t.attrGet("data-line")}"` : "");

  // --- code fences: highlight, copy button, mermaid, math
  md.renderer.rules.fence = (toks, idx) => {
    const t = toks[idx];
    const lang = t.info.trim().split(/\s+/)[0].toLowerCase();
    if (lang === "mermaid") {
      return `<div class="mermaid-block"${lineAttr(t)}><pre class="mermaid">${esc(t.content)}</pre></div>`;
    }
    if (lang === "math") return `<div class="math-block"${lineAttr(t)}>${tex(t.content, true)}</div>`;
    let code;
    try {
      code = lang && hljs.getLanguage(lang)
        ? hljs.highlight(t.content, { language: lang, ignoreIllegals: true }).value
        : esc(t.content);
    } catch (e) {
      code = esc(t.content);
    }
    return `<div class="code-block"${lineAttr(t)}><div class="code-tools">` +
      (lang ? `<span class="code-lang">${esc(lang)}</span>` : "") +
      `<button class="btn code-copy" type="button" title="Code kopieren">Kopieren</button></div>` +
      `<pre><code class="hljs${lang ? " language-" + esc(lang) : ""}">${code}</code></pre></div>`;
  };
  md.renderer.rules.code_block = (toks, idx) =>
    `<div class="code-block"${lineAttr(toks[idx])}><div class="code-tools"><button class="btn code-copy" type="button" title="Code kopieren">Kopieren</button></div><pre><code class="hljs">${esc(toks[idx].content)}</code></pre></div>`;
  md.renderer.rules.table_open = (t, i, o, _e, self) => '<div class="table-wrap">' + self.renderToken(t, i, o);
  md.renderer.rules.table_close = (t, i, o, _e, self) => self.renderToken(t, i, o) + "</div>";
  const defaultLinkOpen = md.renderer.rules.link_open || ((t, i, o, _e, self) => self.renderToken(t, i, o));
  md.renderer.rules.link_open = (t, i, o, e, self) => {
    const href = t[i].attrGet("href") || "";
    if (/^[a-z][a-z0-9+.-]*:/i.test(href) && !/^file:/i.test(href)) t[i].attrJoin("class", "external");
    return defaultLinkOpen(t, i, o, e, self);
  };

  // ------------------------------------------------------------ preprocessing
  const FM_RE = /^---[ \t]*\n(?:([\s\S]*?)\n)?(?:---|\.\.\.)[ \t]*(?:\n|$)/;
  function stripFrontmatter(text) {
    const m = FM_RE.exec(text);
    if (!m) return { body: text, props: null, offset: 0 };
    let props;
    try {
      props = m[1] ? jsyaml.load(m[1]) : {};
    } catch (e) {
      return { body: text, props: null, offset: 0 };
    }
    if (props !== null && typeof props !== "object") return { body: text, props: null, offset: 0 };
    return { body: text.slice(m[0].length), props: props || {}, offset: (m[0].match(/\n/g) || []).length };
  }
  const stripComments = (text) => text.replace(/%%[\s\S]*?%%/g, (m) => m.replace(/[^\n]/g, ""));

  function renderProps(props, env) {
    const keys = Object.keys(props);
    if (!keys.length) return "";
    const chip = (k, v) => /^tags?$/i.test(k)
      ? `<span class="tag">#${esc(String(v).replace(/^#/, ""))}</span>`
      : `<span class="chip">${md.renderInline(String(v), env)}</span>`;
    const value = (k, v) => {
      if (v == null || v === "") return '<span class="prop-empty">Leer</span>';
      if (Array.isArray(v)) return v.map((x) => chip(k, Array.isArray(x) ? `[[${x.flat().join("")}]]` : x)).join("");
      if (typeof v === "boolean") return `<input type="checkbox" class="task" disabled${v ? " checked" : ""}>`;
      if (v instanceof Date) {
        const dateOnly = v.getUTCHours() === 0 && v.getUTCMinutes() === 0;
        return esc(dateOnly
          ? v.toLocaleDateString("de-DE", { timeZone: "UTC", day: "numeric", month: "long", year: "numeric" })
          : v.toLocaleString("de-DE", { dateStyle: "long", timeStyle: "short" }));
      }
      if (typeof v === "object") return `<code>${esc(JSON.stringify(v))}</code>`;
      if (/^(tags?|aliases)$/i.test(k)) return String(v).split(/[,\s]+/).filter(Boolean).map((x) => chip(k, x)).join("");
      return md.renderInline(String(v), env);
    };
    const rows = keys.map((k) => `<tr><th>${esc(k)}</th><td>${value(k, props[k])}</td></tr>`).join("");
    return `<details class="props" open><summary><span class="callout-fold">${ICON.chevron}</span>Eigenschaften</summary><table>${rows}</table></details>`;
  }

  // ------------------------------------------------------------ rendering
  let current = null, outline = [], generation = 0;

  function render(p) {
    current = p;
    const gen = ++generation;
    const anchor = p.keepScroll ? captureAnchor() : null;
    document.title = p.name || "Markdown";
    if (p.error) {
      content.innerHTML = `<div class="empty-state"><div class="empty-icon">${ICON.alert}</div><p>${esc(p.error)}</p></div>`;
      outline = [];
      reveal();
      return;
    }
    const text = p.text.replace(/\r\n?/g, "\n");
    const fm = stripFrontmatter(text);
    md.set({ breaks: !!p.vault });
    const env = { lineOffset: fm.offset, links: p.links || {}, outline: [], depth: 0 };
    let html = md.render(stripComments(fm.body), env);
    if (fm.props) html = renderProps(fm.props, { links: env.links, depth: 1 }) + html;
    if (!html.trim()) html = `<div class="empty-state"><p>Diese Datei ist leer.</p></div>`;
    content.innerHTML = html;
    outline = env.outline;
    if (outlineOpen()) buildOutline();
    if (anchor) restoreAnchor(anchor);
    else if (p.fragment) scrollToFragment(p.fragment, false);
    else window.scrollTo(0, 0);
    reveal();
    if (findOpen()) runFind(findInput.value, true);
    renderMermaid(gen, anchor);
  }

  function reveal() {
    if (!content.classList.contains("ready")) requestAnimationFrame(() => content.classList.add("ready"));
  }

  function captureAnchor() {
    for (const el of content.querySelectorAll("[data-line]")) {
      const r = el.getBoundingClientRect();
      if (r.bottom > 0) return { line: Number(el.dataset.line), top: r.top, y: window.scrollY };
    }
    return { line: null, y: window.scrollY };
  }
  function restoreAnchor(a) {
    if (a.line == null) { window.scrollTo(0, a.y); return; }
    let best = null;
    for (const el of content.querySelectorAll("[data-line]")) {
      if (Number(el.dataset.line) <= a.line) best = el;
      else break;
    }
    if (!best) { window.scrollTo(0, a.y); return; }
    window.scrollBy({ top: best.getBoundingClientRect().top - a.top, behavior: "instant" });
  }

  function findTarget(frag) {
    if (!frag) return null;
    let f = frag;
    try { f = decodeURIComponent(frag); } catch (e) { /* keep raw */ }
    if (f.startsWith("^")) {
      const id = f.slice(1);
      return [...content.querySelectorAll("[data-line]")].find((el) => el.textContent.trim().endsWith("^" + id)) || null;
    }
    const byId = document.getElementById(f) || document.getElementById(slugify(f));
    if (byId) return byId;
    const want = slugify(f.split("#").pop());
    return [...content.querySelectorAll("h1,h2,h3,h4,h5,h6")].find((h) => slugify(h.textContent) === want) || null;
  }
  function scrollToFragment(frag, smooth = true) {
    const el = findTarget(frag);
    if (!el) { if (smooth) toast("Abschnitt nicht gefunden"); return; }
    el.scrollIntoView({ behavior: smooth && !reducedMotion() ? "smooth" : "instant", block: "start" });
    el.classList.remove("flash");
    void el.offsetWidth;
    el.classList.add("flash");
    setTimeout(() => el.classList.remove("flash"), 1200);
  }
  const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  // --- mermaid (loaded on demand, ~2.7 MB)
  let mermaidLoad = null, mermaidKey = "", mermaidSeq = 0;
  const mermaidCache = new Map();
  function loadMermaid() {
    return mermaidLoad || (mermaidLoad = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.nonce = NONCE;
      s.src = ASSETS + "/vendor/mermaid.min.js";
      s.onload = resolve;
      s.onerror = () => { mermaidLoad = null; reject(new Error("mermaid.min.js fehlt")); };
      document.head.appendChild(s);
    }));
  }
  const hexToRgb = (h) => {
    const m = /^#?([0-9a-f]{6})/i.exec(h.trim());
    const n = m ? parseInt(m[1], 16) : 0;
    return [n >> 16, (n >> 8) & 255, n & 255];
  };
  const mix = (a, b, t) => {
    const x = hexToRgb(a), y = hexToRgb(b);
    return "#" + x.map((v, i) => Math.round(v + (y[i] - v) * t).toString(16).padStart(2, "0")).join("");
  };
  function configureMermaid() {
    const cs = getComputedStyle(document.documentElement);
    const c = (n) => cs.getPropertyValue("--c-" + n).trim();
    const bg = c("background"), fg = c("foreground"), acc = c("accent");
    const dark = document.body.dataset.mode === "dark";
    const key = [bg, fg, acc, dark].join();
    if (key === mermaidKey) return;
    mermaidKey = key;
    mermaidCache.clear();
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      fontFamily: "Inter, sans-serif",
      themeVariables: {
        darkMode: dark, background: bg, fontFamily: "Inter, sans-serif", fontSize: "14px",
        primaryColor: mix(bg, acc, 0.13), primaryTextColor: fg, primaryBorderColor: mix(bg, acc, 0.55),
        secondaryColor: mix(bg, fg, 0.07), secondaryTextColor: fg, secondaryBorderColor: mix(bg, fg, 0.3),
        tertiaryColor: mix(bg, fg, 0.035), tertiaryTextColor: fg, tertiaryBorderColor: mix(bg, fg, 0.2),
        lineColor: mix(bg, fg, 0.5), textColor: fg, titleColor: fg,
        mainBkg: mix(bg, acc, 0.12), nodeBorder: mix(bg, acc, 0.55), nodeTextColor: fg,
        clusterBkg: mix(bg, fg, 0.035), clusterBorder: mix(bg, fg, 0.18),
        edgeLabelBackground: bg, noteBkgColor: mix(bg, c("yellow") || acc, 0.16), noteTextColor: fg,
        noteBorderColor: mix(bg, c("yellow") || acc, 0.45),
        actorBkg: mix(bg, acc, 0.12), actorBorder: mix(bg, acc, 0.55), actorTextColor: fg,
        signalColor: fg, signalTextColor: fg, labelBoxBkgColor: mix(bg, fg, 0.05),
      },
    });
  }
  async function renderMermaid(gen, anchor) {
    const blocks = [...content.querySelectorAll("pre.mermaid")];
    if (!blocks.length) return;
    try {
      await loadMermaid();
    } catch (e) {
      blocks.forEach((b) => b.parentElement.classList.add("failed"));
      return;
    }
    if (gen !== generation) return;
    configureMermaid();
    for (const pre of blocks) {
      const host = pre.parentElement, src = pre.textContent;
      let out = mermaidCache.get(src);
      const fresh = !out;
      if (!out) {
        const id = "mmd" + ++mermaidSeq;
        try {
          out = (await mermaid.render(id, src)).svg;
          mermaidCache.set(src, out);
        } catch (e) {
          document.getElementById("d" + id)?.remove();
          document.getElementById(id)?.remove();
          out = `<div class="mermaid-error"><strong>Mermaid-Fehler</strong><pre>${esc(e.message || e)}</pre></div>`;
        }
        if (gen !== generation) return;
      }
      host.innerHTML = out;
      host.classList.add(fresh ? "rendered" : "cached");
    }
    if (anchor) restoreAnchor(anchor);
  }

  function setTheme(css, mode) {
    document.getElementById("theme").textContent = css;
    document.body.dataset.mode = mode;
    if (current && content.querySelector(".mermaid-block")) render({ ...current, keepScroll: true, fragment: null });
  }
  function setMotion(css) {
    document.getElementById("henri-ui").textContent = css;
  }

  // ------------------------------------------------------------ chrome: toolbar, find, outline, toast
  const toolbar = document.createElement("nav");
  toolbar.id = "toolbar";
  toolbar.innerHTML =
    `<button class="tb" data-act="outline" title="Gliederung (Strg+Umschalt+O)" aria-label="Gliederung">${ICON.list}</button>` +
    `<button class="tb" data-act="find" title="Suchen (Strg+F)" aria-label="Suchen">${ICON.search}</button>` +
    `<button class="tb" data-act="edit" title="Im Editor öffnen (Strg+E)" aria-label="Bearbeiten">${ICON.pencil}</button>`;
  document.body.appendChild(toolbar);

  const outlinePop = document.createElement("div");
  outlinePop.id = "outline";
  outlinePop.className = "ui-menu ui-popover surface";
  outlinePop.style.setProperty("--origin", "top right");
  outlinePop.tabIndex = -1;
  outlinePop.setAttribute("role", "menu");
  document.body.appendChild(outlinePop);

  const findBar = document.createElement("div");
  findBar.id = "findbar";
  findBar.className = "ui-menu surface";
  findBar.style.setProperty("--origin", "top right");
  findBar.innerHTML =
    `<span class="find-icon">${ICON.search}</span>` +
    `<input id="find-input" type="search" placeholder="Suchen" spellcheck="false" autocomplete="off">` +
    `<span id="find-count" aria-live="polite"></span>` +
    `<button class="tb" data-act="prev" title="Vorheriger Treffer (Umschalt+Enter)" aria-label="Vorheriger Treffer">${ICON.up}</button>` +
    `<button class="tb" data-act="next" title="Nächster Treffer (Enter)" aria-label="Nächster Treffer">${ICON.down}</button>` +
    `<button class="tb" data-act="closefind" title="Schließen (Esc)" aria-label="Suche schließen">${ICON.x}</button>`;
  document.body.appendChild(findBar);
  const findInput = findBar.querySelector("#find-input");
  const findCount = findBar.querySelector("#find-count");

  const toastEl = document.createElement("div");
  toastEl.id = "toast";
  toastEl.setAttribute("role", "status");
  document.body.appendChild(toastEl);
  let toastTimer = 0;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.dataset.open = "";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => delete toastEl.dataset.open, 1600);
  }

  const outlineOpen = () => outlinePop.hasAttribute("data-open");
  const findOpen = () => findBar.hasAttribute("data-open");

  // toolbar hides while reading downwards, returns on scroll up or near the top
  let lastY = 0;
  const showToolbar = (show) => toolbar.classList.toggle("hidden", !show);
  addEventListener("scroll", () => {
    const y = window.scrollY;
    if (y < 48 || y < lastY - 6) showToolbar(true);
    else if (y > lastY + 6 && !outlineOpen() && !findOpen()) showToolbar(false);
    lastY = y;
  }, { passive: true });
  addEventListener("mousemove", (e) => { if (e.clientY < 72) showToolbar(true); }, { passive: true });

  // --- outline popover
  let hl = -1;
  function buildOutline() {
    if (!outline.length) {
      outlinePop.innerHTML = '<div class="menu-empty">Keine Überschriften</div>';
      return;
    }
    const minLevel = Math.min(...outline.map((o) => o.level));
    outlinePop.innerHTML = outline.map((o, i) =>
      `<button class="menu-item" role="menuitem" data-i="${i}" style="--indent:${o.level - minLevel}">${esc(o.text)}</button>`).join("");
  }
  function currentSection() {
    let idx = -1;
    outline.forEach((o, i) => {
      const el = document.getElementById(o.slug);
      if (el && el.getBoundingClientRect().top < 120) idx = i;
    });
    return idx;
  }
  function setHl(i) {
    const items = outlinePop.querySelectorAll(".menu-item");
    items.forEach((el, k) => el.classList.toggle("hl", k === i));
    hl = i;
    if (items[i]) items[i].scrollIntoView({ block: "nearest" });
  }
  function openOutline() {
    closeFind(false);
    buildOutline();
    const cur = currentSection();
    outlinePop.querySelectorAll(".menu-item").forEach((el, k) => el.classList.toggle("current", k === cur));
    showToolbar(true);
    outlinePop.dataset.open = "";
    toolbar.querySelector('[data-act="outline"]').classList.add("active");
    setHl(Math.max(cur, 0));
    outlinePop.focus({ preventScroll: true });
  }
  function closeOutline() {
    if (!outlineOpen()) return false;
    delete outlinePop.dataset.open;
    toolbar.querySelector('[data-act="outline"]').classList.remove("active");
    hl = -1;
    outlinePop.querySelectorAll(".hl").forEach((el) => el.classList.remove("hl"));
    return true;
  }
  function activateOutline(i) {
    const item = outlinePop.querySelectorAll(".menu-item")[i];
    if (!item) return;
    const flash = motionMs("--flash-duration", 70);
    item.classList.remove("hl");
    setTimeout(() => item.classList.add("hl"), flash);
    setTimeout(() => { closeOutline(); scrollToFragment(outline[i].slug, true); }, flash * 2);
  }
  outlinePop.addEventListener("mousemove", (e) => {
    const item = e.target.closest(".menu-item");
    if (item && Number(item.dataset.i) !== hl) setHl(Number(item.dataset.i));
  });
  outlinePop.addEventListener("mouseleave", () => setHl(-1));
  outlinePop.addEventListener("click", (e) => {
    const item = e.target.closest(".menu-item");
    if (item) activateOutline(Number(item.dataset.i));
  });
  outlinePop.addEventListener("keydown", (e) => {
    const n = outline.length;
    if (!n) return;
    const moves = { ArrowDown: hl + 1, ArrowUp: hl - 1, Home: 0, End: n - 1 };
    if (e.key in moves) { e.preventDefault(); setHl(Math.min(n - 1, Math.max(0, moves[e.key]))); }
    else if (e.key === "Enter" && hl >= 0) { e.preventDefault(); activateOutline(hl); }
  });

  // --- find (CSS Custom Highlight API, DOM untouched)
  let hits = [], hitIdx = -1;
  const canHighlight = typeof Highlight !== "undefined" && CSS.highlights;
  function runFind(q, keepPos = false) {
    const prevRange = hits[hitIdx];
    hits = [];
    hitIdx = -1;
    if (canHighlight) { CSS.highlights.delete("find"); CSS.highlights.delete("find-current"); }
    findBar.classList.remove("no-hits");
    if (!q) { findCount.textContent = ""; return; }
    const needle = q.toLocaleLowerCase();
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.parentElement.closest(".katex-mathml, style, script") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let n = walker.nextNode(); n && hits.length < 5000; n = walker.nextNode()) {
      const hay = n.data.toLocaleLowerCase();
      for (let i = hay.indexOf(needle); i !== -1; i = hay.indexOf(needle, i + needle.length)) {
        const r = new Range();
        r.setStart(n, i);
        r.setEnd(n, Math.min(n.data.length, i + q.length));
        hits.push(r);
      }
    }
    if (!hits.length) {
      findCount.textContent = "Keine Treffer";
      findBar.classList.add("no-hits");
      return;
    }
    if (canHighlight) CSS.highlights.set("find", new Highlight(...hits));
    const refTop = keepPos && prevRange ? prevRange.getBoundingClientRect().top - 1 : 0;
    const start = hits.findIndex((r) => r.getBoundingClientRect().top >= refTop);
    focusHit(start < 0 ? 0 : start, !keepPos);
  }
  function focusHit(i, scroll = true) {
    if (!hits.length) return;
    hitIdx = (i + hits.length) % hits.length;
    const r = hits[hitIdx];
    if (canHighlight) CSS.highlights.set("find-current", new Highlight(r));
    findCount.textContent = `${hitIdx + 1} von ${hits.length}`;
    if (!scroll) return;
    const rect = r.getBoundingClientRect();
    if (rect.top < 80 || rect.bottom > innerHeight - 40) {
      window.scrollBy({ top: rect.top - innerHeight / 3, behavior: reducedMotion() ? "instant" : "smooth" });
    }
  }
  function openFind() {
    closeOutline();
    showToolbar(true);
    findBar.dataset.open = "";
    const sel = String(getSelection());
    if (sel && !sel.includes("\n") && sel.length < 80) findInput.value = sel;
    findInput.focus();
    findInput.select();
    runFind(findInput.value);
  }
  function closeFind(refocus = true) {
    if (!findOpen()) return false;
    delete findBar.dataset.open;
    if (canHighlight) { CSS.highlights.delete("find"); CSS.highlights.delete("find-current"); }
    const r = hits[hitIdx];
    hits = [];
    if (refocus) {
      findInput.blur();
      if (r) { const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
    }
    return true;
  }
  let findTimer = 0;
  findInput.addEventListener("input", () => {
    clearTimeout(findTimer);
    findTimer = setTimeout(() => runFind(findInput.value), hits.length > 500 ? 120 : 30);
  });
  findInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); focusHit(hitIdx + (e.shiftKey ? -1 : 1)); }
  });

  // --- toolbar + find buttons
  const actions = {
    outline: () => (outlineOpen() ? closeOutline() : openOutline()),
    find: () => (findOpen() ? closeFind() : openFind()),
    edit: () => post("edit"),
    prev: () => focusHit(hitIdx - 1),
    next: () => focusHit(hitIdx + 1),
    closefind: () => closeFind(),
  };
  for (const root of [toolbar, findBar]) {
    root.addEventListener("click", (e) => {
      const b = e.target.closest("[data-act]");
      if (b) actions[b.dataset.act]();
    });
  }

  // click outside the outline closes it and is swallowed (macOS popover behaviour)
  let swallowClick = false;
  addEventListener("pointerdown", (e) => {
    if (!outlineOpen() || outlinePop.contains(e.target) || e.target.closest('[data-act="outline"]')) return;
    closeOutline();
    swallowClick = true;
    e.preventDefault();
    e.stopPropagation();
  }, true);
  addEventListener("click", (e) => {
    if (swallowClick) { swallowClick = false; e.preventDefault(); e.stopPropagation(); }
  }, true);

  // --- content clicks: links, tasks, copy
  document.addEventListener("click", (e) => {
    if (e.defaultPrevented) return;
    const box = e.target.closest("input.task");
    if (box) {
      if (box.disabled || box.dataset.line == null) { e.preventDefault(); return; }
      box.closest("li")?.classList.toggle("is-checked", box.checked);
      post("toggle", { line: Number(box.dataset.line), checked: box.checked });
      return;
    }
    const copy = e.target.closest(".code-copy");
    if (copy) {
      post("copy", { text: copy.closest(".code-block").querySelector("code").textContent });
      copy.textContent = "Kopiert";
      copy.classList.add("done");
      setTimeout(() => { copy.textContent = "Kopieren"; copy.classList.remove("done"); }, 1400);
      return;
    }
    const a = e.target.closest("a");
    if (!a || !content.contains(a)) return;
    e.preventDefault();
    if (a.dataset.wiki != null) { post("wikilink", { target: a.dataset.wiki }); return; }
    const href = a.getAttribute("href");
    if (!href) return;
    if (href.startsWith("#")) { scrollToFragment(href.slice(1), true); return; }
    post("link", { href: a.href });
  });
  document.addEventListener("auxclick", (e) => { if (e.target.closest("a")) e.preventDefault(); });
  addEventListener("mouseup", (e) => {
    if (e.button === 3) post("back");
    else if (e.button === 4) post("forward");
  });

  // --- keyboard
  addEventListener("keydown", (e) => {
    const mod = e.ctrlKey || e.metaKey;
    const k = e.key.toLowerCase();
    const typing = e.target.matches?.("input[type=search], input[type=text], textarea");
    if (e.key === "Escape") {
      if (closeOutline() || closeFind()) e.preventDefault();
      return;
    }
    if (mod && e.shiftKey && k === "o") { e.preventDefault(); actions.outline(); return; }
    if (mod && !e.shiftKey && !e.altKey) {
      const map = {
        f: openFind, e: () => post("edit"), o: () => post("open"), r: () => post("reload"),
        p: () => post("print"), w: () => post("close"), q: () => post("close"),
        "=": () => post("zoom", { step: 1 }), "+": () => post("zoom", { step: 1 }),
        "-": () => post("zoom", { step: -1 }), "0": () => post("zoom", { step: 0 }),
        g: () => focusHit(hitIdx + 1),
      };
      if (map[k]) { e.preventDefault(); map[k](); }
      return;
    }
    if (mod && e.shiftKey && k === "g") { e.preventDefault(); focusHit(hitIdx - 1); return; }
    if (e.altKey && e.key === "ArrowLeft") { e.preventDefault(); post("back"); return; }
    if (e.altKey && e.key === "ArrowRight") { e.preventDefault(); post("forward"); return; }
    if (!typing && !mod && !e.altKey && e.key === "/") { e.preventDefault(); openFind(); }
  });

  window.MdView = { render, setTheme, setMotion, scrollToFragment, toast };
})();
