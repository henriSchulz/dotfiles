function isBoundaryChar(previous, current) {
  return /[\s\/_.:#?&=-]/.test(previous) || (/[a-z]/.test(previous) && /[A-Z]/.test(current));
}

function isBoundary(text, index) {
  if (index === 0) return true;
  return isBoundaryChar(text[index - 1], text[index]);
}

// Word-boundary flags per rawText. Menu labels, aliases and ids repeat on
// every keystroke, so they are worked out once instead of once per DP cell.
var boundaryCache = {};
var boundaryCacheSize = 0;

function boundariesFor(rawText) {
  var cached = boundaryCache[rawText];
  if (cached) return cached;
  var flags = new Uint8Array(rawText.length);
  for (var i = 0; i < rawText.length; i++) {
    var code = rawText.charCodeAt(i);
    if (i === 0) flags[i] = 1;
    else {
      var prev = rawText.charCodeAt(i - 1);
      // Same classes as isBoundaryChar, without a regex per character.
      if (prev === 32 || prev === 9 || prev === 10 || prev === 13 || prev === 12 || prev === 11 || prev === 160
          || prev === 47 || prev === 95 || prev === 46 || prev === 58 || prev === 35 || prev === 63
          || prev === 38 || prev === 61 || prev === 45) flags[i] = 1;
      else if (prev >= 97 && prev <= 122 && code >= 65 && code <= 90) flags[i] = 1;
      else if (prev > 127 && isBoundaryChar(rawText[i - 1], rawText[i])) flags[i] = 1;
    }
  }
  if (boundaryCacheSize > 4000) { boundaryCache = {}; boundaryCacheSize = 0; }
  boundaryCache[rawText] = flags;
  boundaryCacheSize++;
  return flags;
}

function scoreToken(rawQuery, rawText) {
  if (!rawText) return -1;
  rawText = String(rawText);
  var caseSensitive = rawQuery !== rawQuery.toLowerCase();
  var query = caseSensitive ? rawQuery : rawQuery.toLowerCase();
  var text = caseSensitive ? rawText : rawText.toLowerCase();
  var n = text.length;
  var m = query.length;
  if (m > n) return -1;

  // Nearly every row fails to contain the query as a subsequence, and those
  // rows would come out of the DP below as -Infinity anyway. Reject them in
  // one linear pass before allocating anything.
  var at = 0;
  for (var s = 0; s < m; s++) {
    at = text.indexOf(query[s], at);
    if (at < 0) return -1;
    at++;
  }

  var boundary = boundariesFor(rawText);
  var NEG = -Infinity;
  var previous = new Float64Array(n);
  var current = new Float64Array(n);
  var first = query[0];
  for (var j = 0; j < n; j++) {
    previous[j] = text[j] === first ? 16 + (boundary[j] ? 18 : 0) - Math.min(j, 24) : NEG;
  }

  for (var i = 1; i < m; i++) {
    var bestGap = NEG;
    var ch = query[i];
    for (var k = 0; k < n; k++) {
      if (k > 0 && previous[k - 1] !== NEG)
        bestGap = Math.max(bestGap - 1, previous[k - 1] - 2);

      if (text[k] !== ch) current[k] = NEG;
      else {
        var consecutive = k > 0 && previous[k - 1] !== NEG ? previous[k - 1] + 28 : NEG;
        var gapped = bestGap === NEG ? NEG : bestGap + 12;
        current[k] = Math.max(consecutive, gapped) + (boundary[k] ? 10 : 0);
      }
    }
    var swap = previous;
    previous = current;
    current = swap;
  }

  var best = NEG;
  for (var b = 0; b < n; b++) if (previous[b] > best) best = previous[b];
  if (best === NEG) return -1;
  if (text === query) best += 240;
  else if (text.indexOf(query) === 0) best += 120;
  else if (text.indexOf(query) >= 0) best += 55;
  return best;
}

function scoreBookmark(query, bookmark) {
  var tokens = query
    .trim()
    .split(/\s+/)
    .filter(function (token) {
      return token.length > 0;
    });
  if (!tokens.length) return 1;
  var fields = [
    { text: bookmark.title || "", weight: 5 },
    { text: bookmark.domain || "", weight: 3 },
    { text: (bookmark.tags || []).join(" "), weight: 2 },
    { text: bookmark.link || "", weight: 1 },
  ];
  var total = 0;
  for (var i = 0; i < tokens.length; i++) {
    var best = -1;
    for (var j = 0; j < fields.length; j++) {
      var score = scoreToken(tokens[i], fields[j].text);
      if (score >= 0) best = Math.max(best, score * fields[j].weight);
    }
    if (best < 0) return -1;
    total += best;
  }
  if (bookmark.important) total += 40;
  return total;
}

function search(query, bookmarks) {
  if (!query.trim()) return bookmarks.slice();
  return bookmarks
    .map(function (bookmark, index) {
      return { bookmark: bookmark, index: index, score: scoreBookmark(query, bookmark) };
    })
    .filter(function (item) {
      return item.score >= 0;
    })
    .sort(function (a, b) {
      return b.score - a.score || a.index - b.index;
    })
    .map(function (item) {
      return item.bookmark;
    });
}
