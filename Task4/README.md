# Task 4. Защита доступа к Kubernetes — RBAC

Сделано:
- `roles-table.md` — заполненная таблица ролей и групп пользователей.
- `01-create-users.sh` — namespaces + пять пользователей (x509-аутентификация
  через `CertificateSigningRequest`).
- `02-create-roles.sh` — пять `ClusterRole`-ей (две привилегированные,
  две cluster-уровня для не-привилегированных, две для namespace-уровня).
- `03-bind-roles.sh` — `ClusterRoleBinding`-и и `RoleBinding`-и на каждом
  домене.
- `manifests/` — генерируемые скриптами YAML-манифесты (для удобства диффа
  и применения отдельно).

## Запуск

```bash
cd Task4
./01-create-users.sh    # namespaces + пользователи + kubeconfigs/
./02-create-roles.sh    # ClusterRole-ы
./03-bind-roles.sh      # биндинги
```

Каждый скрипт идемпотентен: можно перезапускать без сноса.

## Проверка

Подробный список команд — в [`roles-table.md` §«Проверочные команды»](roles-table.md#проверочные-команды).
Если кратко:

```bash
# Платформенный админ: всё разрешено
kubectl --kubeconfig=kubeconfigs/dmitry.kubeconfig auth can-i '*' '*' --all-namespaces
# ИБ: видит секреты, но не правит
kubectl --kubeconfig=kubeconfigs/vera.kubeconfig auth can-i get secrets -n sales
kubectl --kubeconfig=kubeconfigs/vera.kubeconfig auth can-i create pods -n sales
# Sales-разработчик: только в своём namespace
kubectl --kubeconfig=kubeconfigs/carol.kubeconfig auth can-i create deployments -n sales
kubectl --kubeconfig=kubeconfigs/carol.kubeconfig auth can-i create deployments -n tenant
```

## Идея модели в одном абзаце

Связываем биндинги по **группам**, а группа кодируется в поле `O`
сертификата пользователя. Это позволяет управлять составом групп извне K8s
(в реальности — через корпоративный IdP), не трогая RBAC.

Привилегированных ролей строго две — платформенный админ и аудитор ИБ.
Все остальные либо ограничены одним доменом (через `RoleBinding` в
namespace), либо имеют только инфраструктурные/просмотровые права на
весь кластер. Доступ к секретам отделён от просмотра, доступ к RBAC —
отделён от всех остальных прав.

Это закрывает контроли **K8S-01** и **K8S-06** из [Task 2](../Task2/README.md),
а доменная сегментация — основу для **NET-T3-01** из [Task 3](../Task3/README.md).

## Снос (необязательно)

```bash
# Удалить созданные RBAC и kubeconfig'и
kubectl delete clusterrolebinding -l managed-by=task4-rbac
kubectl delete rolebinding -A -l managed-by=task4-rbac
kubectl delete clusterrole -l managed-by=task4-rbac
rm -rf kubeconfigs .work
# namespaces по умолчанию НЕ удаляются (могут быть полезны для следующих заданий).
```
