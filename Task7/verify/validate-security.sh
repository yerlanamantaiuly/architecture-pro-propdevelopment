#!/usr/bin/env bash
# Проверяет OPA Gatekeeper отдельно от PSA.
#
# Что делаем:
#   1. Создаём namespace gatekeeper-test БЕЗ PSA-меток.
#      В нём PSA нас не остановит — только Gatekeeper.
#   2. Применяем те же три insecure-манифеста, что и в audit-zone, но с
#      патчем namespace → gatekeeper-test. Каждый должен быть отклонён
#      именно Gatekeeper-ом, с соответствующим msg из ConstraintTemplate.
#   3. Применяем secure-манифесты в gatekeeper-test — должны пройти.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

c_grn="\033[32m"; c_red="\033[31m"; c_blu="\033[34m"; c_rst="\033[0m"
say() { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()  { printf "${c_grn}✓${c_rst} %s\n" "$*"; }
bad() { printf "${c_red}✗${c_rst} %s\n" "$*"; }

# 0. Готовим namespace для чистого теста Gatekeeper (без PSA-меток).
say "Готовлю namespace gatekeeper-test (БЕЗ PSA)"
kubectl create namespace gatekeeper-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n gatekeeper-test delete pod --all --ignore-not-found >/dev/null 2>&1 || true

# Помощник: меняет namespace в манифесте на лету.
swap_ns() {
  sed 's/namespace: audit-zone/namespace: gatekeeper-test/g' "$1"
}

declare -i BLOCKED=0 PASSED=0

say "1. Insecure manifests в gatekeeper-test (ожидание: Gatekeeper отклоняет)"
for f in "$ROOT"/insecure-manifests/*.yaml; do
  base=$(basename "$f")
  out=$(swap_ns "$f" | kubectl apply -f - 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    if echo "$out" | grep -qi "denied the request\|violation"; then
      ok "$base — отклонён Gatekeeper-ом"
      echo "$out" | grep -oE 'violation[s]?[^"]*' | head -1 | sed 's/^/    /'
      BLOCKED+=1
    else
      bad "$base — отклонён, но похоже что не Gatekeeper-ом. Ответ:"
      echo "$out" | head -3 | sed 's/^/    /'
    fi
  else
    bad "$base — admission принял манифест, Gatekeeper не сработал!"
  fi
done

echo
say "2. Secure manifests в gatekeeper-test (ожидание: принимаются)"
for f in "$ROOT"/secure-manifests/*.yaml; do
  base=$(basename "$f")
  out=$(swap_ns "$f" | kubectl apply -f - 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "$base — принят"
    PASSED+=1
  else
    bad "$base — отклонён. Ответ:"
    echo "$out" | head -5 | sed 's/^/    /'
  fi
done

echo
say "3. Состояние констрейнтов и нарушений"
kubectl get constrainttemplates 2>/dev/null
echo
kubectl get constraints 2>/dev/null

echo
say "Итог:"
echo "  Gatekeeper отверг insecure: $BLOCKED / 3"
echo "  secure прошли:               $PASSED / 3"

if [[ $BLOCKED -eq 3 && $PASSED -eq 3 ]]; then
  ok "OPA Gatekeeper работает как задумано"
  exit 0
else
  bad "Поведение не сошлось с ожиданиями"
  exit 1
fi
