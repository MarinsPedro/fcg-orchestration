# Instalacao do FCG Fase 2 (Windows + Docker Desktop)

## 1. Pre-requisitos

- Windows PowerShell 5.1 ou PowerShell 7, Docker Desktop ligado em Linux containers.
- Docker Compose v2 moderno (suporte a `additional_contexts` e `docker compose up --wait`).
- Kubernetes Docker Desktop habilitado (contexto `docker-desktop`) **ou** Kind instalado no PATH (script cria `kind-fcg` se nenhum cluster ativo).
- `kubectl` no PATH; acesso a internet para Docker Hub, Microsoft .NET e nuget.org.
- Oito repositorios lado a lado: 7 microsservicos + `fcg-dotnet-building-blocks`; `fcg-orchestration` ao lado deles.

## 2. Compose - um comando

```powershell
cd D:\Dev\FCG-Fase2\fgc-orchestrator-service
docker compose up --build
```

1. Compila as imagens dos sete projetos com BuildingBlocks local e fontes NuGet publicas.
2. Sobe PostgreSQL com `postgres/postgres` e RabbitMQ com o plugin `rabbitmq_delayed_message_exchange`, usando os arquivos versionados em `config/compose/`.
3. Executa sete migrations; cada uma cria seu database logico quando necessario e aplica o schema. O Identity inicializa o cliente OAuth2 configurado para desenvolvimento.
4. Inicia 7 APIs + 4 Workers somente depois das dependencias concluirem com sucesso.

Para reutilizar imagens ja construidas, execute `docker compose up --no-build`. Para consultar o estado, execute `docker compose ps --all`.

## 3. Kubernetes - outro comando, independente do Compose

```powershell
.\FCG-K8S.cmd
```

1. Verifica o contexto local Kubernetes, cria namespace `fcg`.
2. Lê/gera `runtime/k8s.env` com senhas DEV, cria `fcg-dev-secrets` e `fcg-domain-dev-secrets`.
3. Cria 18 ConfigMaps de processos a partir dos `.env` não sensíveis de `config/`.
4. Compila imagens (nao precisa iniciar Compose) e as marca `fcg-<nome>:local`; carrega no Kind quando detectado.
5. Cria PostgreSQL e RabbitMQ como StatefulSets, com PVCs independentes do Compose. Valida plugin atrasado.
6. Cria sete bancos/usuarios e executa sete Jobs de migrations (incluindo Notifications); o MassTransit declara os endpoints ao iniciar os servicos.
7. Aplica os manifests de cada projeto em `fcg-<service>-service/k8s/`, valida 11 Deployments, abre port-forwards e dashboard local.

O K8s pode existir sem nenhum container do Compose. Se o Docker Desktop nao tiver Kubernetes ativo e Kind nao estiver instalado, o instalador para com instrucoes de dependencia.

## 4. Acessos e credenciais

| Recurso | Docker Compose | Kubernetes |
|---|---|---|
| Identity | `localhost:5081/swagger` | `localhost:5181/swagger` |
| Payments | 5082 | 5182 |
| Library | 5083 | 5183 |
| Catalog | 5084 | 5184 |
| Promotions | 5085 | 5185 |
| Orders | 5086 | 5186 |
| Notifications | **5087** | **5187** |
| RabbitMQ | `localhost:15672` | `localhost:15673` |
| PostgreSQL | `localhost:5433` | `localhost:55432` |

Os `env_file` versionados do Compose usam PostgreSQL `postgres/postgres`, RabbitMQ `fcg/Fiap@123456` e segredos Identity `Fiap@123456`. Esses valores sao exclusivamente academicos. No Kubernetes, `runtime/k8s.env` continua sendo a fonte de verdade.

## 5. Conferir depois de instalar

```powershell
docker compose ps --all
.\FCG-K8S.cmd -Status
kubectl get pods,deployments,jobs,pvc -n fcg
kubectl get configmaps,secrets -n fcg
kubectl logs -n fcg deployment/notifications-worker --tail=100
docker compose logs --tail=100 notifications-worker
```

**Atenção:** execute o `docker compose` dentro da pasta `fgc-orchestrator-service`, onde esta o YAML. Os arquivos de ambiente do Compose ja estao versionados em `config/compose/`.

## 6. Atualizar uma instalação antiga

O instalador do Kubernetes adiciona `PG_NOTIFICATIONS_PASSWORD` aos `.env` privados ja existentes, **sem trocar as senhas antigas**; cria apenas o novo banco/papel onde estiver ausente. Se voce quer mesmo a senha fixa em todos os bancos antigos, nao altere os `.env` de forma isolada: isso causaria erro de autenticacao. Faça backup e configure um ambiente realmente novo ou realize uma rotacao coordenada das senhas no PostgreSQL, RabbitMQ e Identity.

Nenhum script faz `down -v`, `kubectl delete pvc`, `reset` ou limpeza destrutiva.
