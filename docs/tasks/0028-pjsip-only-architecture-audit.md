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
única referência a arquivo legado é `#include snep/snep-sip-hints.conf`,
comentada na linha 170. `pjsip.conf` inclui somente os três arquivos
`senma-pjsip*`. Não há `sip.conf` nem `iax.conf` no runtime, embora os
templates de instalação os contenham. Portanto, nenhum dos seis artefatos
tem uma cadeia Asterisk ativa nesta coleta; a classificação não se baseia
apenas na ausência do arquivo, mas também na ausência dos drivers em execução
necessários para os parsers SIP/IAX2.

| Arquivo | Cadeia de carga reproduzida | Conteúdo efetivo redigido | Classificação |
| --- | --- | --- | --- |
| `snep-sip.conf` | Nenhuma cadeia ativa; o template `sip.conf` não está instalado; `chan_sip` não está carregado. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-sip-trunks.conf` | Nenhuma cadeia ativa; o template `sip.conf` não está instalado; `chan_sip` não está carregado. | 11 linhas: cabeçalho gerado somente; zero seções. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
| `snep-sip-hints.conf` | `extensions.conf -> snep/snep-features.conf -> #include ...` (comentado; não é include efetivo). | 2 linhas: seção `[hints]`; zero entradas `exten =>`. | `GENERATED_BUT_NOT_LOADED`; `headers/includes only` |
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

A inspeção recursiva das diretivas de include encontrou apenas os três
artefatos PJSIP em `pjsip.conf` (linhas 16, 17 e 24). Em `extensions.conf`, a
cadeia ativa é `extensions.conf:48 -> snep/snep-features.conf`; a única
referência a hint SIP nesse arquivo é a diretiva comentada da linha 170. Não
houve diretiva efetiva para nenhum dos seis arquivos legados. A inspeção
estrutural redigida mostrou 11 linhas de cabeçalho e zero seções de endpoint
ou tronco em cada um dos quatro arquivos de pares/troncos, e duas linhas
(` [hints]`, precedida por linha em branco) com zero `exten =>` em cada arquivo
de hints. O snapshot de instalação agora contém ambos os placeholders de hints
que `Snep_InterfaceConf::loadConfFromDb()` escreve, portanto os seis destinos
de geração podem ser conferidos também antes do bootstrap Docker.
