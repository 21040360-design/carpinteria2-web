"""Backend de Carpintería Artesanos del Bosque (Flask + MySQL)."""
import hashlib
import os
import re
import secrets
from datetime import datetime
from functools import wraps

import pymysql
from dotenv import load_dotenv
from flask import Flask, g, jsonify, request, send_from_directory
from werkzeug.security import check_password_hash

load_dotenv()
app = Flask(__name__, static_folder="static", static_url_path="/static")

COOKIE = "sid"
SESION_HORAS = 8
MAX_INTENTOS = 5      # intentos fallidos antes de bloquear
BLOQUEO_MIN = 15      # minutos de bloqueo
USAR_HTTPS = os.environ.get("USAR_HTTPS", "0") == "1"
# Hash falso: se compara cuando el correo no existe, para que tarde lo mismo.
HASH_FALSO = "pbkdf2:sha256:600000$relleno$" + "0" * 64

# Estados que muestra el panel  <->  estados de la base de datos
ESTADO_UI = {"Pendiente de Cotización": "En Espera", "Cotizada": "Cotizando",
             "Aceptada": "Aprobado", "Rechazada": "Rechazado", "Cancelada": "Cancelado"}
UI_ESTADO = {v: k for k, v in ESTADO_UI.items()}


# ---------------------------------------------------------------- base de datos
def db():
    if "db" not in g:
        g.db = pymysql.connect(
            host=os.environ.get("DB_HOST", "localhost"),
            port=int(os.environ.get("DB_PORT", "3306")),
            user=os.environ.get("DB_USER", "root"),
            password=os.environ.get("DB_PASSWORD", ""),
            database=os.environ.get("DB_NAME", "prog_web"),
            charset="utf8mb4", cursorclass=pymysql.cursors.DictCursor)
    return g.db


@app.teardown_appcontext
def cerrar_db(_):
    con = g.pop("db", None)
    if con:
        con.close()


def consulta(sql, args=(), uno=False):
    with db().cursor() as cur:
        cur.execute(sql, args)
        return cur.fetchone() if uno else cur.fetchall()


def ejecutar(sql, args=()):
    con = db()
    with con.cursor() as cur:
        cur.execute(sql, args)
        nuevo = cur.lastrowid
    con.commit()
    return nuevo


@app.errorhandler(pymysql.MySQLError)
def error_db(e):
    app.logger.exception(e)
    return jsonify(error="Error en la base de datos."), 500


@app.before_request
def solo_json():
    # Un formulario de otro sitio no puede enviar application/json sin permiso (anti-CSRF).
    if request.path.startswith("/api/") and request.method in ("POST", "PATCH", "PUT", "DELETE") \
            and not request.is_json:
        return jsonify(error="Se requiere JSON."), 415


# ---------------------------------------------------------------- sesiones
def hash_token(token):
    return hashlib.sha256(token.encode()).hexdigest()


def usuario_actual():
    token = request.cookies.get(COOKIE)
    if not token:
        return None
    return consulta(
        """SELECT u.id_usuario, u.nombre_completo, u.rol
             FROM sesiones s JOIN usuarios u ON u.id_usuario = s.id_usuario
            WHERE s.token_hash = %s AND s.revocada = 0 AND s.expira > NOW() AND u.activo = 1""",
        (hash_token(token),), uno=True)


def requiere_rol(*roles):
    def decorador(f):
        @wraps(f)
        def envoltura(*a, **k):
            u = usuario_actual()
            if not u:
                return jsonify(error="Inicia sesión."), 401
            if u["rol"] not in roles:
                return jsonify(error="No tienes permiso."), 403
            g.usuario = u
            return f(*a, **k)
        return envoltura
    return decorador


PERSONAL = ("Cotizador", "Administrador")


