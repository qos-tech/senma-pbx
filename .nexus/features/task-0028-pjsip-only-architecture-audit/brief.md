---
stepsCompleted: [1, 2, 3, 4, 5]
inputDocuments:
  - ".nexus/features/task-0028-pjsip-only-architecture-audit/feature.yaml"
  - "docs/tasks/0028-pjsip-only-architecture-audit.md"
  - "docs/tasks/0028a-pjsip-extension-product-surface.md"
  - "docs/tasks/0028b-pjsip-external-endpoint-trunks.md"
  - "docs/tasks/0028c-pjsip-legacy-runtime-closure.md"
date: "2026-09-02"
author: "Diego"
---

# Brief de Produto: SENMA PBX

<!-- O conteúdo será construído sequencialmente por descoberta colaborativa. -->

## Resumo executivo

O SENMA PBX precisa concluir sua transição de um produto PJSIP-first para um
produto PJSIP-only. A base atual já provisiona ramais, troncos e transportes
PJSIP, porém superfícies de criação, POSTs diretos, dados persistidos,
geradores, fábricas e trechos de dialplan ainda tornam SIP/IAX alcançáveis.
Essa ambiguidade amplia o custo operacional e de manutenção, além de tornar
arriscada qualquer remoção prematura de componentes legados.

O resultado desejado é sequencial: primeiro, toda nova provisão e todo
roteamento devem obedecer exclusivamente a contratos PJSIP; depois, os
componentes SIP/IAX só serão removidos fisicamente após evidência de que não
existem produtores, dados ou regras dependentes. A padronização completa em
PJSIP entrega um contrato operacional único para administradores e uma
arquitetura mais coerente e sustentável para a engenharia.

---

## Visão central

### Declaração do problema

O SENMA opera hoje com uma arquitetura híbrida: PJSIP é a tecnologia atual,
mas caminhos SIP/IAX permanecem visíveis ou alcançáveis por interfaces,
requisições diretas, registros históricos e lógica de geração ou discagem.
Como esses caminhos ainda podem produzir ou consumir configuração operacional,
a remoção de drivers, classes, arquivos ou campos legados sem migração
verificável pode interromper serviços ou corromper a semântica de registros
existentes.

### Impacto do problema

Para administradores e operações de PBX, a coexistência de tecnologias cria
incerteza sobre quais opções são suportadas, qual configuração chega ao
Asterisk e quais mudanças são seguras. Para engenharia e manutenção, ela
preserva ramificações, testes e compatibilidades que impedem uma fronteira
clara de produto e elevam o custo de evolução. Sem o encerramento controlado
desse estado misto, capacidades futuras de telefonia continuam apoiadas em
contratos ambíguos e difíceis de validar.

### Por que as soluções atuais não bastam

Ter geradores PJSIP e runtime PJSIP carregado não basta: a superfície de
produto ainda aceita ou interpreta tecnologias legadas, e dados como
`canal`, `channel`, `id_regex` e `technology` continuam sendo dependências de
migração. Bloquear ou apagar o legado apenas por contagem lexical ou por uma
observação isolada de runtime trocaria ambiguidade por ruptura. A abordagem
atual precisa evoluir de coexistência implícita para uma sequência explícita de
fechamento, migração, prova e remoção.

### Solução proposta

Estabelecer PJSIP como o único contrato para novas criações e roteamentos,
preservando compatibilidade de leitura e uma migração explícita para registros
legados. A iniciativa deve fechar superfícies e POSTs legados, completar os
contratos PJSIP para ramais, troncos e endpoints externos, migrar dados e
regras dependentes e, somente então, retirar geradores, includes, reloads,
dialplan e módulos SIP/IAX que se tornarem comprovadamente inalcançáveis.

### Diferenciais principais

- Padronização completa da operação e da arquitetura em PJSIP, em vez de
  manter tecnologias concorrentes sob uma interface única.
- Sequenciamento verificável: contrato PJSIP-only primeiro; remoção física do
  legado somente após prova de zero produtores e dados dependentes.
