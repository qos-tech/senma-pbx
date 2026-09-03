# Modelo de Dados

## Persistência

- **SGBD atual:** MariaDB 10.11 em container `db`.
- **Acesso da aplicação:** `Snep_Db`, com adaptador Zend `Pdo_Mysql`.
- **Fonte de esquema:** `snep/install/database/schema.sql`; dados de sistema, CNL e atualizações históricas ficam no mesmo diretório.
- **Módulos com esquema próprio:** billing e portability.

## Domínios principais

| Domínio | Tabelas principais |
|---|---|
| Roteamento e regras | `regras_negocio`, `regras_negocio_actions`, `regras_negocio_actions_config`, `expr_alias`, `expr_alias_expression`, `date_alias`, `date_alias_list` |
| Telefonia | `peers`, `trunks`, `queues`, `queue_members`, `queue_peers`, `queues_agent`, `pjsip_transports`, `pjsip_transport_networks` |
| Chamadas e operação | `cdr`, `services_log`, `queue_log`, `time_history`, `voicemail_messages`, `voicemail_users` |
| Identidade e autorização | `users`, `profiles`, `permissions`, `profiles_permissions`, `users_permissions`, `users_queues_permissions`, `login_attempts`, `password_recovery` |
| Contatos e geografia | `contacts_group`, `contacts_names`, `contacts_phone`, `core_cnl_country`, `core_cnl_state`, `core_cnl_city`, `core_cnl_prefix`, `core_country`, `core_state`, `core_city` |
| Configuração e auditoria | `core_config`, `registry`, `itc_register`, `itc_consumers`, `logs_users`, `core_notifications`, `ccustos` |
| Grupos e vínculos | `grupos`, `core_groups`, `core_peer_groups`, `core_binds`, `core_binds_exceptions` |
| Billing | `telcos`, `billing_types`, `billing`, `rated_calls` |

## Ciclo de inicialização

O container MariaDB recebe os scripts de `snep/install/database/` e `snep/modules/billing/install/` na inicialização de um volume vazio. O script `docker/db-init/00-import-snep-schema.sh` define a ordem e os limites da importação.

## Integração com Asterisk

O Asterisk usa ODBC para acessar o banco e compartilha as mesmas variáveis de banco do container da aplicação. A configuração ODBC é regenerada no boot do container Asterisk; segredos vêm do ambiente, não dos arquivos versionados.

## Limites de evolução

O esquema é legado e orientado a MariaDB/MySQL. PostgreSQL é uma hipótese futura, não uma meta desta documentação nem uma recomendação de alteração imediata.
