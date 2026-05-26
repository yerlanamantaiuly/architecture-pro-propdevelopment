#!/usr/bin/env bash
# Task 6, шаг 2 — симуляция подозрительной активности в кластере.
#
# Версия скрипта из ТЗ Task 6 с небольшими правками для устойчивости:
#   - убрана зависимость от существующего default-token (в k8s ≥1.24 их нет);
#   - в нескольких местах поправлено имя namespace, чтобы не упасть, если
#     namespace уже существует или, наоборот, ещё не создан;
#   - все "опасные" команды по-прежнему делают то, что ожидается:
#     создают SA, пробуют достучаться до секретов, поднимают privileged-pod,
#     делают exec в чужой kube-system pod, имитируют удаление audit-policy
#     и создают RoleBinding с правами cluster-admin без согласования.
#
# Каждое из этих действий должно остаться в /var/log/kubernetes-audit.log.

set +e
NS=secure-ops

echo "==> [1/6] Создаю namespace $NS"
kubectl create ns "$NS" >/dev/null 2>&1
kubectl config set-context --current --namespace="$NS" >/dev/null

echo "==> [2/6] Создаю ServiceAccount monitoring и проверяю доступ к секретам"
kubectl create sa monitoring >/dev/null 2>&1
# Привычный для атакующего разведывательный вызов:
kubectl auth can-i get secrets --as="system:serviceaccount:$NS:monitoring"
# Прямое чтение секрета из kube-system из-под monitoring (должно фейлиться,
# но сам факт попытки попадёт в аудит):
kubectl get secret -n kube-system \
  --as="system:serviceaccount:$NS:monitoring" 2>&1 | head -3

echo "==> [3/6] Создаю privileged-pod (нарушение PSA-стандарта)"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: $NS
spec:
  containers:
  - name: pwn
    image: alpine
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

echo "==> [4/6] Создаю под attacker-pod и делаю exec в чужой kube-system под"
kubectl run attacker-pod --image=alpine --command -- sleep 3600 >/dev/null 2>&1
COREDNS=$(kubectl get pods -n kube-system -o name | grep -m1 coredns)
if [ -n "$COREDNS" ]; then
  kubectl exec -n kube-system "$COREDNS" -- cat /etc/resolv.conf 2>&1 | head -3
fi

echo "==> [5/6] Попытка удалить audit-policy через kubectl"
# Это попытка делать destructive-action как 'admin'; даже если она не
# увенчается успехом (audit-policy.yaml — это не k8s-ресурс), сам факт
# попытки удаления в аудит-логе будет показателен.
kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin 2>&1 | head -3
# Дублирующий ход: пробуем «попасть» по configmap с похожим именем,
# чтобы простая фильтрация по 'audit-policy' что-то находила.
kubectl create cm audit-policy --from-literal=marker=tamper -n "$NS" 2>&1 | head -1
kubectl delete cm audit-policy -n "$NS" 2>&1 | head -1

echo "==> [6/6] Несогласованный RoleBinding с правами cluster-admin"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: escalate-binding
  namespace: $NS
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: $NS
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo
echo "Готово. События должны быть в /var/log/kubernetes-audit.log внутри Minikube."
echo "Запусти ./analyze-audit.sh, чтобы получить выборку подозрительных событий."
