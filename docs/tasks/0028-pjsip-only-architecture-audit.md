# TASK-0028 — Auditoria de arquitetura PJSIP-only

## 1. Resumo executivo

O SENMA é PJSIP-first, mas ainda não é PJSIP-only. Há geradores dedicados de
PJSIP para ramais, troncos e transportes, mas SIP/IAX2 permanecem alcançáveis
por UI, POST direto, dados persistidos, geradores, fábricas de interface e
construção de canais no dialplan. Portanto, não é seguro remover `chan_sip`,
`chan_iax2`, arquivos legados ou campos de banco nesta fase.

Decisões de produto posteriores à auditoria: Manual será removido; Virtual será
substituído por uma integração genérica de endpoint PJSIP externo, de ramal ou
tronco, criado diretamente no Asterisk. O SENMA referenciará o nome PJSIP,
validará sua existência por AMI antes de persistir e não gerará endpoint, auth
ou AOR para ele. Criação legada será bloqueada antes da migração dos registros
SIP/IAX existentes. A remoção física de geradores, classes e módulos continua
dependente da conversão desses dados.

## 2. Runtime atual e limitações de evidência

`compose.yaml` declara `app`, `db`, `asterisk` e `provider`. Na coleta de
runtime, os quatro serviços estavam saudáveis. O Asterisk é dedicado; o
provider é uma instância local independente. O `pjsip.conf` inclui
`senma-pjsip-transports.conf`, `senma-pjsip.conf` e
`senma-pjsip-trunks.conf`. `modules.conf` usa autoload e não bloqueia
explicitamente os drivers legados.

Evidência de 2026-09-02, fornecida a partir do host Docker: Asterisk 22.11.0;
`chan_pjsip.so` e 50 módulos PJSIP carregados; `chan_sip` sem módulos; e
`chan_iax2.so` instalado, porém `Not Running`. Estavam configurados os
transports PJSIP `udp` e `tcp` em `0.0.0.0:5060`, e `wss` em `0.0.0.0:8089`.
No instante da coleta, `pjsip show endpoints` e `pjsip show registrations`
retornaram zero objetos. Isso prova que chan_sip não está carregado na imagem
em execução e que IAX2 não está carregado naquele instante; não prova que os
produtores SIP/IAX2 do aplicativo sejam mortos.

ODBC, dialplan ativo e conteúdo efetivo dos arquivos gerados não foram
coletados nesta sessão. O agente não tinha Docker no seu ambiente isolado; a
evidência de runtime acima foi executada no host por Diego.

## 3. Inventário de tecnologia

Contagem lexical no escopo de primeira parte (`snep/`, `docker/`, `scripts/`,
`compose.yaml` e `Makefile`; inclui comentários e testes): PJSIP 538,
`chan_sip` 40, `chan_iax2` 1, IAX2 135, `PJSIP/` 40, `SIP/` 117 e `IAX2/` 8.
Contagens não são prova de alcance.

| ID | Evidência | Tecnologia | Alcance | Classificação |
| --- | --- | --- | --- | --- |
| T01 | `Snep_PjsipConf::renderExtension` | PJSIP | ativo | PJSIP_CURRENT |
| T02 | `Snep_PjsipTrunkConf::renderTrunk` | PJSIP | ativo | PJSIP_CURRENT |
| T03 | `Snep_PjsipTransportConf` | PJSIP | ativo | PJSIP_CURRENT |
| T04 | `Snep_InterfaceConf::loadConfFromDb` | SIP/IAX2 | alcançável | LEGACY_REACHABLE |
| T05 | `PBX_Trunks` e interfaces SIP/IAX2 | SIP/IAX2 | dependente de dados | LEGACY_REACHABLE |
| T06 | `sip.conf`, `iax.conf`, `snep/snep-*.conf` | SIP/IAX2 | inclusão não provada | MIXED |
| T07 | formulários MVC | SIP/IAX2/PJSIP | visível | VISIBLE_AND_REACHABLE |
| T08 | Virtual/Manual | canal genérico | indireto | HIDDEN_REACHABLE |

## 4. Ciclo de vida de ramal

`extensions/addedit.phtml` expõe SIP, PJSIP, IAX2, Khomp, Virtual e Manual.
`ExtensionsController::execAdd()` aceita `technology`, persiste `peers` e
`peers.canal` e chama os geradores.

```text
formulário → ExtensionsController → peers/transport_id
→ PjsipConf → endpoint + auth + AOR → Asterisk → registro → Dial(PJSIP/...)
```

O controlador também aciona `InterfaceConf` para SIP/IAX2. Inclusão múltipla
oferece SIP/IAX2/Virtual, mas não PJSIP. `type=peer|user|friend` é LEGACY_ONLY;
`transport_id` é PJSIP_REQUIRED; NAT, codecs, qualify, contexto, DTMF e direct
media têm semântica compartilhada e exigem mapeamento. `canal` é dado crítico
de migração.

## 5. Ciclo de vida de tronco

`trunks/addedit.phtml` expõe SIP, IAX2, Khomp, Virtual, Snep SIP, Snep IAX e
PJSIP. `TrunksController::preparePost()` aceita os valores e constrói
`channel`/`id_regex` legados; para PJSIP usa `PJSIP/trunk-<id>`.

```text
formulário → TrunksController → peers + trunks
→ PjsipTrunkConf ou InterfaceConf → Asterisk
→ PBX_Trunks/fábrica → regra → Dial(PJSIP/...|SIP/...|IAX2/...)
```

Tronco PJSIP requer endpoint, AOR/contact, auth quando aplicável, registration
ou identify para IP-auth, proxy e transport. Virtual aceita canal/regex
arbitrários: necessita decisão de produto antes de um contrato PJSIP-only.

## 6. Transportes e geradores

`pjsip_transports` e `pjsip_transport_networks`, o controlador e o renderer
são PJSIP-only. Há suporte a UDP, TCP, TLS, WS, WSS, bind, endereços externos,
`local_net`, transporte simétrico e reload de `res_pjsip`; a efetividade em
runtime permanece pendente.

| Gerador | Saída/efeito | Classificação |
| --- | --- | --- |
| `PjsipConf` | `senma-pjsip.conf`; ramais; `res_pjsip` | PJSIP_CURRENT |
| `PjsipTrunkConf` | `senma-pjsip-trunks.conf`; troncos | PJSIP_CURRENT |
| `PjsipTransportConf` | `senma-pjsip-transports.conf`; transportes | PJSIP_CURRENT |
| `InterfaceConf` | SIP/IAX, trunks, hints; reloads SIP/IAX/dialplan | LEGACY_REACHABLE |

O branch legado ainda é controlado pelo usuário e pelos dados; não é DEAD.
As proteções de seleção/validação de transport das TASK-0019/0020/0026E devem
ser preservadas na migração.

## 7. Dialplan e banco

O dialplan estático usa `Dial(${INTERFACE},...)`; o prefixo provém da abstração
persistida. `PBX_Trunks::get` instancia interfaces SIP/IAX2/PJSIP por
`trunks.type`. `DiscarRamal` usa o canal persistido e ainda contém
`SIPAddHeader`, que exige equivalente PJSIP. `getChannelOwner` usa `id_regex`,
`canal` e Manual/Virtual, logo é ponto de migração de entrada.

`peers` contém `canreinvite`, `host`, `insecure`, `nat`, `qualify`, `type`
(default `friend`), `defaultuser`, `canal`, `peer_type`, `directmedia` e
`transport_id`; `trunks` contém `channel`, `type`, `dialmethod`, `id_regex`,
`technology` e `transport_id`.

| Classe | Elementos |
| --- | --- |
| REQUIRED_PJSIP | tabelas de transport e `transport_id` de PJSIP |
| COMPATIBILITY_REQUIRED | campos de peer/trunk enquanto houver dados legados |
| LEGACY_REMOVE_CANDIDATE | `friend`, `insecure`, valores SIP/IAX após migração |
| NAME_ONLY_TECHNICAL_DEBT | identificadores históricos SNEP sem semântica runtime |

`canal`, `channel`, `id_regex` e `technology` não são apenas dívida nominal;
são dependências de migração.

## 8. Superfícies e API

