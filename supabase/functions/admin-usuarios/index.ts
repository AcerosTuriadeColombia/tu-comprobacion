// TU comprobación · alta de usuarios y restablecimiento de contraseña.
// Solo contabilidad puede usarla. "inicial" crea el primer usuario de contabilidad cuando aún no existe ninguno.
import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DOMINIO = "usuarios.tucomprobacion.app"; // correo interno: <login>@DOMINIO (no se envían correos)

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function claveTemporal() {
  const abc = "abcdefghijkmnpqrstuvwxyz";
  const r = crypto.getRandomValues(new Uint32Array(8));
  let s = "Tu";
  for (let i = 0; i < 6; i++) s += abc[r[i] % abc.length];
  return s + String(10 + (r[6] % 90));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return resp({ error: "Método no permitido" }, 405);
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
  let body: any;
  try { body = await req.json(); } catch { return resp({ error: "Solicitud inválida" }, 400); }
  const accion = body?.accion;

  // Quién llama
  let llamante: any = null;
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (token) {
    const { data } = await admin.auth.getUser(token);
    if (data?.user) {
      const { data: p } = await admin.from("perfiles").select("id, rol, activo, bloqueado").eq("id", data.user.id).maybeSingle();
      llamante = p;
    }
  }
  const esContabilidad = llamante && llamante.rol === "contabilidad" && llamante.activo && !llamante.bloqueado;

  async function crear(login: string, datos: Record<string, unknown>) {
    login = String(login || "").trim().toLowerCase();
    if (!/^[a-z0-9._-]{3,}$/.test(login)) return resp({ error: "Usuario: mínimo 3 caracteres, sin espacios ni tildes" }, 400);
    const { data: existe } = await admin.from("perfiles").select("id").eq("login", login).maybeSingle();
    if (existe) return resp({ error: "Ese usuario ya existe" }, 400);
    // Validar antes de crear la cuenta
    const { error: ev } = await admin.rpc("_normalizar_perfil", { p_id: crypto.randomUUID(), d: datos });
    if (ev) return resp({ error: ev.message }, 400);
    const clave = claveTemporal();
    const { data: u, error: eu } = await admin.auth.admin.createUser({
      email: `${login}@${DOMINIO}`, password: clave, email_confirm: true, user_metadata: { login },
    });
    if (eu || !u?.user) return resp({ error: eu?.message || "No se pudo crear el usuario" }, 400);
    const { error: ep } = await admin.rpc("crear_perfil", { p_id: u.user.id, p_login: login, d: datos });
    if (ep) {
      await admin.auth.admin.deleteUser(u.user.id);
      return resp({ error: ep.message }, 400);
    }
    return resp({ id: u.user.id, login, clave });
  }

  if (accion === "inicial") {
    const { data: hay } = await admin.rpc("hay_usuarios");
    if (hay) return resp({ error: "La configuración inicial ya se hizo" }, 403);
    return await crear(body.login, { ...body.datos, rol: "contabilidad" });
  }

  if (!esContabilidad) return resp({ error: "Solo contabilidad administra usuarios" }, 403);

  if (accion === "crear") return await crear(body.login, body.datos || {});

  if (accion === "restablecer") {
    const id = String(body.id || "");
    const { data: p } = await admin.from("perfiles").select("id, login").eq("id", id).maybeSingle();
    if (!p) return resp({ error: "Usuario no existe" }, 404);
    const clave = claveTemporal();
    const { error } = await admin.auth.admin.updateUserById(id, { password: clave });
    if (error) return resp({ error: error.message }, 400);
    await admin.from("perfiles").update({ cambiar_clave: true, bloqueado: false, intentos: 0 }).eq("id", id);
    return resp({ id, login: p.login, clave });
  }

  return resp({ error: "Acción no válida" }, 400);
});
