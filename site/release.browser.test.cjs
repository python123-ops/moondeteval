// Import the exact batches produced by examples/release_integration.py.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require('playwright');

const root = path.resolve(process.env.RELEASE_VIEWER_ROOT || path.join(__dirname, '../_build/site'));
const prefix = '/moondeteval/';
let result, server, browser, base, scratch;

before(async () => {
  assert.ok(process.env.RELEASE_INTEGRATION_RESULT,
    'Set RELEASE_INTEGRATION_RESULT to the installed-release result.json; source builds are not a fallback');
  result = JSON.parse(fs.readFileSync(process.env.RELEASE_INTEGRATION_RESULT, 'utf8'));
  assert.equal(result.status, 'passed');
  assert.match(result.version, /^0\.2\.[012]$/);
  assert.equal(result.source_cli_fallback, false);
  assert.equal(result.cli.source, 'registry');
  assert.equal(result.cli.package, `python123-ops/moondeteval/cli@${result.version}`);
  assert.equal(result.copied_source_sha256['batch_eval.py'],
    require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(__dirname, '../examples/batch_eval.py'))).digest('hex'),
    'Regenerate batches after changing the batch runner');
  for (const kind of ['bbox', 'segm']) {
    assert.ok(path.isAbsolute(result.batches[kind]));
    assert.ok(fs.statSync(path.join(result.batches[kind], 'index.json')).isFile());
  }
  scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'moondeteval-release-viewer-'));
  server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (!url.pathname.startsWith(prefix)) { res.writeHead(404).end(); return; }
    let relative;
    try { relative = decodeURIComponent(url.pathname.slice(prefix.length)); }
    catch { res.writeHead(400).end(); return; }
    let file = path.resolve(root, relative || 'index.html');
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
    const types = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.css': 'text/css'};
    res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'});
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}${prefix}`;
  browser = await chromium.launch({headless: true});
});

after(async () => {
  if (browser) await browser.close();
  if (server) await new Promise(resolve => server.close(resolve));
  if (scratch) {
    assert.equal(path.dirname(scratch), path.resolve(os.tmpdir()));
    assert.ok(path.basename(scratch).startsWith('moondeteval-release-viewer-'));
    fs.rmSync(scratch, {recursive: true, force: true});
  }
});

async function imported(page, name = 'baseline') {
  await page.waitForFunction(name =>
    document.getElementById('batch-status').textContent.includes(name + '.report.json：SHA-256') ||
    !document.getElementById('load-error').hidden, name);
  assert.equal(await page.locator('#load-error').isVisible(), false,
    await page.locator('#load-error').textContent());
}

for (const [mode, viewport] of [
  ['project URL', {width: 1440, height: 1000}],
  ['mobile file URL', {width: 390, height: 844}],
]) {
  test(`registry CLI batches retain native metrics and gate failures in the viewer (${mode})`, async () => {
    const context = await browser.newContext({viewport});
    try {
      const page = await context.newPage();
      const errors = [], requests = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(mode === 'project URL' ? base + 'viewer/' : pathToFileURL(path.join(root, 'viewer/index.html')).href);
      await page.waitForLoadState('networkidle');
      page.on('request', request => requests.push(request.url()));
      for (const kind of ['bbox', 'segm']) {
        const index = JSON.parse(fs.readFileSync(path.join(result.batches[kind], 'index.json'), 'utf8'));
        assert.equal(index.format_version, '2');
        assert.equal(index.iou_type, kind);
        await page.locator('#batch-folder').setInputFiles(result.batches[kind]);
        await imported(page);
        assert.deepEqual(await page.locator('#batch-table tbody tr td:last-child').allTextContents(),
          ['基线参照', '失败', '通过']);
        for (const name of ['candidate', 'unchanged', 'baseline']) {
          const report = JSON.parse(fs.readFileSync(path.join(result.batches[kind], name + '.report.json'), 'utf8'));
          assert.equal(report.evaluator_version, result.version);
          await page.locator('#batch-model').selectOption(name);
          await imported(page, name);
          const metric = kind === 'bbox' ? 'ap50' : 'ap';
          const row = kind === 'bbox' ? 1 : 0;
          assert.equal(await page.locator('#overall-table tbody tr').nth(row).locator('td').nth(1).textContent(),
            report.summary[metric].toFixed(4));
          if (name === 'baseline') {
            assert.equal(await page.locator('#gate-view').isVisible(), false);
          } else {
            const native = report.metric_gates;
            assert.equal(native.status, name === 'candidate' ? 'failed' : 'passed');
            assert.match(await page.locator('#gate-meta').textContent(), name === 'candidate' ? /^失败/ : /^通过/);
            assert.match(await page.locator('#gate-table').textContent(),
              new RegExp(native.checks[0].drop.toFixed(4).replace('.', '\\.')));
            if (name === 'candidate') {
              assert.equal(native.checks[0].reason, 'drop_exceeded');
              assert.match(await page.locator('#gate-table').textContent(), /下降量超限/);
            }
          }
        }
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      }
      assert.deepEqual(errors, []);
      assert.deepEqual(requests, [], 'Local batch data must not trigger network requests');
    } finally { await context.close(); }
  });
}

test('a changed installed-release report is rejected before display and the original batch recovers', async () => {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await page.goto(base + 'viewer/');
    const changed = path.join(scratch, 'changed');
    fs.mkdirSync(changed);
    for (const name of fs.readdirSync(result.batches.segm)) {
      const source = path.join(result.batches.segm, name);
      if (fs.statSync(source).isFile()) fs.copyFileSync(source, path.join(changed, name));
    }
    fs.appendFileSync(path.join(changed, 'candidate.report.json'), ' ');
    await page.locator('#batch-folder').setInputFiles(changed);
    await imported(page);
    await page.locator('#batch-model').selectOption('candidate');
    await page.locator('#load-error').waitFor({state: 'visible'});
    assert.match(await page.locator('#load-error').textContent(), /SHA-256/);
    assert.equal(await page.locator('#report-view').isVisible(), false);
    await page.locator('#batch-folder').setInputFiles(result.batches.segm);
    await imported(page);
    await page.locator('#batch-model').selectOption('candidate');
    await imported(page, 'candidate');
    assert.match(await page.locator('#gate-table').textContent(), /下降量超限/);
  } finally { await context.close(); }
});
