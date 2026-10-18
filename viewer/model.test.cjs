const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const { test } = require('node:test');
const path = require('node:path');
const api = require('./model.js');

const root = path.resolve(__dirname, '..');
const args = ['run', 'cli', '--target', 'native', '--'];
test('native regression gates bind to report values without browser threshold decisions',()=>{
  const result=spawnSync('moon',[...args,'examples/compare-ground-truth.json','examples/compare-baseline.json',
    '--compare','examples/compare-candidate.json','--max-metric-drop','ap50=0.1'],{cwd:root,encoding:'utf8'});
  assert.equal(result.status,3);
  const model=api.parseReport(result.stdout);
  assert.equal(api.metricGates(model).checks[0].drop,.75);
  for(const change of [v=>v.metric_gates.checks[0].candidate=.5,v=>v.metric_gates.checks[0].drop=.5,
    v=>v.metric_gates.checks[0].category_id=999,v=>v.metric_gates.status='passed',
    v=>v.metric_gates.checks.push(v.metric_gates.checks[0])]){
    const value=JSON.parse(result.stdout);change(value);assert.throws(()=>api.parseReport(JSON.stringify(value)),/门禁/);
  }
});
function report(extra = []) {
  return execFileSync('moon', [...args, 'examples/compare-ground-truth.json',
    'examples/compare-baseline.json', ...extra], { cwd: root, encoding: 'utf8' });
}

test('real single report preserves undefined metrics and optional-data absence', () => {
  const model = api.parseReport(report());
  assert.equal(model.kind, 'single');
  assert.equal(api.overallMetrics(model).length, 12);
  assert.equal(api.overallMetrics(model).find(x => x.name === 'ap50').value, 1);
  assert.equal(api.formatValue(-1), '未定义');
  assert.equal(api.imageRows(model).length, 0);
  assert.equal(api.curveOptions(model, 'single').length, 0);
  assert.equal(api.filterDiagnostics(model, 'single', { status: '', threshold: '', imageId: '', categoryId: '' }, 1, 40).total, 0);
});

test('real comparison keeps CLI deltas, image regression order, and diagnostic filters', () => {
  const model = api.parseReport(report(['--compare', 'examples/compare-candidate.json',
    '--diagnostics', '--image-ranking', '--pr-curves']));
  assert.equal(model.kind, 'comparison');
  assert.equal(api.overallMetrics(model).find(x => x.name === 'ap50').delta, -0.75);
  assert.equal(api.imageRows(model)[0].error_delta, 4);
  assert.equal(api.classMetrics(model, 1).length, 12);
  const options = api.curveOptions(model, 'candidate');
  assert.ok(options.length > 0);
  const curve = api.curveData(model, 'candidate', options[0].index);
  assert.equal(curve.precision.length, 101);
  const filters = { status: 'fp', threshold: '0.5', imageId: '1', categoryId: '1' };
  const first = api.filterDiagnostics(model, 'candidate', filters, 1, 2);
  assert.ok(first.total > 0);
  assert.ok(first.rows.every(x => x.status === 'fp' && x.image_id === 1 && x.category_id === 1));
  assert.ok(first.rows.length <= 2);
});

test('bad JSON and incompatible or incomplete reports fail without partial model', () => {
  assert.throws(() => api.parseReport('{'), /JSON 解析失败/);
  const base = JSON.parse(report());
  base.schema_version = '9.0.0';
  assert.throws(() => api.parseReport(JSON.stringify(base)), /schema_version/);
  base.schema_version = '0.1.0';
  delete base.counts;
  assert.throws(() => api.parseReport(JSON.stringify(base)), /缺少/);
});

test('undefined PR data and invalid coordinates are distinct', () => {
  const base = JSON.parse(report(['--pr-curves']));
  assert.ok(base.pr_curves.length > 0);
  const missing = structuredClone(base);
  missing.pr_curves[0].ap = -1;
  missing.pr_curves[0].max_recall = -1;
  missing.pr_curves[0].precision.fill(-1);
  assert.equal(api.curveData(api.parseReport(JSON.stringify(missing)), 'single', 0).defined, false);
  missing.pr_curves[0].precision[5] = 2;
  assert.throws(() => api.curveData(api.parseReport(JSON.stringify(missing)), 'single', 0), /无效数值/);
});

test('unsafe 64-bit diagnostic IDs are rejected instead of silently rounded', () => {
  const base = JSON.parse(report(['--diagnostics']));
  base.diagnostics[0].ground_truth_id = 9007199254740992;
  assert.throws(() => api.parseReport(JSON.stringify(base)), /无损 JSON 工具/);
});

test('real mask comparison retains geometry and rejects mixed or unknown types', () => {
  const text = execFileSync('moon', [...args, 'examples/mask-ground-truth.json',
    'examples/mask-baseline.json', '--iou-type', 'segm', '--compare',
    'examples/mask-candidate.json', '--image-ranking', '--pr-curves'],
    { cwd: root, encoding: 'utf8' });
  const model = api.parseReport(text);
  assert.equal(api.iouType(model), 'segm');
  assert.equal(api.iouType(api.parseReport(report())), 'bbox');
  assert.equal(api.overallMetrics(model).find(x => x.name === 'ap').delta, 1);
  assert.equal(api.curveData(model, 'candidate', 0).precision.length, 101);
  const mixed = JSON.parse(text);
  delete mixed.baseline.iou_type;
  assert.throws(() => api.parseReport(JSON.stringify(mixed)), /评测类型不同/);
  mixed.baseline.iou_type = 'unknown';
  assert.throws(() => api.parseReport(JSON.stringify(mixed)), /iou_type/);
});