| Superfície | Estado | Disposição |
| --- | --- | --- |
| criação/edição SIP/IAX2 de ramal | VISIBLE_AND_REACHABLE | MIGRATE_TO_PJSIP, depois REMOVE_NOW |
| inclusão múltipla sem PJSIP | VISIBLE_AND_REACHABLE | MIGRATE_TO_PJSIP antes de remover |
| troncos SIP/IAX2/SNEP | VISIBLE_AND_REACHABLE | MIGRATE_TO_PJSIP, depois REMOVE_NOW |
| Virtual/Manual | VISIBLE/HIDDEN_REACHABLE | DEFER_WITH_REASON |
| IP Status SIP/IAX | BACKEND_ONLY de leitura | KEEP_COMPATIBILITY_READ_ONLY |
| ajuda SIP/IAX | VISIBLE_AND_REACHABLE | atualizar/remover com a UI |
| PJSIP Transports | VISIBLE_AND_REACHABLE | KEEP |

Não há endpoint standalone identificado para provisionar tecnologia. A API de
exportação pode expor `peers.canal`; mantê-la em leitura compatível até a
migração, pois removê-la é breaking change.

## 9. Prova de alcance e arquitetura-alvo

`pjsip-config-security-smoke-test.sh` posta `technology=sip` e verifica
`snep-sip.conf`; a suíte residual de SQL cria SIP e verifica a seção gerada.
`InterfaceConf` percorre SIP/IAX2 e é chamado após mutações. Classificação:
SIP/IAX2/InterfaceConf/fábricas são LIVE_REACHABLE por produtor;
Virtual/Manual são HIDDEN_REACHABLE; configurações vendorizadas são MIXED.
Nenhum desses itens é DEAD nesta auditoria.

O alvo é: ramal = endpoint + auth + AOR (+ transport); tronco = endpoint +
AOR/contact + auth/registration/identify/transport conforme o cenário;
roteamento materializa exclusivamente `PJSIP/<destino>` por abstração interna
que não aceita prefixo arbitrário; os três arquivos PJSIP são a única
propriedade de configuração; e `SIPAddHeader` é substituído por API PJSIP.

## 10. Classificação, dependências e cobertura

| Componente | Disposição |
| --- | --- |
| geradores PJSIP/transportes | KEEP_COMPATIBILITY_READ_ONLY |
| criação SIP/IAX2/SNEP | MIGRATE_TO_PJSIP, então REMOVE_NOW |
| dados/canais/regex legados | KEEP_TEMPORARILY_FOR_DATA_MIGRATION |
| InterfaceConf e interfaces SIP/IAX2 | MIGRATE_TO_PJSIP, então DEAD_DELETE com prova |
| configs/includes/módulos legados | DEFER_WITH_REASON até zero produtores/dados |
| Virtual/Manual | DEFER_WITH_REASON: decisão de produto |

```text
decisão Virtual/Manual e superfície de criação
→ validação server-side e compatibilidade de leitura
→ migração de peers/trunks, canal/channel/id_regex e regras
→ abstração de discagem, owner resolution e cabeçalhos PJSIP
→ PJSIP completo e testes
→ zero produtores: InterfaceConf/includes/reloads
→ remoção de chan_sip/chan_iax2
```

| Capacidade | Cobertura atual | Lacuna |
| --- | --- | --- |
| ramal PJSIP, endpoint/auth/AOR/registro/chamada | forte: `call-smoke` | edição dedicada |
| tronco registration, saída/entrada/CDR | forte: `trunk-smoke` | IP-auth sem registro |
| transport CRUD/reload | forte: `transport-smoke` | runtime desta sessão |
| rota/dialplan PJSIP | forte em call/trunk smoke | CRUD UI |
| Simulator | fraca | simulação/assert de tecnologia |
| WebRTC/WSS | fraca | E2E |
| rejeição de legado e migração | ausente | obrigatório antes da remoção |

## 11. Riscos e plano

| Prioridade | Risco | Mitigação |
| --- | --- | --- |
| P0 | produtores SIP/IAX e POSTs ativos | migrar antes de bloquear/remover |
| P0 | Virtual/Manual reintroduz tecnologia | decisão de produto e allowlist |
| P0 | remover módulo antes de dados/regras | respeitar dependências |
| P1 | `SIPAddHeader` sem equivalente | migrar dialplan antes |
| P1 | IP-auth/provider sem prova específica | smoke PJSIP dedicado |
| P1 | ODBC/dialplan/arquivos gerados ainda sem coleta | complementar baseline runtime |

1. **TASK-0028A — Fechamento da superfície legada**: decidir Virtual/Manual,
   oferecer PJSIP em inclusão múltipla e bloquear server-side novas tecnologias
   legadas somente com modo de leitura/edição/migração existente.
2. **TASK-0028B — Completude PJSIP e migração de dados**: migrar ramais,
   troncos, regras e identificadores; cobrir IP-auth, provider, WebRTC/WSS e
   migrações; substituir semânticas SIP.
3. **TASK-0028C — Encerramento de dialplan e geração legada**: após zero
   produtores/dados e matriz verde, retirar InterfaceConf, classes/includes e
   então módulos; atualizar suites que hoje provam alcance legado.

0028A depende da decisão de produto. 0028B depende de 0028A. 0028C depende de
prova de zero dados/produtores e cobertura verde de 0028B.

## 12. Revisão adversarial, decisão e checkpoint

O revisor confirmou como P0: gerador/reloads `InterfaceConf`; POSTs e
seletores de ramal; troncos SIP/IAX/SNEP/Virtual; fábricas e regras por dados.
Como P1, apontou Manual/Virtual, `getChannelOwner` e fallback SIP; como P2,
suites canônicas que ainda codificam alcance legado. Todas as objeções são
aceitas e resolvidas no plano. Nenhuma alegação DEAD é aceita sem prova de
rota, persistência, geração, inclusão e driver.

Decisão final: o destino é PJSIP-only, porém o estado atual é misto. TASK-0028
encerra no checkpoint de auditoria e não inicia 0028A/B/C.

- Alteração: somente este documento.
- `make lint`: BLOCKED no ambiente do agente, exit 2 (`docker` ausente).
- `make regression`: BLOCKED no ambiente do agente, exit 2 (`docker` ausente).
- Baseline runtime: coletada no host Docker por Diego; Asterisk 22.11.0,
  PJSIP carregado, chan_sip ausente, chan_iax2 não carregado, três transports
  PJSIP e zero endpoints/registrations no instante da consulta.
- O worktree já estava sujo antes desta tarefa, com alterações não relacionadas
  em `AGENTS.md`, `CLAUDE.md`, skills e `.nexus/`; elas foram preservadas.
- Mensagem de commit proposta, não executada: `docs: auditar arquitetura PJSIP-only`.

## 13. Evidência independente — fase 1 (2026-09-03T15:07:51-03:00)

Esta seção é um acréscimo de evidência reproduzível da fase 1. Ela não
substitui a análise humana anterior, não aciona gerador, reload nem alteração
de banco. Valores de autenticação, registro, contato e senha não foram
coletados nem registrados.

### 13.1 Ledger de runtime, módulos e ODBC (T01)

Coleta executada no diretório raiz com os comandos somente-leitura da seção E
do `PLAN.md`: `docker compose ps`, consultas `asterisk -rx`, leitura de
includes e inspeção estrutural dos seis arquivos. Naquele instante, `app`,
`asterisk`, `db` e `provider` estavam `healthy`; o runtime era Asterisk
22.11.0 em Linux/aarch64. ODBC reportou a fonte `snep` com uma conexão ativa
(de uma). Estes resultados confirmam e refinam o baseline aceito no §2.

`module show like chan_` mostrou `chan_pjsip.so` em execução,
`chan_iax2.so` instalado mas `Not Running`, e nenhuma linha para `chan_sip`.
`pjsip show transports` mostrou três transports: UDP e TCP em `0.0.0.0:5060`
e WSS em `0.0.0.0:8089`. `modules.conf` tem `autoload=yes` e não tem
`noload` para PJSIP, SIP ou IAX2.

O inventário do dialplan da mesma coleta preserva os achados legados como
evidência de runtime, sem lhes atribuir consumo dos arquivos abaixo:

| Origem ativa | Evidência filtrada |
| --- | --- |
| `extensions.conf:135` | `Dial(${INTERFACE},${ARG2},${ARG3})` |
| `extensions.conf:113` | `SIPAddHeader(Alert-Info: Bellcore-r2)` |
| `custom/preagi.conf:6` | `Dial(SIP/1003,60,twg)` |
| `snep-features.conf:99` | `Channel: SIP/${EXTEN:3}` em arquivo `.call` |

### 13.2 Cadeia de carga e conteúdo redigido dos arquivos gerados legados (T01)

