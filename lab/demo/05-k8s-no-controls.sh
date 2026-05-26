#!/usr/bin/env bash
# Сценарий 5: K8s без защитных контролей.
# Демонстрирует базовое состояние кластера до Task4–Task7:
#   - нет NetworkPolicy (любой под может позвать любой другой);
#   - PSA не задан (можно запустить privileged-pod);
#   - default ServiceAccount позволяет лишнее.
set -euo pipefail
cd "$(dirname "$0")"; source ./_lib.sh
ensure_tester

hdr "1. NetworkPolicy в namespace propdev?"
NP=$(kubectl -n propdev get netpol -o name 2>/dev/null || true)
if [[ -z "$NP" ]]; then bad "NetworkPolicy нет — трафик между подами не ограничен"; else ok "Есть: $NP"; fi

hdr "2. Может ли любой под достучаться до partner-api?"
note "В нормальном дизайне partner-api должен быть доступен только из определённых сервисов"
curl_from_tester -o /dev/null -w "HTTP %{http_code}\n" -H 'X-Partner-Token: token-uk-a-secret' http://partner-api/buildings

hdr "3. Уровень PodSecurity на namespace propdev"
kubectl get ns propdev -o jsonpath='{.metadata.labels}' | jq .
note "Если pod-security.kubernetes.io/enforce пуст — admission ничего не блокирует"

hdr "4. Пробуем запустить privileged-pod"
cat <<EOF | kubectl apply -f - 2>&1 | sed 's/^/   /'
apiVersion: v1
kind: Pod
metadata:
  name: pwn-test
  namespace: propdev
spec:
  containers:
  - name: pwn
    image: alpine:3.20
    command: ["sleep","30"]
    securityContext:
      privileged: true
EOF
sleep 2
STATUS=$(kubectl -n propdev get pod pwn-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "absent")
if [[ "$STATUS" == "Running" || "$STATUS" == "Pending" ]]; then
  bad "Privileged-pod создан без сопротивления (status=$STATUS) → PSA не enforced"
else
  ok "Privileged-pod заблокирован"
fi
kubectl -n propdev delete pod pwn-test --grace-period=0 --force 2>/dev/null || true

hdr "5. Что может default ServiceAccount?"
kubectl -n propdev auth can-i list secrets --as=system:serviceaccount:propdev:default && \
  bad "default SA может листать секреты — это лишнее" || ok "default SA НЕ может листать секреты"

say "Эти провалы и закрываются в Task4 (RBAC), Task5 (NetworkPolicy), Task6 (audit), Task7 (PSA + OPA)"
