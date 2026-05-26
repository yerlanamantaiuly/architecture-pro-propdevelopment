# Таблица ролей и групп пользователей K8s

Соответствие между организационной структурой PropDevelopment и моделью
RBAC в Kubernetes. Все идентификаторы здесь — рабочие, ровно эти имена
используются в скриптах `01-create-users.sh`, `02-create-roles.sh`,
`03-bind-roles.sh`.

## Принципы выбора

1. **Привилегированные роли** даём только тем, кому они действительно
   нужны: платформенным админам и единственному ИБ-специалисту компании.
2. **Минимум 2 непривилегированные группы** (требование задания):
   - `prop-cluster-viewers` — только просмотр ресурсов кластера;
   - `prop-cluster-configurers` — настройка инфраструктурных ресурсов
     (Ingress, StorageClass, namespaces), без доступа к секретам и RBAC.
3. **Разграничение по орг.структуре**: для каждого домена компании
   (Продажи, ЖКУ, Финансы, Дата) создаём отдельный namespace и пары
   `devs / managers` со своими RoleBinding-ами. Это закрывает требование
   «разграничить доступ к ресурсам кластера, исходя из организационной
   структуры».
4. **Намespace под Smart Home** (`smart-home`) выделен отдельно, чтобы
   реализовать сетевую изоляцию из [Task 3](../Task3/README.md), §4.7.

## Namespace-ы PropDevelopment

| Namespace | Домен | Системы (из Task 2) |
| --------- | ----- | ------------------- |
| `sales` | Продажи | `client-mart-app`, `client-tour-app`, `client-crm-app`, `auth-service-1`, витрина продаж |
| `tenant` | ЖКУ | `tenant-core-app`, CRM собственников, витрина ЖКУ |
| `smart-home` | ЖКУ (новый, Task 3) | `smart-home-bridge-app`, `webhook-receiver`, `smart-home-db` |
| `finance` | Финансы | `accountant-service-1`, AD финансового домена |
| `data` | Дата | DWH, BI, отчётность |

## Таблица ролей

| # | Роль (K8s) | Группа пользователей | Привилегированная | Объём | Полномочия | Тип ресурса |
| --- | ---------- | -------------------- | :---------------: | ----- | ---------- | ----------- |
| 1 | `cluster-admin` (built-in) | `prop-platform-admins` | ✅ | весь кластер | Полный доступ ко всем ресурсам, включая RBAC, секреты, конфигурации API-сервера | ClusterRole + ClusterRoleBinding |
| 2 | `prop-security-auditor` | `prop-security-officers` | ✅ | весь кластер | Read-only по всем ресурсам **включая secrets**. Не может вносить изменения — только аудит и расследование инцидентов | ClusterRole + ClusterRoleBinding |
| 3 | `prop-cluster-viewer` | `prop-cluster-viewers` | ❌ | весь кластер | Read-only по всем ресурсам **кроме secrets**. Используется руководителями, бизнес-аналитиками с кросс-доменным интересом | ClusterRole + ClusterRoleBinding |
| 4 | `prop-cluster-configurer` | `prop-cluster-configurers` | ❌ | весь кластер | Управляет инфраструктурными ресурсами: создание/удаление namespaces, StorageClass, IngressClass, CSIDriver, PriorityClass. **Не имеет** доступа к secrets и RBAC. Группа DevOps-инженеров | ClusterRole + ClusterRoleBinding |
| 5 | `prop-namespace-developer` | `prop-domain-devs-<domain>` | ❌ | один namespace | CRUD по Deployment, StatefulSet, Service, ConfigMap, Pod, Job. Чтение событий и логов. **Не может** читать/писать secrets, RBAC, NetworkPolicy | Role + RoleBinding (на каждый namespace домена) |
| 6 | `prop-namespace-viewer` | `prop-domain-managers-<domain>` | ❌ | один namespace | Read-only в namespace, **без секретов**. Группа менеджеров операционной команды | Role + RoleBinding |

## Соответствие групп организационной структуре PropDevelopment

