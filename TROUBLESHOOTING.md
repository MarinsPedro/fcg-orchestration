# Diagnostico do FCG

## Compose

```powershell
.\FCG-COMPOSE.cmd -Status
docker compose ps --all
docker compose logs --tail=150 postgres rabbitmq
docker compose logs --tail=150 notifications-api notifications-worker notifications-migrations
docker exec fcg-rabbitmq rabbitmq-plugins list -e
```

## Kubernetes

```powershell
.\FCG-K8S.cmd -Status
kubectl get pods,deployments,jobs -n fcg
kubectl describe pod -n fcg -l app=notifications-worker
kubectl logs -n fcg deployment/notifications-worker --tail=150
kubectl logs -n fcg job/notifications-migrations --tail=150
kubectl exec -n fcg rabbitmq-0 -- rabbitmq-plugins list -e
kubectl get configmap fcg-notifications-worker-config -n fcg -o yaml
kubectl describe secret fcg-domain-dev-secrets -n fcg
```

## Erros comuns

- **RabbitMQ plugin nao ativo**: confira logs e a imagem `fcg-rabbitmq:4.3.6-delayed`. O script interrompe antes da saga.
- **NuGet / BuildingBlocks**: mantenha todos os oito repositorios lado a lado; o build usa `UseLocalBuildingBlocks=true` e a fonte publica NuGet.
- **Senha nao funciona no Compose**: confira `config/compose/infrastructure/*.env` e o arquivo do processo. As credenciais DEV sao PostgreSQL `postgres/postgres` e RabbitMQ `fcg/Fiap@123456`. Volumes criados por uma configuracao antiga podem conservar usuarios anteriores; preserve os dados ou recrie o ambiente conscientemente.
- **`ImagePullBackOff` no K8s local**: carregue as imagens no Kind com `kind load docker-image` ou execute o instalador sem `-NoBuild` com contexto local correto.
- **Notificacao nao chega**: confira `notifications-worker`, declaracao das cinco filas/exchanges e registros em `fcg_notifications`. `LogNotificationSender` nao envia email real.
- **Sem acesso aos Swagger K8s**: executar novamente `FCG-K8S.cmd -NoBuild` recria os port-forwards; `-StopAccess` encerra os tuneis sem apagar Pods.
- **Docker Desktop sem Kubernetes e sem Kind CLI**: habilite Kubernetes nas configuracoes do Desktop ou instale Kind.

Nunca apague volumes, PVCs ou namespace indiscriminadamente para corrigir problemas de inicializacao.
