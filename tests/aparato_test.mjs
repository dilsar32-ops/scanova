// El aviso de aparato nuevo (13-oct): compara la versión del enlace con la del teléfono.
import fs from 'fs';
const src = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const m = src.match(/export function aparatoViejo\(remota, local\)\{[\s\S]*?\n\}/);
const aparatoViejo = new Function('return ' + m[0].replace('export ', ''))();
let ok = 0, mal = 0;
const t = (n, c) => { if(c) ok++; else { mal++; console.log('FAIL', n); } };
t('más nueva en el enlace -> aviso', aparatoViejo('20261014', '20261013') === true);
t('igual -> nada', aparatoViejo('20261014', '20261014') === false);
t('el teléfono más nuevo -> nada', aparatoViejo('20261013', '20261014') === false);
t('sin la pieza (aparato viejo) -> aviso', aparatoViejo('20261014', '') === true);
t('archivo vacío o raro -> nada', aparatoViejo('', '3') === false && aparatoViejo('<html>', '3') === false);
t('solo en la app del iPhone', /isNativePlatform\(\)/.test(src) && /APARATO_TXT/.test(src));
t('la barra no usa verde', !/barra-aparato[^}]*(green|#0f0|#2e7d32|#16a34a)/i.test(fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8')));
console.log('aparato:', ok, 'ok,', mal, 'fallas');
if(mal) process.exit(1);
