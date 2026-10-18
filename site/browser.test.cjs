const {test,before,after} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const {createFixtures} = require('../viewer/batch-fixtures.cjs');

const root = path.resolve(__dirname,'../_build/site');
const prefix = '/moondeteval/';
let server, browser, base, batches;
before(async()=>{
  batches=createFixtures();
  server=http.createServer((req,res)=>{
    const url = new URL(req.url,'http://localhost');
    if(!url.pathname.startsWith(prefix)){res.writeHead(404).end();return;}
    let relative;try{relative=decodeURIComponent(url.pathname.slice(prefix.length));}catch{res.writeHead(400).end();return;}
    let file=path.resolve(root,relative || 'index.html');
    if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
    if(fs.existsSync(file)&&fs.statSync(file).isDirectory())file=path.join(file,'index.html');
    if(!fs.existsSync(file)){res.writeHead(404).end();return;}
    const mime={'.html':'text/html; charset=utf-8','.css':'text/css','.js':'application/javascript','.json':'application/json','.svg':'image/svg+xml'};
    res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  base=`http://127.0.0.1:${server.address().port}${prefix}`;
  browser=await chromium.launch({headless:true});
});
after(async()=>{if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));batches?.cleanup();});
async function context(options={}){const ctx=await browser.newContext(options);return [ctx,await ctx.newPage()];}
async function ready(page){await page.waitForFunction(()=>document.getElementById('score-baseline').textContent!=='—');}

test('product reports are CLI-backed and work under a project subpath',async()=>{
  const [ctx,page]=await context();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base);await ready(page);
  assert.equal(await page.locator('#score-baseline').textContent(),'1.00');
  assert.equal(await page.locator('#score-candidate').textContent(),'0.25');
  assert.equal(await page.locator('#score-delta').textContent(),'-0.75');
  assert.equal(await page.locator('#demo-curve polyline').count(),2);
  for(const [demo,left,right] of [['mask','0.00','1.00'],['polygon','1.00','1.00']]){
    await page.locator(`[data-demo="${demo}"]`).click();await ready(page);
    assert.equal(await page.locator('#score-baseline').textContent(),left);assert.equal(await page.locator('#score-candidate').textContent(),right);
    assert.match(await page.locator('#open-viewer').getAttribute('href'),new RegExp(`demo=${demo}`));
  }
  assert.deepEqual(errors,[]);await ctx.close();
});

test('both languages persist and copy commands through the real clipboard',async()=>{
  const [ctx,page]=await context();await ctx.grantPermissions(['clipboard-read','clipboard-write']);
  await page.goto(base);await ready(page);await page.locator('#language').click();
  assert.equal(await page.locator('html').getAttribute('lang'),'en');
  assert.match(await page.locator('h1').textContent(),/Detection and instance segmentation evaluation/);
  assert.equal(await page.getByText('undefined',{exact:true}).count(),0);
  await page.locator('[data-copy="install-code"]').click();
  await page.waitForFunction(()=>document.getElementById('copy-status').textContent==='Copied to clipboard');
  assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'moon add python123-ops/moondeteval@0.1.0');
  await page.reload();await ready(page);assert.equal(await page.locator('html').getAttribute('lang'),'en');
  await page.locator('#language').focus();await page.keyboard.press('Enter');
  assert.equal(await page.locator('html').getAttribute('lang'),'zh-CN');await ctx.close();
});

test('clipboard failure is explained and keyboard navigation remains available',async()=>{
  const [ctx,page]=await context();await page.addInitScript(()=>Object.defineProperty(navigator,'clipboard',{value:{writeText:()=>Promise.reject(new Error('denied'))}}));
  await page.goto(base);await ready(page);await page.locator('[data-copy="install-code"]').click();
  await page.waitForFunction(()=>document.getElementById('copy-status').textContent.includes('无法访问'));
  await page.locator('[data-demo="mask"]').focus();await page.keyboard.press('Enter');await ready(page);
  assert.equal(await page.locator('#score-candidate').textContent(),'1.00');await ctx.close();
});

