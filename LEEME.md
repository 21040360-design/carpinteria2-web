# Artesanos del Bosque – tienda + panel conectados a MySQL

## Puesta en marcha (Windows)
1. **Base de datos:** importa `basedatosproweb_v2.sql` en MySQL (phpMyAdmin → Importar). Borra y recrea las tablas de `prog_web`.
2. **Entorno Python** (en esta carpeta):
   ```
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   ```
3. Copia `.env.example` a `.env` y escribe la contraseña de tu MySQL en `DB_PASSWORD`.
4. **Contraseña del administrador** (los usuarios de prueba no pueden entrar hasta hacer esto):
   ```
   python asignar_contrasena.py admin@artesanos.com
   ```
   Repite con `cotizador@artesanos.com` si lo quieres usar.
5. `python app.py` y abre http://127.0.0.1:5000

## Qué ya funciona con la base de datos
- Pedidos de la tienda (con o sin cuenta): se guardan en `solicitudes` + `solicitud_items` y el cliente recibe un folio.
- Login del panel (solo Administrador y Cotizador): contraseñas con hash, bloqueo de 15 min tras 5 intentos fallidos, sesión de 8 h.
- Panel → Solicitudes: lista real y cambio de estatus.
- API para cotizar: `POST /api/admin/solicitudes/<id>/cotizacion` con `materiales`, `mano_obra`, `herrajes_barniz`, `dias` y `vigencia_dias` (aún sin pantalla en el panel).

## Sigue siendo demostración (datos de ejemplo del HTML)
Catálogo, cotizaciones, proyectos, inventario, usuarios y reportes del panel. El catálogo público también sigue viniendo del HTML, no de la tabla `productos`.

## Para publicarlo
Usa HTTPS y pon `USAR_HTTPS=1` y `DEBUG=0` en `.env`; ejecútalo con un servidor de producción (por ejemplo `waitress` en Windows o `gunicorn` en Linux), no con `python app.py`. El precio de cada mueble en el pedido es solo una estimación enviada por el navegador: el precio real es el de la cotización.
