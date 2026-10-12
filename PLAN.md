# Scanova — plan técnico (12 oct 2026)

Plataforma propia de fotos de trabajos, al estilo de CompanyCam / Encircle.
**Independiente** de Field Reports: otro repositorio, otro enlace, otras tablas, otra carpeta
de fotos. Nada de la página actual se toca.

## 1. Lo que ya existe (y se aprovecha sin tocarlo)

| Pieza | Hoy | En la nueva página |
|---|---|---|
| GitHub | cuenta `dilsar32-ops`; `amg-reportes` publicada por GitHub Pages (gratis, un solo `index.html` de 2.9 MB) | repositorio nuevo `scanova` → `dilsar32-ops.github.io/scanova`; código partido en archivos pequeños |
| Supabase | proyecto Pro `ogrvdsawqpiqkkevaewb`: 42 tablas, 78 funciones, 6 funciones edge, 3 buckets (`app` público, `recibos` y `contenidos` privados) | **mismas cuentas** (`auth`, `companies`, `profiles`, `my_company()`, `my_role()`, `my_status()`); tablas NUEVAS con prefijo `fotos_`; funciones edge NUEVAS con prefijo `fotos-` |
| Cómo entra la gente | manager: correo + contraseña · crew: sesión anónima + código del equipo + código personal · temporales: nombre + PIN (sin cuenta) | igual: el manager y el crew entran con lo que ya tienen; los temporales **no** entran a la plataforma de fotos (no tienen cuenta); si hace falta, se les da código personal como al crew |
| Fotos | CompanyCam (de pago) + bucket `contenidos` (solo Contenidos) | **Cloudflare R2** (sin cobro por descargas) |
| Nativo | app iOS (Capacitor) publicada por enlace | de momento, la página en Safari / instalable en la pantalla de inicio; envoltura nativa después si hace falta cámara en serie |

## 2. Estructura de la nueva página

```
scanova/
  docs/           la página (GitHub Pages solo publica la raíz o la carpeta /docs; por eso se llama así)
    index.html    cascarón: cabecera, pantallas, barra de abajo
    estilo.css    estilo (mismo lenguaje visual que Field Reports: barras deslizables, pastillas)
    app.js        arranque, sesión, navegación
    trabajos.js   lista de trabajos, buscar, crear, archivar
    fotos.js      línea de tiempo por día, visor, notas, etiquetas
    subida.js     cola de subida (al disco primero, a R2 después, reintentos)
    compartir.js  enlace para el cliente, reporte PDF
    sw.js + manifest.json   instalable en el teléfono, funciona sin señal para lo ya visto
  sql/            tablas, políticas y funciones (prefijo fotos_)
  funciones/      funciones edge (prefijo fotos-): firmar subidas y lecturas de R2
  tests/          pruebas en Node, como en Field Reports
  notas/          este plan y las decisiones
```

Regla de oro: **cada archivo chico y con un solo trabajo**. Field Reports creció en un solo
archivo de 2.9 MB y eso hace cada cambio más lento y más riesgoso. Aquí no.

## 3. Datos (Supabase, tablas nuevas)

- `fotos_trabajos` — un trabajo = un perfil: cliente, dirección, teléfono, tipo (agua / moho /
  fuego / mudanza / otro), estado (activo / archivado), quién lo creó, fechas. Pertenece a la
  empresa (`company_id = my_company()`).
- `fotos_fotos` — una fila por foto: trabajo, quién la subió, cuándo se tomó (EXIF) y cuándo se
  subió, dónde (GPS si viene), rutas en R2 (original, 1600 px, miniatura 320 px), tamaño, huella
  (sha256), nota, estado (activa / en papelera).
- `fotos_etiquetas` y `fotos_foto_etiquetas` — etiquetas por empresa (Antes / Después / Daño /
  Equipo / Firma…) y cuáles lleva cada foto.
- `fotos_comentarios` — comentarios por foto (quién, cuándo, texto).
- `fotos_enlaces` — enlaces para compartir con el cliente: token, trabajo, caducidad, qué deja ver.
- `fotos_documentos` — PDFs y otros archivos del trabajo (reportes, estimados).
- Políticas RLS: todo por empresa; crew activo lee y sube; solo el manager borra, archiva y
  comparte. Las claves de R2 viven **solo** en los secretos de Supabase; la página nunca las ve.