test('viewer loads each deep link, rejects bad files and restores local report import',async()=>{
  const [ctx,page]=await context();
  for(const id of ['bbox','mask','polygon']){
    await page.goto(base+'viewer/?demo='+id);await page.locator('#report-view').waitFor({state:'visible'});
    assert.equal(await page.locator('#load-error').isVisible(),false);
    assert.ok(await page.locator('#overall-table tbody tr').count()>=12);
  }
  await page.locator('#report-file').setInputFiles({name:'bad.json',mimeType:'application/json',buffer:Buffer.from('{')});
  await page.locator('#load-error').waitFor({state:'visible'});assert.equal(await page.locator('#report-view').isVisible(),false);
  await page.locator('#report-file').setInputFiles({name:'local.json',mimeType:'application/json',buffer:fs.readFileSync(path.join(root,'demos/bbox.json'))});
  await page.locator('#report-view').waitFor({state:'visible'});assert.equal(await page.locator('#load-error').isVisible(),false);
  await page.locator('#diag-status').selectOption('fp');
  assert.equal(await page.locator('#diag-table').isVisible(),false);
  assert.equal(await page.locator('#diag-empty').isVisible(),true);
  await page.locator('#diag-side').selectOption('candidate');
  assert.match(await page.locator('#diag-table').textContent(),/fp/);await ctx.close();
});

test('viewer rejects arbitrary demo URLs without issuing a remote request',async()=>{
  const [ctx,page]=await context();const remote=[];page.on('request',req=>{if(!req.url().startsWith(base))remote.push(req.url());});
  await page.goto(base+'viewer/?demo='+encodeURIComponent('https://example.invalid/report.json'));
  await page.locator('#load-error').waitFor({state:'visible'});assert.deepEqual(remote,[]);await ctx.close();
});

test('an older in-flight demo cannot overwrite the newest selection',async()=>{
  const [ctx,page]=await context();let release;const gate=new Promise(resolve=>release=resolve);
  await page.route('**/demos/bbox.json',async route=>{await gate;await route.continue();});
  await page.goto(base+'viewer/?demo=bbox');await page.locator('[data-demo="mask"]').click();
  await page.locator('#report-view').waitFor({state:'visible'});release();
  await page.waitForLoadState('networkidle');assert.match(await page.locator('#report-meta').textContent(),/演示：mask/);await ctx.close();
});

test('file URLs retain local import even though hosted demos require HTTP',async()=>{
  const [ctx,page]=await context();const {pathToFileURL}=require('node:url');
  await page.goto(pathToFileURL(path.join(root,'viewer/index.html')).href);
  await page.locator('[data-demo="mask"]').click();await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/HTTP/);
  await page.locator('#report-file').setInputFiles({name:'local.json',mimeType:'application/json',buffer:fs.readFileSync(path.join(root,'demos/mask.json'))});
  await page.locator('#report-view').waitFor({state:'visible'});await ctx.close();
});

async function batchReady(page,name='baseline'){
  await page.waitForFunction(name=>document.getElementById('batch-status').textContent.includes(name+'.report.json：SHA-256') || !document.getElementById('load-error').hidden,name);
  assert.equal(await page.locator('#load-error').isVisible(),false,await page.locator('#load-error').textContent());
}

test('policy batch import verifies snapshot hash and rules before showing results',async()=>{
  const [ctx,page]=await context();await page.goto(base+'viewer/');
  await page.locator('#batch-folder').setInputFiles(batches.policy);await batchReady(page);
  assert.match(await page.locator('#batch-meta').textContent(),/策略快照 SHA-256 及规则已核对/);
  await page.locator('#batch-model').selectOption('candidate');await batchReady(page,'candidate');
  assert.match(await page.locator('#gate-table').textContent(),/下降量超限/);
  const folder=path.join(batches.directory,'broken-policy');fs.mkdirSync(folder);
  for(const name of fs.readdirSync(batches.policy))fs.copyFileSync(path.join(batches.policy,name),path.join(folder,name));
  fs.appendFileSync(path.join(folder,'gate-policy.json'),' ');
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/策略快照 SHA-256/);
  assert.equal(await page.locator('#batch-view').isVisible(),false);
  fs.unlinkSync(path.join(folder,'gate-policy.json'));
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/缺少策略快照/);
  await ctx.close();
});

