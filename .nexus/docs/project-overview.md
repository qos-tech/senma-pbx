# Visão Geral do Projeto

**Data:** 2026-09-02  
**Tipo:** monólito, aplicação web/backend PHP  
**Arquitetura:** MVC Zend Framework 1 com integração PBX/AGI

## Resumo executivo

SENMA PBX é a evolução modernizada de SNEP 3.07 para uma plataforma PBX reproduzível e sustentável. A aplicação preserva o comportamento legado enquanto executa em Docker com PHP 8.4, MariaDB e Asterisk 22/PJSIP.

## Classificação

- **Repositório:** monólito.
- **Código de produto:** `snep/`.
- **Runtime:** Docker Compose com `app`, `db`, `asterisk` e `provider`.
- **Entrada principal:** `snep/index.php`.

## Stack

| Categoria | Tecnologia |
|---|---|
| Linguagem | PHP 8.4 |
| Framework | Zend Framework 1 vendorizado + extensões `Snep_*` |
| Servidor web | Apache |
| Banco | MariaDB 10.11 |
| Telefonia | Asterisk 22.11.0, PJSIP e AGI |
| Ambiente | Docker Compose |
| Automação | Make e Bash |

## Capacidades principais

- Administração de extensões, troncos, rotas, filas, grupos, usuários, perfis e permissões.
- Relatórios e exportação de dados de chamadas.
- Integração Asterisk por AMI, ODBC, dialplan e AGI.
- Provisionamento PJSIP e simulador local de provedor para validação de troncos.
- Gates de smoke, segurança, lint e regressão.

## Início rápido

```bash
cp .env.example .env
make dev
make ps
```

Consulte [development-guide.md](./development-guide.md) para o fluxo diário e [architecture.md](./architecture.md) para a visão técnica.