@app.post("/api/login")
def login():
    d = request.get_json(silent=True) or {}
    correo = str(d.get("correo", "")).strip().lower()[:150]
    clave = str(d.get("contrasena", ""))[:200]
    u = consulta("""SELECT id_usuario, nombre_completo, contrasena, rol, activo,
                           (bloqueado_hasta IS NOT NULL AND bloqueado_hasta > NOW()) AS bloqueado
                      FROM usuarios WHERE correo_electronico = %s""", (correo,), uno=True)
    if u and u["bloqueado"]:
        return jsonify(error=f"Demasiados intentos. Espera {BLOQUEO_MIN} minutos."), 429
    ok = check_password_hash(u["contrasena"] if u else HASH_FALSO, clave)
    if not (u and u["activo"] and ok):
        if u:  # el orden importa: intentos_fallidos ya vale +1 al evaluar el IF
            ejecutar("""UPDATE usuarios SET intentos_fallidos = intentos_fallidos + 1,
                          bloqueado_hasta = IF(intentos_fallidos >= %s,
                                               DATE_ADD(NOW(), INTERVAL %s MINUTE), bloqueado_hasta)
                        WHERE id_usuario = %s""", (MAX_INTENTOS, BLOQUEO_MIN, u["id_usuario"]))
        return jsonify(error="Correo o contraseña incorrectos."), 401

    token = secrets.token_urlsafe(32)
    ejecutar("""UPDATE usuarios SET intentos_fallidos = 0, bloqueado_hasta = NULL,
                ultimo_acceso = NOW() WHERE id_usuario = %s""", (u["id_usuario"],))
    ejecutar("""INSERT INTO sesiones (id_usuario, token_hash, ip, user_agent, expira)
                VALUES (%s, %s, %s, %s, DATE_ADD(NOW(), INTERVAL %s HOUR))""",
             (u["id_usuario"], hash_token(token), request.remote_addr,
              (request.user_agent.string or "")[:255], SESION_HORAS))
    r = jsonify(usuario={"nombre": u["nombre_completo"], "rol": u["rol"]})
    r.set_cookie(COOKIE, token, max_age=SESION_HORAS * 3600, httponly=True,
                 samesite="Lax", secure=USAR_HTTPS)
    return r


@app.post("/api/logout")
def logout():
    token = request.cookies.get(COOKIE)
    if token:
        ejecutar("UPDATE sesiones SET revocada = 1 WHERE token_hash = %s", (hash_token(token),))
    r = jsonify(ok=True)
    r.delete_cookie(COOKIE)
    return r


# ---------------------------------------------------------------- pedidos (público)
def error(msg, code=400):
    return jsonify(error=msg), code


@app.post("/api/solicitudes")
def crear_solicitud():
    d = request.get_json(silent=True) or {}
    nombre = str(d.get("nombre", "")).strip()[:150]
    tel = str(d.get("telefono", "")).strip()[:20]
    correo = str(d.get("correo", "")).strip()[:150] or None
    notas = str(d.get("notas", "")).strip()[:2000] or None
    items = d.get("items")
    if not nombre or not tel:
        return error("Nombre y teléfono son obligatorios.")
    if correo and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", correo):
        return error("El correo no es válido.")
    if not isinstance(items, list) or not 1 <= len(items) <= 20:
        return error("Agrega entre 1 y 20 muebles.")

    filas = []
    for it in items:
        if not isinstance(it, dict) or not str(it.get("nombre", "")).strip():
            return error("Mueble no válido.")
        try:
            precio = round(float(it.get("precio", 0)), 2)
        except (TypeError, ValueError):
            precio = 0
        if not 0 <= precio < 10**8:   # también descarta NaN
            precio = 0
        filas.append((str(it["nombre"]).strip()[:150],
                      str(it.get("detalle", "")).strip()[:1000] or None, precio))

    u = usuario_actual()
    id_cliente = u["id_usuario"] if u and u["rol"] == "Cliente" else None
    con = db()
    try:
        with con.cursor() as cur:
            cur.execute("""INSERT INTO solicitudes (id_cliente, nombre_contacto, telefono_contacto,
                           correo_contacto, notas_cliente) VALUES (%s, %s, %s, %s, %s)""",
                        (id_cliente, nombre, tel, correo, notas))
            sid = cur.lastrowid
            folio = f"AB-{datetime.now().year}-{sid:04d}"
            cur.execute("UPDATE solicitudes SET folio = %s WHERE id_solicitud = %s", (folio, sid))
            cur.executemany("""INSERT INTO solicitud_items (id_solicitud, nombre_item,
                               especificaciones, precio_estimado) VALUES (%s, %s, %s, %s)""",
                            [(sid, n, e, p) for n, e, p in filas])
        con.commit()
    except Exception:
        con.rollback()
        raise
    return jsonify(folio=folio, id=sid), 201


