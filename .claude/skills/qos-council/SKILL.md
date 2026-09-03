---
name: qos-council
description: Run a five-advisor council (Contrarian, First Principles, Expansionist, Outsider, Executor) with anonymous peer review and chairman synthesis for consequential decisions and real tradeoffs. Explicit triggers "council this", "run the council", "war room this", "pressure-test this", "stress-test this", "debate this". Contextual triggers only with genuine uncertainty or competing options, e.g. "should I choose X or Y", "I cannot decide". Skip for factual lookups, yes/no questions, casual choices, summarization, translation, or single-answer questions.
---

Read all files in `references/`. Execute the council workflow in `references/council.md` using the same semantics as the QoS Claude plugin.

1. Read `references/council.md` and the seven role files: `references/contrarian.md`, `references/first-principles.md`, `references/expansionist.md`, `references/outsider.md`, `references/executor.md`, `references/reviewer.md`, `references/chairman.md`.
2. Replace Claude Task-based sub-agent delegation with role passes in the current session: five isolated advisor passes (Contrarian, First Principles, Expansionist, Outsider, Executor — draft each without looking back at an earlier pass), then five isolated peer-review passes over the anonymized responses, then one chairman synthesis pass. Mark `advisor_execution_mode: sequential` and `peer_review_execution_mode: sequential` in the transcript — never claim these ran in parallel.
3. Preserve every role's contract: advisor isolation, the Outsider's missing `context_refs`, anonymization before review, reviewer blindness to advisor identity, and the chairman's five-section synthesis.
4. Use the user's arguments as the decision, question, or idea text (or a file path to it).
5. Write both `.qos-harness/reports/council/council-transcript-<UTC_TIMESTAMP>.md` and `.qos-harness/reports/council/council-report-<UTC_TIMESTAMP>.html` exactly as `references/chairman.md` defines — both are written by default, never gated behind a flag; skip only if the session has no write capability at all. Never write reports to the project root or into `.spec/`. Never claim multi-model consensus — this session ran within one engine.
6. Never read or recommend `.env`, `.env.*`, private keys, SSH key directories, credential stores, token caches, or unrelated home-directory files as context sources.
7. Return the chairman's full synthesis directly to the user; do not force them to open the transcript to learn the result.
