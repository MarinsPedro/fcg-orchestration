# Registro de validação - entrega atualizada (7 serviços)

## Validações executadas nesta entrega

- Auditoria do arquivo ZIP de origem, inclusive presença de Notifications API, Worker, migrations e eventos.
- Análise sintática de YAML e JSON do conjunto consolidado.
- Parse de arquivos XML .NET e NuGet.Config.
- Inspeção de 21 definições Compose e caminhos dos Dockerfiles / contextos BuildingBlocks.
- Inspeção de `k8s/` nos sete serviços, 18 ConfigMaps por processo e referências a Secrets.
- Inspeção de ausência de senhas de banco e RabbitMQ em `appsettings.json` e PAT em NuGet.Config.
- Verificação de ausência de diretórios `.git`, `bin` e `obj` no pacote final.
- Garantia de que Compose e Kubernetes usam portas distintas e não compartilham persistência.

## Limitações

**Não foram executados** `dotnet restore`, `dotnet build`, `docker compose build/up`, `kubectl apply`, migrations reais nem testes E2E neste contêiner: SDK .NET, Docker Engine e kubectl não estão disponíveis aqui. Os instaladores têm as etapas de runtime, mas a validação real requer Windows/Docker Desktop do usuário. O teste ponta a ponta anteriormente realizado pelo usuário refere-se à versão anterior; a inclusão do Notifications ainda precisa dessa comprovação.

## Teste de aceite recomendado no Windows

1. Executar `docker compose up --build`; conferir 7 APIs saudáveis, 4 Workers, 1 bootstrap e 7 migrations concluídas.
2. Executar `FCG-K8S.cmd`; conferir 11 Deployments, 2 StatefulSets, 7 migrations e Secrets/ConfigMaps.
3. Validar sucesso e rejeição no fluxo Orders > Payments > Library, em ambos os ambientes.
4. Validar que Notifications registra eventos recebidos em `fcg_notifications` e verificar os logs do `notifications-worker`.
5. Verificar que o e-mail ainda é simulado pelo `LogNotificationSender`; não confundir gravação de notificação com entrega externa.

**Status:** verificação estrutural concluída; validação de execução e E2E do pacote atualizado pendente.
