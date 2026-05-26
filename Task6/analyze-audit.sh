#!/usr/bin/env bash
# Task 6, шаг 3 — фильтрация audit.log и выгрузка подозрительных событий.
#
# Что делает скрипт:
#   1. Копирует свежий /var/log/kubernetes-audit.log из Minikube наружу
#      (в Task6/audit.log).
#   2. Пачкой jq-запросов вытаскивает события, соответствующие каждому
#      из пяти сценариев из ТЗ:
#         - доступ к secrets (особенно от SA monitoring);
#         - создание привилегированных подов;
#         - kubectl exec в чужом поде;
#         - удаление/трогание audit-policy;
#         - создание RoleBinding с ClusterRole cluster-admin.
#   3. Все найденные события сливает в audit-extract.json
#      (массив JSON-объектов, по одному на событие).
#   4. Печатает в stdout краткую сводку: кто, что, когда — её удобно
#      переносить в analysis.md.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/audit.log"
EXTRACT="$ROOT/audit-extract.json"

command -v jq       >/dev/null || { echo "нужен jq"; exit 1; }
command -v minikube >/dev/null || { echo "нужен minikube"; exit 1; }

c_grn="\033[32m"; c_red="\033[31m"; c_blu="\033[34m"; c_ylw="\033[33m"; c_rst="\033[0m"
say() { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()  { printf "${c_grn}✓${c_rst} %s\n" "$*"; }

# ---------------------------------------------------------------------------
# 1. Выгружаем audit.log из Minikube
# ---------------------------------------------------------------------------
say "Копирую audit.log из Minikube в $LOG"
minikube ssh -- "sudo cat /var/log/kubernetes-audit.log" > "$LOG"
total=$(wc -l < "$LOG")
ok "Получено $total строк аудит-лога"

# Файл — построчный JSON. Чтобы было удобно работать с фильтрами,
# нормализуем сразу в массив. Это позволяет вытаскивать срезы как
# подмножества массива.
ALL_JSON="$(jq -s '.' "$LOG")"

# ---------------------------------------------------------------------------
# 2. Фильтры по типам подозрительных событий
# ---------------------------------------------------------------------------
# Каждый фильтр оставляет в потоке те события, которые подходят под
# определение конкретного типа угрозы. Между типами объединяем
# (union по .auditID) — чтобы события не дублировались.

filter_secrets_access() {
  # GET/LIST по secrets, исключая legitimate-операторов (apiserver, controller-manager).
  jq '[ .[]
    | select(.objectRef.resource == "secrets")
    | select(.verb == "get" or .verb == "list")
    | select((.user.username // "") | startswith("system:apiserver") | not)
    | select((.user.username // "") | startswith("system:kube-controller-manager") | not)
  ]' <<< "$ALL_JSON"
}

filter_privileged_pod() {
  # POST/PUT по pods с privileged=true в spec.
  jq '[ .[]
    | select(.objectRef.resource == "pods")
    | select(.verb == "create" or .verb == "update" or .verb == "patch")
    | select(.requestObject.spec.containers // [] | any(.securityContext.privileged == true))
  ]' <<< "$ALL_JSON"
}

filter_exec_in_pod() {
  # exec — это subresource "exec" на pods, и происходит через CONNECT/CREATE.
  jq '[ .[]
    | select(.objectRef.resource == "pods")
    | select(.objectRef.subresource == "exec")
  ]' <<< "$ALL_JSON"
}

filter_audit_policy_tamper() {
  # Любое упоминание объекта с именем audit-policy в objectRef или в requestURI.
  # Важно: объединение условий — внутри ОДНОГО select, иначе
  # `select(X) or select(Y)` в jq даёт boolean, а не отфильтрованный объект.
  jq '[ .[]
    | select(
        ((.objectRef.name // "") | test("audit-policy"; "i"))
        or
        ((.requestURI // "") | test("audit-policy"; "i"))
      )
  ]' <<< "$ALL_JSON"
}

filter_cluster_admin_binding() {
  # Создание RoleBinding/ClusterRoleBinding, в roleRef которого cluster-admin.
  jq '[ .[]
    | select(.objectRef.resource == "rolebindings" or .objectRef.resource == "clusterrolebindings")
    | select(.verb == "create" or .verb == "update" or .verb == "patch")
    | select((.requestObject.roleRef.name // "") == "cluster-admin")
  ]' <<< "$ALL_JSON"
}

say "Извлекаю события по 5 категориям"
SECRETS=$(filter_secrets_access)
PRIV=$(filter_privileged_pod)
EXEC=$(filter_exec_in_pod)
TAMPER=$(filter_audit_policy_tamper)
ESCALATE=$(filter_cluster_admin_binding)

# ---------------------------------------------------------------------------
# 3. Складываем всё в audit-extract.json (без дубликатов по auditID)
# ---------------------------------------------------------------------------
say "Собираю audit-extract.json"
jq -n --argjson a "$SECRETS" --argjson b "$PRIV" --argjson c "$EXEC" \
       --argjson d "$TAMPER" --argjson e "$ESCALATE" \
       '$a + $b + $c + $d + $e
        # Политика RequestResponse пишет два события на запрос
        # (RequestReceived и ResponseComplete). Берём только ResponseComplete —
        # там полностью заполнены user, impersonatedUser, responseStatus.
        | map(select(.stage != "RequestReceived"))
        | unique_by(.auditID)
        | map({
            auditID,
            stage,
            verb,
            requestReceivedTimestamp,
            user: .user.username,
            impersonatedUser: (.impersonatedUser.username // null),
            sourceIPs,
            objectRef,
            responseStatus: .responseStatus.code,
            # Категория определяется первым подошедшим условием. Порядок важен:
            # exec проверяем раньше privileged-pod, потому что exec — тоже pod-операция.
            category: (
              if .objectRef.subresource == "exec" then
                "exec-in-pod"
              elif .objectRef.resource == "secrets" and (.verb == "get" or .verb == "list") then
                "secrets-access"
              elif .objectRef.resource == "pods"
                   and ((.requestObject.spec.containers // []) | any(.securityContext.privileged == true)) then
                "privileged-pod"
              elif ((.objectRef.name // "") | test("audit-policy"; "i"))
                   or ((.requestURI // "")   | test("audit-policy"; "i")) then
                "audit-policy-tamper"
              elif (.objectRef.resource == "rolebindings" or .objectRef.resource == "clusterrolebindings")
                   and ((.requestObject.roleRef.name // "") == "cluster-admin") then
                "cluster-admin-binding"
              else
                "uncategorized"
              end
            )
          })' > "$EXTRACT"

count=$(jq 'length' "$EXTRACT")
ok "В $EXTRACT: $count событий"

# ---------------------------------------------------------------------------
# 4. Сводная таблица в stdout — это «черновик» для analysis.md
# ---------------------------------------------------------------------------
say "Сводка по категориям (для analysis.md):"
jq -r '
  group_by(.category)
  | map({ category: .[0].category, count: length, users: (map(.user) | unique) })
  | .[]
  | "\(.category): \(.count) события, кто инициировал: \(.users | join(", "))"
' "$EXTRACT"

echo
say "Первые 5 событий целиком (для глазного просмотра):"
jq '.[0:5]' "$EXTRACT"