Foi feita uma busca recursiva de diretivas `#include`, `#tryinclude` e
`include` sob `/etc/asterisk`, seguida da inspeção das cadeias pai. A cadeia
de dialplan ativa é `extensions.conf -> snep/snep-features.conf`; nela, a
única referência a arquivo legado é `#include snep/snep-sip-hints.conf`, na
linha 170. **Correção (TASK-0028-DIAG, 2026-09-03T21:59-03, ver §14.1/§14.2):**
essa diretiva NÃO está comentada — inspeção byte-a-byte (`od -c`) confirma
ausência de `;` antes de `#include`, e `#include` é um comando de
pré-processador do Asterisk, não uma sintaxe comentável. O arquivo está,
portanto, `INCLUDED_DIRECTLY`, não `NOT_INCLUDED`. `pjsip.conf` inclui além
disso os três arquivos `senma-pjsip*`. Não há `sip.conf` nem `iax.conf` no
runtime, embora os templates de instalação os contenham. Dos seis artefatos
legados, cinco não têm cadeia Asterisk ativa nesta coleta; o sexto
(`snep-sip-hints.conf`) tem uma cadeia ativa mas não contribui dados (sua
seção `[hints]` está vazia). A classificação de cada um não se baseia apenas
na ausência/presença do arquivo, mas também na ausência dos drivers em
execução necessários para os parsers SIP/IAX2 dar efeito a qualquer dado que
viesse a existir.

| Arquivo | Cadeia de carga reproduzida | Conteúdo efetivo redigido | Classificação |
| --- | --- | --- | --- |
| `snep-sip.conf` | Nenhuma cadeia ativa; o template `sip.conf` não está instalado; `chan_sip` não está carregado. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-sip-trunks.conf` | Nenhuma cadeia ativa; o template `sip.conf` não está instalado; `chan_sip` não está carregado. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-sip-hints.conf` | `extensions.conf:48 -> snep/snep-features.conf:170 -> #include snep/snep-sip-hints.conf` (diretiva ativa, não comentada — ver correção em §14.1). | 2 linhas: seção `[hints]`; zero entradas `exten =>`. | `INCLUDED_DIRECTLY`; `GENERATED_AND_LOADED` (sem dados) |
| `snep-iax2.conf` | Nenhuma cadeia ativa; o template `iax.conf` não está instalado; `chan_iax2` está `Not Running`. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-iax2-trunks.conf` | Nenhuma cadeia ativa; o template `iax.conf` não está instalado; `chan_iax2` está `Not Running`. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-iax2-hints.conf` | Nenhuma cadeia ativa; nenhum include IAX2 foi encontrado; `chan_iax2` está `Not Running`. | 2 linhas: seção `[hints]`; zero entradas `exten =>`. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |

Essa é uma classificação de consumo do runtime observado, não uma autorização
para apagar os produtores: a geração ainda tem chamadores e dados-fonte,
documentados em §13.3. Uma inclusão dinâmica fora de `/etc/asterisk` ou uma
mudança posterior de módulos torna esta prova datada e exige nova coleta.

### 13.3 Matriz de produtores, dados, saídas e efeitos de runtime (T02)

As consultas `codegraph explore` e as buscas da seção F foram feitas antes da
leitura dirigida das classes. Cada linha abaixo traz: ponto de entrada, alcance
por usuário/chamador, fonte DB, saída e efeito de load/reload. Linhas de
arquivo referem-se ao snapshot desta coleta.

| Família/gerador | Ponto de entrada e alcance | Fonte DB | Saída | Efeito de runtime e estado |
| --- | --- | --- | --- | --- |
| `senma-pjsip-transports.conf` / `Snep_PjsipTransportConf::loadConfFromDb` | CRUD autenticado de `PjsipTransportsController` (`add`, `edit`, `remove`, linhas 118–270), que chama `regenerateAll` (438–440). | `pjsip_transports` habilitados e `pjsip_transport_networks` por `transport_id` (`PjsipTransportConf.php:86–94`). | Arquivo em `/etc/asterisk/snep/` (`:67`), com seções `type=transport`. | Escreve o arquivo e executa `module reload res_pjsip.so` (`:98–100`, `:168–177`). O arquivo é incluído por `pjsip.conf:16`; `chan_pjsip` está em execução. `LIVE_REACHABLE`. |
| `senma-pjsip.conf` / `Snep_PjsipConf::loadConfFromDb` | Mutações de ramal em `ExtensionsController` chamam o gerador (por exemplo, 909–910, 965–970, 1026–1031 e 1066–1071); o CRUD de transports também o regenera (439). | `peers` habilitados, `peer_type='R'`, `canal LIKE 'PJSIP/%'` (`PjsipConf.php:129`). | Arquivo em `/etc/asterisk/snep/` (`:104`), com endpoint, auth e AOR PJSIP. | Escreve e executa `module reload res_pjsip.so` (`:158`, `:415–424`). Incluído por `pjsip.conf:17`; `LIVE_REACHABLE`. |
| `senma-pjsip-trunks.conf` / `Snep_PjsipTrunkConf::loadConfFromDb` | Mutações de tronco chamam o gerador (por exemplo, `TrunksController.php:297–298`, 332–333, 534–535 e 603–604); CRUD de transports também o regenera (440). | `peers` habilitados, `peer_type='T'`, `canal LIKE 'PJSIP/%'`, com lookup em `trunks` pelo nome (`PjsipTrunkConf.php:113–125`). | Arquivo em `/etc/asterisk/snep/` (`:87`), com objetos de tronco PJSIP. | Escreve e executa `module reload res_pjsip.so` (`:149`, `:348–357`). Incluído por `pjsip.conf:24`; `LIVE_REACHABLE`. |
| `snep-sip.conf`, `snep-sip-trunks.conf`, `snep-sip-hints.conf` / `Snep_InterfaceConf::loadConfFromDb` | Chamado após mutações de ramal e tronco, inclusive em caminhos que regeneram PJSIP (`ExtensionsController.php:900, 965, 1026, 1066`; `TrunksController.php:289, 328, 530, 599`). O formulário atual de criação de ramal inicia em PJSIP (`ExtensionsController.php:222–244`) e o `preparePost` atual de tronco aceita somente `pjsip` ou `pjsip_external` (`TrunksController.php:616–622`); dados legados persistidos ainda são a fonte possível deste gerador. | Para `sip`, `peers` habilitados cujo `canal LIKE 'SIP%'`; para linhas de tronco, lookup em `trunks` por nome (`InterfaceConf.php:39–45`, 73–74, 121–133). Hints vêm de `peers.blf` e `peers.canal` (`:233–247`). | Três arquivos `/etc/asterisk/snep/snep-sip*.conf` (`:43–45`, 240–247). | Executa `sip reload`, `dialplan reload` e `iax2 reload` (`:250–254`) após escrever, mas a coleta T01 não executou esses comandos. Sem cadeia ativa e sem `chan_sip` em execução: `GENERATED_BUT_UNUSED` no snapshot, não `DEAD`. |
| `snep-iax2.conf`, `snep-iax2-trunks.conf`, `snep-iax2-hints.conf` / `Snep_InterfaceConf::loadConfFromDb` | Mesmo ponto de entrada e alcance da família SIP: o único laço percorre `sip` e `iax2` (`InterfaceConf.php:39`). | Para `iax2`, `peers` habilitados cujo `canal LIKE 'IAX2%'`; lookup em `trunks` e hints são os mesmos da linha SIP (`:73–74`, 121–133, 233–247). | Três arquivos `/etc/asterisk/snep/snep-iax2*.conf` (`:43–45`, 240–247). | Mesmo trio de comandos de reload (`:250–254`). Sem cadeia ativa e com `chan_iax2` `Not Running`: `GENERATED_BUT_UNUSED` no snapshot, não `DEAD`. |

Os dois últimos grupos não têm lacuna de produção: sua classe, chamadores,
consulta, seis destinos e tentativa de reload estão todos demonstrados. A
lacuna deliberadamente limitada é de consumo futuro: esta fase não recarregou
o Asterisk e não alterou nem consultou linhas de banco para materializar dados
legados. Assim, o estado é suficiente para distinguir gerado de carregado,
mas não para declarar os produtores mortos.

#### Reprodução da evidência de fonte

Foram executados os quatro `rg` da seção F contra `snep`, `docker` e
`scripts`, além de duas explorações indexadas: `Snep_InterfaceConf
loadConfFromDb ...` e `Snep_PjsipConf Snep_PjsipTrunkConf
Snep_PjsipTransportConf ...`. Os resultados localizam as três inclusões PJSIP
em `docker/asterisk-config/pjsip.conf:16–24`, os destinos legados dos
templates `sip.conf`/`iax.conf`, todos os chamadores de
`loadConfFromDb`, as consultas e os comandos de reload citados acima. A busca
de dialplan também confirma que `SIPAddHeader`, `Dial(SIP/...)`, `Channel:
SIP/...` e `Dial(${INTERFACE},...)` pertencem a superfícies a serem tratadas
nas fases posteriores, e não são prova de que algum dos seis arquivos gerados
tenha sido carregado.

