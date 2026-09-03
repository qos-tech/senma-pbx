# Inventário de Componentes

## Camadas funcionais

| Camada | Local | Responsabilidade |
|---|---|---|
| Entrada HTTP | `snep/index.php` | Configura ambiente, configuração, namespaces, banco e Zend Application. |
| Bootstrap | `snep/Bootstrap.php` | Sessão, autenticação, autorização, CSRF, rotas, locale, logger e view. |
| Controllers MVC | `snep/modules/default/controllers/` | Casos de uso administrativos e relatórios. |
| Serviços e managers | `snep/lib/Snep/` | Domínio PBX, persistência, segurança, configuração e integração. |
| API JSON | `snep/modules/default/api/` | Serviços Basic Auth para relatórios, contatos e CSV. |
| AGI | `snep/agi/` | Fluxos de telefonia acionados pelo dialplan. |
| Módulos adicionais | `snep/modules/{billing,ivr,callback,portability}/` | Capacidades opcionais ou especializadas. |

## Áreas do painel principal

- Telefonia: extensões, grupos, troncos, filas, rotas, PJSIP transports e conferência.
- Administração: usuários, perfis, permissões, parâmetros, módulos, auditoria e logs.
- Relatórios: chamadas, ranking, serviços, exportação e CDR.
- Dados auxiliares: contatos, grupos de contatos, centros de custo, sons e música em espera.
- Operação: status, inspeção, notificações, versões e simulador de rota.

## Segurança transversal

- `Snep_AuthPlugin`: controla acesso autenticado.
- `Snep_PermissionPlugin`: autorização default-deny com allowlist explícita e aliases auditados.
- `Snep_CsrfPlugin`: exige token para POST autenticado.
- `Snep_Security_LoginThrottle` e `Snep_Auth_Adapter_Password`: autenticação, limitação de tentativas e migração compatível de credenciais.

## Interface web

As views estão em `snep/modules/*/views/`, com layouts em `snep/modules/default/views/layouts/`. CSS, JavaScript e imagens legados vivem em `snep/css/`, `snep/includes/javascript/` e `snep/images/`. Não há design system moderno independente detectado; a UI segue a composição e helpers do Zend Framework 1.
