# Registro de validação - entrega atualizada (7 serviços)

## Validações executadas nesta entrega

- Auditoria do arquivo ZIP de origem, inclusive presença de Notifications API, Worker, migrations e eventos.
- Análise sintática de YAML e JSON do conjunto consolidado.
- Parse de arquivos XML .NET e NuGet.Config.
- Inspeção de 20 definições Compose e caminhos dos Dockerfiles / contextos BuildingBlocks.
- Inspeção de `k8s/` nos sete serviços, 18 ConfigMaps por processo e referências a Secrets.
- Inspeção de ausência de senhas de banco e RabbitMQ em `appsettings.json` e PAT em NuGet.Config.
- Verificação de ausência de diretórios `.git`, `bin` e `obj` no pacote final.
- Garantia de que Compose e Kubernetes usam portas distintas e não compartilham persistência.
- Execução de `docker compose config --quiet` sem erros.
- Execução de `docker compose up --build -d` com código de saída `0` em 04/11/2026.
- Sete migrations concluídas com código `0`.
- Teste isolado comprovando criação automática de database por `MigrateAsync()` com `postgres` e falha esperada sem a permissão `CREATEDB`.
- Primeiro boot em volume PostgreSQL vazio, sem `db-bootstrap`: as migrations criaram os sete databases `fcg_*` e preencheram `__EFMigrationsHistory` em todos eles.
- Sete APIs com estado `healthy` e resposta HTTP `200` em `/health/ready`.
- APIs, Workers e migrations .NET executando como usuário não-root, UID `1654`.

## Limitações

Ainda não foram executados nesta validação o `kubectl apply` do ambiente Kubernetes nem os fluxos funcionais E2E completos entre Orders, Payments, Library e Notifications.

## Teste de aceite recomendado no Windows

1. Executar `docker compose up --build`; conferir 7 APIs saudáveis, 4 Workers e 7 migrations concluídas.
2. Executar `FCG-K8S.cmd`; conferir 11 Deployments, 2 StatefulSets, 7 migrations e Secrets/ConfigMaps.
3. Validar sucesso e rejeição no fluxo Orders > Payments > Library, em ambos os ambientes.
4. Validar que Notifications registra eventos recebidos em `fcg_notifications` e verificar os logs do `notifications-worker`.
5. Verificar que o e-mail ainda é simulado pelo `LogNotificationSender`; não confundir gravação de notificação com entrega externa.

**Status:** verificação estrutural e execução do Docker Compose concluídas; validações Kubernetes e E2E de negócio pendentes.
