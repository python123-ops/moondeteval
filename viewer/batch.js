(function (root, factory) {
  "use strict";
  const api = factory(typeof module === "object" && module.exports ? require("./model.js") : root.MoonDetEvalReport);
  if (typeof module === "object" && module.exports) module.exports = api;
  root.MoonDetEvalBatch = api;
})(globalThis, function (reports) {
  "use strict";
  const TRUTH = ["images", "categories", "ground_truths"];
  const COUNTS = [...TRUTH, "detections", "evaluated_detections"];
  const CONFIG = ["iou_thresholds", "include_diagnostics", "include_image_summaries", "include_pr_curves", "ignore_policy"];
  const hash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
  const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
  function requireValue(condition, message) { if (!condition) throw new Error(message); }
  function countFields(value, keys) {
    return object(value) && keys.every(key => Number.isSafeInteger(value[key]) && value[key] >= 0);
  }
  function sameFields(left, right, keys) {
    return object(left) && object(right) && keys.every(key => JSON.stringify(left[key]) === JSON.stringify(right[key]));
  }
  function parseIndex(text) {
    let value;
    try { value = JSON.parse(text); } catch (_) { throw new Error("批量索引不是有效 JSON。"); }
    requireValue(object(value) && ["1", "2"].includes(value.format_version), "仅支持 batch_eval.py 的格式 1 或 2 索引。");
    const type = value.format_version === "1" ? "bbox" : value.iou_type;
    requireValue(["bbox", "segm"].includes(type) && (value.iou_type === undefined || value.iou_type === type), "批量索引的评测类型无效。");
    requireValue(typeof value.evaluator_version === "string" && value.evaluator_version.length > 0 && value.evaluator_version.length <= 64, "索引缺少评测器版本。");
    requireValue(hash(value.ground_truth_sha256), "索引的真值 SHA-256 无效。");
    requireValue(countFields(value.ground_truth_counts, TRUTH), "索引的真值计数无效。");
    const config = value.config;
    requireValue(object(config) && Array.isArray(config.iou_thresholds) && config.iou_thresholds.length > 0 && config.iou_thresholds.length <= 1000 &&
      config.iou_thresholds.every((n, i, all) => Number.isFinite(n) && n > 0 && n <= 1 && (i === 0 || n > all[i - 1])) &&
      CONFIG.slice(1, 4).every(key => typeof config[key] === "boolean") &&
      ["coco_bbox", "coco_segm", "respect_explicit"].includes(config.ignore_policy), "索引的评测配置无效。");
    requireValue(!(type === "segm" && config.ignore_policy === "coco_bbox") && !(type === "bbox" && config.ignore_policy === "coco_segm"), "索引的忽略策略与评测类型不同。");
    requireValue(Array.isArray(value.models) && value.models.length >= 2 && value.models.length <= 1000, "批量索引须含 2 至 1000 个模型。");
    const names = new Set();
    for (const model of value.models) {
      requireValue(object(model) && typeof model.name === "string" && /^[A-Za-z0-9_-]+$/.test(model.name), "模型名称无效。");
      requireValue(!names.has(model.name.toLowerCase()), "批量索引含重复模型名称。");
      names.add(model.name.toLowerCase());
      requireValue(model.report_file === `${model.name}.report.json`, "报告文件必须是当前目录下的模型名.report.json，不能使用路径或网址。");
      requireValue(hash(model.report_sha256) && hash(model.prediction_sha256), "模型的 SHA-256 无效。");
      requireValue(value.format_version === "1" ? model.iou_type === undefined || model.iou_type === "bbox" : model.iou_type === type, "模型的评测类型与索引不同。");
      requireValue(countFields(model.counts, COUNTS) && sameFields(model.counts, value.ground_truth_counts, TRUTH), "模型的真值计数与索引不同。");
      requireValue(object(model.summary) && reports.METRICS.every(key => Number.isFinite(model.summary[key]) && (model.summary[key] === -1 || (model.summary[key] >= 0 && model.summary[key] <= 1))), "模型摘要无效。");
    }
    const baseline = value.models.find(model => model.name === value.baseline);
    requireValue(baseline, "批量索引找不到基线模型。");
    for (const model of value.models) {
      requireValue(object(model.delta_from_baseline), "模型缺少相对基线差值。");
      for (const key of reports.METRICS) {
        const expected = model.summary[key] === -1 || baseline.summary[key] === -1 ? null : model.summary[key] - baseline.summary[key];
        const delta = model.delta_from_baseline[key];
        requireValue(expected === null ? delta === null : Number.isFinite(delta) && Math.abs(expected - delta) <= 1e-12, "模型差值与索引摘要不一致。");
      }
    }
    // Retain only fields used by the viewer; source paths and replay commands are not displayed or followed.
    return {format: value.format_version, iouType: type, version: value.evaluator_version, baseline: value.baseline,
      config, truthCounts: value.ground_truth_counts,
      models: value.models.map(model => ({name: model.name, file: model.report_file, sha256: model.report_sha256,
        counts: model.counts, summary: model.summary, delta: model.delta_from_baseline}))};
  }
  async function verifyReport(batch, entry, bytes, subtle) {
    requireValue(subtle, "浏览器不支持 SHA-256 校验，请通过 HTTPS 或本地 HTTP 打开查看器。");
    const digest = Array.from(new Uint8Array(await subtle.digest("SHA-256", bytes)), byte => byte.toString(16).padStart(2, "0")).join("");
    requireValue(digest === entry.sha256, "报告 SHA-256 与索引不同，文件可能被修改或选错。");
    const text = new TextDecoder("utf-8", {fatal: true}).decode(bytes);
    const model = reports.parseReport(text);
    requireValue(model.kind === "single", "批量索引只能引用单模型报告。");
    requireValue(reports.iouType(model) === batch.iouType, "报告的评测类型与索引不同。");
    requireValue(model.raw.evaluator_version === batch.version, "报告的评测器版本与索引不同。");
    requireValue(sameFields(model.raw.config, batch.config, CONFIG), "报告的配置与索引不同。");
    requireValue(sameFields(model.raw.counts, entry.counts, COUNTS), "报告计数与索引不同。");
    requireValue(sameFields(model.raw.summary, entry.summary, reports.METRICS), "报告摘要与索引不同。");
    return model;
  }
  return {parseIndex, verifyReport};
});
