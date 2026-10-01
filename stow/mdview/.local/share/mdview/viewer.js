/* mdview — renderer, source editor, folder sidebar + UI inside the web view.
 * Python calls MdView.render(payload) and friends; the page talks back via
 * window.webkit.messageHandlers.mdview (JSON strings). */
"use strict";
(() => {
  const NONCE = document.currentScript.nonce;
  const ASSETS = document.currentScript.src.replace(/\/[^/]*$/, "");
  const content = document.getElementById("content");
  const baseEl = document.querySelector("base");
  // Anything that leaves the file or the window hands over unsaved edits first.
  const LEAVING = new Set(["back", "forward", "open", "reload", "close", "print", "external", "note", "newnote", "folder", "rename", "trash"]);
  const post = (type, data = {}) => {
    if (LEAVING.has(type)) flushSave();
    window.webkit?.messageHandlers?.mdview?.postMessage(JSON.stringify({ type, ...data }));
  };
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
    sidebar: svg('<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>'),
    plus: svg('<path d="M12 5v14M5 12h14"/>'),
    title: svg('<path d="M5 7V5h14v2M12 5v14M9 19h6"/>'),
    folder: svg('<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>'),
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
      let slug = slugify(text) || "section";
      const n = slugs.get(slug) || 0;
      slugs.set(slug, n + 1);
      if (n) slug += "-" + n;
      if (env.depth) continue;
      t.attrSet("id", slug);
      env.outline?.push({ level: Number(t.tag.slice(1)), text, slug, line: t.map ? t.map[0] + (env.lineOffset || 0) : 0 });
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
      `<button class="btn code-copy" type="button" title="Copy code">Copy</button></div>` +
      `<pre><code class="hljs${lang ? " language-" + esc(lang) : ""}">${code}</code></pre></div>`;
  };
  md.renderer.rules.code_block = (toks, idx) =>
    `<div class="code-block"${lineAttr(toks[idx])}><div class="code-tools"><button class="btn code-copy" type="button" title="Copy code">Copy</button></div><pre><code class="hljs">${esc(toks[idx].content)}</code></pre></div>`;
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
      if (v == null || v === "") return '<span class="prop-empty">Empty</span>';
      if (Array.isArray(v)) return v.map((x) => chip(k, Array.isArray(x) ? `[[${x.flat().join("")}]]` : x)).join("");
      if (typeof v === "boolean") return `<input type="checkbox" class="task" disabled${v ? " checked" : ""}>`;
      if (v instanceof Date) {
        const dateOnly = v.getUTCHours() === 0 && v.getUTCMinutes() === 0;
        return esc(dateOnly
          ? v.toLocaleDateString(undefined, { timeZone: "UTC", day: "numeric", month: "long", year: "numeric" })
          : v.toLocaleString(undefined, { dateStyle: "long", timeStyle: "short" }));
      }
      if (typeof v === "object") return `<code>${esc(JSON.stringify(v))}</code>`;
      if (/^(tags?|aliases)$/i.test(k)) return String(v).split(/[,\s]+/).filter(Boolean).map((x) => chip(k, x)).join("");
      return md.renderInline(String(v), env);
    };
    const rows = keys.map((k) => `<tr><th>${esc(k)}</th><td>${value(k, props[k])}</td></tr>`).join("");
    return `<details class="props" open><summary><span class="callout-fold">${ICON.chevron}</span>Properties</summary><table>${rows}</table></details>`;
  }

  // ------------------------------------------------------------ rendering
  let current = null, outline = [], generation = 0;
  let mode = "read"; // "read" | "edit"

  function render(p) {
    const prev = current;
    p.text = p.text.replace(/\r\n?/g, "\n");
    current = p;
    document.title = p.name || "Markdown";
    if (p.base && baseEl.href !== p.base) baseEl.href = p.base; // relative links and images
    if (!prev || prev.path !== p.path) markActiveNote(true);
    if (mode === "edit") {
      if (prev && prev.path === p.path) { adoptDisk(p); return; }
      leaveEditNow();
    }
    draw(p, p.keepScroll ? captureAnchor() : null);
  }

  // A folder window with nothing to show (no notes yet).
  function clear() {
    if (mode === "edit") { flushSave(); leaveEditNow(); }
    current = null;
    outline = [];
    document.title = folder ? folder.name : "Markdown";
    content.innerHTML = `<div class="empty-state"><div class="empty-icon">${ICON.folder}</div><p>No notes in this folder yet.</p></div>`;
    window.scrollTo(0, 0);
    reveal();
    markActiveNote(false);
  }

  // quiet: fill the (hidden) reading view without touching scroll or find
  function draw(p, anchor, quiet = false) {
    const gen = ++generation;
    if (p.error) {
      content.innerHTML = `<div class="empty-state"><div class="empty-icon">${ICON.alert}</div><p>${esc(p.error)}</p></div>`;
      outline = [];
      reveal();
      return;
    }
    const fm = stripFrontmatter(p.text);
    md.set({ breaks: !!p.vault });
    const env = { lineOffset: fm.offset, links: p.links || {}, outline: [], depth: 0 };
    let html = md.render(stripComments(fm.body), env);
    if (fm.props) html = renderProps(fm.props, { links: env.links, depth: 1 }) + html;
    if (!html.trim()) html = `<div class="empty-state"><p>This file is empty.</p></div>`;
    content.innerHTML = html;
    outline = env.outline;
    reveal();
    if (quiet) { renderMermaid(gen, null); return; }
    if (outlineOpen()) buildOutline();
    if (anchor) restoreAnchor(anchor);
    else if (p.fragment) scrollToFragment(p.fragment, false);
    else window.scrollTo(0, 0);
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
    if (!el) { if (smooth) toast("Section not found"); return; }
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
      s.onerror = () => { mermaidLoad = null; reject(new Error("mermaid.min.js missing")); };
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
          out = `<div class="mermaid-error"><strong>Mermaid error</strong><pre>${esc(e.message || e)}</pre></div>`;
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
    if (current && mode === "read" && content.querySelector(".mermaid-block")) draw(current, captureAnchor());
  }
  function setMotion(css) {
    document.getElementById("henri-ui").textContent = css;
  }

  // ------------------------------------------------------------ chrome: toolbar, find, outline, toast
  const toolbar = document.createElement("nav");
  toolbar.id = "toolbar";
  toolbar.innerHTML =
    `<button class="tb" data-act="sidebar" title="Sidebar (Ctrl+Alt+S)" aria-label="Sidebar">${ICON.sidebar}</button>` +
    `<button class="tb" data-act="outline" title="Outline (Ctrl+Shift+O)" aria-label="Outline">${ICON.list}</button>` +
    `<button class="tb" data-act="find" title="Find (Ctrl+F)" aria-label="Find">${ICON.search}</button>` +
    `<button class="tb" data-act="edit" title="Edit (Ctrl+E)" aria-label="Edit" aria-pressed="false">${ICON.pencil}</button>`;
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
    `<input id="find-input" type="search" placeholder="Find" spellcheck="false" autocomplete="off">` +
    `<span id="find-count" aria-live="polite"></span>` +
    `<button class="tb" data-act="prev" title="Previous match (Shift+Enter)" aria-label="Previous match">${ICON.up}</button>` +
    `<button class="tb" data-act="next" title="Next match (Enter)" aria-label="Next match">${ICON.down}</button>` +
    `<button class="tb" data-act="closefind" title="Close (Esc)" aria-label="Close find">${ICON.x}</button>`;
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
      outlinePop.innerHTML = '<div class="menu-empty">No headings</div>';
      return;
    }
    const minLevel = Math.min(...outline.map((o) => o.level));
    outlinePop.innerHTML = outline.map((o, i) =>
      `<button class="menu-item" role="menuitem" data-i="${i}" style="--indent:${o.level - minLevel}">${esc(o.text)}</button>`).join("");
  }
  const headingEl = (o) => (mode === "edit" ? edBack.children[o.line] : document.getElementById(o.slug));
  function currentSection() {
    let idx = -1;
    outline.forEach((o, i) => {
      const el = headingEl(o);
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
    if (mode === "edit") outline = editorOutline();
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
    setTimeout(() => {
      closeOutline();
      if (mode === "edit") goToLine(outline[i].line);
      else scrollToFragment(outline[i].slug, true);
    }, flash * 2);
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
    if (mode === "edit") {
      const hay = edInput.value.toLocaleLowerCase();
      for (let i = hay.indexOf(needle); i !== -1 && hits.length < 5000; i = hay.indexOf(needle, i + needle.length)) {
        const r = rangeOf(i, i + q.length);
        r.at = i;
        hits.push(r);
      }
    } else {
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
    }
    if (!hits.length) {
      findCount.textContent = "No matches";
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
    findCount.textContent = `${hitIdx + 1} of ${hits.length}`;
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
    const sel = mode === "edit" ? edInput.value.slice(edInput.selectionStart, edInput.selectionEnd) : String(getSelection());
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
      if (mode === "edit") {
        edInput.focus({ preventScroll: true });
        if (r) edInput.setSelectionRange(r.at, r.at + String(r).length);
      } else if (r) { const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
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

  // ------------------------------------------------------------ editor
  // A plain <textarea> holds the text (native caret, undo, IME); its glyphs are
  // transparent. #ed-back on top shows the same text, one <div class="ln"> per
  // source line, with Markdown syntax coloured. Same font and width in both, so
  // they wrap alike; the backdrop gives the height and the page scrolls.
  const AUTOSAVE_MS = 800;
  const editor = document.createElement("section");
  editor.id = "editor";
  editor.innerHTML =
    '<div id="ed-wrap"><textarea id="ed-input" spellcheck="false" autocomplete="off" autocapitalize="off"' +
    ' aria-label="Markdown source" placeholder="Start writing…"></textarea><div id="ed-back" aria-hidden="true"></div></div>';
  content.after(editor);
  const edWrap = editor.firstChild;
  const edInput = edWrap.firstChild;
  const edBack = edWrap.lastChild;
  const editBtn = toolbar.querySelector('[data-act="edit"]');

  let edPath = null;     // file the editor holds; null = nothing loaded
  let edFresh = false;   // text was just loaded: put the caret where the reader was
  let edReveal = false;  // caret was placed by the caller (new note): scroll to it
  let edKeys = [];       // per line: class + html currently in #ed-back
  let lineStarts = [0];  // offset of every line in the textarea value
  let savedText = null;  // what is on disk as far as we know
  let saveTimer = 0, swapTimer = 0;

  // --- syntax colours (line based; text content always equals the source)
  const span = (cls, html) => `<span class="m-${cls}">${html}</span>`;
  const EMPH = { "**": "b", "__": "b", "~~": "s", "==": "mark" };
  const INLINE = new RegExp([
    /\\./,                                              // escape
    /(`+)(?:(?!\1).)+?\1/,                              // 1: code span
    /!?\[\[[^\[\]]+?\]\]/,                              // wikilink, embed
    /!?\[[^\]]*\]\([^)]*\)/,                            // link, image
    /(\*\*|__|~~|==)(?=\S)(.+?)(?<=\S)\2/,              // 2, 3: bold, strike, highlight
    /\*(?=\S)(.+?)(?<=\S)\*/,                           // 4: italic
    /(?<![\p{L}\p{N}_])_(?=\S)(.+?)(?<=\S)_(?![\p{L}\p{N}_])/, // 5: italic
    /\$(?=[^\s$])[^$]*?(?<=\S)\$(?!\d)/,                // math
    /%%.*?%%/,                                          // comment
    /<\/?[a-zA-Z][^>]*>/,                               // html tag
    /(?<![\p{L}\p{N}/#&])#[\p{L}\p{N}_\-/]+/,           // tag
    /https?:\/\/[^\s<>)\]]+/,                           // bare url
  ].map((r) => r.source).join("|"), "gu");
  function hlInline(s) {
    let out = "", last = 0;
    for (const m of s.matchAll(INLINE)) {
      const t = m[0];
      out += esc(s.slice(last, m.index));
      last = m.index + t.length;
      if (t[0] === "\\") out += span("dim", "\\") + esc(t.slice(1));
      else if (m[1]) out += span("code", esc(t));
      else if (m[2]) { const d = span("dim", esc(m[2])); out += span(EMPH[m[2]], d + hlInline(m[3]) + d); }
      else if (m[4] != null) out += span("i", span("dim", "*") + hlInline(m[4]) + span("dim", "*"));
      else if (m[5] != null) out += span("i", span("dim", "_") + hlInline(m[5]) + span("dim", "_"));
      else if (t.startsWith("%%")) out += span("comment", esc(t));
      else if (t[0] === "$") out += span("math", esc(t));
      else if (t[0] === "<") out += span("html", esc(t));
      else if (t[0] === "#") out += /^#[\d/_-]+$/.test(t) ? esc(t) : span("tag", esc(t));
      else if (t[0] === "h") out += span("url", esc(t));
      else if (t.endsWith("]]")) out += span("link", esc(t));
      else { const i = t.indexOf("]("); out += span("link", esc(t.slice(0, i + 1))) + span("dim", esc(t.slice(i + 1))); }
    }
    return out + esc(s.slice(last));
  }
  // -> [html, line class, next state]. States: "start" (line 0), "" (text),
  // "fm" (frontmatter), "math" ($$ block), or the fence that opened a code block.
  function hlLineRaw(line, st) {
    let m;
    if (st === "start" && /^---[ \t]*$/.test(line)) return [span("dim", esc(line)), "meta", "fm"];
    if (st === "fm") {
      if (/^(---|\.\.\.)[ \t]*$/.test(line)) return [span("dim", esc(line)), "meta", ""];
      m = /^(\s*(?:- )?[^\s:#][^:]*?)(:)(\s.*|)$/.exec(line);
      return [m ? span("key", esc(m[1])) + span("dim", ":") + esc(m[3]) : esc(line), "meta", "fm"];
    }
    if (st[0] === "`" || st[0] === "~") {
      m = /^\s*(`{3,}|~{3,})[ \t]*$/.exec(line);
      return m && m[1][0] === st[0] && m[1].length >= st.length
        ? [span("dim", esc(line)), "code code-end", ""]
        : [esc(line), "code", st];
    }
    if (st === "math") return [span("math", esc(line)), "", line.trim().endsWith("$$") ? "" : "math"];
    if ((m = /^(\s*)(`{3,}(?=[^`]*$)|~{3,})(.*)$/.exec(line))) {
      return [span("dim", esc(m[1] + m[2])) + span("lang", esc(m[3])), "code code-start", m[2]];
    }
    if (/^ {0,3}\$\$/.test(line)) {
      const rest = line.trim().slice(2);
      return [span("math", esc(line)), "", rest.length >= 2 && rest.endsWith("$$") ? "" : "math"];
    }
    if ((m = /^( {0,3}#{1,6})([ \t].*|)$/.exec(line))) return [span("h", span("dim", m[1]) + hlInline(m[2])), "", ""];
    if (/^ {0,3}([-*_])([ \t]*\1){2,}[ \t]*$/.test(line)) return [span("dim", esc(line)), "", ""];
    let out = "", rest = line, cls = "";
    if ((m = /^\s*(?:>[ \t]?)+/.exec(rest))) {
      out += span("quote", esc(m[0]));
      rest = rest.slice(m[0].length);
      cls = "quote";
      if ((m = /^\[![\w-]+\][+-]?/.exec(rest))) { out += span("callout", esc(m[0])); rest = rest.slice(m[0].length); }
    }
    if ((m = /^(\s*)([-*+]|\d{1,9}[.)])(\s+)(\[.\](?=\s|$))?/.exec(rest))) {
      out += m[1] + span("list", esc(m[2])) + m[3] + (m[4] ? span("task", esc(m[4])) : "");
      rest = rest.slice(m[0].length);
    }
    return [out + hlInline(rest), cls, ""];
  }
  const hlCache = new Map();
  function hlLine(line, st) {
    const key = st + "\n" + line;
    let r = hlCache.get(key);
    if (!r) {
      if (hlCache.size > 20000) hlCache.clear();
      hlCache.set(key, r = hlLineRaw(line, st));
    }
    return r;
  }

  // Repaint the backdrop; only the lines that changed are touched.
  function paint(text) {
    const lines = text.split("\n"), n = lines.length;
    const keys = new Array(n), html = new Array(n), cls = new Array(n);
    lineStarts = new Array(n);
    let st = "start", off = 0;
    for (let i = 0; i < n; i++) {
      lineStarts[i] = off;
      off += lines[i].length + 1;
      const r = hlLine(lines[i], st);
      html[i] = r[0];
      cls[i] = r[1];
      keys[i] = r[1] + "\n" + r[0];
      st = r[2];
    }
    const old = edKeys, max = Math.min(old.length, n);
    let a = 0, b = 0;
    while (a < max && old[a] === keys[a]) a++;
    while (b < max - a && old[old.length - 1 - b] === keys[n - 1 - b]) b++;
    if (!a && !b) edBack.textContent = "";
    else for (let i = old.length - b - 1; i >= a; i--) edBack.children[i].remove();
    const frag = document.createDocumentFragment();
    for (let i = a; i < n - b; i++) {
      const d = document.createElement("div");
      d.className = cls[i] ? "ln " + cls[i] : "ln";
      d.innerHTML = html[i] || "<br>";
      frag.appendChild(d);
    }
    edBack.insertBefore(frag, edBack.children[a] || null);
    edKeys = keys;
  }
  function setEditorText(text) {
    edInput.value = text;
    paint(text);
  }

  // --- geometry: textarea offsets -> backdrop DOM
  function lineOf(offset) {
    let lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) lo = mid; else hi = mid - 1;
    }
    return lo;
  }
  function locate(offset) {
    const li = lineOf(offset), el = edBack.children[li];
    let rem = offset - lineStarts[li], last = null;
    const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let n = w.nextNode(); n; n = w.nextNode()) {
      if (rem <= n.data.length) return [n, rem];
      rem -= n.data.length;
      last = n;
    }
    return last ? [last, last.data.length] : [el, 0];
  }
  function rangeOf(start, end) {
    const r = new Range();
    r.setStart(...locate(start));
    r.setEnd(...locate(end));
    return r;
  }
  function revealCaret() {
    if (mode !== "edit") return;
    const pos = edInput.selectionDirection === "backward" ? edInput.selectionStart : edInput.selectionEnd;
    const r = rangeOf(pos, pos).getClientRects()[0] || edBack.children[lineOf(pos)].getBoundingClientRect();
    const top = 64, bottom = innerHeight - 48;
    if (r.top < top) window.scrollBy({ top: r.top - top, behavior: "instant" });
    else if (r.bottom > bottom) window.scrollBy({ top: r.bottom - bottom, behavior: "instant" });
  }
  function captureEditAnchor() {
    const els = edBack.children;
    if (!els.length || window.scrollY < 4) return { line: null, y: 0 };
    let lo = 0, hi = els.length - 1; // first line that reaches below the top edge
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (els[mid].getBoundingClientRect().bottom > 0) hi = mid; else lo = mid + 1;
    }
    return { line: lo, top: els[lo].getBoundingClientRect().top, y: window.scrollY };
  }
  function goToLine(line) {
    const el = edBack.children[line];
    if (!el) return;
    edInput.focus({ preventScroll: true });
    edInput.setSelectionRange(lineStarts[line], lineStarts[line]);
    el.scrollIntoView({ behavior: reducedMotion() ? "instant" : "smooth", block: "start" });
    el.classList.remove("flash");
    void el.offsetWidth;
    el.classList.add("flash");
    setTimeout(() => el.classList.remove("flash"), 1200);
  }
  function editorOutline() {
    const fm = stripFrontmatter(edInput.value);
    const env = { lineOffset: fm.offset, links: {}, outline: [], depth: 0 };
    md.parse(stripComments(fm.body), env);
    return env.outline;
  }

  // --- saving: automatic, shortly after the last keystroke
  const dirty = () => edPath != null && edInput.value !== savedText;
  function flushSave() {
    clearTimeout(saveTimer);
    saveTimer = 0;
    if (!dirty()) return;
    savedText = edInput.value;
    if (current && current.path === edPath) { current.text = savedText; current.error = null; }
    post("save", { text: savedText, path: edPath });
  }
  function flush(thenClose) {
    flushSave();
    if (thenClose) post("close");
  }
  function saveFailed(msg) {
    savedText = null; // still dirty: the next edit or mode switch tries again
    toast(`Couldn't save: ${msg}`);
  }
  // The file changed on disk while it is open in the editor.
  function adoptDisk(p) {
    if (p.text === edInput.value) { savedText = p.text; return; }
    if (dirty()) {
      p.text = edInput.value;
      toast("File changed on disk — keeping your edits");
      return;
    }
    const pos = edInput.selectionStart;
    setEditorText(p.text);
    savedText = p.text;
    edInput.setSelectionRange(pos, pos);
    if (findOpen()) runFind(findInput.value, true);
  }
  addEventListener("blur", flushSave);

  // --- switching between reading and editing: the views crossfade one after
  // the other (they share the page scroll) and stay on the same source line.
  function setMode(next, caret) {
    if (next === mode || !current) return;
    if (next === "edit") {
      if (current.readonly) { toast(`Can't edit: ${current.readonly}`); return; }
      if (edPath !== current.path || (!dirty() && edInput.value !== current.text)) {
        setEditorText(current.text);
        savedText = current.text;
        edPath = current.path;
        edFresh = true;
      }
      if (caret === "end") { edInput.setSelectionRange(edInput.value.length, edInput.value.length); edFresh = false; edReveal = true; }
    } else {
      flushSave();
    }
    mode = next;
    post("mode", { edit: mode === "edit" });
    editBtn.classList.toggle("active", mode === "edit");
    editBtn.setAttribute("aria-pressed", String(mode === "edit"));
    editBtn.title = mode === "edit" ? "Done (Ctrl+E)" : "Edit (Ctrl+E)";
    closeOutline();
    document.body.classList.add("swapping", "swapped");
    clearTimeout(swapTimer);
    swapTimer = setTimeout(swapView, motionMs("--dur-fast", 160) * 0.7);
  }
  function swapView() {
    swapTimer = 0;
    const body = document.body;
    if ((body.dataset.view || "read") !== mode) {
      if (mode === "edit") {
        const a = window.scrollY < 4 ? { line: null } : captureAnchor();
        body.dataset.view = "edit";
        const el = a.line == null ? null : edBack.children[Math.min(a.line, edBack.children.length - 1)];
        if (el) window.scrollBy({ top: el.getBoundingClientRect().top - a.top, behavior: "instant" });
        else window.scrollTo(0, 0);
        if (edFresh) {
          const pos = el ? lineStarts[Math.min(a.line, lineStarts.length - 1)] : 0;
          edInput.setSelectionRange(pos, pos);
          edFresh = false;
        }
      } else {
        const a = captureEditAnchor();
        edInput.blur();
        body.dataset.view = "read";
        current.text = edInput.value;
        draw(current, a);
        // links were resolved for the text as it was before editing
        if (current.text.includes("[[")) post("reload");
      }
      if (findOpen()) runFind(findInput.value);
    }
    void body.offsetWidth;
    body.classList.remove("swapping");
    if (mode === "edit" && !findOpen()) edInput.focus({ preventScroll: true });
    if (mode === "edit" && edReveal) revealCaret();
    edReveal = false;
  }
  // Another file took over the window: back to reading, without the fade.
  function leaveEditNow() {
    clearTimeout(swapTimer);
    clearTimeout(saveTimer);
    swapTimer = saveTimer = 0;
    mode = "read";
    edPath = null;
    document.body.dataset.view = "read";
    document.body.classList.remove("swapping");
    editBtn.classList.remove("active");
    editBtn.setAttribute("aria-pressed", "false");
    editBtn.title = "Edit (Ctrl+E)";
    post("mode", { edit: false });
  }
  function printDoc() {
    if (mode === "edit") { // print the rendered page, not the source
      flushSave();
      draw({ ...current, text: edInput.value }, null, true);
    }
    post("print");
  }

  // --- typing helpers. Edits go through execCommand so native undo keeps working.
  function edReplace(start, end, text, selA, selB) {
    edInput.focus({ preventScroll: true });
    edInput.setSelectionRange(start, end);
    const ok = text ? document.execCommand("insertText", false, text) : start === end || document.execCommand("delete");
    if (!ok) {
      edInput.setRangeText(text, start, end, "end");
      edInput.dispatchEvent(new Event("input"));
    }
    if (selA != null) edInput.setSelectionRange(selA, selB ?? selA);
    revealCaret();
  }
  const LIST_LINE = /^\s*(?:[-*+]|\d{1,9}[.)])\s/;
  function edIndent(outdent) {
    const v = edInput.value, s = edInput.selectionStart, e = edInput.selectionEnd;
    const unit = /^\t/m.test(v) ? "\t" : "    ";
    const ls = v.lastIndexOf("\n", s - 1) + 1;
    let le = v.indexOf("\n", e > s && v[e - 1] === "\n" ? e - 1 : e);
    if (le < 0) le = v.length;
    const block = v.slice(ls, le);
    if (s === e && !outdent && !LIST_LINE.test(block)) { edReplace(s, e, unit); return; }
    const lines = block.split("\n");
    const out = lines.map((l) => (outdent ? l.replace(/^(?:\t| {1,4})/, "") : l && unit + l));
    const text = out.join("\n");
    if (text === block) return;
    if (s === e) edReplace(ls, le, text, Math.max(ls, s + out[0].length - lines[0].length));
    else edReplace(ls, le, text, ls, ls + text.length);
  }
  // Enter continues lists, tasks and quotes; on an empty item it ends them.
  function edNewline() {
    const v = edInput.value, s = edInput.selectionStart;
    if (s !== edInput.selectionEnd) return false;
    const ls = v.lastIndexOf("\n", s - 1) + 1;
    let le = v.indexOf("\n", s);
    if (le < 0) le = v.length;
    const line = v.slice(ls, le);
    const m = /^([ \t]*(?:>[ \t]?)*[ \t]*)((?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[.\][ \t]+)?)?/.exec(line);
    if (!m[0] || s - ls < m[0].length) return false;
    if (line.length === m[0].length) {
      if (!m[2] && !m[1].includes(">")) return false;
      edReplace(ls, le, "");
      return true;
    }
    let next = m[1];
    if (m[2]) {
      const n = /^(\d+)([.)])/.exec(m[2]);
      next += (n ? Number(n[1]) + 1 + n[2] + m[2].slice(n[0].length) : m[2]).replace(/\[.\]/, "[ ]");
    }
    edReplace(s, s, "\n" + next);
    return true;
  }
  function edSurround(mark) {
    const v = edInput.value, s = edInput.selectionStart, e = edInput.selectionEnd, n = mark.length;
    if (s >= n && v.slice(s - n, s) === mark && v.slice(e, e + n) === mark) {
      edReplace(s - n, e + n, v.slice(s, e), s - n, e - n);
    } else {
      edReplace(s, e, mark + v.slice(s, e) + mark, s + n, e + n);
    }
  }
  function edLink() {
    const v = edInput.value, s = edInput.selectionStart, e = edInput.selectionEnd, sel = v.slice(s, e);
    if (/^https?:\/\/\S+$/.test(sel)) edReplace(s, e, `[](${sel})`, s + 1);
    else edReplace(s, e, `[${sel}](url)`, e + 3, e + 6);
  }
  const EDIT_KEYS = { b: () => edSurround("**"), i: () => edSurround("*"), k: edLink };

  edInput.addEventListener("input", () => {
    paint(edInput.value);
    revealCaret();
    clearTimeout(saveTimer);
    saveTimer = setTimeout(flushSave, AUTOSAVE_MS);
    if (findOpen()) {
      clearTimeout(findTimer);
      findTimer = setTimeout(() => runFind(findInput.value, true), 120);
    }
  });
  edInput.addEventListener("keydown", (e) => {
    if (e.isComposing) return;
    const mod = e.ctrlKey || e.metaKey, plain = !mod && !e.altKey;
    if (e.key === "Tab" && plain) { e.preventDefault(); edIndent(e.shiftKey); }
    else if (e.key === "Enter" && plain && !e.shiftKey) { if (edNewline()) e.preventDefault(); }
    else if ((e.key === "PageDown" || e.key === "PageUp") && plain) {
      // like macOS: paging scrolls, the caret stays (the textarea is as tall as the text)
      e.preventDefault();
      window.scrollBy({ top: (e.key === "PageDown" ? 1 : -1) * (innerHeight - 80), behavior: reducedMotion() ? "instant" : "smooth" });
    }
    else if (mod && !e.shiftKey && !e.altKey && EDIT_KEYS[e.key.toLowerCase()]) { e.preventDefault(); EDIT_KEYS[e.key.toLowerCase()](); }
    else if (/^(Arrow|Home|End)/.test(e.key)) requestAnimationFrame(revealCaret);
  });
  // the textarea never scrolls on its own; the page does
  edInput.addEventListener("scroll", () => { edInput.scrollTop = 0; edInput.scrollLeft = 0; });
  editor.addEventListener("mousedown", (e) => {
    if (e.target !== editor && e.target !== edWrap) return;
    e.preventDefault(); // margin around the text: focus, below it: caret to the end
    edInput.focus({ preventScroll: true });
    if (e.clientY > edBack.getBoundingClientRect().bottom) edInput.setSelectionRange(edInput.value.length, edInput.value.length);
  });

  // ------------------------------------------------------------ sidebar (folder windows)
  // Python sends the folder's notes as a tree (setFolder) and again whenever
  // something in the folder changes. The DOM is reconciled by path, so rows
  // keep their state and only new or removed ones animate.
  const sidebar = document.createElement("aside");
  sidebar.id = "sidebar";
  sidebar.innerHTML =
    `<header class="sb-head">` +
    `<button class="sb-folder" data-act="folder" title="Open another folder (Ctrl+Alt+O)">${ICON.folder}<span class="sb-folder-name"></span></button>` +
    `<button class="tb" data-act="titles" aria-pressed="false">${ICON.title}</button>` +
    `<button class="tb" data-act="newnote" title="New note (Ctrl+N)" aria-label="New note">${ICON.plus}</button>` +
    `</header>` +
    `<div class="sb-new sb-fold"><div class="sb-in"><input id="sb-new-input" class="sb-field" type="text" placeholder="Note name" aria-label="New note name" spellcheck="false" autocomplete="off"></div></div>` +
    `<nav class="sb-list" aria-label="Notes"></nav>`;
  document.body.appendChild(sidebar);
  const sbHead = sidebar.querySelector(".sb-head");
  const sbList = sidebar.querySelector(".sb-list");
  const sbNew = sidebar.querySelector(".sb-new");
  const sbNewInput = sidebar.querySelector("#sb-new-input");
  const sbTitlesBtn = sbHead.querySelector('[data-act="titles"]');

  let folder = null;        // { root, name, tree } while this window browses a folder
  let sbTitles = false;     // rows show the note title (first H1) instead of the file name
  const sbOpen = new Set(); // expanded directories
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const sidebarOpen = () => document.body.dataset.sidebar === "open";
  const byLabel = (a, b) => collator.compare(a.label, b.label);

  function entriesOf(dir) {
    const dirs = dir.dirs.map((d) => ({ key: d.path, dir: d, label: d.name }));
    const notes = dir.notes.map((n) => ({ key: n.path, note: n, label: (sbTitles && n.title) || n.name }));
    return [...dirs.sort(byLabel), ...notes.sort(byLabel)];
  }
  function makeItem(e, depth) {
    const item = document.createElement("div");
    item.className = e.dir ? "sb-item sb-fold is-dir" : "sb-item sb-fold";
    item.dataset.key = e.key;
    item.innerHTML = `<div class="sb-in"><button class="sb-row" type="button" style="--depth:${depth}">` +
      (e.dir ? `<span class="sb-chev">${ICON.chevron}</span>` : "") + `<span class="sb-label"></span></button>` +
      (e.dir ? `<div class="sb-kids sb-fold"><div class="sb-in"></div></div>` : "") + `</div>`;
    if (e.note) item.firstChild.firstChild.dataset.real = e.note.real;
    return item;
  }
  function syncDir(box, dir, depth, fresh) {
    const have = new Map();
    for (const el of box.children) if (!el.classList.contains("leaving")) have.set(el.dataset.key, el);
    let prev = null;
    for (const e of entriesOf(dir)) {
      let el = have.get(e.key);
      if (el && el.classList.contains("is-dir") !== !!e.dir) el = null;
      if (el) have.delete(e.key);
      else {
        el = makeItem(e, depth);
        if (fresh) { el.classList.add("enter"); fresh.push(el); }
      }
      const at = prev ? prev.nextSibling : box.firstChild;
      if (at !== el) box.insertBefore(el, at);
      prev = el;
      const row = el.firstChild.firstChild, label = row.lastChild;
      if (label.textContent !== e.label) label.textContent = e.label;
      row.title = e.note ? e.note.path.slice(folder.root.length + 1) : "";
      if (e.dir) {
        el.classList.toggle("open", sbOpen.has(e.key));
        row.setAttribute("aria-expanded", String(sbOpen.has(e.key)));
        syncDir(row.nextSibling.firstChild, e.dir, depth + 1, fresh);
      }
    }
    for (const el of have.values()) {
      if (!fresh) { el.remove(); continue; }
      el.classList.add("leaving");
      setTimeout(() => el.remove(), motionMs("--spring-smooth-dur", 510));
    }
  }
  function syncList(animate) {
    const fresh = animate ? [] : null;
    const any = folder.tree.dirs.length || folder.tree.notes.length;
    sbList.querySelector(":scope > .menu-empty")?.remove();
    syncDir(sbList, folder.tree, 0, fresh);
    if (!any) sbList.insertAdjacentHTML("afterbegin", '<div class="menu-empty">No notes yet</div>');
    if (fresh && fresh.length) {
      void sbList.offsetWidth;
      fresh.forEach((el) => el.classList.remove("enter"));
    }
  }
  function setFolder(f) {
    if (titlesAt) { // the list is fading out for a names/titles switch: swap once it is gone
      const wait = titlesAt + motionMs("--dur-fast", 160) * 0.7 - performance.now();
      titlesAt = 0;
      clearTimeout(titlesTimer);
      titlesTimer = setTimeout(() => { applyFolder(f, false); sbList.classList.remove("swap"); }, Math.max(0, wait));
      return;
    }
    applyFolder(f, true);
  }
  function applyFolder(f, animate) {
    const first = !folder || folder.root !== f.root;
    if (first) { sbOpen.clear(); sbList.textContent = ""; }
    folder = f;
    sbTitles = f.titles;
    sbTitlesBtn.classList.toggle("active", sbTitles);
    sbTitlesBtn.setAttribute("aria-pressed", String(sbTitles));
    sbTitlesBtn.title = sbTitlesBtn.ariaLabel = sbTitles ? "Show file names" : "Show note titles";
    sidebar.querySelector(".sb-folder-name").textContent = f.name;
    document.body.dataset.folder = "";
    if (first) openAncestors();
    syncList(animate && !first);
    markActiveNote(first);
    showSidebar(f.visible, !first);
    if (!current) clear();
  }

  // --- the note on screen: highlighted, its folders open, scrolled into view
  function openAncestors() {
    if (!folder || !current) return;
    const walk = (dir) => {
      if (dir.notes.some((n) => n.real === current.path)) return true;
      for (const d of dir.dirs) if (walk(d)) { sbOpen.add(d.path); return true; }
      return false;
    };
    walk(folder.tree);
  }
  function markActiveNote(reveal) {
    if (!folder) return;
    if (reveal && current) {
      const before = sbOpen.size;
      openAncestors();
      if (sbOpen.size !== before) syncList(true);
    }
    let active = null;
    for (const row of sbList.querySelectorAll(".sb-row[data-real]")) {
      const on = !!current && row.dataset.real === current.path;
      row.classList.toggle("active", on);
      if (on) { row.setAttribute("aria-current", "page"); active = row; } else row.removeAttribute("aria-current");
    }
    if (reveal && active) active.scrollIntoView({ block: "nearest" });
  }
  function toggleDir(item) {
    const key = item.dataset.key, open = !sbOpen.has(key);
    if (open) sbOpen.add(key); else sbOpen.delete(key);
    item.classList.toggle("open", open);
    item.firstChild.firstChild.setAttribute("aria-expanded", String(open));
  }
  sbList.addEventListener("click", (e) => {
    const row = e.target.closest(".sb-row");
    if (!row) return;
    const item = row.closest(".sb-item");
    if (item.classList.contains("is-dir")) toggleDir(item);
    else if (!row.classList.contains("active")) post("note", { path: item.dataset.key });
  });
  sbList.addEventListener("keydown", (e) => {
    const row = e.target.closest(".sb-row");
    if (!row || e.ctrlKey || e.metaKey || e.altKey) return;
    const item = row.closest(".sb-item"), isDir = item.classList.contains("is-dir");
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      // rows inside a closed (or closing) folder are skipped
      const rows = [...sbList.querySelectorAll(".sb-row")].filter((r) => {
        for (let p = r.closest(".sb-item").parentElement.closest(".sb-item"); p; p = p.parentElement.closest(".sb-item")) {
          if (!p.classList.contains("open")) return false;
        }
        return !r.closest(".leaving");
      });
      const next = rows[rows.indexOf(row) + (e.key === "ArrowDown" ? 1 : -1)];
      e.preventDefault();
      if (next) { next.focus({ preventScroll: true }); next.scrollIntoView({ block: "nearest" }); }
    } else if (e.key === "F2" && !isDir) { e.preventDefault(); startRename(item); }
    else if (e.key === "Delete" && !isDir) { e.preventDefault(); post("trash", { path: item.dataset.key }); }
    else if (e.key === "ArrowRight" && isDir && !item.classList.contains("open")) { e.preventDefault(); toggleDir(item); }
    else if (e.key === "ArrowLeft") {
      e.preventDefault();
      if (isDir && item.classList.contains("open")) toggleDir(item);
      else item.parentElement.closest(".sb-item")?.firstChild.firstChild.focus();
    }
  });

  // --- rename (in place) and trash, from the context menu or F2 / Delete on a row
  const ctx = document.createElement("div");
  ctx.id = "ctxmenu";
  ctx.className = "ui-menu surface";
  ctx.style.setProperty("--origin", "top left");
  ctx.tabIndex = -1;
  ctx.setAttribute("role", "menu");
  ctx.innerHTML =
    `<button class="menu-item" role="menuitem" data-cmd="rename">Rename<span class="menu-key">F2</span></button>` +
    `<button class="menu-item danger" role="menuitem" data-cmd="trash">Move to Trash<span class="menu-key">Del</span></button>`;
  document.body.appendChild(ctx);
  const ctxItems = [...ctx.children];
  let ctxFor = null, ctxHl = -1;
  const ctxOpen = () => ctx.hasAttribute("data-open");
  const setCtxHl = (i) => { ctxHl = i; ctxItems.forEach((el, k) => el.classList.toggle("hl", k === i)); };
  function openCtx(item, x, y) {
    if (ctxFor) ctxFor.classList.remove("ctx-target");
    ctxFor = item;
    item.classList.add("ctx-target");
    setCtxHl(-1);
    ctx.style.left = Math.max(8, Math.min(x, innerWidth - ctx.offsetWidth - 8)) + "px";
    ctx.style.top = Math.max(8, Math.min(y, innerHeight - ctx.offsetHeight - 8)) + "px";
    ctx.dataset.open = "";
    ctx.focus({ preventScroll: true });
  }
  function closeCtx(refocus) {
    if (!ctxOpen()) return false;
    delete ctx.dataset.open;
    ctxFor.classList.remove("ctx-target");
    if (refocus) ctxFor.firstChild.firstChild.focus({ preventScroll: true });
    return true;
  }
  function runCtx(i) {
    const el = ctxItems[i], item = ctxFor;
    if (!el) return;
    const flash = motionMs("--flash-duration", 70); // blink once, then act — like NSMenu
    el.classList.remove("hl");
    setTimeout(() => el.classList.add("hl"), flash);
    setTimeout(() => {
      closeCtx(false);
      if (!item.isConnected) return;
      if (el.dataset.cmd === "rename") startRename(item);
      else post("trash", { path: item.dataset.key });
    }, flash * 2);
  }
  sidebar.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const item = e.target.closest(".sb-row")?.closest(".sb-item");
    if (item && !item.classList.contains("is-dir")) openCtx(item, e.clientX, e.clientY);
  });
  ctx.addEventListener("contextmenu", (e) => e.preventDefault());
  ctx.addEventListener("mousemove", (e) => {
    const i = ctxItems.indexOf(e.target.closest(".menu-item"));
    if (i !== ctxHl) setCtxHl(i);
  });
  ctx.addEventListener("mouseleave", () => setCtxHl(-1));
  ctx.addEventListener("click", (e) => runCtx(ctxItems.indexOf(e.target.closest(".menu-item"))));
  ctx.addEventListener("keydown", (e) => {
    const n = ctxItems.length;
    const moves = { ArrowDown: ctxHl + 1, ArrowUp: ctxHl < 0 ? n - 1 : ctxHl - 1, Home: 0, End: n - 1 };
    if (e.key in moves) { e.preventDefault(); setCtxHl(Math.min(n - 1, Math.max(0, moves[e.key]))); }
    else if (e.key === "Enter" && ctxHl >= 0) { e.preventDefault(); runCtx(ctxHl); }
  });

  function startRename(item) {
    const row = item.firstChild.firstChild;
    if (row.hidden) return;
    const stem = item.dataset.key.replace(/^.*\//, "").replace(/\.[^.]+$/, "");
    const input = document.createElement("input");
    input.className = "sb-field sb-rename";
    input.type = "text";
    input.value = stem;
    input.spellcheck = false;
    input.autocomplete = "off";
    input.setAttribute("aria-label", "File name");
    input.style.setProperty("--depth", row.style.getPropertyValue("--depth"));
    let done = false;
    const finish = (commit) => {
      if (done) return;
      done = true;
      const name = input.value.trim();
      const focused = document.activeElement === input;
      input.remove();
      row.hidden = false;
      if (focused) row.focus({ preventScroll: true });
      if (commit && name && name !== stem) post("rename", { path: item.dataset.key, name });
    };
    input.addEventListener("keydown", (e) => {
      if (e.isComposing) return;
      if (e.key === "Enter") { e.preventDefault(); finish(true); }
      else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); finish(false); }
      else if (e.key.startsWith("Arrow") || e.key === "Delete" || e.key === "F2") e.stopPropagation(); // not the list's keys
    });
    input.addEventListener("blur", () => finish(true)); // clicking away keeps the name, like Finder
    row.hidden = true;
    row.after(input);
    input.focus({ preventScroll: true });
    input.select();
  }
  // Python renamed a file: keep its row (and the open note) instead of removing and re-adding it.
  function noteRenamed(r) {
    for (const item of sbList.querySelectorAll(".sb-item:not(.is-dir)")) {
      if (item.dataset.key !== r.old) continue;
      item.dataset.key = r.path;
      item.firstChild.firstChild.dataset.real = r.real;
    }
    if (current && current.path === r.oldReal) {
      current.path = r.real;
      current.name = r.name;
      document.title = r.name;
    }
    if (edPath === r.oldReal) edPath = r.real;
  }

  // --- file names <-> titles: the list crossfades, since every row may move
  let titlesTimer = 0, titlesAt = 0;
  function setTitles(on) {
    post("sidebar", { titles: on }); // Python rescans (titles are only read when shown) and answers with setFolder
    sbTitlesBtn.classList.toggle("active", on);
    sbList.classList.add("swap");
    titlesAt = performance.now();
    clearTimeout(titlesTimer);
    titlesTimer = setTimeout(() => { titlesAt = 0; sbList.classList.remove("swap"); }, 2000); // no answer: show the list again
  }

  // --- showing / hiding: the sidebar slides, the text column glides to its new
  // place (transform only; the width change itself is applied at once)
  function showSidebar(open, animate) {
    if (sidebarOpen() === !!open && document.body.dataset.sidebar) return;
    const col = mode === "edit" ? editor : content;
    const anchor = mode === "edit" ? captureEditAnchor() : captureAnchor();
    const before = col.getBoundingClientRect().left;
    sidebar.classList.toggle("no-anim", !animate);
    document.body.dataset.sidebar = open ? "open" : "closed";
    if (mode === "edit") {
      const el = anchor.line == null ? null : edBack.children[anchor.line];
      if (el) window.scrollBy({ top: el.getBoundingClientRect().top - anchor.top, behavior: "instant" });
    } else if (current) restoreAnchor(anchor);
    const dx = before - col.getBoundingClientRect().left;
    if (!animate || !dx || reducedMotion()) return;
    col.style.transition = "none";
    col.style.transform = `translateX(${dx}px)`;
    void col.offsetWidth;
    col.style.transition = "";
    col.style.transform = "";
  }

  // --- new note: a name field unfolds under the header; Enter creates the file
  function openNewNote() {
    if (!sidebarOpen()) { showSidebar(true, true); post("sidebar", { visible: true }); }
    sbNewInput.value = "";
    sbNew.classList.add("open");
    sbNewInput.focus({ preventScroll: true });
  }
  function closeNewNote() {
    if (!sbNew.classList.contains("open")) return false;
    sbNew.classList.remove("open");
    sbNewInput.blur();
    return true;
  }
  sbNewInput.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" || e.isComposing) return;
    e.preventDefault();
    // next to the note on screen, if that one lives in this folder
    const here = current && current.path.startsWith(folder.root + "/") ? current.path.replace(/\/[^/]*$/, "") : folder.root;
    const name = sbNewInput.value;
    closeNewNote();
    post("newnote", { name, dir: here });
  });
  sbNewInput.addEventListener("blur", () => closeNewNote());

  // --- toolbar + find buttons
  const actions = {
    outline: () => (outlineOpen() ? closeOutline() : openOutline()),
    find: () => (findOpen() ? closeFind() : openFind()),
    edit: () => setMode(mode === "edit" ? "read" : "edit"),
    sidebar: () => { if (folder) { showSidebar(!sidebarOpen(), true); post("sidebar", { visible: sidebarOpen() }); } },
    titles: () => setTitles(!sbTitles),
    newnote: () => openNewNote(),
    folder: () => post("folder"),
    prev: () => focusHit(hitIdx - 1),
    next: () => focusHit(hitIdx + 1),
    closefind: () => closeFind(),
  };
  for (const root of [toolbar, findBar, sbHead]) {
    root.addEventListener("click", (e) => {
      const b = e.target.closest("[data-act]");
      if (b) actions[b.dataset.act]();
    });
  }

  // click outside the outline closes it and is swallowed (macOS popover behaviour)
  let swallowClick = false;
  addEventListener("pointerdown", (e) => {
    if (ctxOpen() && !ctx.contains(e.target)) {
      closeCtx(false);
      if (e.button !== 0) return; // a right click goes on to open the next menu
    } else if (!outlineOpen() || outlinePop.contains(e.target) || e.target.closest('[data-act="outline"]')) return;
    else closeOutline();
    swallowClick = e.button === 0;
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
      copy.textContent = "Copied";
      copy.classList.add("done");
      setTimeout(() => { copy.textContent = "Copy"; copy.classList.remove("done"); }, 1400);
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
      if (closeCtx(true) || closeNewNote() || closeOutline() || closeFind()) e.preventDefault();
      return;
    }
    if (mod && e.shiftKey && k === "o") { e.preventDefault(); actions.outline(); return; }
    if (mod && e.shiftKey && k === "e") { e.preventDefault(); post("external"); return; }
    if (mod && e.altKey && !e.shiftKey && k === "s") { e.preventDefault(); actions.sidebar(); return; }
    if (mod && e.altKey && !e.shiftKey && k === "o") { e.preventDefault(); post("folder"); return; }
    if (mod && !e.shiftKey && !e.altKey) {
      const map = {
        f: openFind, e: actions.edit, o: () => post("open"), r: () => post("reload"),
        s: () => { if (mode === "edit") { flushSave(); toast("Saved"); } },
        n: () => { if (folder) openNewNote(); },
        p: printDoc, w: () => post("close"), q: () => post("close"),
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

  window.MdView = { render, setTheme, setMotion, scrollToFragment, toast, setMode, flush, saveFailed, setFolder, clear, noteRenamed };
})();
