.pragma library
// The calculator in the search field. calcTokenize/calcEvaluate are henri.menu-v3's
// (MenuModel.js), copied; evaluate() adds what a German keyboard types: "2,5" and × ÷ ·.
function calcTokenize(expr) {
  var tokens = []
  var i = 0
  while (i < expr.length) {
    var ch = expr[i]
    if (ch === " " || ch === "\t") { i++; continue }
    if ((ch >= "0" && ch <= "9") || ch === ".") {
      var num = ""
      while (i < expr.length && ((expr[i] >= "0" && expr[i] <= "9") || expr[i] === ".")) num += expr[i++]
      if (num === "." || num.split(".").length > 2) throw new Error("bad number")
      tokens.push({ type: "num", value: parseFloat(num) })
      continue
    }
    if ("+-*/%^()".indexOf(ch) >= 0) { tokens.push({ type: "op", value: ch }); i++; continue }
    throw new Error("bad char")
  }
  return tokens
}

function calcEvaluate(query) {
  var expr = String(query || "").trim()
  if (!/^[0-9\s+\-*/%^().]+$/.test(expr)) return null
  if (!/[0-9]/.test(expr) || !/[+\-*/%^]/.test(expr.replace(/^\s*-/, ""))) return null
  var tokens
  try { tokens = calcTokenize(expr) } catch (e) { return null }
  var pos = 0
  function peek() { return pos < tokens.length ? tokens[pos] : null }
  function next() { return tokens[pos++] }
  function parsePrimary() {
    var t = next()
    if (!t) throw new Error("end")
    if (t.type === "num") return t.value
    if (t.type === "op" && t.value === "(") {
      var v = parseExpr()
      var c = next()
      if (!c || c.type !== "op" || c.value !== ")") throw new Error("paren")
      return v
    }
    throw new Error("primary")
  }
  function parseUnary() {
    var t = peek()
    if (t && t.type === "op" && (t.value === "-" || t.value === "+")) { next(); var v = parseUnary(); return t.value === "-" ? -v : v }
    return parsePrimary()
  }
  function parseFactor() {
    var base = parseUnary()
    var t = peek()
    if (t && t.type === "op" && t.value === "^") { next(); return Math.pow(base, parseFactor()) }
    return base
  }
  function parseTerm() {
    var v = parseFactor()
    for (;;) {
      var t = peek()
      if (!t || t.type !== "op") break
      if (t.value === "*") { next(); v *= parseFactor() }
      else if (t.value === "/") { next(); v /= parseFactor() }
      else if (t.value === "%") { next(); v %= parseFactor() }
      else break
    }
    return v
  }
  function parseExpr() {
    var v = parseTerm()
    for (;;) {
      var t = peek()
      if (!t || t.type !== "op") break
      if (t.value === "+") { next(); v += parseTerm() }
      else if (t.value === "-") { next(); v -= parseTerm() }
      else break
    }
    return v
  }
  try {
    var result = parseExpr()
    if (pos !== tokens.length) return null
    if (typeof result !== "number" || !isFinite(result)) return null
    return Math.round(result * 1e10) / 1e10
  } catch (e) { return null }
}

// "2,5 × 4" -> 10, or null when the query is not arithmetic
function evaluate(query) {
  var q = String(query || "").replace(/×|·/g, "*").replace(/÷|:/g, "/")
  // a comma between digits is a decimal comma (no thousands grouping in a launcher)
  q = q.replace(/(\d),(\d)/g, "$1.$2")
  return calcEvaluate(q)
}

// German display of a result: decimal comma, no grouping
function format(value) {
  return String(value).replace(".", ",")
}
