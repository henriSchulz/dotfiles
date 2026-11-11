// Draws the active tab's address as a QR code. qrcode.mjs is
// qrcode-generator 2.0.4 by Kazuhiko Arase (MIT), unchanged.
import qrcode from "./qrcode.mjs";

// The library keeps only the low byte of each character; cameras read QR
// byte mode as UTF-8.
qrcode.stringToBytes = text => Array.from(new TextEncoder().encode(text));

const QUIET_ZONE = 4; // blank modules around the code, as the QR spec asks

// M survives glare on the screen; L still fits the longest addresses.
function encode(text) {
  for (const level of ["M", "L"]) {
    try {
      const qr = qrcode(0, level);
      qr.addData(text);
      qr.make();
      return qr;
    } catch {
      // too long for this level
    }
  }
  return null;
}

// One path, a rectangle per run of dark modules in a row.
function draw(qr) {
  const n = qr.getModuleCount();
  let d = "";
  for (let row = 0; row < n; row++) {
    for (let col = 0; col < n; col++) {
      if (!qr.isDark(row, col)) continue;
      let run = 1;
      while (col + run < n && qr.isDark(row, col + run)) run++;
      d += `M${col} ${row}h${run}v1h${-run}z`;
      col += run;
    }
  }
  const side = n + 2 * QUIET_ZONE;
  document.getElementById("code").setAttribute("viewBox", `${-QUIET_ZONE} ${-QUIET_ZONE} ${side} ${side}`);
  document.getElementById("modules").setAttribute("d", d);
}

function show(title, host) {
  document.getElementById("title").textContent = title;
  document.getElementById("host").textContent = host;
}

const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
const qr = tab?.url ? encode(tab.url) : null;
if (qr) {
  draw(qr);
  let host = tab.url;
  try { host = new URL(tab.url).host || tab.url; } catch {}
  show(tab.title || host, host);
} else {
  document.body.classList.add("empty");
  show(tab?.url ? "This address is too long for a QR code." : "This tab has no address to show.", "");
}
