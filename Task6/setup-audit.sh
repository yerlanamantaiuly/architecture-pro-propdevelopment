#!/usr/bin/env bash
# Task 6, шаг 1 — настройка аудита в Minikube.
#
# Что делаем:
#   1. Копируем audit-policy.yaml внутрь Minikube в /etc/kubernetes/audit/.
#   2. Патчим /etc/kubernetes/manifests/kube-apiserver.yaml: добавляем
#      args --audit-policy-file и --audit-log-path, плюс volume и
#      volumeMount, чтобы:
#         - apiserver видел файл политики,
#         - писал лог в /var/log/kubernetes-audit.log на ноду Minikube.
#   3. Ждём, пока kubelet перевыкатит apiserver (он у него static pod).
#   4. Проверяем, что лог создаётся.
#
# Скрипт идемпотентен: повторный запуск ничего не дублирует, только
# обновляет файл политики.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

c_grn="\033[32m"; c_red="\033[31m"; c_blu="\033[34m"; c_ylw="\033[33m"; c_rst="\033[0m"
say()  { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_rst} %s\n" "$*"; }
note() { printf "${c_ylw}!${c_rst} %s\n" "$*"; }
die()  { printf "${c_red}✗ %s${c_rst}\n" "$*" >&2; exit 1; }

command -v minikube >/dev/null || die "minikube не найден"
command -v kubectl  >/dev/null || die "kubectl не найден"

# ---------------------------------------------------------------------------
# 1. Копируем политику внутрь Minikube
# ---------------------------------------------------------------------------
say "Копирую audit-policy.yaml в Minikube"
minikube ssh -- "sudo mkdir -p /etc/kubernetes/audit && sudo touch /var/log/kubernetes-audit.log"
minikube cp "$ROOT/audit-policy.yaml" /etc/kubernetes/audit/audit-policy.yaml
ok "audit-policy.yaml лежит в /etc/kubernetes/audit/"

# ---------------------------------------------------------------------------
# 2. Патчим static pod apiserver
# ---------------------------------------------------------------------------
say "Патчу /etc/kubernetes/manifests/kube-apiserver.yaml"

# Чтобы не зависеть от наличия PyYAML внутри Minikube, забираем manifest
# наружу, патчим локально (PyYAML установлен на хосте) и кладём обратно.
TMP_ORIG=$(mktemp)
TMP_PATCHED=$(mktemp)
trap 'rm -f "$TMP_ORIG" "$TMP_PATCHED"' EXIT

minikube ssh -- "sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml" > "$TMP_ORIG"

python3 - "$TMP_ORIG" "$TMP_PATCHED" <<'PYEOF'
import sys
import yaml

orig, out = sys.argv[1], sys.argv[2]
with open(orig) as f:
    doc = yaml.safe_load(f)

container = doc['spec']['containers'][0]
container.setdefault('command', [])
container.setdefault('volumeMounts', [])
doc['spec'].setdefault('volumes', [])

needed_args = [
    '--audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml',
    '--audit-log-path=/var/log/kubernetes-audit.log',
    '--audit-log-maxage=2',
    '--audit-log-maxbackup=1',
    '--audit-log-maxsize=20',
]
existing = container['command']
for a in needed_args:
    key = a.split('=')[0]
    existing[:] = [x for x in existing if not x.startswith(key + '=')]
    existing.append(a)

needed_mounts = [
    {'name': 'audit-policy', 'mountPath': '/etc/kubernetes/audit', 'readOnly': True},
    {'name': 'audit-log',    'mountPath': '/var/log/kubernetes-audit.log'},
]
mnt_names = {m['name'] for m in container['volumeMounts']}
for vm in needed_mounts:
    if vm['name'] not in mnt_names:
        container['volumeMounts'].append(vm)

needed_volumes = [
    {'name': 'audit-policy',
     'hostPath': {'path': '/etc/kubernetes/audit', 'type': 'DirectoryOrCreate'}},
    {'name': 'audit-log',
     'hostPath': {'path': '/var/log/kubernetes-audit.log', 'type': 'FileOrCreate'}},
]
vol_names = {v['name'] for v in doc['spec']['volumes']}
for v in needed_volumes:
    if v['name'] not in vol_names:
        doc['spec']['volumes'].append(v)

with open(out, 'w') as f:
    yaml.dump(doc, f, default_flow_style=False, sort_keys=False)
print('patched on host')
PYEOF

# Кладём обратно. kubelet увидит изменение mtime и перевыкатит apiserver.
minikube cp "$TMP_PATCHED" /etc/kubernetes/manifests/kube-apiserver.yaml
ok "kube-apiserver.yaml пропатчен"

# ---------------------------------------------------------------------------
# 3. Ждём перезапуска apiserver
# ---------------------------------------------------------------------------
say "Жду перезапуска kube-apiserver (до 120с)"
# kubelet видит изменение mtime → удаляет старый pod → запускает новый.
# До завершения старого pod-а апи временно недоступно.
sleep 5
for i in $(seq 1 60); do
  if kubectl get --raw=/healthz >/dev/null 2>&1; then
    ok "kube-apiserver снова отвечает"
    break
  fi
  sleep 2
done

# Доп.проверка: в логах apiserver должны появиться audit-events
say "Проверяю, что аудит-лог пишется"
sleep 3
if minikube ssh -- "sudo test -s /var/log/kubernetes-audit.log"; then
  size=$(minikube ssh -- "sudo wc -l < /var/log/kubernetes-audit.log" | tr -d '\r')
  ok "Лог пишется (строк уже: $size)"
else
  note "Лог пуст или отсутствует — apiserver мог не успеть. Подожди ещё минуту и перезапусти setup-audit.sh"
fi

cat <<'EOF'

Следующий шаг: запустить симуляцию атак, потом фильтрацию аудита:
  bash simulate-incident.sh
  bash analyze-audit.sh
EOF
