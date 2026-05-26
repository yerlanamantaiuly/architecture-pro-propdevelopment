"""client-crm-app — CRM-система для клиентских данных.

В лабе нарочно содержит проблемы из кейса:
  - Список всех клиентов доступен без аутентификации (предполагается «внутренний» сервис,
    но в кластере он open-relay внутри namespace без NetworkPolicy).
  - Своя таблица users, никак не синхронизирована с client-mart-app — отсюда дубликаты.
"""
import os

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DB_DSN = os.environ.get(
    "CRM_DB_DSN",
    "postgresql://crm:crm@client-crm-db:5432/client_crm",
)

app = FastAPI(title="client-crm-app", version="0.1-vulnerable")


def db():
    return psycopg.connect(DB_DSN, autocommit=True)


class ClientIn(BaseModel):
    full_name: str
    phone: str
    email: str
    source: str = "manual"


@app.get("/health")
def health():
    return {"status": "ok", "service": "client-crm-app"}


@app.get("/clients")
def list_clients():
    """Возвращает всех клиентов. БЕЗ авторизации (предполагается, что «внутренний» эндпоинт)."""
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, full_name, phone, email, source FROM clients ORDER BY id")
        rows = cur.fetchall()
    return [
        {"id": r[0], "full_name": r[1], "phone": r[2], "email": r[3], "source": r[4]}
        for r in rows
    ]


@app.get("/clients/{client_id}")
def get_client(client_id: int):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, full_name, phone, email, source FROM clients WHERE id=%s",
            (client_id,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(404, "not found")
    return {"id": row[0], "full_name": row[1], "phone": row[2], "email": row[3], "source": row[4]}


@app.post("/clients")
def add_client(body: ClientIn):
    """Создаёт клиента. БЕЗ проверки уникальности по email — дубликаты допустимы.
    БЕЗ интеграции с client-mart-app — один и тот же человек может появляться в обеих системах."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO clients(full_name, phone, email, source) VALUES (%s,%s,%s,%s) RETURNING id",
            (body.full_name, body.phone, body.email, body.source),
        )
        new_id = cur.fetchone()[0]
    return {"client_id": new_id}
