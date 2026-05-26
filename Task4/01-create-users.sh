#!/usr/bin/env bash
# Task 4, шаг 1 — создание namespace-ов и пользователей K8s.
#
# Пользователи создаются стандартным x509-способом: генерируем RSA-ключ,
# готовим CSR с CN=<username> и O=<group>, передаём в K8s API через
# CertificateSigningRequest, апрувим, забираем сертификат и собираем
# готовый kubeconfig.
#
# В результате в Task4/kubeconfigs/ появляется по одному kubeconfig'у на
# каждого пользователя. Их же мы используем в скрипте 03 и в проверках
# из roles-table.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/.work"
KUBECONFIGS="$ROOT/kubeconfigs"
mkdir -p "$WORK" "$KUBECONFIGS"

c_grn="\033[32m"; c_red="\033[31m"; c_blu="\033[34m"; c_ylw="\033[33m"; c_rst="\033[0m"
say()  { printf "${c_blu}==>${c_rst} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_rst} %s\n" "$*"; }
note() { printf "${c_ylw}!${c_rst} %s\n" "$*"; }
die()  { printf "${c_red}✗ %s${c_rst}\n" "$*" >&2; exit 1; }

command -v kubectl  >/dev/null || die "kubectl не найден"
command -v openssl  >/dev/null || die "openssl не найден"

# --- 1. Namespace-ы по организационной структуре ---------------------------
say "Создаю namespace-ы по доменам PropDevelopment"
for ns in sales tenant smart-home finance data; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  ok "namespace $ns"
done

# --- 2. Пользователи -------------------------------------------------------
# user-name : группа-O в сертификате
USERS=(
  "dmitry:prop-platform-admins"
  "vera:prop-security-officers"
  "alice:prop-cluster-viewers"
  "bob:prop-cluster-configurers"
  "carol:prop-domain-devs-sales"
)

# Параметры кластера для будущих kubeconfig'ов
CLUSTER_SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_NAME=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_CA_DATA=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
[ -z "$CLUSTER_CA_DATA" ] && die "не получилось вытащить CA из kubeconfig"

create_user() {
  local username="$1" group="$2"
  local key="$WORK/$username.key" csr="$WORK/$username.csr" crt="$WORK/$username.crt"
  local csr_name="csr-$username"

  say "Создаю пользователя $username (группа $group)"

  # 2.1 Ключ и CSR (CN=имя_пользователя, O=группа)
  openssl genrsa -out "$key" 2048 2>/dev/null
  openssl req -new -key "$key" -out "$csr" -subj "/CN=$username/O=$group" 2>/dev/null

  # 2.2 Удаляем старый CSR с тем же именем (идемпотентность)
  kubectl delete csr "$csr_name" --ignore-not-found=true >/dev/null

  # 2.3 Подаём CSR в K8s API
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $csr_name
spec:
  signerName: kubernetes.io/kube-apiserver-client
  request: $(base64 -w0 < "$csr")
  usages:
    - client auth
EOF

  # 2.4 Аппрувим
  kubectl certificate approve "$csr_name" >/dev/null

  # 2.5 Ждём, пока контроллер выпишет сертификат
  for _ in $(seq 1 20); do
    cert_b64=$(kubectl get csr "$csr_name" -o jsonpath='{.status.certificate}' 2>/dev/null || true)
    [ -n "$cert_b64" ] && break
    sleep 1
  done
  [ -z "$cert_b64" ] && die "сертификат для $username не выписан"
  echo "$cert_b64" | base64 -d > "$crt"

  # 2.6 Собираем kubeconfig (всё в одном файле, без ссылок на хост)
  local user_cert_data user_key_data
  user_cert_data=$(base64 -w0 < "$crt")
  user_key_data=$(base64 -w0 < "$key")
  cat > "$KUBECONFIGS/$username.kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: $CLUSTER_NAME
    cluster:
      server: $CLUSTER_SERVER
      certificate-authority-data: $CLUSTER_CA_DATA
users:
  - name: $username
    user:
      client-certificate-data: $user_cert_data
      client-key-data: $user_key_data
contexts:
  - name: $username@$CLUSTER_NAME
    context:
      cluster: $CLUSTER_NAME
      user: $username
      namespace: default
current-context: $username@$CLUSTER_NAME
EOF
  ok "$username готов → kubeconfigs/$username.kubeconfig"

  # Подчищаем CSR — он больше не нужен и не должен мешать повторным запускам
  kubectl delete csr "$csr_name" --ignore-not-found=true >/dev/null
}

for entry in "${USERS[@]}"; do
  IFS=':' read -r u g <<< "$entry"
  create_user "$u" "$g"
done

echo
ok "Готово. Создано $(ls "$KUBECONFIGS" | wc -l) kubeconfig-ов в $KUBECONFIGS/"
note "До запуска 02-create-roles.sh у пользователей не будет никаких прав"
note "(K8s по умолчанию запрещает всё, что явно не разрешено)."
