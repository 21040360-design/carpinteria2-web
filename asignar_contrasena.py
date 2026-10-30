"""Asigna (o cambia) la contraseña de un usuario. Uso: python asignar_contrasena.py correo@ejemplo.com"""
import getpass
import os
import sys

import pymysql
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash

load_dotenv()
correo = (sys.argv[1] if len(sys.argv) > 1 else input("Correo del usuario: ")).strip().lower()
clave = getpass.getpass("Nueva contraseña (mínimo 10 caracteres): ")
if len(clave) < 10 or clave != getpass.getpass("Repítela: "):
    sys.exit("La contraseña es muy corta o no coincide.")

con = pymysql.connect(host=os.environ.get("DB_HOST", "localhost"), port=int(os.environ.get("DB_PORT", "3306")), user=os.environ.get("DB_USER", "root"),
                      password=os.environ.get("DB_PASSWORD", ""), database=os.environ.get("DB_NAME", "prog_web"),
                      charset="utf8mb4")
with con.cursor() as cur:
    cur.execute("""UPDATE usuarios SET contrasena = %s, intentos_fallidos = 0, bloqueado_hasta = NULL
                   WHERE correo_electronico = %s""",
                (generate_password_hash(clave, method="pbkdf2:sha256"), correo))
    if not cur.rowcount:
        sys.exit("No existe un usuario con ese correo.")
con.commit()
print("Contraseña actualizada.")
