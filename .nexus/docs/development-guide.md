# Guia de Desenvolvimento

## Pré-requisitos

- Docker Engine.
- Docker Compose v2.
- Arquivo `.env` criado a partir de `.env.example`.

PHP, MariaDB e Asterisk não são pré-requisitos do host: eles executam nos containers.

## Inicialização local

```bash
cp .env.example .env
make dev
make ps
```

O alvo `make dev` executa `make doctor` e `make up`. A aplicação fica disponível em `http://localhost:8080/`, salvo alteração de porta no ambiente.

## Comandos principais

| Objetivo | Comando |
|---|---|
| Validar pré-requisitos e Compose | `make doctor` |
| Subir ou reconstruir ambiente | `make up` |
| Parar containers sem remover volumes | `make down` |
| Ver estado dos serviços | `make ps` |
| Acompanhar logs | `make logs` |
| Shell da aplicação | `make shell` |
| Shell MariaDB | `make db-shell` |
| CLI Asterisk | `make asterisk-cli` |
| Smoke HTTP | `make smoke` |
| Lint | `make lint` |
| Regressão canônica | `make regression` |

## Validação

`make regression` é o gate integrado: executa a suíte suportada em ordem serial e não converte estados bloqueados ou inconclusivos em sucesso. Há alvos específicos para autorização, SQL, shell, PJSIP, sessão/CSRF, API, disponibilidade de conteúdo externo, chamadas e troncos.

Use `make lint` para uma verificação leve de sintaxe PHP, scripts Bash, XML e `git diff --check`.

## Configuração e segredos

- `.env` é local e não deve conter credenciais reais em versionamento.
- `snep/includes/setup.conf` é gerado uma vez a partir de `setup.conf.dist` e das variáveis de ambiente; configurações alteradas pela UI persistem no volume montado.
- AMI e banco são derivados das mesmas variáveis de ambiente nos entrypoints de `app` e `asterisk`.

## Convenções de mudança

- Preserve comportamento legado antes de modernizar.
- Não renomeie caminhos ou identificadores `snep` oportunisticamente.
- Mantenha o escopo no marco solicitado; o bootstrap Docker não autoriza refatoração arquitetural, migração PostgreSQL ou conversão ampla de SIP/PJSIP.
- Não modifique `snep/lib/Zend/` sem uma justificativa específica: é dependência vendorizada.
