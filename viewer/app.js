(function () {
  "use strict";

  const api = globalThis.MoonDetEvalReport;
  const $ = (id) => document.getElementById(id);
  const state = { model: null, imagePage: 1, diagPage: 1 };
  const IMAGE_PAGE_SIZE = 50;
  const DIAG_PAGE_SIZE = 40;
  const MAX_FILE_BYTES = 128 * 1024 * 1024;
  let loadSequence = 0;
  let batchState = null;

  function clearBatch() {
    batchState = null;
    $("batch-view").hidden = true;
    $("batch-status").textContent = "";
  }

  function cell(row, value, header = false) {
    const element = document.createElement(header ? "th" : "td");
    element.textContent = String(value ?? "—");
    row.append(element);
  }

  function table(id, headings, rows) {
    const element = $(id);
    element.replaceChildren();
    const head = document.createElement("thead");
    const header = document.createElement("tr");
    for (const value of headings) cell(header, value, true);
    head.append(header);
    const body = document.createElement("tbody");
    for (const values of rows) {
      const row = document.createElement("tr");
      for (const value of values) cell(row, value);
      body.append(row);
    }
    element.append(head, body);
  }

  function options(id, entries) {
    const select = $(id);
    select.replaceChildren();
    for (const [value, label] of entries) {
      const option = document.createElement("option");
      option.value = String(value);
      option.textContent = String(label);
      select.append(option);
    }
  }

  function chip(label, value) {
    const element = document.createElement("span");
    element.className = "chip";
    element.textContent = `${label}：${value}`;
    return element;
  }

  function renderOverview(fileName) {
    const model = state.model;
    const reports = api.sides(model);
    $("report-meta").textContent = `${fileName} · ${model.kind === "comparison" ? "双模型比较" : "单模型评测"} · ${api.iouType(model) === "segm" ? "mask AP" : "bbox AP"} · schema ${model.raw.schema_version}`;
    const counts = $("report-counts");
    counts.replaceChildren();
    for (const { label, report } of reports) {
      for (const [key, value] of Object.entries(report.counts)) {
        counts.append(chip(reports.length === 1 ? key : `${label} ${key}`, value));
      }
    }
    const config = reports[0].report.config;
    $("report-config").textContent = `IoU 阈值：${config.iou_thresholds.map((x) => Number(x).toFixed(2)).join("、")}；忽略策略：${config.ignore_policy}。-1 表示无可评测真值，比较报告中对应指标为 —。`;
  }

  function renderMetrics() {
    const model = state.model;
    const compare = model.kind === "comparison";
    const headings = compare ? ["指标", "基线", "候选", "变化（候选 − 基线）"] : ["指标", "数值"];
    const values = (row) => compare
      ? [row.name, api.formatValue(row.baseline), api.formatValue(row.candidate), api.formatDelta(row.delta)]
      : [row.name, api.formatValue(row.value)];
    table("overall-table", headings, api.overallMetrics(model).map(values));
    const ids = api.classIds(model);
    options("class-select", ids.map((id) => [id, id]));
    $("class-empty").hidden = ids.length > 0;
    $("class-table").hidden = ids.length === 0;
    if (ids.length > 0) table("class-table", headings, api.classMetrics(model, ids[0]).map(values));
  }

  const gateStatus = value => ({passed: "通过", failed: "失败", skipped: "跳过"}[value]);
  function renderGates() {
    const gates = api.metricGates(state.model);
    $("gate-view").hidden = !gates;
    if (!gates) return;
    const reasons = {ok: "满足规则", below_minimum: "低于最低值", drop_exceeded: "下降量超限",
      undefined_candidate: "候选指标未定义", undefined_baseline: "基线指标未定义"};
    const number = value => value === null ? "—" : value.toFixed(4);
    $("gate-meta").textContent = `${gateStatus(gates.status)} · 未定义指标：${gates.undefined_policy === "skip" ? "跳过" : "失败"}${gates.reason === "all_skipped" ? " · 全部规则跳过，整体失败" : ""}`;
    table("gate-table", ["范围", "规则", "指标", "阈值", "实际值", "基线值", "下降量", "状态", "原因"],
      gates.checks.map(row => [row.category_id === null ? "总体" : `类别 ${row.category_id}`,
        row.kind === "minimum" ? "最低值" : "最大下降量", row.metric, number(row.threshold), number(row.candidate),
        number(row.baseline), number(row.drop), gateStatus(row.status), reasons[row.reason]]));
  }

  function renderClass() {
    const compare = state.model.kind === "comparison";
    const headings = compare ? ["指标", "基线", "候选", "变化（候选 − 基线）"] : ["指标", "数值"];
    const rows = api.classMetrics(state.model, $("class-select").value).map((row) => compare
      ? [row.name, api.formatValue(row.baseline), api.formatValue(row.candidate), api.formatDelta(row.delta)]
      : [row.name, api.formatValue(row.value)]);
    table("class-table", headings, rows);
  }

  function pager(prefix, page, pages, total) {
    $(`${prefix}-page`).textContent = `${page} / ${pages} 页 · ${total} 条`;
    $(`${prefix}-prev`).disabled = page <= 1;
    $(`${prefix}-next`).disabled = page >= pages;
  }

  function renderImages() {
    const compare = state.model.kind === "comparison";
    const rows = api.imageRows(state.model);
    const enabled = compare
      ? state.model.raw.baseline.config.include_image_summaries
      : state.model.raw.config.include_image_summaries;
    $("image-heading").textContent = compare ? "图片错误变化（回归优先）" : "逐图结果（IoU 0.50）";
    $("image-empty").textContent = enabled ? "没有逐图记录。" : "生成报告时未启用 --image-ranking。";
    $("image-empty").hidden = rows.length > 0;
    $("image-table").hidden = rows.length === 0;
    $("image-prev").parentElement.hidden = rows.length === 0;
    if (!rows.length) return;
    const pages = Math.ceil(rows.length / IMAGE_PAGE_SIZE);
    state.imagePage = Math.min(state.imagePage, pages);
    const pageRows = rows.slice((state.imagePage - 1) * IMAGE_PAGE_SIZE, state.imagePage * IMAGE_PAGE_SIZE);
    const headings = compare
      ? ["图片 ID", "基线错误", "候选错误", "错误变化"]
      : ["图片 ID", "TP", "FP", "FN", "忽略"];
    table("image-table", headings, pageRows.map((row) => compare
      ? [row.image_id, row.baseline_errors, row.candidate_errors, row.error_delta]
      : [row.image_id, row.tp, row.fp, row.fn_count, row.ignored]));
    pager("image", state.imagePage, pages, rows.length);
  }

  function renderCurveOptions() {
    const sides = api.sides(state.model);
    options("curve-side", sides.map((side) => [side.key, side.label]));
    populateCurves();
  }

  function populateCurves() {
    const curves = api.curveOptions(state.model, $("curve-side").value);
    options("curve-select", curves.map((item) => [item.index, `类别 ${item.categoryId} · IoU ${Number(item.threshold).toFixed(2)}`]));
    renderCurve();
  }

  function renderCurve() {
    const canvas = $("curve-canvas");
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const index = $("curve-select").value;
    if (index === "") {
      $("curve-empty").textContent = "生成报告时未启用 --pr-curves，或没有类别。";
      $("curve-empty").hidden = false;
      $("curve-meta").hidden = true;
      canvas.hidden = true;
      return;
    }
    try {
      const { curve, recall, precision, defined } = api.curveData(state.model, $("curve-side").value, Number(index));
      $("curve-empty").hidden = defined;
      $("curve-empty").textContent = defined ? "" : "此类别没有可评测真值；PR 曲线未定义。";
      $("curve-meta").hidden = !defined;
      canvas.hidden = !defined;
      if (!defined) return;
      $("curve-meta").textContent = `类别 ${curve.category_id} · IoU ${Number(curve.iou_threshold).toFixed(2)} · AP ${api.formatValue(curve.ap)} · 最大召回 ${api.formatValue(curve.max_recall)}`;
      const left = 48, top = 12, width = canvas.width - 65, height = canvas.height - 48;
      ctx.strokeStyle = "#79919a";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(left, top); ctx.lineTo(left, top + height); ctx.lineTo(left + width, top + height); ctx.stroke();
      ctx.fillStyle = "#526a74";
      ctx.font = "12px sans-serif";
      ctx.fillText("1.0", 12, top + 5); ctx.fillText("0", 30, top + height + 4);
      ctx.fillText("召回率 1.0", left + width - 66, top + height + 23);
      ctx.fillText("精确率", left + 3, top + 12);
      ctx.strokeStyle = "#118579";
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (let i = 0; i < recall.length; i += 1) {
        const x = left + recall[i] * width;
        const y = top + (1 - precision[i]) * height;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke();
    } catch (error) {
      $("curve-empty").textContent = error.message;
      $("curve-empty").hidden = false;
      $("curve-meta").hidden = true;
      canvas.hidden = true;
    }
  }

  function renderDiagnosticOptions() {
    const sides = api.sides(state.model);
    options("diag-side", sides.map((side) => [side.key, side.label]));
    populateThresholds();
  }

  function populateThresholds() {
    const report = api.selectedSide(state.model, $("diag-side").value);
    options("diag-threshold", [["", "全部"], ...report.config.iou_thresholds.map((x) => [x, Number(x).toFixed(2)])]);
    state.diagPage = 1;
    renderDiagnostics();
  }

  function renderDiagnostics() {
    const report = api.selectedSide(state.model, $("diag-side").value);
    const filters = {
      status: $("diag-status").value,
      threshold: $("diag-threshold").value,
      imageId: $("diag-image").value.trim(),
      categoryId: $("diag-category").value.trim(),
    };
    const result = api.filterDiagnostics(state.model, $("diag-side").value, filters, state.diagPage, DIAG_PAGE_SIZE);
    state.diagPage = Math.min(state.diagPage, result.pages);
    if (state.diagPage !== result.page) return renderDiagnostics();
    $("diag-empty").textContent = report.config.include_diagnostics
      ? "当前筛选没有匹配的诊断记录。"
      : "生成报告时未启用 --diagnostics。";
    $("diag-empty").hidden = result.total > 0;
    $("diag-table").hidden = result.total === 0;
    $("diag-prev").parentElement.hidden = result.total === 0;
    if (!result.total) return;
    table("diag-table", ["IoU 阈值", "图片 ID", "类别 ID", "检测 ID", "真值 ID", "匹配 IoU", "状态", "原因"],
      result.rows.map((row) => [Number(row.iou_threshold).toFixed(2), row.image_id, row.category_id,
        row.detection_id, row.ground_truth_id, api.formatValue(row.iou), row.status, row.reason]));
    pager("diag", state.diagPage, result.pages, result.total);
  }

  async function loadReport(name, size, read, verified = false) {
    const sequence = ++loadSequence;
    state.model = null;
    $("report-view").hidden = true;
    $("load-error").hidden = true;
    if (size > MAX_FILE_BYTES) {
      $("load-status").textContent = "加载失败";
      $("load-error").textContent = "文件超过 128 MiB 查看上限。";
      $("load-error").hidden = false;
      return false;
    }
    $("load-status").textContent = `正在读取 ${name}…`;
    await new Promise((resolve) => requestAnimationFrame(resolve));
    const start = performance.now();
    try {
      const text = await read();
      if (sequence !== loadSequence) return;
      const byteSize = verified ? size : new Blob([text]).size;
      if (byteSize > MAX_FILE_BYTES) throw new Error("文件超过 128 MiB 查看上限。");
      state.model = verified ? text : api.parseReport(text);
      state.imagePage = 1;
      state.diagPage = 1;
      $("diag-status").value = "";
      $("diag-image").value = "";
      $("diag-category").value = "";
      renderOverview(name);
      renderMetrics();
      renderGates();
      renderImages();
      renderCurveOptions();
      renderDiagnosticOptions();
      $("report-view").hidden = false;
      $("load-status").textContent = `已加载 ${name}（${(byteSize / 1048576).toFixed(1)} MiB，读取校验及首屏渲染 ${(performance.now() - start).toFixed(0)} ms）`;
      return true;
    } catch (error) {
      if (sequence !== loadSequence) return;
      state.model = null;
      $("report-view").hidden = true;
      $("load-status").textContent = "加载失败";
      $("load-error").textContent = ["NotFoundError", "NotReadableError"].includes(error.name)
        ? "浏览器无法读取所选文件。请确认文件仍在原处且可访问；Windows 下可尝试缩短文件夹路径或模型名后重新选择。"
        : error.message;
      $("load-error").hidden = false;
      return false;
    }
  }

  async function loadDemo(id) {
    clearBatch();
    await loadReport(`演示：${id}`, 0, async () => {
      const demo = globalThis.MoonDetEvalDemos.get(id);
      if (location.protocol === "file:") throw new Error("在线示例需要通过 HTTP 打开产品网站；本地 JSON 文件仍可直接选择。");
      const response = await fetch(new URL(`../demos/${demo.file}`, location.href));
      if (!response.ok) throw new Error("示例暂时不可用，请重试或选择本地报告。");
      return response.text();
    });
  }

  $("report-file").addEventListener("change", (event) => {
    const file = event.target.files[0];
    if (file) { clearBatch(); loadReport(file.name, file.size, () => file.text()); }
  });
  async function selectBatchModel() {
    const current = batchState;
    if (!current) return;
    const entry = current.index.models.find(item => item.name === $("batch-model").value);
    for (const [index, row] of Array.from($("batch-table").querySelectorAll("tbody tr")).entries()) {
      row.setAttribute("aria-current", String(current.index.models[index].name === entry.name));
    }
    const file = current.files.get(entry.file);
    $("batch-status").textContent = `正在校验 ${entry.file}…`;
    const success = await loadReport(entry.name, file.size, async () => {
      const bytes = await file.arrayBuffer();
      return globalThis.MoonDetEvalBatch.verifyReport(current.index, entry, bytes, globalThis.crypto?.subtle);
    }, true);
    if (success === undefined) return;
    if (batchState === current && $("batch-model").value === entry.name) $("batch-status").textContent = success
      ? `${entry.file}：SHA-256、评测配置、计数和摘要与索引一致。`
      : "报告校验失败。索引摘要保留在上表，详细报告未显示。";
  }
  $("batch-model").addEventListener("change", selectBatchModel);
  $("batch-folder").addEventListener("change", async event => {
    const selected = Array.from(event.target.files);
    if (!selected.length) return;
    clearBatch();
    const sequence = ++loadSequence;
    state.model = null;
    $("report-view").hidden = true;
    $("load-error").hidden = true;
    $("load-status").textContent = "正在读取批量索引…";
    try {
      const indexes = selected.filter(file => file.name === "index.json");
      if (indexes.length !== 1) throw new Error("请选择只含一份 index.json 的批量结果文件夹。");
      const indexFile = indexes[0];
      if (!indexFile.webkitRelativePath) throw new Error("当前浏览器未提供文件夹路径，请使用支持目录选择的浏览器，或逐个导入 JSON 报告。");
      if (indexFile.size > 4 * 1048576) throw new Error("批量索引超过 4 MiB 上限。");
      const index = globalThis.MoonDetEvalBatch.parseIndex(await indexFile.text());
      if (sequence !== loadSequence) return;
      const prefix = indexFile.webkitRelativePath.slice(0, -indexFile.name.length);
      const paths = new Map();
      for (const file of selected) {
        const relative = file.webkitRelativePath;
        if (paths.has(relative)) throw new Error("选择的文件夹中存在重复文件路径。");
        paths.set(relative, file);
      }
      const files = new Map();
      for (const entry of index.models) {
        const file = paths.get(prefix + entry.file);
        if (!file) throw new Error(`缺少报告：${entry.file}`);
        if (file.size > MAX_FILE_BYTES) throw new Error(`${entry.file} 超过 128 MiB 查看上限。`);
        files.set(entry.file, file);
      }
      batchState = {index, files};
      $("batch-meta").textContent = `格式 ${index.format} · ${index.iouType} · evaluator ${index.version} · 基线 ${index.baseline} · ${index.truthCounts.images} 张图片。下表为索引原有摘要；选中模型后校验对应报告。`;
      table("batch-table", ["模型", "AP", "AP50", "AP75", "Δ AP", "Δ AP50", "指标门禁"], index.models.map(entry => [entry.name,
        ...["ap", "ap50", "ap75"].map(key => api.formatValue(entry.summary[key])), ...["ap", "ap50"].map(key => entry.delta[key] === null ? "—" : entry.delta[key].toFixed(4)),
        entry.name === index.baseline ? "基线参照" : entry.gates ? gateStatus(entry.gates.status) : "未启用"]));
      options("batch-model", index.models.map(entry => [entry.name, entry.name]));
      $("batch-model").value = index.baseline;
      $("batch-view").hidden = false;
    } catch (error) {
      if (sequence !== loadSequence) return;
      clearBatch();
      $("load-status").textContent = "加载失败";
      $("load-error").textContent = error.message;
      $("load-error").hidden = false;
      return;
    }
    await selectBatchModel();
  });
  for (const button of document.querySelectorAll("[data-demo]")) button.addEventListener("click", () => loadDemo(button.dataset.demo));
  const initialDemo = new URLSearchParams(location.search).get("demo");
  if (initialDemo !== null) loadDemo(initialDemo);
  $("class-select").addEventListener("change", renderClass);
  $("image-prev").addEventListener("click", () => { state.imagePage -= 1; renderImages(); });
  $("image-next").addEventListener("click", () => { state.imagePage += 1; renderImages(); });
  $("curve-side").addEventListener("change", populateCurves);
  $("curve-select").addEventListener("change", renderCurve);
  $("diag-side").addEventListener("change", populateThresholds);
  for (const id of ["diag-status", "diag-threshold"]) {
    $(id).addEventListener("change", () => { state.diagPage = 1; renderDiagnostics(); });
  }
  for (const id of ["diag-image", "diag-category"]) {
    $(id).addEventListener("input", () => { state.diagPage = 1; renderDiagnostics(); });
  }
  $("diag-prev").addEventListener("click", () => { state.diagPage -= 1; renderDiagnostics(); });
  $("diag-next").addEventListener("click", () => { state.diagPage += 1; renderDiagnostics(); });
})();
