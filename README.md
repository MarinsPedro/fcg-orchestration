 
# FCG — FIAP Cloud Games | Fase 2

Orquestração dos microsserviços do **FIAP Cloud Games (FCG)** utilizando Docker Compose e Kubernetes em ambiente local de desenvolvimento.

### Arquitetura

- **7 APIs:** Identity, Payments, Library, Catalog, Promotions, Orders e Notifications.
- **4 Workers:** Payments, Library, Orders e Notifications.
- **7 Migration Jobs:** inicialização e atualização dos bancos.
- **PostgreSQL 17:** uma instância com 7 bancos independentes.
- **RabbitMQ + MassTransit:** comunicação assíncrona entre microsserviços.

Docker Compose e Kubernetes funcionam de forma independente.

---

## 1. Docker Compose

Inicializa toda a infraestrutura, executa as migrations e sobe as APIs e Workers automaticamente.

Dentro do diretório `fcg-orchestration`, execute:

```powershell
docker compose up --build -d
```

**Comandos úteis:**

```powershell
# Consultar containers
docker compose ps

# Acompanhar logs
docker compose logs -f

# Encerrar ambiente
docker compose down
```

---

## 2. Kubernetes — OneClick

A implantação Kubernetes é automatizada por um único comando, utilizando manifests YAML organizados por microsserviço.

Dentro do diretório `fcg-orchestration`, execute:

```powershell
.\FCG-K8S.cmd
```

O instalador realiza automaticamente:

1. Build das imagens Docker.
2. Criação do namespace `fcg`.
3. Configuração dos ConfigMaps e Secrets.
4. Inicialização do PostgreSQL e RabbitMQ via StatefulSets.
5. Execução dos 7 Jobs de migrations.
6. Implantação das 7 APIs e 4 Workers via Deployments.
7. Validação dos recursos e configuração dos acessos locais.

**Comandos úteis:**

```powershell
# Executar sem reconstruir imagens
.\FCG-K8S.cmd -NoBuild

# Consultar status do ambiente
.\FCG-K8S.cmd -Status

# Encerrar port-forwards
.\FCG-K8S.cmd -StopAccess
```

O instalador é destinado exclusivamente ao Kubernetes local, utilizando `docker-desktop` ou `kind-fcg`.

---

## 3. Estrutura do projeto

```text
fcg-orchestration/
├── docker-compose.yml       # Docker Compose
├── FCG-K8S.cmd              # Kubernetes OneClick
├── config/
│   ├── compose/             # Configurações Compose
│   └── k8s-*.env            # Configurações Kubernetes
├── k8s/                     # Infraestrutura compartilhada
│   ├── postgres/
│   └── rabbitmq/
├── scripts/                 # Automação Kubernetes
├── rabbitmq/                # Plugin delayed-message
└── runtime/                 # Arquivos locais gerados
```

Os manifests específicos de cada microsserviço ficam na pasta `k8s` do respectivo serviço.

---

## 4. Configuração centralizada

As configurações são gerenciadas pelo projeto de orquestração.

- **Docker Compose:** arquivos versionados em `config/compose/`, carregados por processo.
- **Kubernetes:** ConfigMaps e Secrets gerados automaticamente pelo instalador.
- **Credenciais:** separadas das configurações comuns no Kubernetes.

Para detalhes, consulte [CONFIGURACAO-CENTRALIZADA.md](CONFIGURACAO-CENTRALIZADA.md).

---

## 5. Acesso às APIs

| Microsserviço | Compose | Kubernetes |
|---|---|---|
| Identity | 5081 | 5181 |
| Payments | 5082 | 5182 |
| Library | 5083 | 5183 |
| Catalog | 5084 | 5184 |
| Promotions | 5085 | 5185 |
| Orders | 5086 | 5186 |
| Notifications | 5087 | 5187 |

**Swagger:** `http://localhost:<porta>/swagger` (quando habilitado)

**Health Check:** `http://localhost:<porta>/health/ready`

No Kubernetes, o acesso às APIs é disponibilizado por port-forward.

---

**FIAP Tech Challenge — Fase 2 | FCG**
