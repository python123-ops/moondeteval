(function () {
  "use strict";
  const copy = {
  "zh": {
    "skip": "跳到正文",
    "navDemo": "报告示例",
    "navFeatures": "支持范围",
    "navStart": "安装与运行",
    "eyebrow": "MoonBit 开源评测库 / native CLI",
    "heroTitle": "检测与实例分割评测",
    "heroText": "输入真值和模型预测，计算 COCO AP / AR，检查匹配错误，比较不同模型。支持检测框、RLE 掩码和 COCO 多边形。",
    "tryDemo": "查看示例",
    "getStarted": "安装与运行",
    "openLocal": "打开本地报告",
    "heroNote": "Mooncakes 0.2.0 已发布：bbox、mask、多边形与指标门禁。0.1.0 保持原版本。",
    "playEyebrow": "报告示例",
    "playTitle": "从输入到评测结果",
    "playDescription": "以下合成样例在网站构建时由 MoonBit CLI 运行。可以下载 JSON，也可以在查看器中检查详情。",
    "bboxTab": "bbox 模型比较",
    "maskTab": "相同框，不同掩码",
    "polygonTab": "多边形 / RLE",
    "openReport": "查看完整报告",
    "viewerLanguage": "查看器使用中文；本地文件只在浏览器中读取。",
    "generatedReport": "MoonBit CLI 输出",
    "baseline": "基线",
    "candidateLabel": "候选",
    "change": "差值",
    "curveTitle": "PR 曲线",
    "downloadJson": "下载 JSON",
    "syntheticNotice": "这三个样例使用合成数据，不是模型精度基准。",
    "provenance": "复现命令与文件哈希",
    "featuresEyebrow": "支持范围",
    "featuresTitle": "输入、指标与输出",
    "featuresText": "用于评测已经生成的预测结果，运行时不依赖训练框架。",
    "feature1Title": "评测指标",
    "feature1Text": "12 项 COCO AP / AR、逐类指标、crowd、面积区间与 maxDets。",
    "feature2Title": "错误诊断",
    "feature2Text": "逐图结果、101 点 PR 曲线，以及重复、错类、定位和背景误报的匹配记录。",
    "feature3Title": "接入方式",
    "feature3Text": "MoonBit 内存 API、native CLI、双模型比较、批量 bbox / segm 和总体／逐类 AP、AR 门禁。",
    "batchTitle": "查看一批模型的结果",
    "batchText": "运行 batch_eval.py 后，在查看器中选择输出文件夹。可切换模型查看详情，并核对报告与索引的 SHA-256。",
    "batchOpen": "打开批量查看器",
    "startEyebrow": "开始使用",
    "startTitle": "安装包，或运行源码",
    "startText": "安装 0.2.0 评测库，或克隆源码运行 CLI、批量工具和查看器示例。",
    "published": "Mooncakes 已发布",
    "installTitle": "安装 bbox / mask 评测库",
    "installText": "在 MoonBit 项目中评测检测框与实例掩码。API 以版本包页为准。",
    "copy": "复制",
    "copied": "已复制到剪贴板",
    "copyFailed": "无法访问剪贴板，请选择并复制命令。",
    "packageDocs": "0.2.0 API 文档",
    "sourceCandidate": "源码与完整示例",
    "sourceTitle": "运行 mask 评测示例",
    "sourceText": "需要 MoonBit 0.10.15 兼容工具链。下面的命令比较两份合成 mask 预测。",
    "sourceDocs": "源码使用说明",
    "scopeTitle": "当前不包含",
    "scopeText": "训练、图像解码、模型推理、关键点、旋转框，以及任意历史报告的合并。",
    "evidenceEyebrow": "验证记录",
    "evidenceTitle": "测试与参考对照",
    "viewCi": "查看 CI 运行记录",
    "evidence1Title": "四后端测试",
    "evidence1Text": "Wasm、Wasm GC、JavaScript、native：核心各 99 项，源码消费者各 112 项。",
    "evidence2Title": "参考实现对照",
    "evidence2Text": "178 组多边形像素检查、42 组多边形 AP 场景及 44 组 RLE mask AP 场景。",
    "evidence3Title": "真实分割输出回放",
    "evidence3Text": "64 图 COCO 子集，三组 YOLO11n-seg 预测与参考结果核对。复用已保存输出，不是重新推理。",
    "evidenceFoot": "参考实现：pycocotools 2.0.7 · 指标容差：1e-9 · 覆盖范围与命令见 README",
    "ecosystemEyebrow": "相关项目",
    "ecosystemTitle": "几何与跟踪库",
    "ecosystemText": "可通过消费者示例接入坐标变换和跟踪输出。各库保持独立依赖。",
    "geometryRole": "坐标与几何映射",
    "trackingRole": "多目标跟踪",
    "bridgeTitle": "三库消费者示例",
    "bridgeRole": "适配代码与集成测试",
    "footerText": "MoonBit 检测与实例分割评测库 · Apache-2.0",
    "attribution": "来源与许可证",
    "aiNotice": "AI 使用说明",
    "loading": "正在读取报告…",
    "loadError": "报告暂时不可用。请重试或打开完整报告。",
    "loaded": "报告已加载",
    "curveDetail": "IoU 0.50 · 同一类别 · 101 个召回采样点",
    "demos": {
      "bbox": [
        "bbox 回归样例",
        "候选预测包含重复检测、类别错误和定位偏差。两组预测使用同一份真值。",
        "AP50 从 1 降至 0.25，超过允许下降 0.10 的门禁。完整报告保留失败原因和匹配记录。"
      ],
      "mask": [
        "相同外接框，不同前景像素",
        "基线和候选预测的外接框相同，但基线前景与真值不相交。",
        "mask AP：基线为 0，候选为 1。"
      ],
      "polygon": [
        "等价的多边形与 RLE 预测",
        "一侧输入 COCO 多边形，另一侧输入等价的压缩 RLE。",
        "两侧 AP 都为 1，所有已定义指标的差值为 0。"
      ]
    }
  },
  "en": {
    "skip": "Skip to content",
    "navDemo": "Examples",
    "navFeatures": "Supported inputs",
    "navStart": "Install & run",
    "eyebrow": "Open-source MoonBit library / native CLI",
    "heroTitle": "Detection and instance segmentation evaluation",
    "heroText": "Evaluate ground truths and model predictions with COCO AP / AR. Inspect matches and compare models using boxes, RLE masks or COCO polygons.",
    "tryDemo": "View examples",
    "getStarted": "Install & run",
    "openLocal": "Open local reports",
    "heroNote": "Mooncakes 0.2.0 is published: bbox, masks, polygons and metric gates. The 0.1.0 release is unchanged.",
    "playEyebrow": "Report examples",
    "playTitle": "Inputs and evaluation results",
    "playDescription": "MoonBit CLI runs these synthetic examples during the site build. Download the JSON or inspect it in the viewer.",
    "bboxTab": "BBox comparison",
    "maskTab": "Same boxes, different masks",
    "polygonTab": "Polygon / RLE",
    "openReport": "View full report",
    "viewerLanguage": "The viewer uses Chinese. Local files are read in your browser.",
    "generatedReport": "MoonBit CLI output",
    "baseline": "Baseline",
    "candidateLabel": "Candidate",
    "change": "Delta",
    "curveTitle": "PR curves",
    "downloadJson": "Download JSON",
    "syntheticNotice": "These three examples use synthetic data, not model accuracy benchmarks.",
    "provenance": "Commands & file hashes",
    "featuresEyebrow": "Supported inputs",
    "featuresTitle": "Inputs, metrics and output",
    "featuresText": "Evaluates existing predictions. No training framework is required at runtime.",
    "feature1Title": "Metrics",
    "feature1Text": "12 COCO AP / AR metrics, per-class results, crowd, area ranges and maxDets.",
    "feature2Title": "Diagnostics",
    "feature2Text": "Per-image results, 101-point PR curves and matches for duplicate, class, localization and background errors.",
    "feature3Title": "Integration",
    "feature3Text": "MoonBit API, native CLI, paired comparison, batch bbox / segm and overall / per-class AP, AR gates.",
    "batchTitle": "Inspect a batch of model results",
    "batchText": "Run batch_eval.py, then select its output folder in the viewer. Switch model reports and check their SHA-256 against the index.",
    "batchOpen": "Open batch viewer",
    "startEyebrow": "Getting started",
    "startTitle": "Install the package or run the source",
    "startText": "Install the 0.2.0 library, or clone the source for CLI, batch and viewer examples.",
    "published": "Published on Mooncakes",
    "installTitle": "Install the bbox / mask library",
    "installText": "Evaluate boxes and instance masks in MoonBit. The versioned package page documents the API.",
    "copy": "Copy",
    "copied": "Copied to clipboard",
    "copyFailed": "Clipboard unavailable. Select and copy the command instead.",
    "packageDocs": "0.2.0 API documentation",
    "sourceCandidate": "Source and complete examples",
    "sourceTitle": "Run a mask example",
    "sourceText": "Requires a MoonBit 0.10.15-compatible toolchain. This command compares two synthetic mask predictions.",
    "sourceDocs": "Source usage guide",
    "scopeTitle": "Not included",
    "scopeText": "Training, image decoding, model inference, keypoints, rotated boxes or merging arbitrary historical reports.",
    "evidenceEyebrow": "Validation",
    "evidenceTitle": "Tests and reference comparisons",
    "viewCi": "View CI runs",
    "evidence1Title": "Four compilation targets",
    "evidence1Text": "Wasm, Wasm GC, JavaScript and native: 99 core tests and 112 source-consumer tests per target.",
    "evidence2Title": "Reference comparisons",
    "evidence2Text": "178 polygon pixel checks, 42 polygon AP cases and 44 RLE mask AP cases.",
    "evidence3Title": "Saved segmentation predictions",
    "evidence3Text": "Three YOLO11n-seg configurations on a 64-image COCO subset checked against the reference. Saved-output replay, not a new inference run.",
    "evidenceFoot": "Reference: pycocotools 2.0.7 · Metric tolerance: 1e-9 · Scope and commands in README",
    "ecosystemEyebrow": "Related projects",
    "ecosystemTitle": "Geometry and tracking libraries",
    "ecosystemText": "Consumer examples connect coordinate transforms and tracking outputs. Each library keeps independent dependencies.",
    "geometryRole": "Coordinates and geometric mapping",
    "trackingRole": "Multi-object tracking",
    "bridgeTitle": "Three-library consumer",
    "bridgeRole": "Adapters and integration tests",
    "footerText": "Detection and instance segmentation evaluation in MoonBit · Apache-2.0",
    "attribution": "Sources and licenses",
    "aiNotice": "AI usage disclosure",
    "loading": "Loading report…",
    "loadError": "Report unavailable. Retry or open the full report.",
    "loaded": "Report loaded",
    "curveDetail": "IoU 0.50 · Same category · 101 recall samples",
    "demos": {
      "bbox": [
        "BBox regression example",
        "Candidate predictions contain duplicates, class errors and localization errors. Both sets use the same ground truths.",
        "AP50 falls from 1 to 0.25, exceeding the allowed drop of 0.10. The full report retains the failed rule and matching records."
      ],
      "mask": [
        "Same enclosing boxes, different foreground",
        "Both prediction sets have the same enclosing boxes, but baseline foreground does not intersect the ground truth.",
        "Mask AP is 0 for the baseline and 1 for the candidate."
      ],
      "polygon": [
        "Equivalent polygon and RLE predictions",
        "One side uses COCO polygons; the other uses equivalent compressed RLE.",
        "Both sides have AP 1. Every defined metric has zero delta."
      ]
    }
  }
};
  const $ = id => document.getElementById(id);
  let locale = "zh", selected = "bbox", model = null, request = 0;
  try { locale = localStorage.getItem("moondeteval-language") === "en" ? "en" : "zh"; } catch (_) {}
  const queryLanguage = new URLSearchParams(location.search).get("lang");
  if (queryLanguage === "zh" || queryLanguage === "en") locale = queryLanguage;
  function applyLanguage() {
    document.documentElement.lang = locale === "zh" ? "zh-CN" : "en";
    document.title = locale === "zh" ? "MoonDetEval · 检测与实例分割评测" : "MoonDetEval · Detection and segmentation evaluation";
    for (const element of document.querySelectorAll("[data-i18n]")) element.textContent = copy[locale][element.dataset.i18n];
    $("language").textContent = locale === "zh" ? "EN" : "中文";
    $("language").setAttribute("aria-label", locale === "zh" ? "Switch to English" : "切换到中文");
    renderText();
  }
  function renderText() {
    const description = copy[locale].demos[selected];
    $("demo-title").textContent = description[0]; $("demo-description").textContent = description[1]; $("demo-insight").textContent = description[2];
    $("curve-detail").textContent = copy[locale].curveDetail;
    $("open-viewer").href = `viewer/?demo=${selected}&lang=${locale}`;
    $("download-report").href = `demos/${MoonDetEvalDemos.get(selected).file}`;
    $("demo-geometry").textContent = selected === "bbox" ? "BBOX" : "SEGM";
    $("demo-metric").textContent = selected === "bbox" ? "AP50" : "AP";
    $("copy-status").textContent = "";
    if (model) $("demo-status").textContent = copy[locale].loaded;
  }
  function svgElement(tag, attributes) {
    const element = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
    return element;
  }
  function drawCurve() {
    const svg = $("demo-curve"); svg.replaceChildren();
    for (const value of [0, .5, 1]) {
      svg.append(svgElement("line", {x1:25,x2:548,y1:135-value*120,y2:135-value*120,stroke:"#d7dfda","stroke-width":1}));
      const label = svgElement("text", {x:3,y:139-value*120,fill:"#53625c","font-size":10}); label.textContent = value; svg.append(label);
    }
    const category = model.raw.baseline.classes[0].category_id;
    for (const [side,color] of [["baseline","#6c7784"],["candidate","#176b51"]]) {
      const options = MoonDetEvalReport.curveOptions(model,side);
      const option = options.find(item => item.categoryId === category && item.threshold === .5) || options[0];
      if (!option) continue;
      const curve = MoonDetEvalReport.curveData(model,side,option.index);
      if (!curve.defined) continue;
      const points = curve.precision.map((y,index) => `${25+index/100*523},${135-y*120}`).join(" ");
      svg.append(svgElement("polyline", {points,fill:"none",stroke:color,"stroke-width":2.3,"stroke-linejoin":"round",...(side === "baseline" ? {"stroke-dasharray":"5 4"} : {})}));
    }
    for (const [x,text] of [[25,"0"],[279,locale === "zh" ? "召回率" : "Recall"],[540,"1"]]) {const label=svgElement("text",{x,y:155,fill:"#53625c","font-size":10});label.textContent=text;svg.append(label);}
  }
  async function loadDemo(id) {
    const sequence = ++request; selected = id; model = null;
    renderText();
    for (const button of document.querySelectorAll("[data-demo]")) {const active=button.dataset.demo === id;button.classList.toggle("active",active);button.setAttribute("aria-pressed",String(active));}
    $("demo-status").textContent = copy[locale].loading;
    for (const key of ["baseline","candidate","delta"]) $("score-"+key).textContent = "—";
    $("demo-curve").replaceChildren();
    try {
      const response = await fetch(`demos/${MoonDetEvalDemos.get(id).file}`);
      if (!response.ok) throw new Error("Report unavailable");
      const parsed = MoonDetEvalReport.parseReport(await response.text());
      if (sequence !== request) return;
      model = parsed;
      const row = MoonDetEvalReport.overallMetrics(model).find(item=>item.name === MoonDetEvalDemos.get(id).metric);
      $("score-baseline").textContent = row.baseline.toFixed(2);$("score-candidate").textContent = row.candidate.toFixed(2);
      $("score-delta").textContent = (row.delta>0?"+":"")+row.delta.toFixed(2);
      document.querySelector(".delta-cell").classList.toggle("positive",row.delta>=0);
      drawCurve();$("demo-status").textContent = copy[locale].loaded;
    } catch (_) {if (sequence === request) $("demo-status").textContent = copy[locale].loadError;}
  }
  $("language").addEventListener("click",()=>{locale=locale==="zh"?"en":"zh";try{localStorage.setItem("moondeteval-language",locale);}catch(_){}applyLanguage();if(model)drawCurve();});
  for (const button of document.querySelectorAll("[data-demo]")) button.addEventListener("click",()=>loadDemo(button.dataset.demo));
  for (const button of document.querySelectorAll("[data-copy]")) button.addEventListener("click",async()=>{try{await navigator.clipboard.writeText($(button.dataset.copy).textContent);$("copy-status").textContent=copy[locale].copied;}catch(_){$("copy-status").textContent=copy[locale].copyFailed;}});
  applyLanguage();loadDemo("bbox");
})();