- Migração não destrutiva: nenhum registro legado é convertido ou eliminado
  silenciosamente.
- Decisões apoiadas em evidência de rota, persistência, geração, inclusão e
  runtime, não apenas em buscas textuais ou intenção arquitetural.

---

## Usuários-alvo

### Usuários primários

**Marina — administradora de PBX e operações de telefonia.** Marina pode
administrar a telefonia crítica de sua própria organização ou operar ambientes
gerenciados para vários clientes. Ela cria e altera ramais, troncos e
transportes, precisa preservar continuidade de serviço e responder por cada
mudança aplicada. Seu objetivo é trabalhar com uma fronteira de suporte
inequívoca: uma nova configuração deve produzir exclusivamente o contrato
PJSIP esperado, sem opções legadas ocultas, sem canais arbitrários e sem
surpresas entre a UI, a persistência e o Asterisk. Ela considera a iniciativa
bem-sucedida quando pode operar PJSIP com previsibilidade e tratar registros
legados por uma migração explícita, sem conversões silenciosas.

**Rafael — engenheiro de manutenção e operação da plataforma SENMA.** Rafael
evolui o núcleo legado com segurança e também responde pela automação de
entrega, pelo runtime e pela regressão da plataforma. Ele precisa identificar
produtores e consumidores de SIP/IAX antes de removê-los, distinguir evidência
de alcance de mera ocorrência lexical e manter o ambiente reproduzível. Seu
objetivo é reduzir ramificações e compatibilidades históricas até que o produto
tenha um único contrato de telefonia. Para Rafael, sucesso é poder encerrar um
componente legado com prova de zero dados e produtores dependentes, cobertura
verde e comportamento operacional verificável.

### Usuários secundários

Não há um terceiro segmento prioritário nesta fase. Gestores técnicos,
suporte e demais equipes que dependem da telefonia se beneficiam indiretamente
de uma operação previsível e de menor risco, mas não são o foco de desenho da
solução.

### Jornada do usuário

1. **Diagnóstico e decisão:** Marina identifica uma necessidade de provisão
   ou mudança; Rafael mapeia a rota de UI, POST, persistência, geração e
   runtime que a suporta.
2. **Adoção do contrato PJSIP:** Marina cria ou altera o objeto usando apenas
   contratos PJSIP permitidos. Rafael valida que a mudança produz a
   configuração e o comportamento esperados, sem reintroduzir caminhos
   SIP/IAX.
3. **Primeiro momento de valor:** ambos observam uma mudança PJSIP aplicada de
   ponta a ponta, com fronteira explícita e resultado operacional verificável.
4. **Migração controlada:** registros, regras e identificadores legados são
   inventariados e migrados por etapas, sem conversão implícita.
5. **Segundo momento de valor:** Rafael remove um componente legado somente
   após demonstrar ausência de dependências; Marina mantém continuidade de
   serviço com uma operação padronizada em PJSIP.
6. **Rotina sustentável:** a plataforma passa a evoluir sobre um único
   contrato de telefonia, com menor ambiguidade para operações e manutenção.

---

## Métricas de sucesso

O sucesso será medido em duas fases, conectando previsibilidade operacional
para Marina à capacidade de evolução segura de Rafael:

1. **Adoção PJSIP-only:** 100% das novas provisões e roteamentos usam
   exclusivamente contratos PJSIP permitidos. Qualquer criação ou rota nova
   que aceite SIP/IAX ou um prefixo arbitrário é falha de aceitação.
2. **Encerramento seguro do legado:** para cada componente SIP/IAX removido,
   há evidência de zero produtores, zero dados dependentes e regressão verde.
   A remoção física sem os três requisitos não é contabilizada como sucesso.

Indicadores líderes devem acompanhar, por fluxo e por componente: superfícies
de criação bloqueadas para tecnologias legadas; POSTs legados rejeitados no
servidor; inventário de registros e regras dependentes; migrações explícitas
concluídas; e cobertura de smoke/regressão para os contratos PJSIP resultantes.