# ---------------------------------------------------------------- panel (Cotizador / Administrador)
@app.get("/api/admin/solicitudes")
@requiere_rol(*PERSONAL)
def listar_solicitudes():
    filas = consulta("""
        SELECT s.id_solicitud, s.folio, s.nombre_contacto, s.telefono_contacto, s.correo_contacto,
               s.notas_cliente, s.estado, DATE_FORMAT(s.fecha_creacion, '%%d/%%m/%%Y') AS fecha,
               GROUP_CONCAT(i.nombre_item SEPARATOR ', ') AS productos
          FROM solicitudes s LEFT JOIN solicitud_items i ON i.id_solicitud = s.id_solicitud
         GROUP BY s.id_solicitud
         ORDER BY s.fecha_creacion DESC, s.id_solicitud DESC LIMIT 500""")
    return jsonify([{
        "id": f["id_solicitud"], "cliente": f["nombre_contacto"],
        "producto": f["productos"] or "—", "fecha": f["fecha"],
        "estado": ESTADO_UI.get(f["estado"], f["estado"]),
        "detalle": f"Folio {f['folio']}. Tel: {f['telefono_contacto']}. "
                   f"Correo: {f['correo_contacto'] or 'No proporcionado'}. "
                   f"{f['notas_cliente'] or ''}".strip(),
    } for f in filas])


@app.patch("/api/admin/solicitudes/<int:sid>/estado")
@requiere_rol(*PERSONAL)
def cambiar_estado(sid):
    nuevo = UI_ESTADO.get((request.get_json(silent=True) or {}).get("estado"))
    if not nuevo:
        return error("Estado no válido.")
    if not consulta("SELECT 1 FROM solicitudes WHERE id_solicitud = %s", (sid,), uno=True):
        return error("La solicitud no existe.", 404)
    ejecutar("UPDATE solicitudes SET estado = %s WHERE id_solicitud = %s", (nuevo, sid))
    return jsonify(ok=True)


@app.post("/api/admin/solicitudes/<int:sid>/cotizacion")
@requiere_rol(*PERSONAL)
def cotizar(sid):
    d = request.get_json(silent=True) or {}
    try:
        costos = [round(float(d.get(k)), 2) for k in ("materiales", "mano_obra", "herrajes_barniz")]
        dias, vigencia = int(d.get("dias")), int(d.get("vigencia_dias", 15))
    except (TypeError, ValueError):
        return error("Revisa los montos y los días.")
    if not all(0 <= c < 10**8 for c in costos) or not 1 <= dias <= 365 or not 1 <= vigencia <= 90:
        return error("Valores fuera de rango.")
    if not consulta("SELECT 1 FROM solicitudes WHERE id_solicitud = %s", (sid,), uno=True):
        return error("La solicitud no existe.", 404)
    con = db()
    with con.cursor() as cur:
        cur.execute("""INSERT INTO cotizaciones (id_solicitud, id_cotizador, costo_materiales,
                       costo_mano_obra, costo_herrajes_barniz, dias_estimados_fabricacion, vigencia_hasta)
                       VALUES (%s, %s, %s, %s, %s, %s, DATE_ADD(CURDATE(), INTERVAL %s DAY))""",
                    (sid, g.usuario["id_usuario"], *costos, dias, vigencia))
        idc = cur.lastrowid
        cur.execute("""UPDATE solicitudes SET estado = 'Cotizada', id_cotizador = %s
                       WHERE id_solicitud = %s AND estado = 'Pendiente de Cotización'""",
                    (g.usuario["id_usuario"], sid))
    con.commit()
    total = consulta("SELECT total FROM cotizaciones WHERE id_cotizacion = %s", (idc,), uno=True)
    return jsonify(id=idc, total=float(total["total"])), 201


# ---------------------------------------------------------------- página
@app.get("/")
def inicio():
    return send_from_directory("static", "index.html")


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=os.environ.get("DEBUG") == "1")
