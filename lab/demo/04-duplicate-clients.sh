#!/usr/bin/env bash
# Сценарий 4: Несколько точек регистрации без координации.
# Демонстрирует «нарушен контроль данных, несколько точек регистрации, нет координации».
#
# Что делаем:
#   1) Видим Алису и Боба в client-mart-app (users).
#   2) Видим тех же людей в client-crm-app (clients), но с РАСХОЖДЕНИЯМИ
#      (другая почта у Алисы, другой телефон у Боба), плюс ручной дубликат.
#   3) Регистрируем нового клиента в mart — он НЕ появляется в CRM автоматически.
set -euo pipefail
cd "$(dirname "$0")"; source ./_lib.sh
ensure_tester

hdr "1. Кто есть в client-mart-app (users)?"
curl_from_tester "http://client-mart-app/profile?user_id=1" | jq '{src:"mart", full_name, phone, email}'
curl_from_tester "http://client-mart-app/profile?user_id=2" | jq '{src:"mart", full_name, phone, email}'

hdr "2. Кто есть в client-crm-app (clients)?"
curl_from_tester "http://client-crm-app/clients" | jq 'map({src:"crm", full_name, phone, email, source})'

hdr "3. Регистрируем нового клиента в mart"
# email уникальный на каждый запуск, чтобы демо был идемпотентным
NEW_EMAIL="dmitry-$(date +%s)@example.com"
NEW_NAME="Дмитрий Новый $(date +%H%M%S)"
RESP=$(curl_from_tester -X POST http://client-mart-app/register \
  -H 'content-type: application/json' \
  -d "{\"full_name\":\"$NEW_NAME\",\"phone\":\"+7-900-000-0099\",\"email\":\"$NEW_EMAIL\",\"passport_number\":\"4510 999999\",\"password\":\"pwd-dmitry\"}")
echo "$RESP" | jq

hdr "4. Появился ли он в CRM?"
note "Ожидание (правильное поведение): да, автоматически"
curl_from_tester "http://client-crm-app/clients" | jq --arg name "$NEW_NAME" 'map(select(.full_name==$name))'

bad "Mart и CRM ведут свои реестры. Один клиент = две (часто противоречивые) записи"
say "Это первая проблема из кейса: 'нарушен контроль данных, нет координации точек регистрации'"
