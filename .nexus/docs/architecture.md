# Arquitetura Técnica

## Resumo executivo

SENMA PBX é um monólito PHP derivado de SNEP 3.07. O painel administrativo executa sobre Zend Framework 1; a telefonia usa Asterisk e AGI; MariaDB mantém configuração operacional, identidade, roteamento e dados de chamadas. Docker Compose estabelece o runtime reproduzível.

## Fluxo HTTP

```text
Navegador
  → Apache/PHP (`app`)
  → `snep/index.php`
  → Zend Application + `Bootstrap`
  → AuthPlugin → PermissionPlugin → CsrfPlugin
  → Controller MVC → Manager `Snep_*` → MariaDB / AMI / arquivos de configuração
```

`Bootstrap` registra os plugins de autorização e CSRF. Após autenticação, controllers não registrados como recurso são negados por padrão; POSTs autenticados exigem token CSRF, salvo exceção explicitamente mantida para reinício operacional.

## Fluxo de telefonia

```text
MariaDB / interface SENMA
  → arquivos de configuração PJSIP em volume
  → Asterisk 22 + PJSIP
  → dialplan
  → AGI em `snep/agi/`
  → MariaDB / serviços SENMA
```

O entrypoint Asterisk monta sua configuração em volume a partir de fontes versionadas e configura ODBC. Os scripts AGI são montados somente para leitura e expostos pela árvore esperada pelo Asterisk.

## Dados

`Snep_Db` fornece um singleton Zend `Pdo_Mysql`. O esquema contém domínios de roteamento, extensões/troncos/filas, CDR, contatos, usuários/perfis/permissões, PJSIP, configuração, logs e billing. A fonte é SQL versionado em `snep/install/database/`.

## Limites de serviço

- `app`: UI e lógica PHP.
- `db`: MariaDB persistente.
- `asterisk`: runtime de telefonia e AGI.
- `provider`: simulador local de tronco, isolado e sem credenciais comerciais.

Todos compartilham a rede interna Compose. A conexão AMI não é publicada no host.

## API independente

`modules/default/api/index.php` fornece JSON protegido por Basic Auth. Um registro estático seleciona seis serviços permitidos, evitando inclusão de arquivo a partir de entrada externa.

## Estratégia de evolução

O projeto privilegia compatibilidade e mudanças incrementais. O marco corrente é Docker/bootstrap; PHP 8.4, Asterisk, PJSIP e segurança já possuem histórico técnico no repositório, mas qualquer alteração ampla deve respeitar os limites da fase explicitamente solicitada.
