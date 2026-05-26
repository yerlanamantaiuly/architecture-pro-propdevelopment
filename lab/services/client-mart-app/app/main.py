"""client-mart-app — витрина и онлайн-сделка для клиентов PropDevelopment.

В лабе нарочно содержит уязвимости из кейса:
  - IDOR в /profile и /bookings: user_id берётся из query, без валидации сессии.
  - Endpoint возвращает паспорт и телефон клиента без need-to-know.
  - Регистрация не координируется с client-crm-app (см. сценарий 04-duplicate-clients).
"""
import os
from typing import Optional

import psycopg
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

DB_DSN = os.environ.get(
    "MART_DB_DSN",
    "postgresql://mart:mart@client-mart-db:5432/client_mart",
)

app = FastAPI(title="client-mart-app", version="0.1-vulnerable")


def db():
    return psycopg.connect(DB_DSN, autocommit=True)


class LoginIn(BaseModel):
    email: str
    password: str


class RegisterIn(BaseModel):
    full_name: str
    phone: str
    email: str
    passport_number: str
    password: str


class BookingIn(BaseModel):
    user_id: int
    property_id: int
    viewing_type: str = "offline"


@app.get("/health")
def health():
    return {"status": "ok", "service": "client-mart-app"}


@app.post("/login")
def login(body: LoginIn):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM users WHERE email=%s AND password_hash=%s",
            (body.email, body.password),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(401, "invalid credentials")
    # "Токен" = просто user_id. В реальной системе должна быть JWT/сессия.
    return {"token": f"mart-{row[0]}", "user_id": row[0]}


@app.post("/register")
def register(body: RegisterIn):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO users(full_name, phone, email, passport_number, password_hash)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
            """,
            (body.full_name, body.phone, body.email, body.passport_number, body.password),
        )
        new_id = cur.fetchone()[0]
    return {"user_id": new_id, "note": "client also has to be created in CRM separately"}


@app.get("/profile")
def profile(user_id: int = Query(...), token: Optional[str] = None):
    """ПРОБЛЕМА (IDOR): user_id берётся из query без проверки, что токен принадлежит этому пользователю.
    Достаточно поменять ?user_id=N — и увидишь чужой ЛК."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, full_name, phone, email, passport_number FROM users WHERE id=%s",
            (user_id,),
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
    }


@app.get("/bookings")
def bookings(user_id: int = Query(...)):
    """Та же IDOR. Возвращает чужие брони."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT b.id, b.property_id, p.address, b.status, b.viewing_type
            FROM bookings b JOIN properties p ON p.id=b.property_id
            WHERE b.user_id=%s
            """,
            (user_id,),
        )
        rows = cur.fetchall()
    return [
        {"id": r[0], "property_id": r[1], "address": r[2], "status": r[3], "viewing_type": r[4]}
        for r in rows
    ]


@app.post("/bookings")
def make_booking(body: BookingIn):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO bookings(user_id, property_id, status, viewing_type) VALUES (%s,%s,'new',%s) RETURNING id",
            (body.user_id, body.property_id, body.viewing_type),
        )
        new_id = cur.fetchone()[0]
    return {"booking_id": new_id}
