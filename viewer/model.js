(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.MoonDetEvalReport = api;
})(globalThis, function () {
  "use strict";

  const METRICS = [
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large",
    "ar1", "ar10", "ar100", "ar_small", "ar_medium", "ar_large",
  ];

  function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function arrayField(value, name) {
    if (!Array.isArray(value)) throw new Error(`${name} 必须是数组`);
    return value;
  }

  function safeIds(rows, fields, name) {
    for (const row of rows) {
      if (!object(row)) continue;
      for (const field of fields) {
        const id = row[field];
        if (typeof id === "number" && Number.isInteger(id) && !Number.isSafeInteger(id)) {
          throw new Error(`${name}.${field} 超出浏览器可精确表示的整数范围；请用无损 JSON 工具查看原始 ID`);
        }
      }
    }
  }

  function evaluation(value, name) {
    if (!object(value) || value.schema_version !== "0.1.0") {
      throw new Error(`${name} 不是 MoonDetEval schema 0.1.0 报告`);
    }
    if (!object(value.summary) || !object(value.config) || !object(value.counts)) {
      throw new Error(`${name} 缺少 summary、config 或 counts`);
    }
    if (value.iou_type !== undefined && value.iou_type !== "bbox" && value.iou_type !== "segm") {
      throw new Error(`${name}.iou_type 必须是 bbox 或 segm`);
    }
    for (const metric of METRICS) {
      if (!Number.isFinite(value.summary[metric])) {
        throw new Error(`${name}.summary.${metric} 缺失或不是有限数字`);
      }
    }
    arrayField(value.classes, `${name}.classes`);
    for (const key of ["diagnostics", "image_summaries", "pr_curves", "recall_thresholds", "quality_warnings"]) {
      arrayField(value[key], `${name}.${key}`);
    }
    safeIds(value.classes, ["category_id"], `${name}.classes`);
    safeIds(value.image_summaries, ["image_id"], `${name}.image_summaries`);
    safeIds(value.pr_curves, ["category_id"], `${name}.pr_curves`);
    safeIds(value.diagnostics, ["image_id", "category_id", "detection_id", "ground_truth_id"], `${name}.diagnostics`);
    return value;
  }

  function parseReport(text) {
    let value;
    try {
      value = JSON.parse(text);
    } catch (error) {
      throw new Error(`JSON 解析失败：${error.message}`);
    }
    if (!object(value) || value.schema_version !== "0.1.0") {
      throw new Error("只支持 MoonDetEval schema_version=0.1.0 的 JSON 报告");
    }
    if (object(value.baseline) || object(value.candidate)) {
      evaluation(value.baseline, "baseline");
      evaluation(value.candidate, "candidate");
      if ((value.baseline.iou_type || "bbox") !== (value.candidate.iou_type || "bbox")) {
        throw new Error("双模型报告的评测类型不同，不能比较 bbox 与 mask AP");
      }
      arrayField(value.metrics, "metrics");
      arrayField(value.classes, "classes");
      arrayField(value.image_changes, "image_changes");
      safeIds(value.classes, ["category_id"], "classes");
      safeIds(value.image_changes, ["image_id"], "image_changes");
      if (METRICS.some((name) => !value.metrics.some((row) => object(row) && row.name === name))) {
        throw new Error("双模型报告缺少 12 项总体指标");
      }
      return { kind: "comparison", raw: value };
    }
    evaluation(value, "report");
    return { kind: "single", raw: value };
  }

  function sides(model) {
    return model.kind === "comparison"
      ? [{ key: "baseline", label: "基线", report: model.raw.baseline },
        { key: "candidate", label: "候选", report: model.raw.candidate }]
      : [{ key: "single", label: "报告", report: model.raw }];
  }

  function selectedSide(model, key) {
    const found = sides(model).find((side) => side.key === key);
    if (!found) throw new Error("未知模型侧");
    return found.report;
  }

  function overallMetrics(model) {
    if (model.kind === "single") {
      return METRICS.map((name) => ({ name, value: model.raw.summary[name] }));
    }
    return METRICS.map((name) => {
      const row = model.raw.metrics.find((item) => item.name === name);
      return { name, baseline: row.baseline, candidate: row.candidate, delta: row.delta };
    });
  }

  function classIds(model) {
    return model.raw.classes.map((row) => row.category_id);
  }

  function classMetrics(model, categoryId) {
    const row = model.raw.classes.find((item) => String(item.category_id) === String(categoryId));
    if (!row) return [];
    if (model.kind === "comparison") {
      return METRICS.map((name) => {
        const metric = row.metrics.find((item) => item.name === name);
        return metric || { name, baseline: null, candidate: null, delta: null };
      });
    }
    return METRICS.map((name) => ({ name, value: row.metrics[name] }));
  }

  function imageRows(model) {
    return model.kind === "comparison"
      ? model.raw.image_changes
      : model.raw.image_summaries;
  }

  function curveOptions(model, sideKey) {
    const report = selectedSide(model, sideKey);
    return report.pr_curves.map((curve, index) => ({
      index, categoryId: curve.category_id, threshold: curve.iou_threshold,
    }));
  }

  function curveData(model, sideKey, index) {
    const report = selectedSide(model, sideKey);
    const curve = report.pr_curves[index];
    if (!object(curve)) throw new Error("曲线不存在");
    const recall = report.recall_thresholds;
    const precision = arrayField(curve.precision, "precision");
    if (recall.length !== 101 || precision.length !== 101) {
      throw new Error("PR 曲线必须包含 101 个召回与精确率点");
    }
    if (!recall.every((v) => Number.isFinite(v) && v >= 0 && v <= 1) ||
        !precision.every((v) => Number.isFinite(v) && (v === -1 || (v >= 0 && v <= 1)))) {
      throw new Error("PR 曲线包含无效数值");
    }
    if (!Number.isFinite(curve.ap) || !Number.isFinite(curve.max_recall)) {
      throw new Error("PR 曲线包含无效 AP 或最大召回");
    }
    return { curve, recall, precision, defined: curve.ap !== -1 };
  }

  function filterDiagnostics(model, sideKey, filters, page, pageSize) {
    const source = selectedSide(model, sideKey).diagnostics;
    const start = (page - 1) * pageSize;
    let total = 0;
    const rows = [];
    for (const row of source) {
      if (!object(row)) continue;
      if (filters.status && row.status !== filters.status) continue;
      if (filters.threshold !== "" && Number(row.iou_threshold) !== Number(filters.threshold)) continue;
      if (filters.imageId !== "" && String(row.image_id) !== filters.imageId) continue;
      if (filters.categoryId !== "" && String(row.category_id) !== filters.categoryId) continue;
      if (total >= start && rows.length < pageSize) rows.push(row);
      total += 1;
    }
    return { rows, total, page, pageSize, pages: Math.max(1, Math.ceil(total / pageSize)) };
  }

  function formatValue(value) {
    if (value === null || value === undefined) return "—";
    if (value === -1) return "未定义";
    if (typeof value === "number" && Number.isFinite(value)) return value.toFixed(4);
    return "无效";
  }

  return {
    iouType: (model) => sides(model)[0].report.iou_type || "bbox",
    METRICS, parseReport, sides, selectedSide, overallMetrics, classIds,
    classMetrics, imageRows, curveOptions, curveData, filterDiagnostics, formatValue,
  };
});
