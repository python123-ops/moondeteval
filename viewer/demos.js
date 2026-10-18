(function (root) {
  "use strict";
  const demos = Object.freeze({
    bbox: Object.freeze({ file: "bbox.json", metric: "ap50", label: "bbox 回归 / Bbox regression" }),
    mask: Object.freeze({ file: "mask.json", metric: "ap", label: "mask 前景 / Mask foreground" }),
    polygon: Object.freeze({ file: "polygon.json", metric: "ap", label: "多边形与 RLE / Polygon & RLE" }),
  });
  function get(id) {
    if (!Object.prototype.hasOwnProperty.call(demos, id)) throw new Error("未知演示 / Unknown demo");
    return demos[id];
  }
  const api = Object.freeze({ demos, get });
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.MoonDetEvalDemos = api;
})(globalThis);
