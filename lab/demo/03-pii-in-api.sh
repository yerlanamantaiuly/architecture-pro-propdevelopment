#!/usr/bin/env bash
# Сценарий 3: ПДн в контракте API.
# Демонстрирует «контракты API содержат категории данных, которые явно
# предоставляют персональные данные».
#
# Что делаем:
#   1) Запрашиваем /owners/1/profile у tenant-core-app.
#   2) Видим, что контракт ВСЕГДА возвращает паспорт и кем выдан, хотя сценариев,
#      где они нужны, единицы.
#   3) Сравниваем с минимально необходимым набором (id, full_name, apartment_address).
set -euo pipefail
cd "$(dirname "$0")"; source ./_lib.sh
ensure_tester

hdr "1. Получаем профиль собственника через tenant-core-app"
PROFILE=$(curl_from_tester http://tenant-core-app/owners/1/profile)
echo "$PROFILE" | jq

hdr "2. Какие поля содержат ПДн?"
echo "$PROFILE" | jq 'to_entries | map({field: .key, value: .value, pii: (.key|test("passport|phone|email|full_name"))})'

hdr "3. Что вообще нужно фронту в типичном сценарии?"
note "Достаточно: id, full_name, apartment_address. Остальное — лишнее в контракте"

bad "Контракт по умолчанию отдаёт паспорт + кем выдан + телефон + email"
say "Need-to-know не соблюдается. Это первый признак, который вскроет аудит безопасности"
