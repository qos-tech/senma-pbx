# TASK-0028A — Superfície de ramais PJSIP-only

## Objetivo

Tornar a criação e edição de ramais exclusivamente PJSIP, sem converter
silenciosamente registros legados.

## Escopo

- Remover SIP, IAX2 e Manual das telas de criação e inclusão múltipla.
- Oferecer PJSIP em todos os fluxos de criação de ramal.
- Validar no servidor que somente PJSIP é aceito, inclusive em POST direto.
- Bloquear edição de ramal legado com mensagem explícita até a migração.
- Manter somente campos com semântica PJSIP; remover da UX os campos
  `peer`/`user`/`friend`.

## Fora de escopo

- Migração de registros existentes.
- Remoção de tabelas, `InterfaceConf` ou drivers Asterisk.
- Alterações de Khomp.

## Aceitação

- Nenhuma superfície de criação de ramal oferece SIP, IAX2 ou Manual.
- Inclusão múltipla cria PJSIP e gera endpoint/auth/AOR.
- POST legado é rejeitado no servidor.
- Registros legados não são alterados automaticamente.

## Validação

Executar `make lint` e `make regression` no host com Docker.

## Registro de implementação

- A criação e a edição unitárias fixam `technology=pjsip` na superfície e
  rejeitam tecnologias diferentes no servidor.
- A inclusão múltipla fixa `technology=pjsip`, disponibiliza a seleção de
  transporte PJSIP e usa defaults explícitos para os campos que não fazem
  parte desse formulário.
- `peer`, `user` e `friend` foram removidos da UX. A coluna histórica
  `peers.type` recebe o valor de compatibilidade `friend` internamente, sem
  representar uma escolha de produto nem afetar a geração PJSIP.
- A edição de registros cujo canal não começa por `PJSIP/` é bloqueada com
  mensagem de migração explícita; não há conversão implícita de dados.
- Validação estática: `git diff --check` passou e a busca nas superfícies de
  ramais não encontrou opções `sip`, `iax2`, `manual`, `virtual` nem o campo
  de tipo legado. Os gates `make lint` e `make regression` não executaram
  neste ambiente porque o binário `docker` não está disponível.
