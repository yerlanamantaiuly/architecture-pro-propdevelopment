#!/usr/bin/env bash
# Task 4, шаг 3 — связываем группы пользователей с ролями.
#
# Биндимся именно на ГРУППЫ (из поля O сертификата), а не на пользователей.
# Это позволяет в будущем добавлять/удалять людей, не трогая RBAC: новый
# DevOps-инженер просто получит сертификат с O=prop-cluster-configurers
# и сразу получит положенные права.
#
# Какие биндинги создаём:
#   ClusterRoleBinding:
#     prop-platform-admins      → cluster-admin (built-in)
#     prop-security-officers    → prop-security-auditor
#     prop-cluster-viewers      → prop-cluster-viewer
#     prop-cluster-configurers  → prop-cluster-configurer
#   RoleBinding (на каждый доменный namespace):
#     prop-domain-devs-<dom>     → prop-namespace-developer  в <dom>
#     prop-domain-managers-<dom> → prop-namespace-viewer     в <dom>

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

c_grn="\033[32m"; c_blu="\033[34m"; c_rst="\033[0m"
say() { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()  { printf "${c_grn}✓${c_rst} %s\n" "$*"; }

# --- Cluster-level биндинги ------------------------------------------------
say "Применяю ClusterRoleBinding-и"

cat > "$ROOT/manifests/cluster-bindings.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prop-platform-admins-binding
  labels: { managed-by: task4-rbac }
subjects:
  - kind: Group
    name: prop-platform-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin           # встроенная роль
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prop-security-officers-binding
  labels: { managed-by: task4-rbac }
subjects:
  - kind: Group
    name: prop-security-officers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: prop-security-auditor
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prop-cluster-viewers-binding
  labels: { managed-by: task4-rbac }
subjects:
  - kind: Group
    name: prop-cluster-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: prop-cluster-viewer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prop-cluster-configurers-binding
  labels: { managed-by: task4-rbac }
subjects:
  - kind: Group
    name: prop-cluster-configurers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: prop-cluster-configurer
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "$ROOT/manifests/cluster-bindings.yaml" | sed 's/^/   /'

# --- Namespace-level биндинги ---------------------------------------------
# Один и тот же набор биндингов применяем в каждом доменном namespace.
say "Применяю RoleBinding-и в каждом домене"

DOMAINS=(sales tenant smart-home finance data)
NS_BINDINGS_FILE="$ROOT/manifests/namespace-bindings.yaml"
: > "$NS_BINDINGS_FILE"

# Имена групп вычисляются по домену:
#   sales       → prop-domain-devs-sales / prop-domain-managers-sales
#   smart-home  → prop-domain-devs-smart-home / prop-domain-managers-smart-home
for ns in "${DOMAINS[@]}"; do
  cat >> "$NS_BINDINGS_FILE" <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prop-devs-binding
  namespace: $ns
  labels: { managed-by: task4-rbac, prop-domain: $ns }
subjects:
  - kind: Group
    name: prop-domain-devs-$ns
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: prop-namespace-developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prop-managers-binding
  namespace: $ns
  labels: { managed-by: task4-rbac, prop-domain: $ns }
subjects:
  - kind: Group
    name: prop-domain-managers-$ns
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: prop-namespace-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
done

kubectl apply -f "$NS_BINDINGS_FILE" | sed 's/^/   /'

echo
ok "Активные ClusterRoleBinding-и:"
kubectl get clusterrolebinding -l managed-by=task4-rbac
echo
ok "Активные RoleBinding-и по namespace-ам:"
kubectl get rolebinding -A -l managed-by=task4-rbac -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ROLE:.roleRef.name,GROUP:.subjects[0].name'

cat <<'EOF'

──────────────────────────────────────────────────────────────────────────
Готово. Проверь поведение пользователей (примеры из roles-table.md):

  # carol — разработчик sales: разрешено в своём namespace, запрещено в чужом
  kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i create deployments -n sales
  kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i create deployments -n tenant
  kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i get secrets -n sales

  # vera — ИБ: может читать секреты везде, но не править
  kubectl --kubeconfig=Task4/kubeconfigs/vera.kubeconfig auth can-i get secrets -n sales
  kubectl --kubeconfig=Task4/kubeconfigs/vera.kubeconfig auth can-i delete pods -n sales

  # bob — конфигуратор: создаёт namespace, но не трогает RBAC
  kubectl --kubeconfig=Task4/kubeconfigs/bob.kubeconfig auth can-i create namespaces
  kubectl --kubeconfig=Task4/kubeconfigs/bob.kubeconfig auth can-i create rolebindings -n sales
EOF
