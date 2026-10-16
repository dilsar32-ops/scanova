// =====================================================================
//  fotos-subir  ·  SCANOVA — la única puerta entre la app y Cloudflare R2 (12 oct 2026)
//  Las claves de R2 viven SOLO aquí (secretos R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
//  R2_SECRET_ACCESS_KEY, R2_BUCKET). La página nunca las ve: pide URLs firmadas.
//  Acciones (POST JSON { accion, ... } con el JWT del usuario en Authorization):
//    prueba          → lista hasta 5 objetos del bucket. Comprueba que las claves sirven. Solo manager.
//    firmar_subida   → { trabajo_id, foto_id, bytes:{original,web,mini} } → una URL firmada PUT por
//                      variante (10 min). La página sube DIRECTO a R2; nada pasa por Supabase.
//    confirmar       → { foto_id, trabajo_id, sha256, bytes:{...}, tomada_at?, lat?, lng?, ancho?, alto? }
//                      → HEAD a R2 por cada variante: si el tamaño coincide, escribe la fila en
//                      fotos_fotos (llave de servicio). Si falta una, NO se escribe nada y lo dice.
//    firmar_lectura  → { foto_ids:[...], variante } → URLs firmadas GET (1 hora), por lotes.
//  Reglas: todo por empresa (my_company del usuario); crew activo sube y lee; prueba solo manager.
// =====================================================================
import { AwsClient } from "npm:aws4fetch@1.0.20";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const env = (k: string): string => ((typeof Deno !== "undefined" && Deno.env.get(k)) || "");
const SB = () => env("SUPABASE_URL");
const sbHeaders = (extra: Record<string, string> = {}) => {
  const k = env("SUPABASE_SERVICE_ROLE_KEY");
  return { apikey: k, Authorization: "Bearer " + k, "Content-Type": "application/json", ...extra };
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// ---- quién llama: usuario con sesión, perfil activo (o manager) de una empresa ----
type Usuario = { id: string; nombre: string; company_id: string; role: string };
export async function usuarioDe(req: Request): Promise<{ usuario?: Usuario; status?: number }> {
  const m = (req.headers.get("authorization") || "").match(/^Bearer\s+([A-Za-z0-9._-]{20,4000})$/);
  if (!m) return { status: 401 };
  let r: Response;
  try { r = await fetch(SB() + "/auth/v1/user", { headers: { apikey: env("SUPABASE_ANON_KEY") || env("SUPABASE_SERVICE_ROLE_KEY"), Authorization: "Bearer " + m[1] } }); }
  catch { return { status: 503 }; }
  if (r.status === 401 || r.status === 403) return { status: 401 };
  if (!r.ok) return { status: 503 };
  const u = await r.json().catch(() => null);
  if (!u || !u.id || u.role === "anon") return { status: 401 };
  let p: Response;
  try { p = await fetch(SB() + "/rest/v1/profiles?id=eq." + encodeURIComponent(u.id) + "&select=company_id,status,role,full_name", { headers: sbHeaders() }); }
  catch { return { status: 503 }; }
  if (!p.ok) return { status: 503 };
  const f = (await p.json().catch(() => []))[0];
  if (!f || !f.company_id) return { status: 403 };
  const role = String(f.role || "crew");
  if (role !== "manager" && (f.status || "active") !== "active") return { status: 403 };
  return { usuario: { id: String(u.id), nombre: String(f.full_name || "").trim().slice(0, 60), company_id: String(f.company_id), role } };
}

// ---- R2 ----
const VARIANTES = ["original", "web", "mini"] as const;
type Variante = typeof VARIANTES[number];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function r2Config() {
  const cuenta = env("R2_ACCOUNT_ID"), llave = env("R2_ACCESS_KEY_ID"), secreto = env("R2_SECRET_ACCESS_KEY"), bucket = env("R2_BUCKET");
  const faltan = [["R2_ACCOUNT_ID", cuenta], ["R2_ACCESS_KEY_ID", llave], ["R2_SECRET_ACCESS_KEY", secreto], ["R2_BUCKET", bucket]].filter(([, v]) => !v).map(([k]) => k);
  if (faltan.length) throw new Error("faltan secretos en Supabase: " + faltan.join(", "));
  const cliente = new AwsClient({ accessKeyId: llave, secretAccessKey: secreto, service: "s3", region: "auto" });
  const base = "https://" + cuenta + ".r2.cloudflarestorage.com/" + bucket;
  return { cliente, base };
}
export const claveDe = (company_id: string, trabajo_id: string, foto_id: string, variante: Variante) =>
  company_id + "/" + trabajo_id + "/" + foto_id + "-" + variante + ".jpg";
async function firmar(metodo: "PUT" | "GET", clave: string, segundos: number): Promise<string> {
  const { cliente, base } = r2Config();
  const url = new URL(base + "/" + clave);
  url.searchParams.set("X-Amz-Expires", String(segundos));
  const firmado = await cliente.sign(new Request(url.toString(), { method: metodo }), { aws: { signQuery: true } });
  return firmado.url;
}
// HEAD firmado: devuelve el tamaño real en R2, o null si no está.
async function tamanoEnR2(clave: string): Promise<number | null> {
  const { cliente, base } = r2Config();
  const r = await cliente.fetch(base + "/" + clave, { method: "HEAD" });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error("R2 HEAD " + r.status);
  const n = Number(r.headers.get("content-length") || "");
  return Number.isFinite(n) ? n : null;
}

// ---- la base, con la llave de servicio ----
async function trabajoDe(id: string, company_id: string) {
  const r = await fetch(SB() + "/rest/v1/fotos_trabajos?id=eq." + id + "&company_id=eq." + company_id + "&select=id,estado", { headers: sbHeaders() });
  if (r.status === 404) throw new Error("falta correr sql/fotos-01-base.sql");
  if (!r.ok) throw new Error("leer trabajo " + r.status);
  const f = await r.json().catch(() => []);
  return Array.isArray(f) && f.length ? f[0] : null;
}
async function fotoExistente(id: string) {
  const r = await fetch(SB() + "/rest/v1/fotos_fotos?id=eq." + id + "&select=*", { headers: sbHeaders() });
  if (!r.ok) throw new Error("leer foto " + r.status);
  const f = await r.json().catch(() => []);
  return Array.isArray(f) && f.length ? f[0] : null;
}
// La misma foto (misma huella) ya en ese trabajo, activa o en la papelera (16-oct, pegar fotos: antes se buscaba por el
// foto_id NUEVO, nunca la encontraba, contestaba 409 y la foto se quedaba con su "!" rojo para siempre).
async function fotoPorHuella(trabajo_id: string, company_id: string, sha256: string) {
  const r = await fetch(SB() + "/rest/v1/fotos_fotos?trabajo_id=eq." + trabajo_id + "&company_id=eq." + company_id + "&sha256=eq." + sha256 + "&select=*&limit=1", { headers: sbHeaders() });
  if (!r.ok) return null;
  const f = await r.json().catch(() => []);
  return Array.isArray(f) && f.length ? f[0] : null;
}
// Las 3 copias que se subieron de más a R2 (la foto ya estaba): se borran. Si falla, no pasa nada.
async function borrarVariantes(company_id: string, trabajo_id: string, foto_id: string) {
  try {
    const { cliente, base } = r2Config();
    for (const v of VARIANTES) { try { await cliente.fetch(base + "/" + claveDe(company_id, trabajo_id, foto_id, v), { method: "DELETE" }); } catch { /* sigue */ } }
  } catch { /* sin R2: nada que borrar */ }
}

// ---- acciones ----
type Cuerpo = Record<string, unknown>;
const bytesDe = (b: unknown): Partial<Record<Variante, number>> => {
  const o = (b && typeof b === "object") ? b as Record<string, unknown> : {};
  const out: Partial<Record<Variante, number>> = {};
  for (const v of VARIANTES) { const n = Number(o[v]); if (Number.isFinite(n) && n > 0 && n < 200 * 1024 * 1024) out[v] = Math.floor(n); }
  return out;
};

async function prueba(u: Usuario) {
  if (u.role !== "manager") return json(403, { ok: false, error: "solo el manager" });
  const { cliente, base } = r2Config();
  const r = await cliente.fetch(base + "?list-type=2&max-keys=5");
  const texto = await r.text();
  if (!r.ok) return json(502, { ok: false, error: "R2 contestó " + r.status, detalle: texto.slice(0, 300) });
  const objetos = (texto.match(/<Contents>/g) || []).length;
  return json(200, { ok: true, bucket: env("R2_BUCKET"), objetos, truncado: /<IsTruncated>true/.test(texto) });
}

async function firmarSubida(u: Usuario, c: Cuerpo) {
  const trabajo_id = String(c.trabajo_id || ""), foto_id = String(c.foto_id || "");
  if (!UUID.test(trabajo_id) || !UUID.test(foto_id)) return json(400, { ok: false, error: "trabajo_id y foto_id tienen que ser uuid" });
  const bytes = bytesDe(c.bytes);
  if (!bytes.original) return json(400, { ok: false, error: "falta bytes.original" });
  const t = await trabajoDe(trabajo_id, u.company_id);
  if (!t) return json(404, { ok: false, error: "ese trabajo no es de su empresa" });
  if (t.estado !== "activo") return json(409, { ok: false, error: "el trabajo está archivado" });
  // Ya está esa misma foto: no se firma nada (la página no sube otra vez y no queda el "!" rojo).
  const sha = String(c.sha256 || "").toLowerCase();
  if (/^[0-9a-f]{64}$/.test(sha)) { const ya = await fotoPorHuella(trabajo_id, u.company_id, sha); if (ya) return json(200, { ok: true, repetida: true, foto: ya }); }
  const urls: Partial<Record<Variante, string>> = {};
  for (const v of VARIANTES) if (bytes[v]) urls[v] = await firmar("PUT", claveDe(u.company_id, trabajo_id, foto_id, v), 600);
  return json(200, { ok: true, urls, caduca_en_s: 600 });
}

async function confirmar(u: Usuario, c: Cuerpo) {
  const trabajo_id = String(c.trabajo_id || ""), foto_id = String(c.foto_id || ""), sha256 = String(c.sha256 || "").toLowerCase();
  if (!UUID.test(trabajo_id) || !UUID.test(foto_id)) return json(400, { ok: false, error: "trabajo_id y foto_id tienen que ser uuid" });
  if (!/^[0-9a-f]{64}$/.test(sha256)) return json(400, { ok: false, error: "sha256 inválido" });
  const bytes = bytesDe(c.bytes);
  if (!bytes.original) return json(400, { ok: false, error: "falta bytes.original" });
  const ya = await fotoExistente(foto_id);
  if (ya) return json(200, { ok: true, foto: ya, repetida: true });
  const t = await trabajoDe(trabajo_id, u.company_id);
  if (!t) return json(404, { ok: false, error: "ese trabajo no es de su empresa" });
  // La prueba de que la foto SÍ está: R2 la tiene y pesa lo que la página dijo.
  const faltas: string[] = [];
  for (const v of VARIANTES) {
    if (!bytes[v]) continue;
    const n = await tamanoEnR2(claveDe(u.company_id, trabajo_id, foto_id, v));
    if (n === null) faltas.push(v + ": no está en R2");
    else if (n !== bytes[v]) faltas.push(v + ": pesa " + n + " y no " + bytes[v]);
  }
  if (faltas.length) return json(409, { ok: false, error: "la foto no llegó completa", faltas });
  const fila = {
    id: foto_id, trabajo_id, company_id: u.company_id, created_by: u.id,
    tomada_at: typeof c.tomada_at === "string" && c.tomada_at ? c.tomada_at : null,
    lat: Number.isFinite(Number(c.lat)) && c.lat !== null && c.lat !== "" ? Number(c.lat) : null,
    lng: Number.isFinite(Number(c.lng)) && c.lng !== null && c.lng !== "" ? Number(c.lng) : null,
    r2_original: claveDe(u.company_id, trabajo_id, foto_id, "original"),
    r2_web: bytes.web ? claveDe(u.company_id, trabajo_id, foto_id, "web") : null,
    r2_mini: bytes.mini ? claveDe(u.company_id, trabajo_id, foto_id, "mini") : null,
    bytes: bytes.original,
    ancho: Number.isFinite(Number(c.ancho)) ? Math.floor(Number(c.ancho)) : null,
    alto: Number.isFinite(Number(c.alto)) ? Math.floor(Number(c.alto)) : null,
    sha256,
    nota: typeof c.nota === "string" ? c.nota.slice(0, 2000) : null,
  };
  const r = await fetch(SB() + "/rest/v1/fotos_fotos", { method: "POST", headers: sbHeaders({ Prefer: "return=representation" }), body: JSON.stringify(fila) });
  const texto = await r.text();
  if (r.status === 409) {
    const otra = await fotoExistente(foto_id) || await fotoPorHuella(trabajo_id, u.company_id, sha256);
    if (otra) { if (otra.id !== foto_id) await borrarVariantes(u.company_id, trabajo_id, foto_id); return json(200, { ok: true, foto: otra, repetida: true }); }
    return json(409, { ok: false, error: "esa misma foto ya está en ese trabajo" });
  }
  if (!r.ok) return json(502, { ok: false, error: "no se pudo anotar la foto (" + r.status + ")", detalle: texto.slice(0, 300) });
  const filas = JSON.parse(texto || "[]");
  if (!Array.isArray(filas) || !filas.length) return json(502, { ok: false, error: "la base no devolvió la fila" });
  return json(200, { ok: true, foto: filas[0] });
}

async function firmarLectura(u: Usuario, c: Cuerpo) {
  const ids = Array.isArray(c.foto_ids) ? c.foto_ids.map(String).filter((x) => UUID.test(x)).slice(0, 200) : [];
  const variante = (VARIANTES as readonly string[]).includes(String(c.variante)) ? String(c.variante) as Variante : "mini";
  if (!ids.length) return json(400, { ok: false, error: "foto_ids vacío" });
  // Solo fotos de su empresa: la llave de servicio no filtra sola, así que se filtra aquí.
  const r = await fetch(SB() + "/rest/v1/fotos_fotos?id=in.(" + ids.join(",") + ")&company_id=eq." + u.company_id + "&select=id,trabajo_id,r2_original,r2_web,r2_mini,estado", { headers: sbHeaders() });
  if (!r.ok) return json(502, { ok: false, error: "leer fotos " + r.status });
  const filas = await r.json().catch(() => []);
  const urls: Record<string, string> = {};
  for (const f of filas) {
    const clave = variante === "original" ? f.r2_original : variante === "web" ? (f.r2_web || f.r2_original) : (f.r2_mini || f.r2_web || f.r2_original);
    if (clave) urls[f.id] = await firmar("GET", clave, 3600);
  }
  return json(200, { ok: true, urls, caduca_en_s: 3600 });
}

export async function atender(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { ok: false, error: "POST" });
  let c: Cuerpo;
  try { c = await req.json(); } catch { return json(400, { ok: false, error: "JSON inválido" }); }
  const quien = await usuarioDe(req);
  if (!quien.usuario) return json(quien.status || 401, { ok: false, error: quien.status === 403 ? "cuenta sin empresa o inactiva" : quien.status === 503 ? "no se pudo comprobar la sesión" : "sin sesión" });
  const u = quien.usuario;
  try {
    switch (String(c.accion || "")) {
      case "prueba": return await prueba(u);
      case "firmar_subida": return await firmarSubida(u, c);
      case "confirmar": return await confirmar(u, c);
      case "firmar_lectura": return await firmarLectura(u, c);
      default: return json(400, { ok: false, error: "accion desconocida" });
    }
  } catch (e) {
    return json(500, { ok: false, error: String((e && (e as Error).message) || e).slice(0, 300) });
  }
}

if (typeof Deno !== "undefined") {
  Deno.serve((req) => atender(req));
}
