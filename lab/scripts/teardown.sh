#!/usr/bin/env bash
# Удаляет namespace propdev. Сам Minikube не трогает —
# для полного сноса используй: minikube delete
set -euo pipefail
echo "==> kubectl delete namespace propdev"
kubectl delete namespace propdev --ignore-not-found
echo "Готово. Minikube остался запущен. Для полного сноса: minikube delete"
