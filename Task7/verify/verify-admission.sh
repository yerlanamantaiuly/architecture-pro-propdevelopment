#!/usr/bin/env bash
# Проверяет PodSecurity Admission (PSA) уровня restricted в namespace audit-zone.
#
# Ожидание:
#   - 3 манифеста из insecure-manifests/ должны быть ОТКЛОНЕНЫ admission'ом;
#   - 3 манифеста из secure-manifests/ должны быть приняты и поды должны
#     запуститься (или хотя бы быть приняты apiserver-ом без отказа).
#
# В выводе ждём admission errors с упоминанием violates PodSecurity.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

c_grn="\033[32m"; c_red="\033[31m"; c_blu="\033[34m"; c_rst="\033[0m"
say() { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()  { printf "${c_grn}✓${c_rst} %s\n" "$*"; }
bad() { printf "${c_red}✗${c_rst} %s\n" "$*"; }

# Подчищаем старые поды на случай повторного запуска
kubectl -n audit-zone delete pod --all --ignore-not-found >/dev/null 2>&1 || true

say "1. Применяю манифест namespace audit-zone (PSA restricted)"
kubectl apply -f "$ROOT/01-create-namespace.yaml"

say "2. Пробую применить insecure-manifests/ — ОЖИДАЕТСЯ отказ от PSA"
declare -i FAILED=0 PASSED=0
for f in "$ROOT"/insecure-manifests/*.yaml; do
  base=$(basename "$f")
  if out=$(kubectl apply -f "$f" 2>&1); then
    bad "$base — apiserver принял (PSA не сработал?). Ответ:"
    echo "    $out" | head -3
  else
    ok "$base — отклонён admission (как и ожидалось)"
    echo "$out" | head -3 | sed 's/^/    /'
    FAILED+=1
  fi
done

echo
say "3. Применяю secure-manifests/ — ДОЛЖНЫ пройти"
for f in "$ROOT"/secure-manifests/*.yaml; do
  base=$(basename "$f")
  if out=$(kubectl apply -f "$f" 2>&1); then
    ok "$base — принят apiserver-ом"
    PASSED+=1
  else
    bad "$base — отвергнут (ожидался accept). Ответ:"
    echo "    $out" | head -5
  fi
done

echo
say "Итог:"
echo "  insecure отклонено: $FAILED / 3"
echo "  secure   принято:    $PASSED / 3"

if [[ $FAILED -eq 3 && $PASSED -eq 3 ]]; then
  ok "PSA admission работает как задумано"
  exit 0
else
  bad "Поведение не сошлось с ожиданиями"
  exit 1
fi
