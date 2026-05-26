# Общие хелперы для demo-сценариев.
# Использование: source "$(dirname "$0")/_lib.sh"

NS="${NS:-propdev}"
TESTER="${TESTER:-tester}"

c_reset="\033[0m"; c_red="\033[31m"; c_grn="\033[32m"; c_ylw="\033[33m"
c_blu="\033[34m"; c_cyn="\033[36m"; c_bold="\033[1m"

say()       { printf "${c_cyn}==>${c_reset} %s\n"  "$*"; }
hdr()       { printf "\n${c_bold}${c_blu}### %s${c_reset}\n" "$*"; }
ok()        { printf "${c_grn}✓${c_reset} %s\n"   "$*"; }
bad()       { printf "${c_red}✗ %s${c_reset}\n"   "$*"; }
note()      { printf "${c_ylw}!${c_reset} %s\n"   "$*"; }

# curl_from_tester <url> [curl args...]
# Запускает curl внутри пода tester. Это эмулирует «соседний под в namespace».
curl_from_tester() {
  kubectl -n "$NS" exec "$TESTER" -- curl -s "$@"
}

ensure_tester() {
  if ! kubectl -n "$NS" get pod "$TESTER" >/dev/null 2>&1; then
    bad "Под '$TESTER' не найден в namespace '$NS'. Запусти ./scripts/bootstrap.sh"
    exit 1
  fi
  # Дождаться готовности (apk install внутри стартового скрипта)
  for _ in $(seq 1 30); do
    if kubectl -n "$NS" exec "$TESTER" -- which curl >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  bad "tester не готов (curl не установился)"; exit 1
}
