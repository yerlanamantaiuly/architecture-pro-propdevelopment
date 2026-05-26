#!/usr/bin/env bash
# Task 4, шаг 2 — создание ClusterRole и Role согласно roles-table.md.
#
# Что создаём (см. raws-table.md):
#  - prop-security-auditor   (ClusterRole) — read all + secrets cluster-wide
#  - prop-cluster-viewer     (ClusterRole) — read all БЕЗ secrets cluster-wide
#  - prop-cluster-configurer (ClusterRole) — управление namespace/StorageClass/Ingress
#  - prop-namespace-developer (ClusterRole, используется как Role в RoleBinding)
#  - prop-namespace-viewer    (ClusterRole, используется как Role в RoleBinding)
#  - cluster-admin не создаём — он есть из коробки
#
# Все определения хранятся в Task4/manifests/*.yaml — скрипт просто
# применяет их, чтобы было удобно версионировать и диффать.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

c_grn="\033[32m"; c_blu="\033[34m"; c_rst="\033[0m"
say() { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()  { printf "${c_grn}✓${c_rst} %s\n" "$*"; }

# Готовим YAML с ролями (записываем рядом со скриптом, чтобы можно было
# просмотреть и переиспользовать).
say "Генерирую манифесты ClusterRole в $ROOT/manifests/"

cat > "$ROOT/manifests/cluster-roles.yaml" <<'EOF'
# ─── prop-security-auditor ────────────────────────────────────────────────
# Привилегированная роль для специалиста по ИБ. Может читать ВСЁ, в т.ч.
# secrets и rolebindings, чтобы расследовать инциденты и проводить аудит.
# Никаких прав на изменение.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prop-security-auditor
  labels: { managed-by: task4-rbac, prop-category: privileged }
rules:
  # Все ресурсы любых API-групп — только get/list/watch
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  # Доступ к нестандартным эндпоинтам для аудита
  - nonResourceURLs: ["*"]
    verbs: ["get"]
---
# ─── prop-cluster-viewer ──────────────────────────────────────────────────
# Непривилегированный просмотр кластера. Не видит секретов — это умышленно,
# чтобы не давать содержимое токенов и паролей бизнес-аналитикам.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prop-cluster-viewer
  labels: { managed-by: task4-rbac, prop-category: cluster-view }
rules:
  # Стандартные «безопасные» ресурсы для просмотра — без secrets и RBAC.
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - persistentvolumeclaims
      - namespaces
      - nodes
      - events
      - serviceaccounts
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
  # Явно НЕТ:
  # - secrets (не должен видеть пароли и токены)
  # - rolebindings / clusterrolebindings / roles / clusterroles (модель доступа)
---
# ─── prop-cluster-configurer ──────────────────────────────────────────────
# Непривилегированная роль настройки кластера. DevOps-инженеры управляют
# инфраструктурными ресурсами, не получая доступа к секретам и RBAC.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prop-cluster-configurer
  labels: { managed-by: task4-rbac, prop-category: cluster-configure }
rules:
  # Namespaces — создавать/удалять/менять метки и квоты
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["*"]
  # StorageClass, PV (cluster-scoped)
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csidrivers", "volumeattachments"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["*"]
  # Ingress инфраструктура и cluster-уровневые сетевые ресурсы
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingressclasses"]
    verbs: ["*"]
  - apiGroups: ["scheduling.k8s.io"]
    resources: ["priorityclasses"]
    verbs: ["*"]
  - apiGroups: ["node.k8s.io"]
    resources: ["runtimeclasses"]
    verbs: ["*"]
  # Возможность смотреть, что происходит в кластере (как viewer, но без секретов)
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "events", "nodes"]
    verbs: ["get", "list", "watch"]
  # Явно НЕТ:
  # - secrets (DevOps работает через ExternalSecrets/Vault, см. Task 3 SEC-T3-01)
  # - rolebindings / clusterrolebindings / roles / clusterroles
EOF

cat > "$ROOT/manifests/namespace-roles.yaml" <<'EOF'
# ─── prop-namespace-developer ─────────────────────────────────────────────
# Доменный разработчик: может развёртывать и менять рабочие нагрузки в
# своём namespace, но не имеет права читать секреты, менять RBAC или
# трогать NetworkPolicy/PSA-метки.
#
# Хранится как ClusterRole (это позволяет переиспользовать через
# RoleBinding в нескольких namespace без копий определений).
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prop-namespace-developer
  labels: { managed-by: task4-rbac, prop-category: namespace-developer }
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
      - services
      - configmaps
      - persistentvolumeclaims
      - serviceaccounts
      - events
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Явно НЕТ:
  # - secrets (приходят через ExternalSecrets/Vault, см. Task 3 SEC-T3-01)
  # - roles / rolebindings (только админ namespace может выдавать права)
  # - networkpolicies (управляется DevOps, см. Task 5)
---
# ─── prop-namespace-viewer ────────────────────────────────────────────────
# Доменный менеджер: только read-only в своём namespace, без секретов.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prop-namespace-viewer
  labels: { managed-by: task4-rbac, prop-category: namespace-viewer }
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - persistentvolumeclaims
      - serviceaccounts
      - events
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]
EOF

say "Применяю манифесты"
kubectl apply -f "$ROOT/manifests/cluster-roles.yaml" | sed 's/^/   /'
kubectl apply -f "$ROOT/manifests/namespace-roles.yaml" | sed 's/^/   /'

echo
ok "Готово. Активные prop-роли:"
kubectl get clusterrole -l managed-by=task4-rbac -o custom-columns='ROLE:.metadata.name,CATEGORY:.metadata.labels.prop-category'