### 13.4 Transcript reproduzível de runtime (T01, 2026-09-03)

Para que a classificação de §13.2 possa ser verificada sem inferência, esta é
a transcrição redigida dos comandos somente-leitura da seção E executados no
host Docker. Nenhum comando de reload, geração ou escrita SQL foi usado.

```text
$ docker compose ps
app, asterisk, db e provider: Up (healthy)

$ docker compose exec -T asterisk asterisk -rx "core show version"
Asterisk 22.11.0 ... aarch64 running Linux

$ docker compose exec -T asterisk asterisk -rx "module show like chan_"
chan_pjsip.so: Running
chan_iax2.so: Not Running
chan_sip.so: no matching module line

$ docker compose exec -T asterisk asterisk -rx "pjsip show transports"
tcp  0.0.0.0:5060
udp  0.0.0.0:5060
wss  0.0.0.0:8089
Objects found: 3

$ docker compose exec -T asterisk asterisk -rx "odbc show"
Name: snep; Number of active connections: 1 (out of 1)
```

O filtro host-side de `dialplan show` devolveu quatro ocorrências relevantes:
`Dial(${INTERFACE},${ARG2},${ARG3})` em `extensions.conf:135`,
`SIPAddHeader(...)` em `extensions.conf:113`, `Dial(SIP/1003,60,twg)` em
`preagi.conf:6` e `Channel: SIP/${EXTEN:3}` em `snep-features.conf:99`.

A inspeção recursiva das diretivas de include encontrou os três artefatos
PJSIP em `pjsip.conf` (linhas 16, 17 e 24), mais uma quarta diretiva ativa:
em `extensions.conf`, a cadeia é `extensions.conf:48 -> snep/snep-features.conf
-> snep-features.conf:170 -> #include snep/snep-sip-hints.conf`, um
`#include` real e não comentado (correção registrada em §14.1 desta revisão;
a versão anterior deste parágrafo descrevia essa diretiva como "comentada",
o que a inspeção byte-a-byte não confirma). Não houve diretiva efetiva para
os outros cinco arquivos legados. A inspeção
estrutural redigida mostrou 11 linhas de cabeçalho e zero seções de endpoint
ou tronco em cada um dos quatro arquivos de pares/troncos, e duas linhas
(` [hints]`, precedida por linha em branco) com zero `exten =>` em cada arquivo
de hints. O snapshot de instalação agora contém ambos os placeholders de hints
que `Snep_InterfaceConf::loadConfFromDb()` escreve, portanto os seis destinos
de geração podem ser conferidos também antes do bootstrap Docker.

### 13.5 Produto, POST/API e valores persistidos (T03, 2026-09-03)

Esta coleta é somente-leitura e descreve o código que está no checkout no
momento da coleta. Ela complementa, sem reescrever, a análise humana anterior:
as tarefas de produto `0028A` e `0028B` já colocaram guards server-side nos
dois controllers. Portanto uma opção que ainda aparece em código legado não é
automaticamente uma criação alcançável.

O schema define a tecnologia do ramal em `peers.canal` (`varchar(255)`) e a do
tronco em `trunks.type`, preservando ainda `trunks.channel`,
`trunks.id_regex` e `trunks.technology` (todos campos de compatibilidade de
canal). A consulta agregada, sem nomes, contatos ou credenciais, foi executada
contra o serviço `db` com o usuário de aplicação:

```sql
SELECT 'peers', UPPER(SUBSTRING_INDEX(canal, '/', 1)), COUNT(*)
  FROM peers WHERE name <> 'admin' AND peer_type = 'R'
 GROUP BY UPPER(SUBSTRING_INDEX(canal, '/', 1))
UNION ALL
SELECT 'trunks', UPPER(type), COUNT(*) FROM trunks GROUP BY UPPER(type);
```

Resultado do snapshot: `peers / PJSIP / 5` e `trunks / PJSIP / 1`; as duas
consultas agregadas restritas a SIP/IAX2 retornaram `0` para ramais e troncos.
Isso é contagem de dados, não prova de que o modelo/fábrica que os consome foi
removido.

| Item e superfície | Prova de criação/edição e leitura | Estado de alcance | Disposição permitida nesta auditoria |
|---|---|---|---|
| Ramal SIP ou IAX2, seletor visível | `extensions/addedit.phtml:80-82` envia apenas `technology=pjsip`; não há seletor SIP/IAX2. | `DEAD` como superfície visível de criação. | Manter o formulário PJSIP-only; não inferir remoção das classes/dados. |
| Ramal SIP ou IAX2, POST direto/edição | `ExtensionsController::execAdd()` rejeita qualquer `technology` diferente de `pjsip` antes de persistir (`:627-638`); `editAction()` redireciona um `canal` não-PJSIP antes de renderizar (`:287-296`). | `LIVE_BUT_BROKEN` para o POST/edição legado: a rota MVC existe, mas o guard o bloqueia de propósito. | Manter o guard; migrar dados legados em tarefa própria. |
| Ramal SIP ou IAX2, valor persistido/leitura | `PBX_Usuarios::get()` deriva a tecnologia de `peers.canal` e ainda instancia interfaces SIP e IAX2 (`snep/lib/PBX/Usuarios.php:53-85`); hoje a contagem legada é zero. | `HIDDEN_REACHABLE` condicionado a uma linha histórica/restaurada; não há produtor de UI/POST atual. | Não declarar `DEAD`; preservar como compatibilidade de leitura até uma migração de dados comprovada. |
| Tronco SIP ou IAX2, seletor visível e POST | `trunks/addedit.phtml:57-62` oferece somente `pjsip` e `pjsip_external`; `TrunksController::preparePost()` aceita somente esses valores (`:618-622`) e é chamado pelos POSTs add/edit (`:245`, `:502`). | `LIVE_BUT_BROKEN` para tentativa POST SIP/IAX2; `DEAD` como seletor visível. | Manter a allowlist; não reintroduzir opção legada. |
| Tronco SIP ou IAX2, valor persistido/leitura | `PBX_Trunks::get()` ainda despacha `trunks.type` SIP/IAX2, inclusive NOAUTH (`snep/lib/PBX/Trunks.php:90-113`); snapshot agregado: zero linhas legadas. | `HIDDEN_REACHABLE` condicionado a dados históricos/restaurados. | Não apagar a fábrica nem os campos sem migração/revisão posterior. |
| API/AJAX e exportação | O inventário de `snep/modules/default/api/actions/` contém contatos e serviços/CSV/relatórios; a busca limitada não encontrou serviço de criação/edição de ramal ou tronco. `CSV_GetParamsService` expõe `peers`/`trunks` como fontes de exportação, portanto é consumidor de leitura, não provisionador. | `DEAD` para API standalone de escrita de tecnologia; `HIDDEN_REACHABLE` para exportação/leitura de valores legados, se voltarem a existir. | Manter a conclusão limitada ao API standalone inventariado; reavaliar se surgir endpoint fora desta árvore. |

As rotas MVC ainda são endpoints de produto alcançáveis e executam
`Snep_InterfaceConf::loadConfFromDb()` após mutações aceitas (ramais
`ExtensionsController.php:900`; troncos `TrunksController.php:288-299` e
`:529-536`). Isso explica por que um dado legado restaurado continua relevante
para T02, embora nenhuma requisição atual possa criá-lo por SIP/IAX2.

### 13.6 Dialplan ativo e resolução genérica de canal (T04, 2026-09-03)

Foi executado, sem reload, o teste exigido:

```bash
docker compose exec -T asterisk asterisk -rx "dialplan show" \
  > /tmp/task-0028-dialplan-show.txt
rg -n -i 'PJSIP/|SIP/|IAX2/|SIPAddHeader|Dial\(|Channel:' \
  /tmp/task-0028-dialplan-show.txt
```

O filtro retornou quatro tokens ativos, e a inspeção do contexto exibido pelo
próprio Asterisk resolveu a cadeia variável abaixo. Arquivos de exemplo
(`sip.conf.sample`, comentários e templates não incluídos) não entram na
matriz.