test('regression gates show native failure reasons, mixed batch outcomes and mobile details',async()=>{
  const [ctx,page]=await context({viewport:{width:390,height:844}});
  await page.goto(base+'viewer/?demo=bbox');await page.locator('#gate-view').waitFor({state:'visible'});
  assert.match(await page.locator('#gate-meta').textContent(),/失败/);
  assert.match(await page.locator('#gate-table').textContent(),/下降量超限/);
  assert.match(await page.locator('#gate-table').textContent(),/0.7500/);
  assert.equal(await page.locator('#overall-table tbody tr').nth(6).locator('td').nth(3).textContent(),'-1.0000');
  assert.equal(await page.locator('#class-table tbody tr').first().locator('td').nth(3).textContent(),'-1.0000');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.locator('#batch-folder').setInputFiles(batches.gated);await batchReady(page);
  assert.equal(await page.locator('#gate-view').isVisible(),false);
  assert.deepEqual(await page.locator('#batch-table tbody tr td:last-child').allTextContents(),['基线参照','失败','通过']);
  await page.locator('#batch-model').selectOption('candidate');await batchReady(page,'candidate');
  assert.match(await page.locator('#gate-table').textContent(),/下降量超限/);
  await page.locator('#batch-model').selectOption('unchanged');await batchReady(page,'unchanged');
  assert.match(await page.locator('#gate-meta').textContent(),/^通过/);
  const report=JSON.parse(fs.readFileSync(path.join(batches.gated,'candidate.report.json'),'utf8'));
  report.metric_gates.checks[0].candidate=.9;
  await page.locator('#report-file').setInputFiles({name:'changed.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(report))});
  await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/门禁数值/);
  await ctx.close();
});

test('real bbox, segm and legacy batch folders open locally and switch reports without uploading',async()=>{
  const [ctx,page]=await context();await page.goto(base+'viewer/');const requests=[];page.on('request',request=>requests.push(request.url()));
  for(const kind of ['bbox','segm','legacy']){
    await page.locator('#batch-folder').setInputFiles(batches[kind]);await batchReady(page);
    assert.equal(await page.locator('#batch-view').isVisible(),true);
    assert.match(await page.locator('#batch-meta').textContent(),new RegExp(kind==='segm'?'segm':'bbox'));
    assert.equal(await page.locator('#batch-table tbody tr').count(),kind==='segm'?3:2);
    await page.locator('#batch-model').selectOption('candidate');await batchReady(page,'candidate');
    assert.match(await page.locator('#report-meta').textContent(),/candidate/);
    const ap50=await page.locator('#overall-table tbody tr').nth(1).locator('td').nth(1).textContent();
    assert.equal(ap50,kind==='segm'?'1.0000':'0.2500');
    await page.locator('#diag-status').selectOption('fp');
    if(kind!=='segm')assert.match(await page.locator('#diag-table').textContent(),/fp/);
  }
  assert.deepEqual(requests,[]);await ctx.close();
});

test('missing or changed batch reports fail and can recover with a valid folder',async()=>{
  const [ctx,page]=await context();await page.goto(base+'viewer/');
  const folder=path.join(batches.directory,'broken');fs.mkdirSync(folder);
  for(const name of fs.readdirSync(batches.bbox))fs.copyFileSync(path.join(batches.bbox,name),path.join(folder,name));
  fs.appendFileSync(path.join(folder,'baseline.report.json'),' ');
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/SHA-256/);assert.equal(await page.locator('#report-view').isVisible(),false);
  fs.renameSync(path.join(folder,'baseline.report.json'),path.join(folder,'missing.json'));
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/缺少/);assert.equal(await page.locator('#batch-view').isVisible(),false);
  fs.renameSync(path.join(folder,'missing.json'),path.join(folder,'baseline.report.json'));
  fs.truncateSync(path.join(folder,'baseline.report.json'),128*1048576+1);
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/128 MiB/);
  fs.truncateSync(path.join(folder,'index.json'),4*1048576+1);
  await page.locator('#batch-folder').setInputFiles(folder);await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/4 MiB/);
  await page.locator('#batch-folder').setInputFiles(batches.segm);await batchReady(page);
  assert.equal(await page.locator('#load-error').isVisible(),false);await ctx.close();
});

test('an index still being read cannot reopen a batch after switching to a demo',async()=>{
  const [ctx,page]=await context();
  await page.addInitScript(()=>{
    const text=File.prototype.text;
    File.prototype.text=async function(){
      if(this.name==='index.json')await new Promise(resolve=>window.releaseIndex=resolve);
      return text.call(this);
    };
  });
  await page.goto(base+'viewer/');await page.locator('#batch-folder').setInputFiles(batches.bbox);
  await page.waitForFunction(()=>typeof window.releaseIndex==='function');
  await page.locator('[data-demo="mask"]').click();await page.locator('#report-view').waitFor({state:'visible'});
  await page.evaluate(()=>window.releaseIndex());
  assert.equal(await page.locator('#batch-view').isVisible(),false);assert.match(await page.locator('#report-meta').textContent(),/演示：mask/);
  await ctx.close();
});

