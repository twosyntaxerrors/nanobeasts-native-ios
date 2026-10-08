const sharp = require('/Users/ervenstnoel/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const fs = require('fs');
const path = require('path');
const project = __dirname;
(async () => {
  const source = path.join(project, 'assets/glitchlet-run-sheet-source.png');
  const meta = await sharp(source).metadata();
  const frames = [], manifest = [];
  const bob = [0, 1, 0, -1, 0, 1, 0, -1];
  for (let i = 0; i < 8; i++) {
    const col = i % 4, row = Math.floor(i / 4);
    const left = Math.round(col * meta.width / 4), top = Math.round(row * meta.height / 2);
    const width = Math.round((col + 1) * meta.width / 4) - left;
    const height = Math.round((row + 1) * meta.height / 2) - top;
    const {data} = await sharp(source).extract({left, top, width, height}).resize(96, 96, {kernel: 'nearest'}).ensureAlpha().raw().toBuffer({resolveWithObject: true});
    let bodyX = 0, bodyCount = 0, eyeY = 0, eyeCount = 0;
    for (let y = 0; y < 96; y++) for (let x = 0; x < 96; x++) {
      const j = (y * 96 + x) * 4, r = data[j], g = data[j + 1], b = data[j + 2], a = data[j + 3];
      if (a < 128) continue;
      if (y >= 35 && y < 70) {bodyX += x; bodyCount++;}
      if (r > 135 && g < 120 && b > 60 && r > b * 1.08) {eyeY += y; eyeCount++;}
    }
    const dx = Math.round(48 - bodyX / bodyCount);
    const dy = Math.round(57 + bob[i] - eyeY / eyeCount);
    const aligned = Buffer.alloc(96 * 96 * 4);
    for (let y = 0; y < 96; y++) for (let x = 0; x < 96; x++) {
      const nx = x + dx, ny = y + dy;
      if (nx >= 0 && nx < 96 && ny >= 0 && ny < 96) data.copy(aligned, (ny * 96 + nx) * 4, (y * 96 + x) * 4, (y * 96 + x) * 4 + 4);
    }
    const png = await sharp(aligned, {raw: {width: 96, height: 96, channels: 4}}).png().toBuffer();
    const file = `glitchlet-run-${i}.png`;
    fs.writeFileSync(path.join(project, 'assets', file), png);
    frames.push({input: png, left: i * 96, top: 0});
    manifest.push({frame: i, file, width: 96, height: 96, alignment: {dx, dy}, bobPixels: bob[i]});
  }
  await sharp({create: {width: 768, height: 96, channels: 4, background: {r: 0, g: 0, b: 0, alpha: 0}}}).composite(frames).png().toFile(path.join(project, 'assets/glitchlet-run-sheet.png'));
  fs.writeFileSync(path.join(project, 'assets/sprite-manifest.json'), JSON.stringify({source: 'glitchlet-run-sheet-source.png', columns: 8, rows: 1, frameWidth: 96, frameHeight: 96, frameRate: 10, frames: manifest}, null, 2));
  console.log('Eight aligned transparent96x96 poses packed.');
})();