| Contexto/localização ativo | Construção direta ou variável | Origem/resolução de tecnologia | Estado | Disposição permitida |
|---|---|---|---|---|
| `hints`, `preagi.conf:6` | `Dial(SIP/1003,60,twg)` direto | Token SIP literal no dialplan carregado. T01 confirmou `chan_sip` ausente/não carregado. | `LIVE_BUT_BROKEN` | Migrar/remover somente em tarefa de dialplan com teste de chamada. |
| `default`, `snep-features.conf:99` | callback spool com `Channel: SIP/${EXTEN:3}` | Token SIP literal gerado quando o código `*33XXXX` é discado; o contexto está no `dialplan show`. | `LIVE_BUT_BROKEN` | Migrar a construção do `.call` para PJSIP antes de remover chan_sip. |
| `ramais-agentes`, `extensions.conf:113` | `SIPAddHeader(Alert-Info: Bellcore-r2)` | Aplicação SIP explícita antes de `Macro(dialpeer,...)`; a ação AGI equivalente também condiciona `SIPAddHeader` a `getTech() == 'SIP'` (`modules/default/actions/DiscarRamal.php:366-387` e `lib/PBX/Rule/Action/DiscarRamal.php:356-372`). | `LIVE_BUT_BROKEN` para a aplicação SIP no runtime atual; a condição AGI é `HIDDEN_REACHABLE` se houver ramal SIP persistido. | Substituir por mecanismo PJSIP somente após validar o comportamento Alert-Info. |
| `macro-dialpeer`, `extensions.conf:125-135` | `AGI(resolv_interface.php,...,INTERFACE)`; possível sobrescrita `INTERFACE=${SIGAME}`; `Dial(${INTERFACE},...)` | `resolv_interface.php:30-42` chama `PBX_Usuarios::get()` e usa `getCanal()`; as classes retornam `SIP/`, `IAX2/` ou `PJSIP/` conforme `peers.canal` (`Usuarios.php:60-85`; interfaces `SIP.php:56-58`, `IAX2.php:55-57`, `PJSIP.php:53-55`). No snapshot os cinco ramais são PJSIP, logo a resolução observável é PJSIP; `SIGAME` é dado de `peers.sigame` e pode substituir a interface. | `LIVE_REACHABLE` para PJSIP; `HIDDEN_REACHABLE` para SIP/IAX2 e para um `SIGAME` que carregue canal legado. | Preservar a cadeia até auditoria/migração de `sigame`; não classificar como PJSIP-only. |
| `default`, captura/spy em `snep-features.conf:13-14,65-93` | `resolv_interface.php(..., INTERFACE)` alimenta `PickupChan`/`ChanSpy` | Mesmo AGI, mesma origem `peers.canal`; são contextos ativos exibidos/ incluídos por `extensions.conf -> snep/snep-features.conf`. | `LIVE_REACHABLE` para PJSIP; `HIDDEN_REACHABLE` para SIP/IAX2 condicionados a dado persistido. | Manter como dependência da migração de dados e testar com endpoint PJSIP. |
| Discagem de regras, `DiscarRamal` | `$ramal->getInterface()->getCanal()` para `exec_dial()` | A mesma fábrica `PBX_Usuarios::get()` fornece a interface; não é prova de token SIP ativo por si só, mas resolve para SIP/IAX2 se uma linha persistida o selecionar. | `HIDDEN_REACHABLE` para SIP/IAX2; `LIVE_REACHABLE` para PJSIP no snapshot. | Não remover as classes de interface antes de zerar/migrar os consumidores. |
| Discagem de tronco, `DiscarTronco` | `getDialStringForDestination()` | `PBX_Trunks::get()` escolhe a interface por `trunks.type`; a implementação-base preserva a concatenação histórica para SIP/IAX2, enquanto PJSIP gera `PJSIP/<destino>@<endpoint>` (`Asterisk/Interface.php:109-143`, `PJSIP.php:66-88`). | `LIVE_REACHABLE` para PJSIP; `HIDDEN_REACHABLE` para SIP/IAX2 condicionados a linhas de tronco. | Migrar dados e cenários de regra antes de remoção. |

Não apareceu `IAX2/` direto no dialplan ativo nesta coleta. Esta é uma
ausência limitada ao output do runtime: IAX2 continua alcançável pela cadeia
genérica de `peers.canal`/`trunks.type`, e a contagem atual zero não autoriza
declará-lo morto. Nenhuma dessas coletas executou geração, reload, escrita SQL
ou alteração de configuração.

### 13.7 Revalidação independente de T03 e T04 (2026-09-03)

Esta revalidação fecha as duas lacunas apontadas no gate independente: ela
executa uma agregação somente-leitura no banco que está em execução e captura
novamente o dialplan que o Asterisk está servindo. Não executa geração,
`reload`, alteração de configuração ou SQL de escrita. As contagens não
incluem nomes, contatos, credenciais ou qualquer outro dado de assinante.

#### T03 — banco, produto e API

Após conferir no schema que `peers.canal`, `trunks.type` e
`trunks.technology` são campos persistidos (`schema.sql:253,426,440`), foi
executado no serviço `db`, autenticado como o usuário da aplicação:

```sql
SELECT 'peers SIP', COUNT(*) FROM peers
 WHERE UPPER(COALESCE(canal, '')) LIKE 'SIP/%';
SELECT 'peers IAX2', COUNT(*) FROM peers
 WHERE UPPER(COALESCE(canal, '')) LIKE 'IAX2/%';
SELECT 'trunks type SIP', COUNT(*) FROM trunks
 WHERE UPPER(COALESCE(type, '')) = 'SIP';
SELECT 'trunks type IAX2', COUNT(*) FROM trunks
 WHERE UPPER(COALESCE(type, '')) = 'IAX2';
SELECT 'trunks technology SIP', COUNT(*) FROM trunks
 WHERE UPPER(COALESCE(technology, '')) = 'SIP';
SELECT 'trunks technology IAX2', COUNT(*) FROM trunks
 WHERE UPPER(COALESCE(technology, '')) = 'IAX2';
```

O resultado atual foi, respectivamente, `0`, `0`, `0`, `0`, `0`, `0`. A
agregação geral de `peers.canal` contém uma única linha `PJSIP/1085`; a
ausência de SIP/IAX2 no snapshot é prova de conteúdo atual, não prova de que
o modelo de persistência ou seus consumidores possam ser removidos.

| Caminho legado | Prova atual | Estado de alcance | Disposição permitida |
| --- | --- | --- | --- |
| Criar/editar ramal SIP/IAX2 pela UI | `extensions/addedit.phtml:80` e `multiadd.phtml:50` submetem somente `technology=pjsip`. | `DEAD` para o seletor visível legado. | Manter a UI PJSIP-only. |
| POST direto de ramal SIP/IAX2 | `ExtensionsController::execAdd()` e `multiaddAction()` rejeitam tecnologia diferente de `pjsip` antes da persistência (`ExtensionsController.php:574-638,1203-1215`); a edição de `canal` não-PJSIP é redirecionada (`:287-296`). | `LIVE_BUT_BROKEN` — rota MVC existente, bloqueio deliberado. | Manter o guard; não recriar o caminho legado. |
| Ramal SIP/IAX2 persistido | `PBX_Usuarios::get()` deriva a tecnologia de `peers.canal` e ainda instancia SIP/IAX2 (`PBX/Usuarios.php:53-85`); o banco atual tem zero linhas legadas. | `HIDDEN_REACHABLE`, condicionado a restauração/migração de dado histórico. | Preservar leitura até migração de dados comprovada. |
| Criar/editar tronco SIP/IAX2 pela UI ou POST | A view oferece apenas `pjsip` e `pjsip_external`; `TrunksController::preparePost()` permite apenas esses dois valores (`TrunksController.php:616-622`). | `DEAD` para seletor visível; `LIVE_BUT_BROKEN` para POST legado forjado. | Manter a allowlist. |
| Tronco SIP/IAX2 persistido | `PBX_Trunks::get()` ainda despacha por `trunks.type` para SIP/IAX2, inclusive NOAUTH (`PBX/Trunks.php:90-113`); as duas colunas de tecnologia retornaram zero. | `HIDDEN_REACHABLE`, condicionado a dado histórico/restaurado. | Não remover fábrica/campos nesta auditoria. |
| API/AJAX de escrita | `api/index.php` mantém registro fechado de seis serviços de relatório, contatos e exportação; não há serviço de provisionamento de ramal/tronco. Exportação pode ler tabelas, mas não cria tecnologia. | `DEAD` para API standalone de escrita; `HIDDEN_REACHABLE` apenas para leitura/exportação de valor que venha a existir. | Conclusão limitada a `modules/default/api`; reauditar qualquer API fora dessa árvore. |

