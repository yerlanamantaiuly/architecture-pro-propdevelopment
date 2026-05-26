#!/usr/bin/env bash
# Сценарий 2: Cross-tenant в partner-api.
# Демонстрирует «партнёр из одной УК может видеть данные другой УК».
#
# Что делаем:
#   1) Запрашиваем /buildings с токеном УК_A → ожидаем дома только УК_A.
#   2) В ответе видим дома УК_B → токен проверен, но фильтрация по tenant не применяется.
#   3) Запрашиваем /owners?building_id=3 (это дом УК_B) с тем же токеном УК_A — получаем ФИО.
set -euo pipefail
cd "$(dirname "$0")"; source ./_lib.sh
ensure_tester

hdr "1. Партнёр УК_A запрашивает список домов"
note "Ожидание: только дома УК_A (mc=UK_A)"
curl_from_tester http://partner-api/buildings \
  -H 'X-Partner-Token: token-uk-a-secret' | jq

hdr "2. Партнёр УК_A пробует получить собственников дома №3 (это дом УК_B!)"
note "Корректное поведение: 403 или фильтрация по mc_id"
curl_from_tester "http://partner-api/owners?building_id=3" \
  -H 'X-Partner-Token: token-uk-a-secret' | jq

bad "Утечка: УК_A видит дома и собственников УК_B"
say "Это второй пункт проблем из кейса: партнёр одной УК видит данные другой"
