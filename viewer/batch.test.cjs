const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {webcrypto,createHash}=require('node:crypto');
const api=require('./batch.js');
const {createFixtures}=require('./batch-fixtures.cjs');
let fixtures;
before(()=>{fixtures=createFixtures();});
after(()=>fixtures?.cleanup());
const text=kind=>fs.readFileSync(path.join(fixtures[kind],'index.json'),'utf8');
const raw=kind=>JSON.parse(text(kind));

test('native bbox and three-model segm indexes preserve summary and null deltas',()=>{
  const bbox=api.parseIndex(text('bbox'));assert.equal(bbox.iouType,'bbox');assert.equal(bbox.models[1].delta.ap50,-.75);
  assert.equal(bbox.models[0].delta.ap_medium,null);
  const segm=api.parseIndex(text('segm'));assert.deepEqual(segm.models.map(model=>model.summary.ap),[0,1,1]);
  assert.equal(segm.iouType,'segm');assert.equal(segm.models[2].delta.ap,1);
  assert.equal('working_directory' in segm,false);
});
test('format 1 bbox shape remains supported without task markers',()=>{
  const batch=api.parseIndex(text('legacy'));assert.equal(batch.format,'1');assert.equal(batch.iouType,'bbox');
});
test('bad schemas, duplicate names, missing baselines and report paths are rejected',()=>{
  assert.throws(()=>api.parseIndex('{'),/JSON/);
  for(const [change,error] of [
    [v=>v.format_version='9',/格式/], [v=>v.models[1].name='BASELINE',/重复/],
    [v=>v.baseline='missing',/基线/], [v=>v.models[0].report_file='../baseline.report.json',/路径/],
    [v=>v.models[0].report_file='https://example.invalid/report.json',/路径/],
    [v=>v.models[0].report_sha256='bad',/SHA-256/], [v=>v.models.length=0,/模型/],
    [v=>v.models=Array(1001).fill(v.models[0]),/模型/],
  ]){const value=raw('bbox');change(value);assert.throws(()=>api.parseIndex(JSON.stringify(value)),error);}
});
test('mixed tasks, malformed config, counts and inconsistent deltas fail before import',()=>{
  for(const change of [v=>v.models[1].iou_type='segm',v=>v.config.iou_thresholds=[.5,.5],
    v=>v.config.include_diagnostics='yes',v=>v.models[0].counts.images+=1,
    v=>v.models[0].summary.ap=null,v=>v.models[1].delta_from_baseline.ap50=0,
    v=>v.models[1].delta_from_baseline.ap_medium=0,v=>v.ground_truth_counts.images=-1]){
    const value=raw('bbox');change(value);assert.throws(()=>api.parseIndex(JSON.stringify(value)));
  }
});
test('every real report passes byte hash and semantic consistency checks',async()=>{
  for(const kind of ['bbox','segm','legacy','gated']){
    const batch=api.parseIndex(text(kind));
    for(const entry of batch.models){
      const bytes=fs.readFileSync(path.join(fixtures[kind],entry.file));
      const model=await api.verifyReport(batch,entry,bytes,webcrypto.subtle);
      assert.equal(model.kind,'single');assert.equal(model.raw.summary.ap,entry.summary.ap);
    }
  }
});

test('native batch gates preserve mixed statuses and reject inconsistent metadata',async()=>{
  const batch=api.parseIndex(text('gated'));
  assert.equal(batch.gates.status,'failed');
  assert.deepEqual(batch.models.map(model=>model.gates?.status),[undefined,'failed','passed']);
  for(const change of [v=>v.metric_gates.status='passed',v=>v.metric_gates.failed_models=[],
    v=>v.models[2].metric_gates.checks[0].threshold=.2,v=>delete v.metric_gates]){
    const value=raw('gated');change(value);assert.throws(()=>api.parseIndex(JSON.stringify(value)),/门禁/);
  }
  const entry=batch.models[1];
  const report=JSON.parse(fs.readFileSync(path.join(fixtures.gated,entry.file),'utf8'));
  report.metric_gates.checks[0].threshold=.2;
  const bytes=Buffer.from(JSON.stringify(report));entry.sha256=createHash('sha256').update(bytes).digest('hex');
  await assert.rejects(api.verifyReport(batch,entry,bytes,webcrypto.subtle),/门禁与索引/);
  const forged=api.parseIndex(text('gated'));
  const item=forged.models[1];
  const changed=JSON.parse(fs.readFileSync(path.join(fixtures.gated,item.file),'utf8'));
  changed.metric_gates.checks[0].baseline=.9;changed.metric_gates.checks[0].drop=.65;
  item.gates=changed.metric_gates;
  const forgedBytes=Buffer.from(JSON.stringify(changed));item.sha256=createHash('sha256').update(forgedBytes).digest('hex');
  await assert.rejects(api.verifyReport(forged,item,forgedBytes,webcrypto.subtle),/基线指标/);
});
test('changed bytes and unavailable digest support do not bypass verification',async()=>{
  const batch=api.parseIndex(text('bbox'));const entry=batch.models[0];
  const bytes=fs.readFileSync(path.join(fixtures.bbox,entry.file));
  await assert.rejects(api.verifyReport(batch,entry,Buffer.concat([bytes,Buffer.from(' ')]),webcrypto.subtle),/SHA-256/);
  await assert.rejects(api.verifyReport(batch,entry,bytes,null),/SHA-256/);
});
test('matching hashes still require the report type, version, config, counts and summary',async()=>{
  for(const [change,error] of [[v=>v.iou_type='segm',/类型/],[v=>v.evaluator_version='other',/版本/],
    [v=>v.config.include_diagnostics=false,/配置/],[v=>v.counts.images+=1,/计数/],[v=>v.summary.ap=.1,/摘要/]]){
    const batch=api.parseIndex(text('bbox'));const entry=batch.models[0];
    const report=JSON.parse(fs.readFileSync(path.join(fixtures.bbox,entry.file),'utf8'));change(report);
    const bytes=Buffer.from(JSON.stringify(report));entry.sha256=createHash('sha256').update(bytes).digest('hex');
    await assert.rejects(api.verifyReport(batch,entry,bytes,webcrypto.subtle),error);
  }
});
