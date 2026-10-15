// Scanova · la dirección del proyecto: sugerencias (Apple Maps en el iPhone, sus proyectos en la web) y el 📍.
import fs from 'node:fs';
import * as D from '../docs/direccion.js';
import { numONulo } from '../docs/trabajos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const src = fs.readFileSync(new URL('../docs/direccion.js', import.meta.url), 'utf8');
const trab = fs.readFileSync(new URL('../docs/trabajos.js', import.meta.url), 'utf8');

ok('sinPais: quita ", United States" y espacios dobles', D.sinPais('McLean, VA  22101, United States') === 'McLean, VA 22101' && D.sinPais('Vienna, VA, USA') === 'Vienna, VA');
ok('unirSugerencia: calle + ciudad, sin el país', D.unirSugerencia({ title:'200 Sample Rd', subtitle:'McLean, VA  22101, United States' }) === '200 Sample Rd, McLean, VA 22101');
ok('unirSugerencia: sin subtítulo o repetido no duplica', D.unirSugerencia({ title:'200 Sample Rd, McLean, VA', subtitle:'' }) === '200 Sample Rd, McLean, VA' && D.unirSugerencia({ title:'McLean, VA', subtitle:'McLean, VA' }) === 'McLean, VA');
ok('direccionDeMapa: número, calle, ciudad, estado corto y zip', D.direccionDeMapa({ house_number:'300', road:'Example Terrace', city:'McLean', state:'Virginia', postcode:'22101' }) === '300 Example Terrace, McLean, VA 22101');
ok('direccionDeMapa: pueblo en vez de ciudad; sin número; vacío', D.direccionDeMapa({ road:'Main St', town:'Vienna', state:'Virginia' }) === 'Main St, Vienna, VA' && D.direccionDeMapa(null) === '');
ok('estadoCorto: Washington DC y uno raro se queda igual', D.estadoCorto('District of Columbia') === 'DC' && D.estadoCorto('Maryland') === 'MD' && D.estadoCorto('Ontario') === 'Ontario');
ok('notaPrecision: dice los metros y que revise la casa', /±12 m/.test(D.notaPrecision(12.4)) && /right house/.test(D.notaPrecision(null)));
const L = [ { cliente:'Ana', direccion:'9 Fake Ln, Vienna VA' }, { cliente:'Carter', direccion:'8942 Fake Dr, Bethesda MD' }, { cliente:'Otro', direccion:'9 Fake Ln, Vienna VA' }, { cliente:'X', direccion:'' } ];
ok('deSusProyectos: las que contienen lo escrito, sin repetir, máximo 3', D.deSusProyectos(L, 'fake').map(s => s.title).join(' | ') === '9 Fake Ln, Vienna VA | 8942 Fake Dr, Bethesda MD' && D.deSusProyectos(L, 'o', 3).length === 0 && D.deSusProyectos(L, 'fake', 1).length === 1);
ok('errorUbicacion: GPS apagado, sin permiso (app y web), no encontró', /GPS/.test(D.errorUbicacion({ code:'gps_off' })) && /Settings/.test(D.errorUbicacion({ code:'denied' })) && /Settings/.test(D.errorUbicacion({ code:1 })) && /outside/.test(D.errorUbicacion({ code:3 })));
ok('numONulo: vacío = null, número = número', numONulo('') === null && numONulo(' ') === null && numONulo('38.94') === 38.94 && numONulo('abc') === null);
ok('forma: el 📍 está DENTRO del campo de dirección, con su lista y el punto escondido', /<div class="dir-campo">\s*<input type="text" id="fDireccion"/.test(idx) && /id="btnUbicar"/.test(idx) && /id="fDireccionSug" hidden/.test(idx) && /id="fLat"/.test(idx) && /id="fLng"/.test(idx));
ok('en el iPhone usa Apple Maps (searchAddress cerca de la última ubicación, suggestAddress, geocode)', /P\.searchAddress\(f \? \{ query:q, lat:f\.lat, lng:f\.lng \}/.test(src) && /P\.suggestAddress\(\)/.test(src) && /P\.geocode\(\{ address: texto \}\)/.test(src));
ok('en la web: GPS del navegador + la dirección de ese punto (una consulta por toque)', /navigator\.geolocation\.getCurrentPosition/.test(src) && /nominatim\.openstreetmap\.org\/reverse/.test(src) && !/nominatim\.openstreetmap\.org\/search/.test(src));
ok('escribir a mano borra el punto (no se queda un punto de otra dirección)', /addEventListener\('input', \(\) => \{ ponerPunto\(null, null\)/.test(src));
ok('el proyecto guarda lat y lng', /lat: f\.lat, lng: f\.lng/.test(trab) && /lat: numONulo\(\$\('#fLat'\)\.value\)/.test(trab));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
