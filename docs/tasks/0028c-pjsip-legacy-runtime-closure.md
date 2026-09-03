# TASK-0028C — Encerramento de runtime legado

## Pré-requisitos

TASK-0028A e TASK-0028B concluídas; inventário de dados legado zerado ou
migrado; matrizes PJSIP verdes.

## Objetivo

Remover produtores, dialplan, testes e configurações SIP/IAX que se tornarem
inutilizados após a migração, sem remover suporte ainda alcançável.

## Escopo

- Migrar registros, regras, `canal`, `channel` e `id_regex` legados.
- Substituir semânticas específicas de SIP no dialplan.
- Remover `InterfaceConf`, classes SIP/IAX, includes e reloads somente após
  provar zero produtores e zero dados dependentes.
- Atualizar testes que hoje comprovam criação legada para provar rejeição.

## Aceitação

- Não há produtor de `SIP/` ou `IAX2/` em runtime.
- `chan_sip` e `chan_iax2` podem ser removidos com evidência de runtime.
- Nenhuma migração de dados é implícita ou destrutiva.
