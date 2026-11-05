# FCG - Orquestracao one-click DEV

Infraestrutura local de **7 APIs + 4 Workers + 7 migration jobs**, com PostgreSQL 17 (7 bancos) e RabbitMQ com plugin de mensagens atrasadas. Docker Compose e Kubernetes executam de forma independente.

**Configuracao centralizada:** os `appsettings*.json` dos microsservicos estao vazios. No Compose, cada API, Worker e Migrations possui um arquivo versionado em `config/compose/<servico>/`. O Kubernetes continua usando ConfigMaps e Secrets gerados pelo instalador. Veja [CONFIGURACAO-CENTRALIZADA.md](CONFIGURACAO-CENTRALIZADA.md).

## Docker Compose - um comando

```powershell
docker compose up --build
```

O Compose aguarda PostgreSQL e RabbitMQ; cada migration cria seu database logico quando necessario, aplica o schema e somente então libera sua API ou Worker. Todos os processos .NET executam com o usuario nao-root `APP_UID` (`1654`), e as dependencias entre APIs aguardam `/health/ready` retornar sucesso.

## Kubernetes local (PowerShell/Windows)

```powershell
.\FCG-K8S.cmd           # constroi e inicia somente Kubernetes

.\FCG-K8S.cmd -NoBuild
.\FCG-K8S.cmd -Status
.\FCG-K8S.cmd -StopAccess  # encerra somente os port-forwards proprios
```

Execute **dentro de `fgc-orchestrator-service`**. Nunca rode o script com o contexto Kubernetes de producao: ele aceita somente `docker-desktop` ou `kind-fcg`.

| API | Compose | K8s (port-forward) |
|---|---|---|
| Identity | 5081 | 5181 |
| Payments | 5082 | 5182 |
| Library | 5083 | 5183 |
| Catalog | 5084 | 5184 |
| Promotions | 5085 | 5185 |
| Orders | 5086 | 5186 |
| Notifications | **5087** | **5187** |

Todas as portas HTTP acima usam `http://127.0.0.1:<porta>/swagger` (quando Swagger habilitado). O health check e `/health/ready`. RabbitMQ Management: Compose `15672`, K8s `15673`. PostgreSQL: Compose `5433` com `postgres/postgres`; K8s `55432` com usuario `fcg_admin`.

## Onde ficam os arquivos

```text
fgc-orchestrator-service/
  FCG-K8S.cmd                   # instalador do Kubernetes local
  docker-compose.yml            # infra + 7 migrations + 7 APIs + 4 Workers
  config/compose/               # arquivos versionados de API, Worker, Migrations e infraestrutura
  config/k8s-*.env              # 18 arquivos nao sensiveis usados como ConfigMaps
  scripts/                      # Common.ps1, FCG-K8S.ps1, Access.ps1
  k8s/                          # namespace + infraestrutura compartilhada
  rabbitmq/                     # imagem com plugin delayed-message
  runtime/                      # GERADO localmente, ignorado no Git: senhas, SQL, log, tunnels
../fcg-<nome>-service/k8s/       # manifests apenas daquele servico
```

### ConfigMap e Secret nao sao arquivos estaticos

- O instalador cria o ConfigMap `fcg-notifications-worker-config` a partir de `config/k8s-notifications-worker.env` por `kubectl create configmap --from-env-file`. Sao **18 ConfigMaps por processo** (7 APIs, 4 Workers, 7 migrations).
- Os Secrets `fcg-dev-secrets` e `fcg-domain-dev-secrets` sao criados a partir de valores gerados/recuperados em `runtime/k8s.env`, e transformados em objetos Kubernetes. As aplicacoes consomem chaves via `secretKeyRef`.
- No Compose, cada processo recebe um unico `env_file` versionado em `config/compose/<servico>/`. Esses arquivos incluem as credenciais fixas de demonstracao local.
- `__` em variaveis de ambiente representa `:` na configuracao hierarquica .NET: `RabbitMq__Host` equivale a `RabbitMq:Host`.

```powershell
kubectl get configmap,secret -n fcg
kubectl get configmap fcg-notifications-worker-config -n fcg -o yaml
kubectl describe secret fcg-domain-dev-secrets -n fcg  # mostra as CHAVES, nao os valores
kubectl get deployment notifications-worker -n fcg -o yaml
```

## Credenciais DEV

Os arquivos versionados do Compose usam PostgreSQL `postgres/postgres`, RabbitMQ `fcg/Fiap@123456` e `Fiap@123456` para os segredos DEV de Identity. O Kubernetes preserva o fluxo de Secrets separado.

**Senha fixa apenas para demonstracao academica.** Secret Kubernetes nao e criptografia automatica; nao publique `runtime/`, nao use esses valores fora de DEV. Para operacoes reais utilize gerenciador de segredos, credenciais unicas e TLS.
