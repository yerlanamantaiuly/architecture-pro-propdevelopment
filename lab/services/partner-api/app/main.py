"""partner-api — эмуляция API внешней управляющей компании.

В лабе нарочно содержит проблему из кейса:
  - Cross-tenant: партнёрский токен УК_A может вытащить данные УК_B.
    Эндпоинт принимает X-Partner-Token, но фильтрация по принадлежности к УК
    нарочно отсутствует.
  - Эндпоинт /owners отдаёт ФИО и контакты любого собственника без проверки,
    относится ли его дом к УК запрашивающего партнёра.
"""
import os

import psycopg
from fastapi import FastAPI, Header, HTTPException, Query
from typing import Optional

DB_DSN = os.environ.get(
    "PARTNER_DB_DSN",
    "postgresql://partner:partner@partner-db:5432/partner",
)

app = FastAPI(title="partner-api", version="0.1-vulnerable")


def db():
    return psycopg.connect(DB_DSN, autocommit=True)


def resolve_partner(x_partner_token: Optional[str]) -> int:
    """Резолвит токен в id УК. Сам токен валидный, но дальше он НЕ используется
    для фильтрации данных — в этом и баг."""
    if not x_partner_token:
        raise HTTPException(401, "missing X-Partner-Token")
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, name FROM management_companies WHERE token=%s", (x_partner_token,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(401, "unknown token")
    return row[0]


@app.get("/health")
def health():
    return {"status": "ok", "service": "partner-api"}


@app.get("/buildings")
def list_buildings(x_partner_token: Optional[str] = Header(None)):
    """ПРОБЛЕМА (cross-tenant): токен резолвим, но фильтр по mc_id не применяется.
    Возвращаются ВСЕ дома всех УК."""
    resolve_partner(x_partner_token)  # токен проверен, но дальше игнорируется
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT b.id, b.address, mc.name AS management_company
            FROM buildings b JOIN management_companies mc ON mc.id=b.mc_id
            ORDER BY b.id
            """
        )
        rows = cur.fetchall()
    return [{"id": r[0], "address": r[1], "management_company": r[2]} for r in rows]


@app.get("/owners")
def list_owners(
    building_id: int = Query(...),
    x_partner_token: Optional[str] = Header(None),
):
    """ПРОБЛЕМА: запрашиваем собственников ЛЮБОГО дома, даже если он не принадлежит
    УК запрашивающего партнёра."""
    resolve_partner(x_partner_token)
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, full_name, phone, email FROM owners WHERE building_id=%s",
            (building_id,),
        )
        rows = cur.fetchall()
    return [{"id": r[0], "full_name": r[1], "phone": r[2], "email": r[3]} for r in rows]
