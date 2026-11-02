# Seguranca / DEV academico

## Credencial demonstrativa

O instalador gera `Fiap@123456` como senha de todas as contas DEV de banco, RabbitMQ, administrador inicial, client secret `web-bff` e `orders-api`. **Esta configuracao e intencional para demo; e insegura em producao.**

- O arquivo `runtime/compose.env` e o `runtime/k8s.env` sao gerados localmente, ignorados em Git.
- No K8s, os valores de `fcg-dev-secrets` e `fcg-domain-dev-secrets` sao criados a partir destes arquivos. `kubectl get secret -o yaml` usa base64, **nao criptografia**.
- Nunca publique `runtime`, dump dos bancos ou env com senhas em repositorios.
- O NuGet usa apenas `nuget.org` e o BuildingBlocks de pasta irma, sem GitHub PAT. Se o token anterior ainda estiver ativo, revogue-o no GitHub.
- Portas expostas pelo Compose e port-forwards K8s vinculam a `127.0.0.1` (acesso local).
- Uma instalacao sobre bancos antigos nao realiza rotacao automatica, para evitar perda de acesso.

## Para producao

Exigir senhas unicas e fortes, TLS entre servicos, Secret Manager/External Secrets, criptografia de Secrets em repouso, RBAC minimo, politicas de rede, registries e tags de imagem imutaveis, backups e restauracao testados.

## Senhas vs chaves criptograficas

`Fiap@123456` e somente uma senha/segredo de acesso **DEV**. A chave privada de assinatura JWT do Identity e um material criptografico diferente e nao deve ser substituida por essa string; no DEV a aplicacao pode gerar a chave efemera conforme a configuracao de Identity.