| Группа K8s | Реальная роль в компании | Кто из задания |
| ---------- | ------------------------ | -------------- |
| `prop-platform-admins` | Платформенные инженеры, ответственные за инфраструктуру кластера | Не описана явно в кейсе, но необходима как операционная команда |
| `prop-security-officers` | Специалист по информационной безопасности | Прямо упомянут в кейсе («Специалист по ИБ один на всю компанию») |
| `prop-cluster-viewers` | Бизнес-аналитики и руководители команд, которым нужен кросс-доменный обзор | Например, BA из домена Дата, владельцы продуктов |
| `prop-cluster-configurers` | DevOps-инженеры (есть в каждой функциональной команде) | Прямо упомянуты в кейсе: «DevOps-инженера» |
| `prop-domain-devs-sales` | Разработчики домена Продажи | Функциональная команда продуктов: витрина, mart-app, tour-app, crm-app |
| `prop-domain-devs-tenant` | Разработчики домена ЖКУ | Функциональная команда `tenant-core-app`, CRM собственников |
| `prop-domain-devs-finance` | Разработчики домена Финансы | Функциональная команда `accountant-service-1` |
| `prop-domain-devs-data` | Дата-инженеры | Функциональная команда DWH, BI, отчётности |
| `prop-domain-managers-sales` | Менеджеры продаж | Операционная команда домена Продажи |
| `prop-domain-managers-tenant` | Менеджеры УК | Операционная команда домена ЖКУ |
| `prop-domain-managers-finance` | Бухгалтеры | Прямо упомянут в C4-диаграмме как актор «Бухгалтер» |
| `prop-domain-managers-data` | Аналитики BI | Прямо упомянут в C4-диаграмме как актор «Аналитик BI» |

## Пользователи, создаваемые в демонстрации

Минимум — два, по требованию задания. Создаём **пять**, чтобы покрыть все
ключевые роли и показать, что модель работает на всех уровнях.

| Пользователь | Группа (`O` в сертификате) | Роль | Что должен мочь |
| ------------ | --------------------------- | ---- | --------------- |
| `dmitry`  | `prop-platform-admins`  | `cluster-admin` | Всё в кластере |
| `vera`    | `prop-security-officers` | `prop-security-auditor` | Читать всё, в т.ч. секреты, во всех namespace; ничего не менять |
| `alice`   | `prop-cluster-viewers`  | `prop-cluster-viewer` | Видеть деплойменты/поды/сервисы в любом namespace; **не** видеть секреты |
| `bob`     | `prop-cluster-configurers` | `prop-cluster-configurer` | Создавать/удалять namespace и StorageClass; **не** трогать RBAC и секреты |
| `carol`   | `prop-domain-devs-sales` | `prop-namespace-developer` в `sales` | Деплоить в `sales`; **не** иметь доступа к `tenant`, `finance`, `data`, `smart-home` |

## Проверочные команды

После запуска трёх скриптов модель проверяется так:

```bash
# Платформенный админ может всё
kubectl --kubeconfig=Task4/kubeconfigs/dmitry.kubeconfig get nodes
kubectl --kubeconfig=Task4/kubeconfigs/dmitry.kubeconfig auth can-i '*' '*' --all-namespaces  # yes

# ИБ может читать секреты, но не править
kubectl --kubeconfig=Task4/kubeconfigs/vera.kubeconfig auth can-i get secrets -n sales         # yes
kubectl --kubeconfig=Task4/kubeconfigs/vera.kubeconfig auth can-i create pods -n sales         # no

# Viewer видит ресурсы, но без секретов
kubectl --kubeconfig=Task4/kubeconfigs/alice.kubeconfig auth can-i get pods -n sales           # yes
kubectl --kubeconfig=Task4/kubeconfigs/alice.kubeconfig auth can-i get secrets -n sales        # no

# Configurer создаёт namespaces, но не RBAC
kubectl --kubeconfig=Task4/kubeconfigs/bob.kubeconfig auth can-i create namespaces             # yes
kubectl --kubeconfig=Task4/kubeconfigs/bob.kubeconfig auth can-i create rolebindings -n sales  # no

# Sales-разработчик работает только в sales
kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i create deployments -n sales  # yes
kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i create deployments -n tenant # no
kubectl --kubeconfig=Task4/kubeconfigs/carol.kubeconfig auth can-i get secrets -n sales         # no
```
