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
    const gates = value.metric_gates;
    if (gates !== undefined) {
      requireValue(object(gates) && gates.format_version === "1" && ["passed", "failed"].includes(gates.status) &&
        ["fail", "skip"].includes(gates.undefined_policy) && Array.isArray(gates.rules), "批量指标门禁汇总无效。");
      requireValue(baseline.metric_gates === undefined, "基线仅作参照，不能含批量指标门禁。");
      const checked = value.models.filter(model => model !== baseline);
      for (const model of checked) {
        reports.gateReport(model.metric_gates);
        const rules = model.metric_gates.checks.map(row => ({kind: row.kind, metric: row.metric, category_id: row.category_id, threshold: row.threshold}));
        const signature = rows => JSON.stringify(rows.map(row => object(row) ? [row.kind, row.metric, row.category_id, row.threshold] : null));
        requireValue(model.metric_gates.undefined_policy === gates.undefined_policy &&
          signature(rules) === signature(gates.rules), "模型指标门禁策略与索引不同。");
      }
      const failed = checked.filter(model => model.metric_gates.status === "failed").map(model => model.name);
      requireValue(gates.checked_models === checked.length && JSON.stringify(gates.failed_models) === JSON.stringify(failed) &&
        gates.status === (failed.length ? "failed" : "passed"), "批量指标门禁状态与模型不同。");
    } else requireValue(value.models.every(model => model.metric_gates === undefined), "模型指标门禁缺少批量汇总。");
    if (value.gate_policy !== undefined) {
      requireValue(value.format_version === "2" && gates && object(value.gate_policy) &&
        value.gate_policy.file === "gate-policy.json" && hash(value.gate_policy.sha256), "批量策略快照元数据无效。");
    }
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
      config, gates, policy: value.gate_policy, truthCounts: value.ground_truth_counts,
      models: value.models.map(model => ({name: model.name, file: model.report_file, sha256: model.report_sha256,
        counts: model.counts, summary: model.summary, gates: model.metric_gates, delta: model.delta_from_baseline}))};
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
    requireValue(reports.gateFingerprint(model.raw.metric_gates) === reports.gateFingerprint(entry.gates), "报告指标门禁与索引不同。");
    for (const row of entry.gates?.checks || []) {
      if (row.category_id === null && (row.kind === "max_drop" || row.baseline !== null)) {
        const baseline = batch.models.find(item => item.name === batch.baseline).summary[row.metric];
        requireValue(row.baseline === (baseline === -1 ? null : baseline), "门禁基线指标与索引不同。");
      }
    }
    return model;
  }
  async function verifyPolicy(batch, bytes, subtle) {
    requireValue(batch.policy && bytes.byteLength <= 262144, "策略快照缺失或超过 256 KiB。");
    requireValue(subtle, "浏览器不支持 SHA-256 校验。");
    const digest = Array.from(new Uint8Array(await subtle.digest("SHA-256", bytes)), byte => byte.toString(16).padStart(2, "0")).join("");
    requireValue(digest === batch.policy.sha256, "策略快照 SHA-256 与索引不同。");
    let value;
    try { value = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes)); } catch (_) { throw new Error("策略快照不是有效 UTF-8 JSON。"); }
    requireValue(object(value) && value.format_version === "1" && Object.keys(value).every(key => ["format_version", "undefined_policy", "rules"].includes(key)) &&
      (value.undefined_policy === undefined ? "fail" : value.undefined_policy) === batch.gates.undefined_policy && Array.isArray(value.rules) &&
      value.rules.length === batch.gates.rules.length, "策略快照与指标门禁策略不同。");
    for (let i = 0; i < value.rules.length; i++) {
      const rule = value.rules[i], expected = batch.gates.rules[i];
      requireValue(object(rule) && Object.keys(rule).every(key => ["kind", "metric", "threshold", "category_id"].includes(key)) &&
        ["kind", "metric", "threshold"].every(key => rule[key] === expected[key]) &&
        (rule.category_id === undefined ? null : rule.category_id) === expected.category_id, "策略快照规则与指标门禁不同。");
    }
    return value;
  }
  return {parseIndex, verifyReport, verifyPolicy};
});
