// YouTube asks the browser which codecs it can play and picks AV1 when it is
// offered. On the M1 both AV1 and VP9 are decoded on the CPU (Chromium's
// hardware path shows green video here), and VP9 is the cheaper of the two.
// Answer "no" for AV1 on every path YouTube uses; it then falls back to VP9.
// H.264 stays available as the last resort for videos that have nothing else.
(() => {
  const isAv1 = type => /av01|av1/i.test(String(type || ""));

  const wrap = (obj, name, deny) => {
    const original = obj && obj[name];
    if (typeof original !== "function") return;
    obj[name] = function (...args) {
      const denied = deny(args);
      return denied !== undefined ? denied : original.apply(this, args);
    };
  };

  wrap(window.MediaSource, "isTypeSupported", ([type]) => (isAv1(type) ? false : undefined));
  wrap(window.ManagedMediaSource, "isTypeSupported", ([type]) => (isAv1(type) ? false : undefined));
  wrap(HTMLMediaElement.prototype, "canPlayType", ([type]) => (isAv1(type) ? "" : undefined));
  wrap(navigator.mediaCapabilities, "decodingInfo", ([config]) =>
    config && config.video && isAv1(config.video.contentType)
      ? Promise.resolve({ supported: false, smooth: false, powerEfficient: false, configuration: config })
      : undefined);
})();
