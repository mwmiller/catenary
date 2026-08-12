#!/usr/bin/env node
// Turn the square RGB PNG produced by `sips` into an RGBA PNG with an
// opaque alpha channel, which Tauri's `generate_context!` requires.
//
// Uses only Node built-ins so icon asset prep stays inside the project's
// .tool-versions toolchain (node) rather than pulling in external image
// tooling.
//
//   sips -s format png -z 1024 1024 <src> --out src-tauri/icons/icon.png
//   node scripts/make-icon.js src-tauri/icons/icon.png
//
const fs = require("fs");
const zlib = require("zlib");

const CRC_TABLE = (() => {
  const t = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++)
    crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}

function decodeRGB(src) {
  if (src.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let off = 8;
  let width = 0;
  let height = 0;
  const idat = [];
  while (off < src.length) {
    const len = src.readUInt32BE(off);
    const type = src.toString("ascii", off + 4, off + 8);
    const data = src.subarray(off + 8, off + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    off += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = 3;
  const stride = width * bpp;
  const out = Buffer.alloc(height * stride);
  let p = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[p++];
    const line = raw.subarray(p, p + stride);
    p += stride;
    const outLine = out.subarray(y * stride, y * stride + stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? outLine[x - bpp] : 0;
      const b = y > 0 ? out[(y - 1) * stride + x] : 0;
      const c = x >= bpp && y > 0 ? out[(y - 1) * stride + x - bpp] : 0;
      let val = line[x];
      switch (filter) {
        case 0:
          break;
        case 1:
          val = (val + a) & 0xff;
          break;
        case 2:
          val = (val + b) & 0xff;
          break;
        case 3:
          val = (val + ((a + b) >> 1)) & 0xff;
          break;
        case 4: {
          const pa = Math.abs(b - c);
          const pb = Math.abs(a - c);
          const pc = Math.abs(a + b - 2 * c);
          const pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          val = (val + pr) & 0xff;
          break;
        }
        default:
          throw new Error("unsupported filter " + filter);
      }
      outLine[x] = val;
    }
  }
  return { width, height, rgb: out };
}

const input = process.argv[2] || "src-tauri/icons/icon.png";
const src = fs.readFileSync(input);
const { width, height, rgb } = decodeRGB(src);

const bpp = 4;
const stride = width * bpp;
const raw = Buffer.alloc(height * (stride + 1));
let p = 0;
for (let y = 0; y < height; y++) {
  raw[p++] = 0;
  for (let x = 0; x < width; x++) {
    const i = y * width * 3 + x * 3;
    raw[p++] = rgb[i];
    raw[p++] = rgb[i + 1];
    raw[p++] = rgb[i + 2];
    raw[p++] = 255;
  }
}
const idat = zlib.deflateSync(raw);

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(width, 0);
ihdr.writeUInt32BE(height, 4);
ihdr[8] = 8;
ihdr[9] = 6;
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", idat),
  chunk("IEND", Buffer.alloc(0))
]);

fs.writeFileSync(process.argv[3] || input, png);
console.log("wrote RGBA PNG " + width + "x" + height + " -> " + (process.argv[3] || input));
