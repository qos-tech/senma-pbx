# Índice da Documentação do SENMA PBX

**Tipo:** monólito  
**Linguagem principal:** PHP 8.4  
**Arquitetura:** MVC Zend Framework 1, MariaDB, Asterisk/AGI e Docker Compose  
**Atualizado em:** 2026-09-02

## Referência rápida

- **Entrada:** `snep/index.php`.
- **Stack:** PHP 8.4, Apache, Zend Framework 1, MariaDB 10.11, Asterisk 22.11.0/PJSIP, Docker Compose.
- **Padrão:** monólito MVC com integração PBX e scripts AGI.
- **Execução local:** `cp .env.example .env && make dev`.

## Documentação gerada

- [Visão Geral](./project-overview.md) — escopo, stack e capacidades.
- [Arquitetura Técnica](./architecture.md) — fluxos HTTP, telefonia, dados e limites de serviço.
- [Árvore de Fontes](./source-tree-analysis.md) — diretórios críticos e pontos de entrada.
- [Inventário de Componentes](./component-inventory.md) — camadas, módulos e segurança transversal.
- [Guia de Desenvolvimento](./development-guide.md) — setup, comandos e validação.
- [Guia de Implantação e Runtime](./deployment-guide.md) — serviços, volumes, saúde e operação.
- [Contratos da API](./api-contracts.md) — API JSON independente e controles de acesso.
- [Modelo de Dados](./data-models.md) — domínios do esquema MariaDB.

## Documentação existente relevante

- [README do projeto](../../README.md) — bootstrap e operação local.
- [Decisão de ambiente](../../docs/decisions/0001-development-environment.md) — escolhas de desenvolvimento.
- [Baseline de segurança](../../docs/SECURITY-BASELINE.md) — postura e controles de segurança.
- [Histórico de tarefas](../../docs/tasks/) — decisões e evidências detalhadas por marco.
- [README da aplicação herdada](../../snep/README.md) — contexto do SNEP.

## Para desenvolvimento assistido por IA

- Mudanças de UI/MVC: consulte `architecture.md`, `component-inventory.md` e `source-tree-analysis.md`.
- Mudanças de API ou persistência: consulte também `api-contracts.md` e `data-models.md`.
- Mudanças de Docker/Asterisk/PJSIP: consulte `deployment-guide.md`, `architecture.md` e as tarefas históricas correspondentes.
- Preserve comportamento legado e não expanda o escopo além do marco explicitamente solicitado.