#### T04 — inventário de dialplan em execução e cadeia genérica

Foi executado no diretório raiz, com filtro no host, o comando exigido:

```bash
docker compose exec -T asterisk asterisk -rx "dialplan show" \
  > /tmp/task-0028-dialplan-show.txt
rg -n -i 'PJSIP/|SIP/|IAX2/|SIPAddHeader|Dial\(|Channel:' \
  /tmp/task-0028-dialplan-show.txt
```

O Asterisk ativo reportou 44 extensões e 183 prioridades em 10 contextos. O
filtro retornou: `Dial(${INTERFACE},${ARG2},${ARG3})`
(`extensions.conf:135`), `SIPAddHeader(Alert-Info: Bellcore-r2)`
(`extensions.conf:113`), `Dial(SIP/1003,60,twg)` (`preagi.conf:6`) e
`Channel: SIP/${EXTEN:3}` (`snep-features.conf:99`). Não retornou token direto
`PJSIP/` ou `IAX2/`; essa ausência não substitui a resolução da variável.

O transcript literal do filtro no host nesta revalidação é o seguinte; a
captura integral teve 205 linhas. Ele é a prova de runtime para esta tarefa,
não uma busca estática nos templates do repositório:

```text
43:                    11. Dial(${INTERFACE},${ARG2},${ARG3})        [extensions.conf:135]
49:                    4. SIPAddHeader(Alert-Info: Bellcore-r2)      [extensions.conf:113]
74:                    2. Dial(SIP/1003,60,twg)                      [preagi.conf:6]
132:                    3. System(echo "Channel: SIP/${EXTEN:3}" >> /tmp/${CALLERID(num)}-${EXTEN:3}.call) [snep-features.conf:99]
```

| Contexto ativo | Construção | Origem da tecnologia e prova | Estado |
| --- | --- | --- | --- |
| `hints` | `Dial(SIP/1003,60,twg)` | SIP literal no dialplan em execução; `chan_sip` não está carregado no snapshot T01. | `LIVE_BUT_BROKEN` |
| `default` callback | `Channel: SIP/${EXTEN:3}` em `.call` | SIP literal em prioridade ativa do contexto `default`; é produzido quando `_*33XXXX` é discado. | `LIVE_BUT_BROKEN` |
| `ramais-agentes` | `SIPAddHeader(...)` antes de `Macro(dialpeer,...)` | Aplicação SIP literal em prioridade ativa; o caminho de regra também condiciona o cabeçalho a tecnologia SIP. | `LIVE_BUT_BROKEN` |
| `macro-dialpeer` | `AGI(resolv_interface.php,...,INTERFACE)` seguido de `Dial(${INTERFACE},...)` | O AGI chama `PBX_Usuarios::get()` e usa o canal derivado de `peers.canal`; a fábrica seleciona SIP, IAX2 ou PJSIP. `SIGAME` pode sobrescrever `INTERFACE`, sendo também valor de `peers`. O snapshot atual resolve os dados existentes para PJSIP, mas a cadeia aceita legado persistido. | `LIVE_REACHABLE` para PJSIP; `HIDDEN_REACHABLE` para SIP/IAX2 |
| `default` pickup/spy | `resolv_interface.php` alimenta `PickupChan` e `ChanSpy(${INTERFACE},...)` | Mesma cadeia AGI → `PBX_Usuarios::get()` → `peers.canal`, em prioridades ativas de `snep-features.conf`. | `LIVE_REACHABLE` para PJSIP; `HIDDEN_REACHABLE` para SIP/IAX2 |
| discagem por regra/tronco | Interface/fábrica retorna dial string | `PBX_Trunks::get()` ainda seleciona SIP/IAX2/PJSIP por `trunks.type`; `PBX_Interfaces::getChannelOwner()` compara `trunks.id_regex` e `peers.canal`. | `HIDDEN_REACHABLE` para SIP/IAX2; `LIVE_REACHABLE` para PJSIP |

Assim, os tokens SIP diretos estão ativos mas quebrados no runtime atual por
ausência de `chan_sip`; IAX2 não possui token direto ativo, mas permanece
alcançável por resolução genérica baseada em valores persistidos. A prova é
limitada ao snapshot: reativar um driver ou restaurar registros legados exige
nova coleta antes de qualquer declaração de remoção.

## 14. TASK-0028-DIAG / TASK-0028-DIAG2 — auditoria independente (2026-09-03T21:59-03)

Esta seção é uma segunda rodada de evidência independente, somente leitura.
Não executou geração, reload, escrita SQL nem alteração de configuração.
Corrige um ponto do §13 (registrado inline nos parágrafos correspondentes,
acima) e fecha as lacunas explicitamente pedidas: status de include de
`snep-sip-hints.conf`, achado de vazamento de contexto, snapshot atual do
banco com timestamp, auditoria de escritores das quatro colunas
(`peers.canal`, `trunks.type`, `trunks.channel`, `trunks.technology`) e
proveniência de `custom/preagi.conf`.

### 14.1 Correção: `snep-sip-hints.conf` está incluído

O §13.2/§13.4 originais classificavam a diretiva em `snep-features.conf:170`
como "comentada" e portanto sem efeito. Isso não resiste à inspeção direta:

```
$ sed -n '169,170p' /etc/asterisk/snep/snep-features.conf | od -c
...  i n c l u d e   = >   c o n f e r e n c e s \n
     # i n c l u d e   s n e p / s n e p - s i p - h i n t s . c o n f \n
```

Não há `;` antes de `#include`. Na sintaxe de configuração do Asterisk,
`;` inicia comentário; `#include` é um comando de pré-processador processado
incondicionalmente — não é uma linha "comentável" da mesma forma que uma
`exten =>`. `snep-features.conf` não tem nenhum cabeçalho `[contexto]` próprio
(confirmado por busca recursiva sensível a locale — o locale padrão do host
trata esse arquivo como binário por conter comentários em ISO-8859 e
retorna zero resultados *sem erro*; foi necessário forçar `LC_ALL=C grep -a`).
Logo, todo o conteúdo desse arquivo herda o contexto `[default]` aberto em
`extensions.conf:47`, até sua última linha (`#include
snep/snep-sip-hints.conf`) abrir de fato um novo contexto `[hints]` via o
cabeçalho `[hints]` que esse arquivo incluído carrega.

**Classificação corrigida:** `snep-sip-hints.conf` = `INCLUDED_DIRECTLY` /
`GENERATED_AND_LOADED`, não `NOT_INCLUDED`/`GENERATED_BUT_NOT_LOADED`. Não
contribui dado algum hoje (sua seção `[hints]` está vazia), mas está de fato
carregado, e essa inclusão tem um efeito colateral real e verificável — ver
§14.2. Os outros cinco arquivos legados permanecem `NOT_INCLUDED`, como já
registrado no §13.

### 14.2 Achado de vazamento de contexto (context-bleed)

Efeito colateral direto de §14.1: `extensions.conf:50` faz `#include
custom/preagi.conf` logo após `#include snep/snep-features.conf` terminar
(linha 48). `custom/preagi.conf` também não tem cabeçalho `[contexto]`
próprio (confirmado por leitura direta do arquivo). Como o `[hints]` aberto
pela inclusão de `snep-sip-hints.conf` é o último contexto aberto na cadeia
até aquele ponto, o conteúdo sem cabeçalho de `preagi.conf` é anexado a esse
contexto — não a `[default]`.

Prova em runtime, `dialplan show` (captura de 205 linhas, 10 contextos):

```
[ Context 'hints' created by 'pbx_config' ]
  '1234' =>         1. Noop(Saida manual)                         [preagi.conf:5]
                    2. Dial(SIP/1003,60,twg)                      [preagi.conf:6]
                    3. Hangup()                                   [preagi.conf:7]
```

Confirmação de que isso não é rotulagem genérica: `extensions.conf:52`
(`exten => _9XX,1,Goto(conferences,${EXTEN},1)`), que vem logo depois de
`preagi.conf` no mesmo arquivo-fonte, aparece corretamente sob `[ Context
'default' ]` no mesmo `dialplan show` — confirmando que o parser realmente
distingue os dois casos, não é um artefato de exibição.

Verificado adicionalmente: nenhuma configuração atribui `context=hints` a
qualquer endpoint/tronco/canal (`grep -rn 'context=hints' /etc/asterisk` sem
resultado), e não existe `Goto(...,hints,...)` nem equivalente em nenhum
arquivo. **A extensão `1234`/`Dial(SIP/1003,60,twg)` está carregada, mas sem
caminho de entrada comprovado** — refinamento da disposição de
`LIVE_BUT_BROKEN` (§13.6) para `LIVE_BUT_ORPHANED_AND_BROKEN`: mesmo que
alguém a alcançasse, ainda falharia por ausência de `chan_sip`.

