---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
inputDocuments:
  - ".nexus/features/task-0028-pjsip-only-architecture-audit/brief.md"
documentCounts:
  productBriefs: 1
  research: 0
  brainstorming: 0
  projectDocs: 0
classification:
  projectType: web_app
  domain: telecomunicações_voip
  complexity: alta
  projectContext: brownfield
workflowType: 'prd'
---

# Documento de Requisitos de Produto — SENMA PBX

**Autor:** Diego
**Data:** 2026-09-03

## Resumo executivo

O SENMA PBX deve concluir a transição de uma arquitetura PJSIP-first para
PJSIP-only. Embora a plataforma já provisione partes do domínio em PJSIP,
superfícies de criação, POSTs diretos, registros persistidos, geradores,
fábricas e segmentos de dialplan ainda podem aceitar, produzir ou consumir
SIP/IAX. Isso mantém um contrato de produto ambíguo e torna remoções legadas
arriscadas para administradores de PBX e para a engenharia de operação.

O resultado pretendido é um contrato único: toda nova provisão e todo novo
roteamento devem usar exclusivamente PJSIP. A compatibilidade de leitura para
dados legados permanece enquanto necessária, mas a conversão ocorre apenas por
migração explícita e verificável. Um componente SIP/IAX só poderá ser removido
depois de evidência de zero produtores, zero dados ou regras dependentes e
regressão verde no escopo afetado.

### O que torna esta iniciativa distinta

A iniciativa não trata a ocorrência textual de SIP/IAX como critério de
remoção. Ela exige rastrear a cadeia de superfície, POST, persistência,
geração, inclusão, dialplan e runtime para separar código inerte de
dependências operacionais. Essa sequência protege a continuidade de serviço e
reduz a ambiguidade que hoje eleva o custo de manutenção e limita a evolução da
plataforma.

### Classificação do projeto

- **Tipo:** aplicação web de administração de PBX.
- **Domínio:** telecomunicações / VoIP.
- **Complexidade:** alta, por criticidade operacional, contratos históricos e
  integração com Asterisk.
- **Contexto:** brownfield; a mudança é incremental e deve preservar o
  comportamento existente até que cada migração seja comprovada.
