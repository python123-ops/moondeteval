const {test,before,after} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

const root = path.resolve(__dirname,'../_build/site');
const prefix = '/moondeteval/';
let server, browser, base;
before(async()=>{
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
after(async()=>{if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));});
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
  assert.match(await page.locator('h1').textContent(),/Understand every model change/);
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
