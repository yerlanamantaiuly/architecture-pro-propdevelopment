# Task 5. Управление трафиком внутри кластера Kubernetes

Реализует изоляцию между парами сервисов в одном namespace с помощью
`NetworkPolicy`. Закрывает контроли `NET-02` и `K8S-02` из
[Task 2](../Task2/README.md) и принцип сегментации `NET-T3-01` из
[Task 3](../Task3/README.md).

## Артефакты

| Файл | Что внутри |
| ---- | ---------- |
| `services.yaml` | Namespace `net-lab` и четыре nginx-пода с метками `role=front-end / back-end-api / admin-front-end / admin-back-end-api` плюс соответствующие Service-ы |
| `non-admin-api-allow.yaml` | Пять NetworkPolicy: default-deny ingress + четыре парные allow-политики |
| `README.md` | Этот документ |

## Целевая матрица трафика

|                          | → front-end | → back-end-api | → admin-front-end | → admin-back-end-api |
| ------------------------ | :---------: | :------------: | :---------------: | :------------------: |
| **front-end**            | —           | ✅             | ❌                 | ❌                    |
| **back-end-api**         | ✅          | —              | ❌                 | ❌                    |
| **admin-front-end**      | ❌          | ❌             | —                  | ✅                    |
| **admin-back-end-api**   | ❌          | ❌             | ✅                 | —                     |
| **прочие поды (test)**   | ❌          | ❌             | ❌                 | ❌                    |

Логика:
- Чтобы запретить всё неявно — добавили `default-deny-ingress` на весь
  namespace.
- Чтобы разрешить **обе стороны** каждой пары — для каждой роли-цели создан
  отдельный NetworkPolicy с правилом `from` соответствующей второй роли.
  NetworkPolicy — **stateful**, поэтому ответный трафик автоматически проходит,
  отдельные egress-правила не нужны.

## ⚠️ Важно: нужен CNI с поддержкой NetworkPolicy

Minikube по умолчанию ставит **kindnet** (или bridge) — они **не enforce**
NetworkPolicy. Манифест применится, но фактически ничего не заблокирует.

Чтобы политики реально работали, нужно поднять кластер с Calico или Cilium:

```bash
minikube delete                                                      # сносим текущий
minikube start --driver=docker --cni=calico --cpus=4 --memory=6g --force
```

После рестарта Calico ставится автоматически вместо kindnet, и NetworkPolicy
начинает работать.

> 💡 Альтернатива без сноса (если важно сохранить состояние кластера):
> установить Calico на существующий кластер через tigera-operator. Это
> сложнее и менее предсказуемо. Для лабы предпочтительнее `minikube delete`.

## Применение

```bash
cd Task5
kubectl apply -f services.yaml
kubectl wait --for=condition=Ready pod --all -n net-lab --timeout=120s
kubectl apply -f non-admin-api-allow.yaml

# Что получили
kubectl get pods,svc,networkpolicy -n net-lab
```

## Проверка трафика

Самый надёжный способ — поднять долгоживущие пробники с нужными метками,
а проверять трафик через `kubectl exec`. Так image pull не съедает таймаут
теста, как это бывает с `kubectl run --rm`.

```bash
# 1. Поднимаем три пробника: с ролью front-end, с ролью admin-front-end и без роли
for role in front-end admin-front-end none; do
  args="--labels=purpose=probe"
  [[ "$role" != "none" ]] && args="$args,role=$role"
  kubectl run "probe-$role" -n net-lab --image=alpine $args --restart=Never \
    --command -- sleep 600
done
kubectl wait pod -n net-lab -l purpose=probe --for=condition=Ready --timeout=60s

# 2. Гоняем матрицу: ожидаемое сравниваем с фактом
check() {
  local pod="$1" target="$2" expect="$3" label="$4"
  if kubectl exec -n net-lab "$pod" -- wget -qO- --timeout=3 "$target" >/dev/null 2>&1
  then got=OK; else got=BLOCKED; fi
  printf "%s %-45s expect=%s got=%s\n" \
    "$([[ $got == $expect ]] && echo ✓ || echo ✗)" "$label" "$expect" "$got"
}

check probe-front-end       http://back-end-api        OK       "front-end → back-end-api"
check probe-front-end       http://admin-back-end-api  BLOCKED  "front-end → admin-back-end-api"
check probe-admin-front-end http://admin-back-end-api  OK       "admin-front-end → admin-back-end-api"
check probe-admin-front-end http://back-end-api        BLOCKED  "admin-front-end → back-end-api"
check probe-none            http://back-end-api        BLOCKED  "no-role → back-end-api"
check probe-none            http://admin-back-end-api  BLOCKED  "no-role → admin-back-end-api"
check probe-none            http://front-end           BLOCKED  "no-role → front-end"

# 3. Снос пробников
kubectl delete pod -n net-lab -l purpose=probe --grace-period=0 --force
```

Проверено на Calico CNI — все 7 ожидаемых результатов сошлись.

### Эквивалент из задания

В шаблоне задания предложен такой однострочник:

```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh
/ # wget -qO- --timeout=2 http://back-end-api
```

Он тоже работает, но требует интерактивной сессии и того, чтобы образ
alpine уже был на ноде (иначе таймаут wget сработает раньше, чем pod
успеет стартовать). При первом запуске лучше использовать форму выше.

## Чистка

```bash
kubectl delete namespace net-lab    # сносит всё, что относится к Task 5
```
