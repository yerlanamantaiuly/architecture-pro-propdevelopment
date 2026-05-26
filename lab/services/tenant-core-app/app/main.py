"""tenant-core-app — сервисы для собственников жилья.

В лабе нарочно содержит проблемы из кейса:
  - API-контракт возвращает полный набор ПДн (паспорт + кем выдан + ФИО + телефон),
    хотя в большинстве сценариев нужны только id и адрес — это и есть «контракты API
    содержат категории данных, которые явно предоставляют персональные данные».
  - Никакой авторизации — любой под в namespace может получить ПДн.
"""
import os

import psycopg
from fastapi import FastAPI, HTTPException

DB_DSN = os.environ.get(
    "TENANT_DB_DSN",
    "postgresql://tenant:tenant@tenant-core-db:5432/tenant_core",
)

app = FastAPI(title="tenant-core-app", version="0.1-vulnerable")


def db():
    return psycopg.connect(DB_DSN, autocommit=True)


@app.get("/health")
def health():
    return {"status": "ok", "service": "tenant-core-app"}


@app.get("/owners/{owner_id}/profile")
def owner_profile(owner_id: int):
    """ПРОБЛЕМА: контракт возвращает паспорт и кем выдан, хотя на UI они не нужны.
    Это и есть «ПДн в API-контрактах» из описания кейса."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, full_name, phone, email, passport_number, passport_issued_by,
                   apartment_address
            FROM owners WHERE id=%s
            """,
            (owner_id,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(404, "not found")
    return {
        "id": row[0],
        "full_name": row[1],
        "phone": row[2],
        "email": row[3],
        "passport_number": row[4],
        "passport_issued_by": row[5],
        "apartment_address": row[6],
    }


@app.get("/owners")
def list_owners():
    """Сводный список собственников — тоже без авторизации. Любой клиент в namespace
    может вытащить весь реестр."""
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, full_name, apartment_address FROM owners ORDER BY id")
        rows = cur.fetchall()
    return [{"id": r[0], "full_name": r[1], "apartment_address": r[2]} for r in rows]
