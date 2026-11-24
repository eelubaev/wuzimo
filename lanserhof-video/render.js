// Frame-exact render: seeks every frame and pipes JPEGs into ffmpeg.
// usage: node render.js out.mp4 [fps] [music.wav]
const { chromium } = require('playwright');
const { spawn } = require('child_process');
(async () => {
  const out = process.argv[2] || 'lanserhof-tegernsee-kz.mp4', fps = +(process.argv[3] || 30), audio = process.argv[4];
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + __dirname + '/index.html?render'); await p.evaluate(() => window.ready);
  const dur = await p.evaluate(() => DUR), total = Math.round(dur * fps);
  const args = ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-'];
  if (audio) args.push('-i', audio);
  args.push('-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-movflags', '+faststart');
  if (audio) args.push('-c:a', 'aac', '-b:a', '192k', '-shortest');
  args.push(out);
  const ff = spawn('ffmpeg', args, { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let i = 0; i < total; i++) {
    const d = await p.evaluate(t => { seek(t); return document.getElementById('c').toDataURL('image/jpeg', 0.95); }, i / fps);
    if (!ff.stdin.write(Buffer.from(d.slice(d.indexOf(',') + 1), 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 300 === 0) console.log(`frame ${i}/${total}`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close(); console.log('done', out);
})();
