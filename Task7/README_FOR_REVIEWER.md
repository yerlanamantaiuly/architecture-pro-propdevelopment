# Task 7. Безопасность контейнеров: PodSecurity Admission + OPA Gatekeeper

Закрывает контроли `K8S-03`, `K8S-04`, `K8S-07` из
[Task 2](../Task2/README.md) и относится к политике `pod-security` из
[Task 3](../Task3/README.md), которая нужна для безопасного
развёртывания `smart-home-bridge-app`.

## Что внутри

| Путь | Содержимое |
| ---- | ---------- |
| `01-create-namespace.yaml` | namespace `audit-zone` с метками PSA restricted (enforce/audit/warn) |
| `insecure-manifests/` | три pod-манифеста, заведомо нарушающих профиль: privileged, hostPath, root |
| `secure-manifests/` | те же поды, приведённые в соответствие с restricted + дополнительными требованиями (readOnlyRootFilesystem, allowPrivilegeEscalation: false, capabilities drop ALL, seccompProfile RuntimeDefault) |
| `gatekeeper/constraint-templates/` | три ConstraintTemplate'а с Rego-логикой запретов |
| `gatekeeper/constraints/` | экземпляры constraint'ов с `enforcementAction: deny` и областью применения (`audit-zone`, `gatekeeper-test`) |
| `verify/verify-admission.sh` | проверка PSA-слоя в `audit-zone` |
| `verify/validate-security.sh` | проверка Gatekeeper-слоя в `gatekeeper-test` (без PSA-меток) |
| `audit-policy.yaml` | расширение audit-policy из Task 6 на ресурсы Gatekeeper |

## Что показывают два namespace-а

- **`audit-zone`** — PSA restricted **+** Gatekeeper constraints.
  Insecure-под отклоняется уже PSA, до Gatekeeper'а очередь не доходит.
  Это нормальная боевая конфигурация: два слоя защиты, ранний отказ.

- **`gatekeeper-test`** — БЕЗ PSA-меток. Сюда добраться можно только
  через Gatekeeper. Эта зона существует только для verify-теста,
  чтобы показать: Gatekeeper-constraints РАБОТАЮТ САМИ ПО СЕБЕ, без PSA.

Это даёт чёткое разделение ответственности: PSA закрывает базовый
стандарт (профили restricted/baseline), Gatekeeper закрывает custom-логику
(в нашем случае — например, обязательный `readOnlyRootFilesystem`,
которого нет в стандартном профиле PSA).

## Запуск (полный workflow)

```bash
# 1. Установить Gatekeeper (если ещё не стоит)
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.16.3/deploy/gatekeeper.yaml
kubectl -n gatekeeper-system wait deploy --all --for=condition=Available --timeout=180s

# 2. Применить constraint templates, затем constraints (10с пауза, чтобы CRD зарегистрировались)
kubectl apply -f Task7/gatekeeper/constraint-templates/
sleep 10
kubectl apply -f Task7/gatekeeper/constraints/

# 3. Создать namespace audit-zone с PSA restricted
kubectl apply -f Task7/01-create-namespace.yaml

# 4. Прогон проверок
./Task7/verify/verify-admission.sh
./Task7/verify/validate-security.sh
```

Оба скрипта возвращают exit 0 при ожидаемом поведении.

## Содержание правил Gatekeeper

### `k8spspprivilegedcontainer`
Запрещает `securityContext.privileged: true` для любого контейнера
(включая `initContainers`).

### `k8spsphostpath`
Запрещает любые `volumes[].hostPath` (любой путь, не важно `/` или
конкретный каталог).

### `k8spsprunasnonroot`
Сразу два требования:
1. `runAsNonRoot: true` хотя бы на уровне пода либо каждого контейнера,
   с дополнительным запретом явного `runAsUser: 0`.
2. `readOnlyRootFilesystem: true` на каждом контейнере.

Эти правила гарантируют профиль «минимум-привилегий», который PSA
restricted покрывает не полностью (readOnlyRootFilesystem в стандартном
профиле — рекомендация, а не enforcement; мы делаем его обязательным).

## Что подтвердил тест

Из последнего прогона verify-скриптов:

```
PSA admission работает как задумано
  insecure отклонено: 3 / 3
  secure   принято:    3 / 3
OPA Gatekeeper работает как задумано
  Gatekeeper отверг insecure: 3 / 3
  secure прошли:               3 / 3
```

Сообщения об отказе содержат конкретные причины (например, для
privileged-pod: `must not set securityContext.privileged=true`,
`must set securityContext.allowPrivilegeEscalation=false`, `must set
capabilities.drop=["ALL"]`, и т.д.), что упрощает диагностику для
разработчика.

## Связь с другими заданиями

- **Task 4 (RBAC)** определяет, кто может создавать поды. Task 7
  определяет, **какие именно** поды могут быть созданы. Это две
  ортогональные оси контроля.
- **Task 6 (audit)** регистрирует попытки нарушения политик (даже
  если они отклоняются на admission). Здесь `audit-policy.yaml`
  расширен на ресурсы Gatekeeper, чтобы любые изменения
  constraint-объектов оставались в аудит-логе.
- **Task 3** называет `Smart Home Bridge`, который будет
  деплоиться в namespace `smart-home` тоже с PSA restricted +
  Gatekeeper. Манифесты bridge'а должны соответствовать тем же
  стандартам, что и `secure-manifests/` здесь.
