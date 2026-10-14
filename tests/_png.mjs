// Lee un PNG (8 bits, color, gris o paleta; sin entrelazar) a { data, width, height } como ImageData (RGBA).
// Solo para las pruebas: así las fotos de verdad del lector viven en tests/fixtures sin instalar nada.
import fs from 'fs';
import zlib from 'zlib';
export function leerPng(ruta){
  const b = fs.readFileSync(ruta);
  let p = 8, W = 0, H = 0, tipo = 0, prof = 0, pal = null, trns = null; const idat = [];
  while(p < b.length){
    const n = b.readUInt32BE(p), t = b.toString('ascii', p + 4, p + 8), d = b.subarray(p + 8, p + 8 + n);
    if(t === 'IHDR'){ W = d.readUInt32BE(0); H = d.readUInt32BE(4); prof = d[8]; tipo = d[9]; if(d[12]) throw new Error('PNG entrelazado'); }
    else if(t === 'PLTE') pal = d;
    else if(t === 'tRNS') trns = d;
    else if(t === 'IDAT') idat.push(d);
    else if(t === 'IEND') break;
    p += 12 + n;
  }
  if(prof !== 8) throw new Error('PNG de ' + prof + ' bits');
  const canales = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[tipo], bpp = canales, fila = W * bpp;
  const raw = zlib.inflateSync(Buffer.concat(idat)), px = new Uint8Array(H * fila);
  for(let y = 0; y < H; y++){
    const f = raw[y * (fila + 1)], src = raw.subarray(y * (fila + 1) + 1, (y + 1) * (fila + 1)), o = y * fila;
    for(let x = 0; x < fila; x++){
      const a = x >= bpp ? px[o + x - bpp] : 0, u = y ? px[o - fila + x] : 0, c = (x >= bpp && y) ? px[o - fila + x - bpp] : 0;
      let v = src[x];
      if(f === 1) v += a; else if(f === 2) v += u; else if(f === 3) v += (a + u) >> 1;
      else if(f === 4){ const pp = a + u - c, pa = Math.abs(pp - a), pb = Math.abs(pp - u), pc = Math.abs(pp - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? u : c); }
      px[o + x] = v & 255;
    }
  }
  const data = new Uint8ClampedArray(W * H * 4);
  for(let i = 0; i < W * H; i++){
    if(tipo === 3){ const k = px[i]; data[i * 4] = pal[k * 3]; data[i * 4 + 1] = pal[k * 3 + 1]; data[i * 4 + 2] = pal[k * 3 + 2]; data[i * 4 + 3] = trns && k < trns.length ? trns[k] : 255; }
    else if(tipo === 2){ data[i * 4] = px[i * 3]; data[i * 4 + 1] = px[i * 3 + 1]; data[i * 4 + 2] = px[i * 3 + 2]; data[i * 4 + 3] = 255; }
    else if(tipo === 6){ for(let c = 0; c < 4; c++) data[i * 4 + c] = px[i * 4 + c]; }
    else if(tipo === 0){ data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = px[i]; data[i * 4 + 3] = 255; }
    else { data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = px[i * 2]; data[i * 4 + 3] = px[i * 2 + 1]; }
  }
  return { data, width: W, height: H };
}
