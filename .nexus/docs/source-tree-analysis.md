# SENMA PBX — Análise da Árvore de Fontes

**Data:** 2026-09-02

## Visão geral

O repositório é um monólito PHP legado, modernizado incrementalmente para execução Docker. A aplicação está em `snep/`; infraestrutura, automação e documentação de evolução ficam na raiz. Dependências Zend Framework são vendorizadas em `snep/lib/Zend/` e não devem ser tratadas como código de domínio.

## Estrutura principal

```text
senma-pbx/
├── snep/                         # Aplicação SENMA/SNEP
│   ├── index.php                 # Entrada HTTP e bootstrap Zend
│   ├── Bootstrap.php             # Plugins, sessão, rotas, logger e view
│   ├── application.ini           # Configuração Zend por ambiente
│   ├── agi/                      # Scripts AGI executados pelo Asterisk
│   ├── configs/                  # Metadados e configuração da aplicação
│   ├── includes/                 # setup.conf gerado e recursos compartilhados
│   ├── install/                  # Esquema MariaDB e configuração Asterisk legada
│   ├── lib/Snep/                 # Serviços, managers, segurança e integração PBX
│   ├── lib/Zend/                 # Zend Framework 1 vendorizado
│   └── modules/                  # Módulos MVC e extensões funcionais
│       ├── default/              # Painel principal, API e recursos administrativos
│       ├── billing/              # Tarifação
│       ├── ivr/                  # URA
│       ├── callback/             # Ações de callback
│       └── portability/          # Portabilidade e rotas associadas
├── docker/                       # Imagens, entrypoints, configuração e fixtures
├── scripts/                      # Smoke tests, segurança, lint e regressão
├── docs/                         # Decisões, tarefas, segurança e marca
├── compose.yaml                  # Topologia app, db, asterisk e provider
├── Makefile                      # Interface operacional do desenvolvedor
└── .env.example                  # Contrato de variáveis do ambiente local
```

## Diretórios críticos

### `snep/modules/default/`

**Finalidade:** painel administrativo MVC, controllers, formulários, views, recursos de autorização e API JSON.  
**Contém:** extensões, troncos, filas, rotas, usuários, perfis, relatórios, PJSIP, auditoria e status operacional.  
**Integração:** depende de `lib/Snep/`, MariaDB e Asterisk por AMI/configuração gerada.

### `snep/lib/Snep/`

**Finalidade:** camada de domínio e infraestrutura da aplicação.  
**Contém:** managers, acesso a banco, autenticação, sessão, CSRF, Asterisk/AGI, geração PJSIP, logging e configuração.

### `snep/agi/`

**Finalidade:** scripts chamados pelo dialplan Asterisk.  
**Contém:** resolução de extensão, grupos, interfaces, follow-me, monitoramento, voicemail e serviços de chamada.  
**Integração:** exposto ao Asterisk em `/var/lib/asterisk/agi-bin/snep` por symlink criado no entrypoint.

### `snep/install/`

**Finalidade:** ativos de instalação e migração herdados.  
**Contém:** esquemas e atualizações SQL, dados iniciais e configuração Asterisk.  
**Nota:** não é superfície HTTP; a proteção desse caminho é validada pelos testes de segurança.

### `docker/`

**Finalidade:** runtime reproduzível.  
**Contém:** Dockerfiles da aplicação/Asterisk, entrypoints, templates de configuração, inicialização MariaDB e provedor SIP local.

### `scripts/`

**Finalidade:** validação operacional e de segurança.  
**Contém:** smoke tests de HTTP e chamadas, verificação de autorização, SQL, shell, PJSIP, sessão/CSRF, conteúdo externo, lint e regressão.

## Pontos de entrada

- `snep/index.php`: configura caminhos, lê `includes/setup.conf`, registra namespaces e inicia `Zend_Application`.
- `snep/Bootstrap.php`: inicia política de cookie/sessão, plugins de autenticação, autorização e CSRF, além de rotas, locale, logger e views.
- `snep/modules/default/api/index.php`: API JSON autenticada por Basic Auth.
- `snep/agi/*.php`: entradas de telefonia disparadas pelo dialplan.
- `docker/entrypoint.sh` e `docker/asterisk-entrypoint.sh`: bootstrap do runtime de containers.

## Padrões de organização

- MVC Zend Framework 1 para o painel web.
- Managers e classes `Snep_*` para domínio e infraestrutura.
- Scripts AGI separados da camada HTTP.
- SQL versionado como fonte de esquema e atualizações incrementais.
- Configuração sensível derivada de `.env` e gerada no runtime; não deve ser versionada.

## Arquivos de configuração relevantes

- `compose.yaml`: contratos entre serviços e volumes.
- `docker/app.Dockerfile`: PHP 8.4, Apache e extensões PHP.
- `docker/asterisk.Dockerfile`: Asterisk 22.11.0, PJSIP e runtime AGI.
- `.env.example`: variáveis de banco, AMI, rede e ambiente local.
- `snep/application.ini`: bootstrap e diretórios MVC do Zend.

## Notas de desenvolvimento

- Preserve caminhos e identificadores legados `snep` até tarefa explícita de rebranding.
- Não altere `snep/lib/Zend/` sem necessidade concreta: é código vendorizado.
- O marco atual é bootstrap Docker; mudanças de arquitetura, PostgreSQL ou migração ampla devem permanecer fora de escopo sem demanda explícita.
