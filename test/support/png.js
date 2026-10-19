'use strict';
// A minimal PNG reader for the screenshots `screencapture` writes: 8-bit RGB or RGBA,
// not interlaced. Returns the pixels as they were captured from the screen.
const fs = require('node:fs');
const zlib = require('node:zlib');

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/** Reads a PNG file into { width, height, rgb(x, y) -> [r, g, b] }. */
function read(file) {
  const data = fs.readFileSync(file);
  if (data.readUInt32BE(0) !== 0x89504e47) throw new Error(`${file} is not a PNG`);
  let offset = 8;
  let width;
  let height;
  let channels;
  const idat = [];
  while (offset < data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.toString('latin1', offset + 4, offset + 8);
    const body = data.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      const depth = body[8];
      const colour = body[9];
      const interlace = body[12];
      if (depth !== 8 || interlace !== 0 || (colour !== 2 && colour !== 6)) {
        throw new Error(`${file}: unsupported PNG (depth ${depth}, colour ${colour}, interlace ${interlace})`);
      }
      channels = colour === 6 ? 4 : 3;
    } else if (type === 'IDAT') {
      idat.push(body);
    } else if (type === 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const pixels = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const left = i >= channels ? pixels[y * stride + i - channels] : 0;
      const up = y > 0 ? pixels[(y - 1) * stride + i] : 0;
      const upLeft = y > 0 && i >= channels ? pixels[(y - 1) * stride + i - channels] : 0;
      let value;
      switch (filter) {
        case 0: value = line[i]; break;
        case 1: value = line[i] + left; break;
        case 2: value = line[i] + up; break;
        case 3: value = line[i] + ((left + up) >> 1); break;
        case 4: value = line[i] + paeth(left, up, upLeft); break;
        default: throw new Error(`${file}: bad PNG filter ${filter}`);
      }
      pixels[y * stride + i] = value & 0xff;
    }
  }
  return {
    width,
    height,
    rgb(x, y) {
      const at = y * stride + x * channels;
      return [pixels[at], pixels[at + 1], pixels[at + 2]];
    },
  };
}

module.exports = { read };