## 4. Fotos (Cloudflare R2)

1. La página achica la foto en el teléfono/computadora **antes** de subir: original + versión web
   (1600 px) + miniatura (320 px). Así la galería carga rápido y R2 no necesita transformar nada.
2. La página le pide a la función `fotos-subir` una **URL firmada** (vale unos minutos) y sube el
   archivo **directo a R2**. No pasa por Supabase: rápido y sin costo de ancho de banda.
3. Al terminar, la función comprueba que el archivo **de verdad está** en R2 (tamaño y huella) y
   solo entonces escribe la fila en `fotos_fotos`. Si no está, no se dice "subida".
4. Para ver fotos, la función `fotos-ver` entrega URLs firmadas por lotes (una llamada por
   pantalla, no una por foto), válidas ~1 hora. El bucket es **privado**: nadie adivina rutas.
5. Cola igual a la probada en Field Reports: la foto va al disco del teléfono primero; si no hay
   señal, espera; reintenta sola; nada se pierde por cerrar la app.

Costo de R2 (orientativo, 2026): sin cobro por descargas; almacenamiento ~US$0.015 por GB al mes,
con los primeros 10 GB gratis. 10,000 fotos de 3 MB ≈ 30 GB ≈ menos de US$0.50 al mes.

## 5. Pantallas

1. **Entrar** — mismas cuentas que Field Reports.
2. **Trabajos** — lista con buscador por cliente/dirección, pestañas Activos / Archivados,
   botón "+ Trabajo". (Mapa de trabajos: después.)
3. **Trabajo** — cabecera (cliente, dirección, teléfono, Llamar/Mensaje), línea de tiempo de fotos
   por día, botón grande de cámara (teléfono) / subir archivos (computadora, varios a la vez),
   filtros por etiqueta y por persona, notas y documentos del trabajo.
4. **Foto** — a pantalla completa, zoom, quién/cuándo/dónde, nota, etiquetas, comentarios,
   Antes/Después, mandar a papelera.
5. **Compartir** — enlace de solo lectura para el cliente (con caducidad) y reporte PDF con las
   fotos y las notas.
6. **Ajustes** — etiquetas de la empresa, logo, quién es quién (viene de `profiles`).

## 6. Pasos (cada uno se prueba con fotos de prueba antes del siguiente)

| Paso | Qué queda funcionando | Qué necesito de Amilcar |
|---|---|---|
| 0. Preparar | este plan, la carpeta del proyecto, el repositorio `scanova`, el SQL de las tablas, la función `fotos-subir` | nombre de la app; cuenta de Cloudflare con un bucket R2 y un token de acceso, **pegados por él** en los secretos de Supabase (yo lo guío clic por clic; nunca manejo sus claves) |
| 1. Entrar y trabajos | entrar con las cuentas de siempre, ver/crear/buscar trabajos, en teléfono y computadora | probarlo en su iPhone y en su computadora |
| 2. Subir y ver fotos | cámara y archivos → R2, línea de tiempo por día, cola con reintentos, comprobación de que la foto sí llegó | una tanda de 50–100 fotos de prueba |
| 3. Detalle de foto | notas, etiquetas, comentarios, Antes/Después, papelera | sus etiquetas de siempre |
| 4. Compartir | enlace para el cliente y reporte PDF | el formato de reporte que quiere (plantilla) |
| 5. Mejor que CompanyCam | importar su historial de CompanyCam (ya tenemos la conexión), ligar cada trabajo con Field Reports (Contenidos, planos, reportes), mapa, listas de verificación, notas de voz | decidir qué va primero |

## 7. Lo que NO se hace sin su visto bueno

- Crear el repositorio público en GitHub (lleva el nombre que él escoja).
- Correr SQL en Supabase (siempre se avisa antes; tablas nuevas, nunca las de Field Reports).
- Subir fotos reales: solo después de que el paso 2 pase con fotos de prueba.
