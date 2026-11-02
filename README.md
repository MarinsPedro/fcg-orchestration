# FCG - Orquestracao one-click DEV

Infraestrutura local de **7 APIs + 4 Workers + 7 migration jobs**, com PostgreSQL 17 (7 bancos) e RabbitMQ com plugin de mensagens atrasadas. Docker Compose e Kubernetes executam de forma independente.

**Configuracao centralizada:** os `appsettings*.json` dos microsservicos estao vazios. Toda configuracao de execucao fica nos arquivos `config/compose-*.env` e `config/k8s-*.env`; as credenciais sao injetadas via `runtime/` ou Secrets. Veja [CONFIGURACAO-CENTRALIZADA.md](CONFIGURACAO-CENTRALIZADA.md).

## Comandos publicos (PowerShell/Windows)

```powershell
.\FCG-COMPOSE.cmd       # constroi e inicia somente Docker Compose
.\FCG-K8S.cmd           # constroi e inicia somente Kubernetes

.\FCG-COMPOSE.cmd -NoBuild
.\FCG-K8S.cmd -NoBuild
.\FCG-COMPOSE.cmd -Status
.\FCG-K8S.cmd -Status
.\FCG-K8S.cmd -StopAccess  # encerra somente os port-forwards proprios
```

Execute **dentro de `fcg-orchestration`**. Nunca rode os scripts com o contexto Kubernetes de producao: eles aceitam somente `docker-desktop` ou `kind-fcg`.

| API | Compose | K8s (port-forward) |
|---|---|---|
| Identity | 5081 | 5181 |
| Payments | 5082 | 5182 |
| Library | 5083 | 5183 |
| Catalog | 5084 | 5184 |
| Promotions | 5085 | 5185 |
| Orders | 5086 | 5186 |
| Notifications | **5087** | **5187** |

Todas as portas HTTP acima usam `http://127.0.0.1:<porta>/swagger` (quando Swagger habilitado). O health check e `/health/ready`. RabbitMQ Management: Compose `15672`, K8s `15673`. PostgreSQL: Compose `5432`, K8s `55432`, usuario `fcg_admin`.

## Onde ficam os arquivos

```text
fcg-orchestration/
  FCG-COMPOSE.cmd, FCG-K8S.cmd  # unicos comandos principais
  docker-compose.yml            # 20 servicos Compose (2 infra + 7 migrations + 7 APIs + 4 Workers)
  config/                       # 18 arquivos compose-*.env + 18 k8s-*.env (NAO sensiveis)
  scripts/                      # Common.ps1, FCG-Compose.ps1, FCG-K8S.ps1, Access.ps1
  k8s/                          # namespace + infraestrutura compartilhada
  rabbitmq/                     # imagem com plugin delayed-message
  runtime/                      # GERADO localmente, ignorado no Git: senhas, SQL, log, tunnels
../fcg-<nome>-service/k8s/       # manifests apenas daquele servico
```

### ConfigMap e Secret nao sao arquivos estaticos

- O instalador cria o ConfigMap `fcg-notifications-worker-config` a partir de `config/k8s-notifications-worker.env` por `kubectl create configmap --from-env-file`. Sao **18 ConfigMaps por processo** (7 APIs, 4 Workers, 7 migrations).
- Os Secrets `fcg-dev-secrets` e `fcg-domain-dev-secrets` sao criados a partir de valores gerados/recuperados em `runtime/k8s.env`, e transformados em objetos Kubernetes. As aplicacoes consomem chaves via `secretKeyRef`.
- No Compose, `config/compose-*.env` configura cada processo e `runtime/compose.env` fornece as senhas para interpolacao no YAML.
- `__` em variaveis de ambiente representa `:` na configuracao hierarquica .NET: `RabbitMq__Host` equivale a `RabbitMq:Host`.

```powershell
kubectl get configmap,secret -n fcg
kubectl get configmap fcg-notifications-worker-config -n fcg -o yaml
kubectl describe secret fcg-domain-dev-secrets -n fcg  # mostra as CHAVES, nao os valores
kubectl get deployment notifications-worker -n fcg -o yaml
```

## Credenciais DEV

Em instalacao nova, `POSTGRES_ADMIN_PASSWORD`, todos os `PG_*_PASSWORD`, `RABBITMQ_PASSWORD`, `IDENTITY_ADMIN_PASSWORD`, `WEB_BFF_SECRET` e `ORDERS_CLIENT_SECRET` recebem **`Fiap@123456`**. Usuario do broker: `fcg`.

**Senha fixa apenas para demonstracao academica.** Secret Kubernetes nao e criptografia automatica; nao publique `runtime/`, nao use esses valores fora de DEV. Para operacoes reais utilize gerenciador de segredos, credenciais unicas e TLS.