### 14.3 Snapshot atual do banco (com timestamp)

Consulta live, mesma forma agregada do §13.5/§13.7, executada em
**2026-09-03T21:59:37-03:00** contra o serviço `db` em execução:

```sql
SELECT COUNT(*), SUM(canal LIKE 'SIP%'), SUM(canal LIKE 'IAX2%'), SUM(canal LIKE 'PJSIP%')
  FROM peers;
-- total=1, sip=0, iax2=0, pjsip=1
SELECT technology, COUNT(*) FROM trunks GROUP BY technology;
-- (vazio: 0 linhas na tabela trunks)
```

**Isto diverge dos números registrados em §13.5/§13.7 no mesmo dia** (`peers
/ PJSIP / 5`, `trunks / PJSIP / 1`, coletados por volta de 15h). O conjunto
de dados mudou dentro do mesmo dia — provável limpeza de fixtures de smoke
test entre sessões, não confirmado. A conclusão direcional (zero linhas
legadas, tudo PJSIP) não muda, mas nenhuma contagem específica deste
documento deve ser tratada como estável entre execuções sem novo timestamp.

### 14.4 Auditoria exaustiva de escritores — `peers.canal`, `trunks.type`, `trunks.channel`, `trunks.technology`

Busca exaustiva no repositório inteiro (não apenas `snep/modules/default`):
`snep/agi/*`, `snep/lib/**`, `snep/modules/**`, `snep/install/database/**`
(schema e todos os diretórios de migração de versão), `snep/modules/default/api/actions/*`,
`scripts/*`, `docker/*`. Classificação conforme definição do TASK-0028-DIAG2
(`CURRENT_SUPPORTED_WRITE`, `LEGACY_WRITE`, `DEAD`, `INSTALL_ONLY`,
`TEST_ONLY`).

| # | Local | Mecanismo | Coluna(s) e valor | Alcance | Classificação |
| --- | --- | --- | --- | --- | --- |
| 1 | `ExtensionsController.php:859,869` (`execAdd()`) | `Zend_Db update/insert('peers', ...)` | `peers.canal = 'PJSIP/'.exten` — `$techType` já travado em `'pjsip'` pelo guard das linhas 627-638 | POST vivo de criação/edição de ramal; também `multiaddAction()` (guard idêntico, linhas 1211-1215) | `CURRENT_SUPPORTED_WRITE` |
| 2 | `TrunksController.php:262,271,276,516,518` (`addAction()`/`editAction()`) | `Zend_Db insert/update('trunks'/'peers', ...)` | `trunks.type`, `trunks.technology`, `trunks.channel`(`id_regex`), `peers.canal` — todos derivados de `$tech`, já restrito a `pjsip`/`pjsip_external` por `preparePost()` (linhas 619-622) | POST vivo de criação/edição de tronco | `CURRENT_SUPPORTED_WRITE` |
| 3 | `TrunksController.php:~754-848` (ramos residuais SIP/IAX2/SNEPSIP/SNEPIAX2/KHOMP dentro de `preparePost()`) | Construção de array que alimentaria os mesmos inserts do #2 | Escreveria `trunks.type`/`channel`/`technology` legados | Inalcançável: está na mesma função cujo guard incondicional (linha 620) já retornou antes para qualquer `$tech` fora de `{pjsip, pjsip_external}` | `DEAD` |
| 4 | `snep/lib/Snep/Extensions.php:195,297` (`Snep_Extensions::commit()`/`update()`) | `Zend_Db insert/update('peers', ...)` | `peers.canal = $exten->getInterface()->getCanal()` — sem guard próprio, aceitaria qualquer tecnologia | `grep -rn "new Snep_Extensions("` em todo o repositório (incl. testes) = zero ocorrências; classe nunca instanciada | `DEAD` |
| 5 | `snep/install/database/{schema,system_data,core-cnl,database}.sql` + todo `snep/install/database/update/*/` (3.01 a 3.07, betha) | `INSERT INTO` | `peers`/`trunks` | Busca exaustiva por `INSERT INTO ... peers`/`trunks`: zero ocorrências em qualquer script de instalação/migração | Superfície `INSTALL_ONLY` confirmada vazia — nada a classificar |
| 6 | `snep/modules/default/api/actions/*.php` (todos os 8 arquivos) | — | — | Zero `->insert(`/`->update(` no diretório inteiro; os 4 arquivos que leem `peers`/`trunks` (`CSV_GetParamsService`, `ServicesReportService`, `RankingReportService`, `CallsReportService`) são exportação somente-leitura | Confirmado não-escritor |
| 7 | `scripts/pjsip-config-security-smoke-test.sh:406-413` (Makefile `lint`/suíte de segurança) | POST HTTP vivo `technology=sip` → `/extensions/add` | `peers.canal` (seria `SIP/<ext>` se tivesse sucesso) | Este é o fixture F15 do TASK-0026E; seu próprio comentário (linha 400-401) descreve `technology=sip` como "opção ainda selecionável na UI atual" — não é mais verdade após o guard de `execAdd()` (commit `0943794`, 2026-09-03 11:46, posterior a todo o histórico deste script) | `TEST_ONLY` — **ver nota de risco abaixo** |
| 8 | `scripts/residual-sql-security-smoke-test.sh:415-422` (fixture CANARY do BLOCKER A, TASK-0026J) | POST HTTP vivo `technology=sip` → `/trunks/add` | `trunks.type`/`peers.canal` | Mesma situação: `preparePost()` (linha 619-622, mesmo commit `0943794`) rejeitaria antes de qualquer insert | `TEST_ONLY` — **ver nota de risco abaixo** |
| 9 | `scripts/residual-sql-security-smoke-test.sh:1928,2130` | `$db->insert('peers', [...'canal' => 'MANUAL/x'])` direto, sem passar por controller | `peers.canal = 'MANUAL/x'` | Fixtures canário TASK-0026N/O para prova de SQL injection, só acionadas pelo próprio script de teste | `TEST_ONLY` |
| — | `snep/lib/Snep/InterfaceConf.php` | — | — | Confirmado: só `SELECT` (linhas 74, 133) e `file_put_contents()` nos arquivos gerados — nunca escreve no banco | Não é escritor |
| — | `snep/agi/{dnd,followme,padlock}.php` | `Zend_Db update`/SQL | `dnd`, `sigame`, `authenticate` | Escritas AGI vivas, mas em colunas fora do escopo das quatro auditadas; `followme.php:67` escreve `peers.sigame`, que pode sobrescrever `${INTERFACE}` diretamente (`extensions.conf:131`) — fora do escopo mas registrado para consciência futura | Fora do escopo (nenhuma das 4 colunas) |

**Nota de risco (#7/#8, não confirmada por execução — está fora do escopo deste
audit rodar a suíte):** análise estática indica que essas duas asserções
provavelmente falhariam (`harness_bad`) se a suíte fosse executada hoje,
porque o guard PJSIP-only (commit `0943794`) bloqueia exatamente o POST que
essas fixtures dependem para se criar. Isso é mais sério para o item #8: a
prova de regressão de injeção SQL do BLOCKER A (TASK-0026J) depende de
primeiro criar esse tronco CANARY `technology=sip`; se essa criação falhar
hoje, a cobertura de regressão daquele achado de segurança pode estar
efetivamente sem execução real, silenciosamente, desde o commit `0943794`.
**Recomenda-se rodar `make regression` (ou os dois scripts isoladamente) para
confirmar antes de considerar o `SECURITY_GATE = GO` do TASK-0026 ainda
totalmente coberto por execução automática.** Isto não é reavaliação do
SECURITY_GATE em si — nenhum defeito de segurança novo foi encontrado, é o
oposto: o bloqueio está funcionando bem demais para o fixture que o testava.

**Resumo:** nenhum escritor além dos já conhecidos caminhos
`ExtensionsController`/`TrunksController`, ambos travados em PJSIP, consegue
hoje colocar um valor legado nas quatro colunas auditadas. A única classe
com capacidade de escrita legada e sem guard (`Snep_Extensions`) está
comprovadamente morta; instalação/schema nunca semeou nenhuma das duas
tabelas; a camada de API é somente leitura.

### 14.5 Proveniência de `custom/preagi.conf`

