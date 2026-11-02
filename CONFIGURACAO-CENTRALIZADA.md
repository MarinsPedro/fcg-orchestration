# Configuracao centralizada - FIAP Cloud Games (Compose e Kind/Kubernetes)

Todas as configuracoes operacionais dos sete microsservicos foram movidas para `fcg-orchestration/config/*.env`.
Os `appsettings.json` e `appsettings.Development.json` dos projetos .NET agora sao `{}`: **nenhuma**
configuracao especifica de ambiente e copiada para dentro da imagem por esses arquivos.

## Onde alterar

- **Docker Compose:** `config/compose-<servico>-<api|worker|migrations>.env`
- **Kubernetes:** `config/k8s-<servico>-<api|worker|migrations>.env`
- **Segredos:** gerenciados pelo OneClick em `runtime/compose.env` e `runtime/k8s.env`, e injetados no Compose
  pelo `docker-compose.yml` ou nos Pods atraves de Kubernetes Secrets. **Nao** inclua senhas nos arquivos `config/*.env`.
- **String de conexao:** injetada pelo Compose/K8s, nao pelo `appsettings`.

Os nomes em `RabbitMq__Topology__*` sao necessarios para configurar as exchanges e filas
**pelo MassTransit**, em cada processo. Nao ha scripts nem Jobs criando topologia RabbitMQ manualmente.
Para mudar um exchange, garanta que os produtores e consumidores usem o mesmo nome.

## Como aplicar

Para a **primeira** execucao depois da atualizacao, use `FCG-COMPOSE.cmd` ou `FCG-K8S.cmd` sem `-NoBuild`,
pois os appsettings dentro das imagens passaram a ser vazios. Depois, para ajustes **apenas** em `config/*.env`,
use `-Service <nome> -NoBuild -SkipMigrations` (com o ambiente ja inicializado).
Quando alterar codigo C# ou qualquer `appsettings.json`, **recompile** a imagem selecionada.

`-Service` permite: identity, payments, library, catalog, promotions, orders, notifications.
No Kubernetes, ConfigMaps usados como variaveis de ambiente exigem um rollout/restart;
o modo seletivo do OneClick ja realiza isso.

## Desenvolvimento local sem orchestration

Ao executar `dotnet run` diretamente no host, sera preciso injetar os valores equivalentes por variaveis de ambiente,
user-secrets ou profiles de desenvolvimento. `appsettings` vazios por si so nao fornecem conexoes, chaves,
enderecos de services nem nomes do RabbitMQ.

## Validacoes

Em especial, **Library Worker** exige `RabbitMq__Topology__Exchanges__GameGrantRequested`,
`GameGranted` e `RabbitMq__Topology__Queues__GameGrantRequested`.
**Payments API e Worker** exigem os exchanges `PaymentRequested`, `PaymentApproved`, `PaymentRejected`
e a queue `PaymentRequested`.
Esses valores agora existem em `config/compose-*.env` e `config/k8s-*.env`.

Observacao: a falha de start do RabbitMQ (healthcheck `unhealthy`) observada em uma das execucoes anteriores
pode ter sido transitoria e nao e resolvida por mudar os appsettings. Conferir os logs do broker caso reapareca.
