# Arquitetura da orquestracao FCG

## Sete microsservicos

| Dominio | API | Worker | Banco |
|---|---|---|---|
| Identity | identity-api | - | fcg_identity |
| Payments | payments-api | payments-worker | fcg_payments |
| Library | library-api | library-worker | fcg_library |
| Catalog | catalog-api | - | fcg_catalog |
| Promotions | promotions-api | - | fcg_promotions |
| Orders | orders-api | orders-worker (saga MassTransit) | fcg_orders |
| Notifications | notifications-api | notifications-worker (5 consumers) | fcg_notifications |

**Fisicamente:** um PostgreSQL por ambiente com sete bancos logicos/usuarios por dominio, e um RabbitMQ por ambiente; cada API e Worker e um processo/container separado. Compose e K8s nao compartilham PVCs, volumes ou credenciais.

## Distribuicao dos manifests K8s

- `fcg-orchestration/k8s/`: namespace, StatefulSets de Postgres/RabbitMQ.
- `fcg-identity-service/k8s/`: API + migrations.
- `fcg-payments-service/k8s/`: API + Worker + migrations.
- `fcg-library-service/k8s/`: API + Worker + migrations.
- `fcg-catalog-service/k8s/`: API + migrations.
- `fcg-promotions-service/k8s/`: API + migrations.
- `fcg-orders-service/k8s/`: API + Worker + migrations.
- `fcg-notifications-service/k8s/`: API + Worker + migrations (SEM PostgreSQL duplicado).

Cada processo tem um arquivo `config/k8s-<service>-<kind>.env` versionavel, transformado automaticamente em ConfigMap; credentials e URLs contendo senhas sao geradas em Secrets. Os Deployments usam `envFrom.configMapRef` e `env.valueFrom.secretKeyRef`.

## Infraestrutura Docker Compose

O `docker-compose.yml` define 20 processos/servicos: 1 PostgreSQL, 1 RabbitMQ, 7 Jobs de migration, 7 APIs e 4 Workers. `healthcheck` e `depends_on` comandam a inicializacao. Cada migration aguarda o PostgreSQL saudavel e cria seu database logico por `MigrateAsync()` quando necessario; isso funciona no Compose DEV porque a connection string usa o usuario administrativo `postgres`. As sete APIs verificam `/health/ready`, e uma API dependente aguarda `service_healthy` em vez de apenas aguardar o inicio do processo. APIs, Workers e migrations .NET executam com o usuario nao-root `APP_UID` (`1654`). Cada processo recebe um arquivo completo e versionado em `config/compose/<servico>/`; as credenciais ali presentes sao exclusivamente academicas.

## Notifications

- `UserCreatedEvent`, `PaymentApprovedEventV1`, `PaymentRejectedEventV1`, `OrderCompletedEventV1`, `OrderFailedEventV1` possuem consumidores separados no Worker.
- O Worker utiliza cinco filas `notifications.*` com entidades RabbitMQ/MassTransit, conforme as configuracoes `RabbitMq__Topology__*`.
- O provedor atual de entrega e `LogNotificationSender`: notificacoes sao registradas/enviadas a um destino simulado (logs); nao equivale a email real entregue.
- **Limite da versao inspecionada:** encontramos `OrderCompletedEventV1` sendo publicado no Orders, mas nao encontramos publicacao de `OrderFailedEventV1` no codigo do Orders fornecido. O consumer correspondente esta preparado, mas nao pressupomos que um pedido rejeitado produz este evento.
- Nao ha importacao manual de definitions no Compose ou Kubernetes: os Workers e APIs configurados com MassTransit declaram suas proprias filas, exchanges e bindings quando iniciam. As variaveis `RabbitMq__Topology__*` sao configuracoes de cada servico, e nao um importador externo.
- O Compose espera o healthcheck do RabbitMQ antes de iniciar as APIs Identity, Payments e Orders e os Workers dependentes. No Kubernetes, o OneClick remove qualquer Job/ConfigMap legado de importacao sem excluir filas ou volumes existentes.

## Saga

O Orders processa pedido, solicita pagamento, recebe desfecho e solicita concessao da licenca/entitlement no Library. A saga utiliza `rabbitmq_delayed_message_exchange` para agendamento de mensagens atrasadas. A integracao Notifications acompanha eventos sem reverter os pedidos quando notificacoes falham.

## Separacao real

| Infraestrutura | Compose | K8s |
|---|---|---|
| APIs externas | 5081-5087 | 5181-5187 via port-forward |
| Postgres | volume Compose, porta local 5433 | StatefulSet + PVC, porta local 55432 |
| RabbitMQ | volume Compose, porta 15672 | StatefulSet + PVC, porta local 15673 |
| Segredos | credenciais DEV nos `env_file` versionados | runtime/k8s.env + Secret no namespace `fcg` |

## Integridade e limites de validação

Em 04/11/2026, o Compose atualizado foi reconstruido e iniciado com sucesso: sete migrations terminaram com codigo `0`, as sete APIs responderam `200` em `/health/ready`, e todos os processos .NET executaram com UID `1654`. Um teste isolado confirmou que `MigrateAsync()` cria o database ausente com o usuario `postgres` e falha com SQLSTATE `42501` quando o usuario nao possui `CREATEDB`. O fluxo funcional E2E completo e o ambiente Kubernetes ainda devem ser validados separadamente.