### Objetivos de negócio

- **Reduzir custo e risco de manutenção:** eliminar ramificações de
  compatibilidade e reduzir a probabilidade de incidentes causados por
  ambiguidade entre UI, persistência, geradores, dialplan e runtime.
- **Habilitar novas capacidades de telefonia:** estabelecer PJSIP como uma
  base única, explícita e verificável para evoluções posteriores do SENMA.

### Indicadores-chave de desempenho

| Indicador | Meta | Método de verificação | Decisão orientada |
| --- | --- | --- | --- |
| Novas provisões e roteamentos exclusivamente PJSIP | 100% antes do encerramento da fase um | Testes de superfície, POST direto, configuração gerada e smoke de chamada/tronco | Bloquear qualquer novo produtor SIP/IAX |
| Superfícies e POSTs legados acessíveis | 0 para novos objetos | Exercícios E2E e testes de validação server-side | Encerrar lacunas de criação e bypasses |
| Componentes legados removidos com gate completo | 100% dos removidos | Inventário de produtores e dados, evidência de runtime e regressão verde | Autorizar ou impedir cada remoção física |
| Registros/regras legados dependentes | 0 antes da remoção do respectivo componente | Inventário e migração explícita de `canal`, `channel`, `id_regex` e `technology` | Priorizar a próxima onda de migração |
| Regressão dos contratos PJSIP | Verde para o escopo afetado | Gates de lint, regressão e smokes executados em host com Docker | Liberar a progressão entre fases |

---

## Escopo de MVP

### Funcionalidades centrais

O MVP é o programa completo de transição PJSIP-only, entregue em ondas com
gates explícitos, e não uma remoção única de componentes:

1. **Auditoria e contrato-alvo:** manter o inventário de tecnologias,
   classificar alcance e dependências, decidir disposições de produto e
   sustentar o contrato PJSIP para ramais, troncos, transportes e endpoints
   externos.
2. **Fechamento de superfícies legadas:** remover da criação novas opções
   SIP/IAX/Manual/Virtual quando substituídas, oferecer PJSIP nos fluxos
   necessários e rejeitar tecnologias, canais e prefixos legados no servidor,
   inclusive por POST direto.
3. **Completude e migração PJSIP:** suportar os cenários de ramal, tronco,
   endpoint externo, roteamento, autenticação, registro, IP-auth e transport
   PJSIP exigidos; migrar explicitamente registros, regras e identificadores
   dependentes.
4. **Encerramento do legado:** substituir semânticas específicas de SIP no
   dialplan e retirar `InterfaceConf`, classes, includes, reloads, testes e
   módulos SIP/IAX somente depois do gate de evidência completo.

### Fora de escopo do MVP

Não há exclusões funcionais adicionais declaradas neste brief. Ainda assim,
mudanças correlatas só integram o programa quando forem necessárias para o
resultado PJSIP-only e tiverem escopo, evidência e validação explícitos. O
programa não autoriza conversões implícitas, perda de dados ou remoções sem o
gate definido de produtores, dados e regressão.

### Critérios de sucesso do MVP

- Todas as novas provisões e roteamentos usam exclusivamente PJSIP.
- As superfícies e os POSTs de criação não permitem reintroduzir SIP/IAX ou
  canais arbitrários para novos objetos.
- Os registros e regras legados são migrados por processo explícito, preservando
  compatibilidade de leitura enquanto necessária.
- Cada remoção física de componente legado apresenta zero produtores, zero
  dados dependentes e regressão verde no escopo afetado.
- Operações e engenharia conseguem verificar o comportamento pela cadeia UI,
  persistência, arquivos gerados, dialplan e runtime.

### Visão futura

Com uma base PJSIP-only comprovada, o SENMA poderá evoluir capacidades de
telefonia avançadas e integrações sobre um contrato único, ao mesmo tempo em
que consolida a modernização integral da plataforma. O programa reduz a
ambiguidade que hoje impede essas duas direções de avançarem com segurança.
