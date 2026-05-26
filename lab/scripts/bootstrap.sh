#!/usr/bin/env bash
# Bootstrap для лабы PropDevelopment.
# Поднимает Minikube, собирает образы внутрь его docker-демона, разворачивает namespace
# 'propdev' со всеми (нарочно уязвимыми) сервисами и наполняет БД.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

c_grn="\033[32m"; c_red="\033[31m"; c_ylw="\033[33m"; c_blu="\033[34m"; c_rst="\033[0m"
say()  { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_rst} %s\n" "$*"; }
die()  { printf "${c_red}✗ %s${c_rst}\n" "$*" >&2; exit 1; }
note() { printf "${c_ylw}!${c_rst} %s\n" "$*"; }

# 0. Проверки
command -v docker   >/dev/null || die "docker не установлен"
command -v minikube >/dev/null || die "minikube не установлен — см. README"
command -v kubectl  >/dev/null || die "kubectl не установлен"
docker info >/dev/null 2>&1   || die "docker не работает без sudo. Выполни: sudo usermod -aG docker \$USER && перелогинься"

# 1. Minikube
if ! minikube status >/dev/null 2>&1; then
  say "Стартую Minikube (driver=docker, 4 CPU, 6 GB RAM)"
  # --force нужен, если ты под root: minikube ругается, но для лабы это ок
  MINIKUBE_FORCE=""
  if [[ $EUID -eq 0 ]]; then MINIKUBE_FORCE="--force"; note "Под root — добавляю --force"; fi
  minikube start --driver=docker --cpus=4 --memory=6g $MINIKUBE_FORCE
else
  ok "Minikube уже запущен"
fi

# 2. Сборка образов внутри Minikube.
# Используем `minikube image build`, а не `eval docker-env`+`docker build`,
# потому что docker, установленный через snap, не имеет прав на /root/.minikube/certs/.
# `minikube image build` отправляет контекст в кластер и собирает там — без проблем
# с правами и без необходимости пересылать tarball.
for svc in client-mart-app client-crm-app tenant-core-app partner-api; do
  say "Собираю $svc:dev (через minikube image build)"
  minikube image build -t "$svc:dev" "services/$svc" >/dev/null
  ok "$svc:dev собран"
done

# 3. Namespace
say "Применяю namespace propdev"
kubectl apply -f k8s/00-namespace.yaml

# 4. ConfigMaps с seed.sql для каждой БД (пересоздаём, чтобы менять seed без удаления PV)
declare -A SEED_MAP=(
  [client-mart-seed]="services/client-mart-app/seed.sql"
  [client-crm-seed]="services/client-crm-app/seed.sql"
  [tenant-core-seed]="services/tenant-core-app/seed.sql"
  [partner-seed]="services/partner-api/seed.sql"
)
for cm in "${!SEED_MAP[@]}"; do
  say "ConfigMap $cm"
  kubectl -n propdev create configmap "$cm" --from-file=seed.sql="${SEED_MAP[$cm]}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

# 5. БД и приложения
say "Применяю БД"
kubectl apply -f k8s/10-databases.yaml
say "Применяю приложения"
kubectl apply -f k8s/20-apps.yaml
say "Применяю тестовый под"
kubectl apply -f k8s/30-tester.yaml

# 6. Ждём готовности
say "Жду готовности БД (до 120с)"
kubectl -n propdev wait deploy/client-mart-db deploy/client-crm-db deploy/tenant-core-db deploy/partner-db --for=condition=Available --timeout=120s

say "Жду готовности приложений (до 120с)"
kubectl -n propdev wait deploy/client-mart-app deploy/client-crm-app deploy/tenant-core-app deploy/partner-api --for=condition=Available --timeout=120s

say "Жду готовности tester"
kubectl -n propdev wait pod/tester --for=condition=Ready --timeout=60s

echo
ok "Лаба поднята. Состояние namespace propdev:"
kubectl -n propdev get pods,svc

cat <<EOF

${c_grn}Готово.${c_rst} Теперь запусти сценарии:
  ./demo/01-idor-leak.sh         # IDOR: чужой ЛК
  ./demo/02-cross-tenant.sh      # партнёр УК_A видит данные УК_B
  ./demo/03-pii-in-api.sh        # ПДн в контракте API
  ./demo/04-duplicate-clients.sh # mart vs crm — дубликаты
  ./demo/05-k8s-no-controls.sh   # нет NetworkPolicy/PSA/RBAC

Снести: ./scripts/teardown.sh (только namespace)  или  minikube delete (всё).
EOF
