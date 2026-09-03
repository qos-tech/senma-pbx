# TASK-0028B — Troncos PJSIP e endpoint externo

## Objetivo

Substituir Virtual por uma integração PJSIP externa, aplicável a ramal ou
tronco criado diretamente no Asterisk, e retirar a criação de troncos SIP/IAX.

## Contrato

- O administrador informa o nome do endpoint PJSIP externo.
- O SENMA valida, por AMI, `pjsip show endpoint <nome>` antes de persistir.
- O canal persistido é `PJSIP/<nome>`; a identificação de entrada é derivada
  de uma expressão PJSIP segura.
- O SENMA não gera endpoint, auth nem AOR para esse objeto externo.

## Escopo

- Remover SIP, IAX2, Snep SIP, Snep IAX e o canal Virtual arbitrário da UX.
- Manter PJSIP provisionado e incluir PJSIP externo.
- Rejeitar no servidor tecnologias e prefixos legados, inclusive POST direto.
- Não converter nem remover troncos existentes nesta tarefa.

## Aceitação

- Novo tronco aceita apenas PJSIP provisionado ou endpoint PJSIP externo.
- Nome externo inválido ou inexistente no runtime é rejeitado.
- Nenhum campo permite tecnologia/canal arbitrário.
- O endpoint externo não aparece nos arquivos gerados pelo SENMA.

## Validação

Cobrir endpoint existente/inexistente e executar `make lint` e `make regression`.

## Implementação

- `technology` aceita exclusivamente `pjsip` e `pjsip_external`; qualquer
  POST legado ou tecnologia/canal arbitrário é recusado antes da persistência.
- `pjsip_external` aceita somente nomes no conjunto
  `[A-Za-z0-9_.-]{1,80}` e confirma a existência pela resposta estrutural de
  `pjsip show endpoint <nome>` via AMI.
- A referência externa persiste `channel` e `id_regex` derivados como
  `PJSIP/<nome>`, com `trunktype=T` e sem linha em `peers`. Assim ela não é
  selecionada pelos geradores de configuração do SENMA.
- A interface oferece apenas PJSIP provisionado e Endpoint PJSIP externo;
  SIP, IAX2, Snep SIP, Snep IAX, Khomp e Virtual não podem mais ser criados.
- Troncos legados existentes não são convertidos nem removidos. Uma tentativa
  de edição com tecnologia legada é recusada pelo mesmo limite do servidor.
