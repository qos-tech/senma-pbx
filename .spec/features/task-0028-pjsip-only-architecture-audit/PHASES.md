# Phases: task-0028-pjsip-only-architecture-audit

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/task-0028-pjsip-only-architecture-audit/PHASES.md`.

## Phase 1: Independent evidence collection

Antes de implementar, leia:
1. `.spec/features/task-0028-pjsip-only-architecture-audit/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/task-0028-pjsip-only-architecture-audit/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Establish runtime and include/load ledger
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`
      Mudança: Registrar módulos, ODBC, cadeia de include e conteúdo redigido dos seis arquivos sem mutação.
      Cobre: RF-01, RF-02, RF-03
      Acceptance criteria: Cada arquivo legado tem cadeia de carga e classificação de conteúdo reproduzível.
      Testes: comandos da seção E do PLAN.md — somente leitura, sem reload.
- [ ] T02 — Trace source generators to configuration and runtime effects
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`, `snep/lib/Snep/`, `snep/modules/default/controllers/`, `docker/`
      Mudança: Mapear entry point, alcance, DB, arquivo e reload/load de cada gerador.
      Cobre: RF-05, RF-07
      Acceptance criteria: Todas as famílias geradas têm cinco campos ou lacuna limitada.
      Testes: buscas da seção F do PLAN.md.

## Phase 2: Product and active-dialplan trace

Antes de implementar, leia:
1. `.spec/features/task-0028-pjsip-only-architecture-audit/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/task-0028-pjsip-only-architecture-audit/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T03 — Audit product, API, and database technology reachability
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`, `snep/modules/default/`, `snep/lib/PBX/`
      Mudança: Classificar criação/edição visível, oculta, POST/API e valores persistidos SIP/IAX2.
      Cobre: RF-06, RF-07
      Acceptance criteria: Cada caminho de ramal/tronco SIP/IAX2 está alcançável, bloqueado ou inconclusivo com prova.
      Testes: busca de código/API e consulta DB agregada somente-leitura.
- [ ] T04 — Classify active dialplan and generic channel construction
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`, `snep/install/etc/asterisk/`, ações/AGI
      Mudança: Inventariar tokens ativos e resolver cadeias de variáveis de interface/canal.
      Cobre: RF-04, RF-07
      Acceptance criteria: Tokens diretos/genéricos têm contexto ativo e origem de dados, ou lacuna limitada.
      Testes: `docker compose exec asterisk asterisk -rx "dialplan show"` com filtro no host.

## Phase 3: Classification and documentation

Antes de implementar, leia:
1. `.spec/features/task-0028-pjsip-only-architecture-audit/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/task-0028-pjsip-only-architecture-audit/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T05 — Build finite architecture classification and follow-up grouping
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`
      Mudança: Consolidar matriz por sete domínios e recomendar 2–4 tarefas posteriores sem iniciá-las.
      Cobre: RF-07, RF-10
      Acceptance criteria: Nenhum item legado fica sem estado de alcance e disposição permitida.
      Testes: Checagem de cobertura contra todas as listas de evidência.
- [ ] T06 — Record audit evidence without changing human analysis
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`
      Mudança: Acrescentar matrizes e checkpoint, preservando texto humano e segredos.
      Cobre: RF-03, RF-10
      Acceptance criteria: O diff atribuível contém apenas acréscimos de evidência de auditoria e nenhum segredo.
      Testes: revisão de diff.

## Phase 4: Independent challenge

Antes de implementar, leia:
1. `.spec/features/task-0028-pjsip-only-architecture-audit/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/task-0028-pjsip-only-architecture-audit/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T07 — Conduct adversarial review of dead and PJSIP-only claims
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`
      Mudança: Desafiar conclusões com includes indiretos, nomes dinâmicos, campos ocultos, rotas, DB e AGI.
      Cobre: RF-08
      Acceptance criteria: Todo item DEAD/não carregado tem resultado; pendências viram INCONCLUSIVE.
      Testes: matriz de objeções e resoluções.

## Phase 5: Final validation

Antes de implementar, leia:
1. `.spec/features/task-0028-pjsip-only-architecture-audit/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/task-0028-pjsip-only-architecture-audit/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T08 — Validate audit-only checkpoint
      Arquivos: `docs/tasks/0028-pjsip-only-architecture-audit.md`
      Mudança: Registrar os gates e confirmar que nenhuma mudança de comportamento foi feita.
      Cobre: RF-09
      Acceptance criteria: `make lint`, `make regression`, `git diff --check` e `git status --short` foram reportados sem correções ad hoc.
      Testes: os quatro comandos obrigatórios.
