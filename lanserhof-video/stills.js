const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const ts = process.argv.slice(2).map(Number); const out = process.env.OUT;
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
  await p.goto('file://' + __dirname + '/index.html?render'); await p.evaluate(() => window.ready);
  for (const t of ts) { const d = await p.evaluate(t => { seek(t); return document.getElementById('c').toDataURL('image/jpeg', .85); }, t);
    fs.writeFileSync(`${out}/f_${String(t).padStart(5, '0')}.jpg`, Buffer.from(d.split(',')[1], 'base64')); }
  console.log('errors:', errs); await b.close();
})();
