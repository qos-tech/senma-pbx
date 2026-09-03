# Contratos da API

## Escopo

Este documento cobre a API JSON independente em `snep/modules/default/api/index.php`. O painel administrativo não expõe um contrato REST separado: ele usa controllers MVC do Zend Framework 1, sob `snep/modules/default/controllers/`.

## Transporte e autenticação

- **Entrada:** `snep/modules/default/api/index.php`.
- **Formato de resposta:** JSON (`application/json` quando autenticada).
- **Autenticação:** HTTP Basic; usuário e senha são encaminhados ao adaptador compartilhado `Snep_Auth_Adapter_Password`.
- **Sem credenciais válidas:** resposta `401 Unauthorized` e desafio Basic.
- **Seleção de serviço:** parâmetro `service`, limitado a um registro interno. O valor da requisição nunca forma um caminho de arquivo.

## Serviços registrados

| Serviço (`service`) | Implementação | Finalidade |
|---|---|---|
| `CallsReport` | `CallsReportService` | Dados para relatório de chamadas. É o padrão quando `service` não é enviado. |
| `Contacts` | `ContactsService` | Consulta de contatos. |
| `CSV_ExportData` | `CSV_ExportDataService` | Exportação de dados CSV. |
| `CSV_GetParams` | `CSV_GetParamsService` | Metadados de tabelas e campos para fluxo CSV. |
| `RankingReport` | `RankingReportService` | Dados de ranking. |
| `ServicesReport` | `ServicesReportService` | Dados de relatório de serviços. |

## Regras de erro relevantes

- Serviço ausente do registro: resposta JSON de erro, sem tentativa de inclusão dinâmica.
- Credencial inválida: erro genérico de usuário ou senha; a aplicação evita distinguir usuário inexistente de senha incorreta.
- O contrato detalhado de parâmetros e campos por serviço permanece dependente da implementação PHP legada; deve ser confirmado por testes autenticados antes de qualquer cliente externo novo.

## Painel MVC relacionado

Os controllers cobrem extensões, troncos, filas, rotas, usuários, perfis, relatórios, contatos, configuração de PJSIP, auditoria e operações do sistema. A autorização é centralizada em `Snep_PermissionPlugin`: recursos não registrados são negados por padrão, com uma lista explícita de exceções autenticadas e aliases de helpers.

Para requisições POST autenticadas, `Snep_CsrfPlugin` exige token de CSRF, salvo a exceção documentada para o endpoint de reinício, que possui mecanismo próprio.