test('long model names remain readable without overflowing mobile pages',async()=>{
  const folder=path.join(batches.directory,'long-names');fs.mkdirSync(folder);
  const index=JSON.parse(fs.readFileSync(path.join(batches.bbox,'index.json'),'utf8'));
  for(const entry of index.models){
    const original=entry.report_file;entry.name+='_'+ 'a'.repeat(96);entry.report_file=entry.name+'.report.json';
    fs.copyFileSync(path.join(batches.bbox,original),path.join(folder,entry.report_file));
  }
  index.baseline=index.models[0].name;fs.writeFileSync(path.join(folder,'index.json'),JSON.stringify(index));
  const [ctx,page]=await context({viewport:{width:390,height:844}});await page.goto(base+'viewer/');
  await page.locator('#batch-folder').setInputFiles(folder);await batchReady(page,index.baseline);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await ctx.close();
});

test('browser file-access errors explain how to recover instead of showing partial results',async()=>{
  const [ctx,page]=await context();
  await page.addInitScript(()=>{File.prototype.arrayBuffer=()=>Promise.reject(new DOMException('file unavailable','NotFoundError'));});
  await page.goto(base+'viewer/');await page.locator('#batch-folder').setInputFiles(batches.bbox);
  await page.locator('#load-error').waitFor({state:'visible'});
  assert.match(await page.locator('#load-error').textContent(),/缩短文件夹路径/);
  assert.equal(await page.locator('#report-view').isVisible(),false);await ctx.close();
});

test('batch digest completion cannot replace a newer local report or leave stale batch controls',async()=>{
  const [ctx,page]=await context();
  await page.addInitScript(()=>{
    const digest=crypto.subtle.digest.bind(crypto.subtle);
    window.releaseDigest=null;
    crypto.subtle.digest=async(...args)=>{await new Promise(resolve=>window.releaseDigest=resolve);return digest(...args);};
  });
  await page.goto(base+'viewer/');await page.locator('#batch-folder').setInputFiles(batches.bbox);
  await page.waitForFunction(()=>typeof window.releaseDigest==='function');
  await page.locator('#report-file').setInputFiles({name:'new-mask.json',mimeType:'application/json',buffer:fs.readFileSync(path.join(root,'demos/mask.json'))});
  await page.locator('#report-view').waitFor({state:'visible'});await page.evaluate(()=>window.releaseDigest());
  await page.waitForFunction(()=>document.getElementById('load-status').textContent.includes('new-mask.json'));
  assert.equal(await page.locator('#batch-view').isVisible(),false);assert.match(await page.locator('#report-meta').textContent(),/new-mask/);
  await ctx.close();
});

test('batch folders also work from file URLs and fit a mobile viewport',async()=>{
  const [ctx,page]=await context({viewport:{width:390,height:844}});const {pathToFileURL}=require('node:url');
  await page.goto(pathToFileURL(path.join(root,'viewer/index.html')).href);
  await page.locator('#batch-folder').setInputFiles(batches.segm);await batchReady(page);
  await page.locator('#batch-model').focus();await page.keyboard.press('p');await page.keyboard.press('Enter');
  await page.locator('#batch-model').selectOption('polygon');await batchReady(page,'polygon');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  if(process.env.SCREENSHOT_DIR)await page.screenshot({path:path.join(process.env.SCREENSHOT_DIR,'mobile-batch.png'),fullPage:true});
  await ctx.close();
});

test('desktop and mobile layouts fit the viewport and produce review screenshots',async()=>{
  for(const [name,width,height] of [['desktop',1440,1000],['mobile',390,844]]){
    const [ctx,page]=await context({viewport:{width,height},deviceScaleFactor:1});
    for(const language of ['zh','en']){
      await page.goto(base+'?lang='+language);await ready(page);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
      if(process.env.SCREENSHOT_DIR){fs.mkdirSync(process.env.SCREENSHOT_DIR,{recursive:true});await page.screenshot({path:path.join(process.env.SCREENSHOT_DIR,name+'-'+language+'.png'),fullPage:true});}
    }
    await page.goto(base+'viewer/?demo=bbox');await page.locator('#report-view').waitFor({state:'visible'});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    if(process.env.SCREENSHOT_DIR)await page.screenshot({path:path.join(process.env.SCREENSHOT_DIR,name+'-viewer.png'),fullPage:true});
    await ctx.close();
  }
});
