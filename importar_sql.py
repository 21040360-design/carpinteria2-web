"""Importa basedatosproweb_v2.sql usando EXACTAMENTE la conexión del archivo .env.
Uso: python importar_sql.py"""
import os
import sys

import pymysql
from dotenv import load_dotenv

load_dotenv()
ruta = sys.argv[1] if len(sys.argv) > 1 else "basedatosproweb_v2.sql"

try:
    con = pymysql.connect(host=os.environ.get("DB_HOST", "localhost"),
                          port=int(os.environ.get("DB_PORT", "3306")),
                          user=os.environ.get("DB_USER", "root"),
                          password=os.environ.get("DB_PASSWORD", ""), charset="utf8mb4")
except pymysql.MySQLError as e:
    sys.exit(f"No se pudo conectar a MySQL: {e}\nRevisa DB_HOST, DB_PORT, DB_USER y DB_PASSWORD en .env")

with con.cursor() as cur:
    cur.execute("SELECT VERSION(), @@port")
    version, puerto = cur.fetchone()
    print(f"Conectado a MySQL {version} (puerto {puerto})")
    sql = open(ruta, encoding="utf-8-sig").read()
    sql = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    instrucciones = [s.strip() for s in sql.split(";") if s.strip()]
    for i, st in enumerate(instrucciones, 1):
        try:
            cur.execute(st)
        except pymysql.MySQLError as e:
            sys.exit(f"Error en la instrucción {i}: {e}\n{st[:200]}")
    con.commit()
    cur.execute("USE prog_web")
    cur.execute("SHOW TABLES")
    print(f"Listo. {len(instrucciones)} instrucciones ejecutadas.")
    print("Tablas en prog_web:", ", ".join(r[0] for r in cur.fetchall()))
