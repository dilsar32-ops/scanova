// Scanova · la cámara propia (muchas fotos seguidas) y el botón del centro que va directo al proyecto abierto.
import fs from 'node:fs';
import * as C from '../docs/camara.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const panel = fs.readFileSync(new URL('../docs/panel.js', import.meta.url), 'utf8');
const fotos = fs.readFileSync(new URL('../docs/fotos.js', import.meta.url), 'utf8');
const cam = fs.readFileSync(new URL('../docs/camara.js', import.meta.url), 'utf8');

ok('pide la cámara de atrás, sin audio, a la resolución más alta (4:3)', C.RESTRICCIONES.audio === false && C.RESTRICCIONES.video.facingMode.ideal === 'environment' && C.RESTRICCIONES.video.width.ideal === 4032 && C.RESTRICCIONES.video.height.ideal === 3024);
ok('nombreFoto: fecha, hora y número, .jpg', C.nombreFoto(3, new Date(2026, 9, 12, 11, 23, 5)) === 'scanova-20261012-112305-3.jpg');
ok('conteoTxt: 0 / 1 / varias', /Tap/.test(C.conteoTxt(0)) && C.conteoTxt(1) === '1 photo' && C.conteoTxt(7) === '7 photos');
ok('puedeCamaraPropia: solo si el aparato tiene getUserMedia', C.puedeCamaraPropia({ mediaDevices:{ getUserMedia(){} } }) && !C.puedeCamaraPropia({}) && !C.puedeCamaraPropia(null));
ok('errorCamara: permiso apagado, sin cámara, ocupada y el resto', /Settings/.test(C.errorCamara({ name:'NotAllowedError' })) && /No camera/.test(C.errorCamara({ name:'NotFoundError' })) && /Another app/.test(C.errorCamara({ name:'NotReadableError' })) && /phone camera/.test(C.errorCamara({})));
ok('pantalla: video, disparador, Done, la última foto con su número y el aviso con la cámara del teléfono', ['camara', 'camVideo', 'camDisparo', 'camListo', 'camUltima', 'camConteo', 'camError', 'camTelefono'].every(id => new RegExp('id="' + id + '"').test(idx)) && /<video id="camVideo" playsinline autoplay muted>/.test(idx));
ok('cada foto entra a la cola de subida al momento (se sube mientras sigue tomando)', /fotos\.encolar\(\[archivo\]\)/.test(cam) && /lastModified: Date\.now\(\)/.test(cam));
ok('el disparador se prende solo cuando ya hay imagen', /loadeddata/.test(cam) && /disabled = !v\.videoWidth/.test(cam));
ok('al bloquear el teléfono se apaga la cámara y al volver se prende', /visibilitychange/.test(cam) && /if\(document\.hidden\) apagar\(\); else encender\(\)/.test(cam));
ok('sin cámara para la página: la del teléfono, dentro del mismo toque', /setAttribute\('capture', 'environment'\)/.test(cam) && /inp\.click\(\)/.test(cam));
ok('botón del centro DENTRO de un proyecto: va directo a ese proyecto (no vuelve a preguntar)', /pantallaActual\(\) === 'pTrabajo' && t && t\.estado !== 'archivado'/.test(panel) && /if\(esTactil\(\)\) camara\.abrir\(t\)/.test(panel));
ok('afuera de un proyecto: se escoge el proyecto y abre la cámara de muchas fotos', /data-camara-para/.test(panel) && /camara\.abrir\(t\)/.test(panel) && /Take photos for/.test(panel));
ok('"Tomar fotos" de la ficha abre la cámara propia (ya no la de una sola foto)', /data-camara><svg class="ic"><use href="#i-camara"\/><\/svg>Tomar fotos/.test(fotos) && !/capture="environment" hidden data-subir/.test(fotos));
ok('la portada de la ficha pasa a ser la foto más nueva', /La portada de la ficha = la foto más nueva/.test(fotos));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
