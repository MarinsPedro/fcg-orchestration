# Instalacao do FCG Fase 2 (Windows + Docker Desktop)

## 1. Pre-requisitos

- Windows PowerShell 5.1 ou PowerShell 7, Docker Desktop ligado em Linux containers.
- Docker Compose v2 moderno (suporte a `additional_contexts` e `docker compose up --wait`).
- Kubernetes Docker Desktop habilitado (contexto `docker-desktop`) **ou** Kind instalado no PATH (script cria `kind-fcg` se nenhum cluster ativo).
- `kubectl` no PATH; acesso a internet para Docker Hub, Microsoft .NET e nuget.org.
- Oito repositorios lado a lado: 7 microsservicos + `fcg-dotnet-building-blocks`; `fcg-orchestration` ao lado deles.

## 2. Compose - um comando

```powershell
cd D:\Dev\FCG-Fase2\fcg-orchestration
.\FCG-COMPOSE.cmd
```

1. Verifica o Docker Desktop e as credenciais em `runtime/compose.env`; se nao existirem e nao houver volume preexistente, cria `Fiap@123456`.
2. Gera `runtime/compose/init/01-create-databases.sql` para sete bancos; sobe o PostgreSQL e garante papeis/bancos ausentes.
3. Compila as imagens dos sete projetos com BuildingBlocks local e fontes NuGet publicas.
4. Sobe RabbitMQ com plugin `rabbitmq_delayed_message_exchange`; o MassTransit declara os endpoints de mensageria, e executa sete migrations.
5. Inicializa o cliente OAuth2 `web-bff` e garante `orders-api` no Identity.
6. Inicia 7 APIs + 4 Workers e confere `/health/ready` das APIs.

Variantes: `-NoBuild` reaproveita imagens anteriores; `-Status` consulta estado.

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
| PostgreSQL | `localhost:5432` | `localhost:55432` |

Usuario RabbitMQ `fcg`, usuario banco administrador `fcg_admin`. **Senha DEV instalada do zero: `Fiap@123456`**; cliente OAuth2 `web-bff` / `orders-api` usa `Fiap@123456` como client secret. `runtime/compose.env` e `runtime/k8s.env` sao as fontes de verdade de cada ambiente.

## 5. Conferir depois de instalar

```powershell
.\FCG-COMPOSE.cmd -Status
.\FCG-K8S.cmd -Status
kubectl get pods,deployments,jobs,pvc -n fcg
kubectl get configmaps,secrets -n fcg
kubectl logs -n fcg deployment/notifications-worker --tail=100
docker compose --env-file runtime/compose.env logs --tail=100 notifications-worker
```

**Atenção:** o `docker compose` manual acima pode ser executado dentro da pasta `fcg-orchestration`, onde esta o YAML. O instalador gerencia o projeto e o arquivo de env automaticamente.

## 6. Atualizar uma instalação antiga

O script adiciona `PG_NOTIFICATIONS_PASSWORD` aos `.env` privados ja existentes, **sem trocar as senhas antigas**; cria apenas o novo banco/papel onde estiver ausente. Se voce quer mesmo a senha fixa em todos os bancos antigos, nao altere os `.env` de forma isolada: isso causaria erro de autenticacao. Faça backup e configure um ambiente realmente novo ou realize uma rotacao coordenada das senhas no PostgreSQL, RabbitMQ e Identity.

Nenhum script faz `down -v`, `kubectl delete pvc`, `reset` ou limpeza destrutiva.