**Histórico git:** um único commit tocou este arquivo,
`b88e1966` ("chore: bootstrap Claude Code development harness", Diego RA,
2026-08-24), que o *adicionou* com o conteúdo atual, verbatim, nunca mais
alterado. Apesar do título do commit, `git show --stat b88e196` mostra um
import de 4187 arquivos/999.245 inserções — o drop original do código-fonte
SNEP, não um commit específico do SENMA. O commit anterior (`e36ea27`,
"Initial commit") não contém nenhum caminho `install/etc/asterisk`
(`git ls-tree -r e36ea27 | grep install/etc/asterisk` vazio). **Portanto,
`preagi.conf` é conteúdo original do SNEP upstream, não algo introduzido por
trabalho específico do SENMA**, apesar do título do commit sugerir o
contrário.

**Origem como template de instalação:** `docker/asterisk-entrypoint.sh:96-100`
copia `$SNEP_ASTERISK_DIALPLAN_SRC/custom/{preagi,posagi,eof}.conf` (ou seja,
`snep/install/etc/asterisk/custom/*.conf`) para `$ASTERISK_ETC/custom/`,
conteúdo estoque, sem template algum.

**Idempotência confirmada por leitura direta:** todo esse bloco de cópia está
sob `if [ ! -f "$ASTERISK_ETC/asterisk.conf" ]` (`asterisk-entrypoint.sh:82`)
— só executa no primeiro boot. Uma vez que `/etc/asterisk/asterisk.conf`
exista (isto é, após o primeiro boot bem-sucedido contra um dado volume),
essa cópia nunca roda de novo; edições do cliente em `custom/preagi.conf`
sobrevivem a reinícios/rebuilds enquanto o volume persistir. Não há
sobrescrita incondicional.

**Referências em outros lugares:** apenas duas menções em todo o
repositório: este próprio documento de auditoria (TASK-0028), e
**`docs/tasks/0008-legacy-telephony-runtime-audit.md:47`**, uma auditoria
anterior que afirma que `custom/{preagi,posagi,eof}.conf` são "arquivos de
hook vendorizados/**vazios**... pontos de extensão intencionalmente vazios."
Essa afirmação está factualmente errada especificamente para `preagi.conf`
— `posagi.conf`/`eof.conf` são de fato só-comentário/vazios, mas
`preagi.conf` sempre trouxe a extensão de 3 linhas `1234`/`Dial(SIP/1003,60,twg)`.
Nenhum outro arquivo, código ou documento trata a extensão `1234` como um
hook conhecido/intencional — não há smoke test, README ou comentário que a
referencie como deliberada.

**Determinação de intenção:** o próprio comentário de cabeçalho do arquivo
("arquivo para customização... inserido logo ANTES da execução do controle
de ligação pelo Agi SNEP") documenta um mecanismo de hook genuinamente
editável pelo cliente — esse mecanismo é real e intencional. Mas o *conteúdo
que é entregue* não é um placeholder neutro: é uma extensão concreta e
discável, amarrada a uma tecnologia legada específica (`SIP/1003`) e a um
cenário de teste ("Saida manual"), que uma auditoria anterior (TASK-0008)
aparentemente nunca abriu de fato antes de declarar que estava vazio. Isso
lê como conteúdo de exemplo/teste esquecido do SNEP upstream, ao redor do
qual um mecanismo de hook para clientes foi construído — não como um exemplo
deliberadamente curado. **Sim** — um `make dev` novo (volume vazio) entrega
essa extensão `Dial(SIP/1003,60,twg)` inalterada, carregada no dialplan ativo,
de fábrica.

Disposição recomendada (fora do escopo de implementação deste audit):
`DEFER_WITH_REASON` — corrigir `docs/tasks/0008-legacy-telephony-runtime-audit.md:47`
e decidir, em tarefa dedicada de dialplan, se o conteúdo de exemplo de
`preagi.conf` deve ser substituído por um placeholder verdadeiramente vazio
(preservando o mecanismo de hook) antes de qualquer remoção de `chan_sip`.

### 14.6 Conclusão de arquitetura final

```text
APPLICATION_EFFECTIVELY_PJSIP_ONLY
```

Mantida em relação ao §12, com evidência adicional que reforça e refina a
mesma conclusão, não a muda: a superfície de escrita das quatro colunas
auditadas está hoje travada em PJSIP/PJSIP_EXTERNAL sem exceção viva
(§14.4); o único ramo de escrita legada sem guard é código morto comprovado
(`Snep_Extensions`); nenhum script de instalação semeia tecnologia legada; a
API é só-leitura. O que resta como dívida antes de uma reivindicação limpa de
"PJSIP-only" (não apenas "efetivamente PJSIP-only"): (a) `InterfaceConf` e as
classes de interface SIP/IAX2 continuam plenamente ativas como caminho de
leitura/compatibilidade (`YES_COMPATIBILITY_ONLY`, §5 do TASK-0028-DIAG); (b)
`snep-sip-hints.conf` está de fato incluído, com o efeito colateral de
vazamento de contexto do §14.2 ainda não corrigido; (c) a extensão órfã
`1234`/`Dial(SIP/1003,...)` e o gerador de spool `*33XXXX` com
`Channel: SIP/...` continuam carregados; (d) a cobertura de regressão de
segurança do BLOCKER A (TASK-0026J) pode estar sem execução real desde o
guard PJSIP-only, pendente de confirmação por execução (§14.4); (e)
`custom/preagi.conf` entrega conteúdo de exemplo legado de fábrica, não um
placeholder vazio, contradizendo o que uma auditoria anterior registrou.
Nenhum desses cinco pontos é alcançável a partir de UI, API ou dado
persistido atual — por isso a arquitetura já é "efetivamente" PJSIP-only no
produto — mas nenhum foi removido, então "PJSIP-only" como propriedade da
arquitetura (não do produto) ainda depende do fechamento do TASK-0028C.

## 15. Atualização — fechamento do TASK-0028C (2026-09-04)

TASK-0028C implementou o fechamento descrito acima como dependência.
Registro objetivo, sem reescrever a análise original: ver
`docs/tasks/0028c-pjsip-legacy-runtime-closure.md` para evidência completa.

- Item (b) do §14.6 — **fechado**: o vazamento de contexto do §14.2 foi
  corrigido (reabertura explícita de `[default]` em `extensions.conf`
  antes do include de `custom/preagi.conf`); `snep-sip-hints.conf`
  continua incluído (mantido — caminho de compatibilidade real para hints
  BLF), mas seu efeito colateral de vazamento foi isolado.
- Item (c) do §14.6 — **fechado**: `custom/preagi.conf`'s `1234` agora
  discia `PJSIP/1003` (não mais `SIP/1003`); o gerador `*33XXXX` agora
  escreve `Channel: PJSIP/${EXTEN:3}` no `.call` gerado — provado ao vivo,
  ponta a ponta, com dois endpoints PJSIP reais (originação, toque e
  atendimento confirmados no log do Asterisk).
- Item (e) do §14.6 — **parcialmente fechado**: o token de tecnologia do
  exemplo em `custom/preagi.conf` foi corrigido para PJSIP; a decisão
  tomada foi preservar o exemplo (agora funcional) em vez de substituí-lo
  por um placeholder vazio, já que corrigir o vazamento do item (b) o
  tornou alcançável pela primeira vez e um `Dial()` quebrado ali seria
  pior que o exemplo original. `docs/tasks/0008-legacy-telephony-runtime-audit.md:47`
  continua com a afirmação factualmente incorreta ("vazio") pendente de
  correção — não alterada nesta tarefa (fora do escopo do TASK-0028C).
- Itens (a) e (d) do §14.6 — **não alterados**, permanecem como dívida:
  `InterfaceConf`/classes de interface SIP/IAX2 seguem ativas como
  caminho de compatibilidade (decisão explícita, não regressão); a
  confirmação por execução do BLOCKER A (TASK-0026J) não foi revisitada
  nesta tarefa.
- Achados adicionais do TASK-0028C, fora do escopo original deste
  documento: `SIPAddHeader` incondicional em `[ramais-agentes]`
  (convertido para `PJSIP_HEADER`, contexto ainda órfão); duas chamadas
  AMI mortas (`sip reload`/`iax2 reload`) removidas de
  `Snep_InterfaceConf::loadConfFromDb()`, confirmadas ao vivo como no-ops
  neste runtime.

A conclusão `APPLICATION_EFFECTIVELY_PJSIP_ONLY` permanece válida e não
muda — esta atualização fecha parte da dívida que a separava de
"PJSIP-only" como propriedade de arquitetura, não revisa o diagnóstico.
