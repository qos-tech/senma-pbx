# TASK-0028C — PJSIP Legacy Runtime Closure

## Status

Implemented and validated. This supersedes the original Portuguese
planning stub (kept below in spirit, not literally — see "Relationship to
the original plan").

## Objective

TASK-0028's own audit (`docs/tasks/0028-pjsip-only-architecture-audit.md`)
concluded `APPLICATION_EFFECTIVELY_PJSIP_ONLY`: supported write paths are
PJSIP-only, but reachable runtime/configuration legacy remained. This task
closes the specific reachable items that audit's §14.6 left open, without
touching data migration, InterfaceConf's removal, or the separately-tracked
redundant-reload debt.

## 1. Live include graph (final)

```text
asterisk.conf
 -> extensions.conf [default]
      -> #include snep/snep-features.conf   (own context: default)
           -> ... 96 lines of feature codes (all under default) ...
           -> #include snep/snep-sip-hints.conf   (opens [hints], empty)
      -> [default] (RE-OPENED, TASK-0028C fix)
      -> #include custom/preagi.conf         (now correctly under default)
      -> exten => _9XX / h / t / OutgoingSpoolFailed / _. / ...
      -> #include custom/posagi.conf         (comment-only, confirmed inert)
 -> extensions.conf [transferencias]
 -> extensions.conf [ramais-agentes]         (orphaned: no producer sets
                                               context=ramais-agentes)
 -> extensions.conf [macro-dialpeer] / [monitor]
      -> #include custom/eof.conf            (comment-only, confirmed inert)
      -> #include snep/snep-conferences.conf
      -> #include snep/snep-parkedcalls.conf

pjsip.conf
 -> #include snep/senma-pjsip-transports.conf   (PJSIP_CURRENT, generated)
 -> #include snep/senma-pjsip.conf              (PJSIP_CURRENT, generated)
 -> #include snep/senma-pjsip-trunks.conf       (PJSIP_CURRENT, generated)

NOT included anywhere (confirmed, unchanged from the parent audit):
  snep-sip.conf, snep-sip-trunks.conf, snep-iax2.conf,
  snep-iax2-trunks.conf, snep-iax2-hints.conf
  (sip.conf/iax.conf templates are not even installed; chan_sip/chan_iax2
  are absent/Not Running)
```

Classification per file (`LIVE_AND_REQUIRED` / `LIVE_BUT_LEGACY` /
`LIVE_CUSTOMER_OWNED` / `GENERATED_EMPTY_LEGACY` / `DEAD_NOT_INCLUDED`):

| File | Classification |
| --- | --- |
| `extensions.conf` | `LIVE_AND_REQUIRED` |
| `snep/snep-features.conf` | `LIVE_AND_REQUIRED` |
| `snep/snep-sip-hints.conf` | `LIVE_AND_REQUIRED` (included; empty today, real compatibility path if a `blf`-enabled legacy peer is ever restored — kept) |
| `custom/preagi.conf` | `LIVE_CUSTOMER_OWNED` |
| `custom/posagi.conf`, `custom/eof.conf` | `LIVE_CUSTOMER_OWNED` (confirmed comment-only) |
| `senma-pjsip*.conf` (3 files) | `LIVE_AND_REQUIRED` |
| `snep-sip.conf`, `snep-sip-trunks.conf`, `snep-iax2*.conf` (5 files) | `GENERATED_EMPTY_LEGACY` / `DEAD_NOT_INCLUDED` |

Verified live (2026-09-04):

```text
module show like chan_        -> chan_pjsip.so Running; chan_iax2.so
                                  Not Running; no chan_sip.so line at all
core show application SIPAddHeader -> "not registered" (pre-fix)
dialplan show                 -> zero bare SIP/ or IAX2/ tokens (post-fix)
```

## 2. Exact legacy runtime hits found (before fix)

1. `custom/preagi.conf`'s extension `1234` (`Dial(SIP/1003,60,twg)`) landed
   in the `[hints]` context instead of `[default]`, due to a context-bleed
   bug (see §3) — orphaned (no producer sets `context=hints` on anything),
   so not reachable *before* the fix, but the fix that makes it reachable
   again (restoring the customer-hook feature to its documented, intended
   behavior) required also closing this `Dial(SIP/...)`.
2. `extensions.conf`'s `[ramais-agentes]` context: unconditional
   `SIPAddHeader(Alert-Info: Bellcore-r2)` before `Macro(dialpeer,...)`.
   Confirmed live: `SIPAddHeader` is not a registered application on this
   build (chan_sip absent) — any call that ever reached this context would
   hard-error at this exact priority. `ramais-agentes` itself is currently
   orphaned (`ExtensionsController` hardcodes `context=default` for every
   created extension; no UI/code path sets `context=ramais-agentes`) — but
   `peers.context` is a real, unguarded DB column, so this was a live risk
   waiting for reachability, not merely historical.
3. `snep/snep-features.conf`'s callback feature (`_*33XXXX`, dial
   `*33<busy-ext>` after a busy signal): generated `.call` spool file used
   `Channel: SIP/${EXTEN:3}`. **This one was fully reachable today** —
   every SENMA-created extension has `context=default`, which is exactly
   where this feature code lives.

## 3. Context-bleed root cause

`snep/snep-features.conf` has no `[context]` header of its own — all its
content (96 lines) belongs to whichever context is "currently open" when
it's `#include`d, which is `[default]` (from `extensions.conf:47`). Its
own very last line is `#include snep/snep-sip-hints.conf`, and that file's
entire content is a bare `[hints]` header (plus a blank line). Asterisk's
config-file `#include` has no per-file scope for context tracking — the
`[hints]` header opened three include-levels deep becomes the "currently
open" context for whatever textually follows, anywhere in the flattened
parse stream, until the next `[header]`. `extensions.conf`'s very next
statement after `#include snep/snep-features.conf` is
`#include custom/preagi.conf`, which — like `snep-features.conf` — has no
`[header]` of its own, so its content silently inherited `[hints]` instead
of the `[default]` its own header comment documents as the intended
placement ("this file is inserted right before SNEP's own AGI call-control
execution", i.e. squarely a `[default]`-context mechanism).

Confirmed empirically (not inferred): a live, reversible test —
temporarily re-opening `[default]` right before the `preagi.conf` include,
`dialplan reload`, observe, then revert — showed `[hints]` going from 1
extension to 0, and `1234` moving from `dialplan show hints` to
`dialplan show default`, with no other change.

## 4. Context-bleed fix

`snep/install/etc/asterisk/extensions.conf`: added a bare `[default]`
re-open immediately before `#include custom/preagi.conf`, with a comment
explaining why. This is the smallest possible fix — one line, no content
moved, `custom/preagi.conf`'s own bytes and `snep-sip-hints.conf`'s own
inclusion are both untouched. Verified live via `dialplan show
hints`/`dialplan show default` before and after, and via a deliberate
negative-control test (removed the fix, confirmed `dialplan show hints`
goes back to showing `1234`, confirmed the new regression suite's own
first dialplan check fails as expected, then restored the fix).

## 5. `custom/preagi.conf` preservation strategy

The file/mechanism itself is untouched: still first-boot-only copied
(`docker/asterisk-entrypoint.sh`'s guard on `[ ! -f asterisk.conf ]`,
confirmed unchanged), still bind-mounted read-only from
`snep/install/etc/asterisk` at `compose.yaml:51` (so a template edit is
immediately visible inside a fresh container, but never overwrites an
already-booted volume's live copy). The *shipped example content*'s one
technology token was changed (`SIP/1003` -> `PJSIP/1003`) because fixing
the context-bleed bug (§4) makes this extension reachable for the first
time in this environment's history — leaving a guaranteed-broken
`Dial(SIP/...)` there would have turned a merely-inert legacy string into
a newly-live failure. This is *not* a reinterpretation of "preserve
customer content": no customer has ever been able to reach this extension
before (it was silently swallowed by the same bug), and a real customer's
own edits to this file (on an already-booted volume) are never touched by
a template change. Everything else in the file — the extension number
`1234`, the comment, the Noop/Hangup shape — is byte-identical.

## 6. `Dial(SIP/...)` disposition

Only one reachable/loaded instance existed: `custom/preagi.conf:1234`
(§5, converted to `PJSIP/1003`). The two other `Dial(...)` constructs in
the live dialplan (`Dial(${INTERFACE},${ARG2},${ARG3})` in
`macro-dialpeer`, and the callback's own eventual `Dial(PJSIP/${EXTEN},...)`
inside `macro-dialpeer` reached via the callback's spooled `.call` file)
were already technology-agnostic/PJSIP-resolving and needed no change —
confirmed via the parent audit's own trace (`PBX_Usuarios::get()` /
`PBX_Trunks::get()` resolve the dial string from `peers.canal`/
`trunks.type`, which are 100% PJSIP in the current dataset).

## 7. `SIPAddHeader` disposition

- `extensions.conf` (`[ramais-agentes]`, unconditional, unguarded):
  **converted** to `Set(PJSIP_HEADER(add,Alert-Info)=Bellcore-r2)` —
  Asterisk's own documented replacement for exactly this "set a header
  before `Dial()` so the outbound leg's INVITE carries it" pattern
  (`res_pjsip_header_funcs`, confirmed loaded and its function synopsis
  matches). `ramais-agentes` remains orphaned (no producer sets
  `context=ramais-agentes` today) — a full live 2-endpoint proof that the
  header actually reaches a real INVITE was judged disproportionate given
  current unreachability and is flagged as residual debt (§13) rather than
  performed here.
- `snep/lib/PBX/Rule/Action/DiscarRamal.php` and
  `snep/modules/default/actions/DiscarRamal.php` (AGI/rule-engine path):
  **left unchanged**. Both are already correctly gated behind
  `$ramal->getInterface()->getTech() == "SIP"` — only fires for a genuine
  legacy SIP extension (currently zero exist). Adding a PJSIP equivalent
  branch here would be a feature addition (distinctive ring for PJSIP
  agent calls), not legacy closure, and is out of this task's scope.

## 8. Callback: old behavior

`_*33XXXX` (dial `*33<ext>` after a busy signal) built a `.call` file via
raw `System(echo ...)` shell commands with `Channel: SIP/${EXTEN:3}`.
Fully reachable: every SENMA-created extension has `context=default`
(`ExtensionsController` hardcodes it), and this feature code lives
directly in `[default]`. `pbx_spool`'s call-file originator cannot
dispatch a `SIP/` channel on a runtime with no `chan_sip` — this callback
was silently broken for every real extension in the system.

## 9. Callback: new behavior

Changed exactly one line (`snep/snep-features.conf:99`, now `:107`) —
`Channel: SIP/${EXTEN:3}` -> `Channel: PJSIP/${EXTEN:3}`. Endpoint naming
is 1:1 identical between the two technologies in this codebase (PJSIP
endpoints are named by the bare extension number, confirmed in
`Snep_PjsipConf::renderExtension()` and via `call-smoke-test.sh`'s own
`Dial(PJSIP/1003)` convention) — no other field in the `.call` file
(CallerID, Context, Extension, MaxRetries/RetryTime/WaitTime) is
technology-specific.

**Proven live, end to end**, not just at the syntax level: provisioned two
real PJSIP extensions via the actual `ExtensionsController` HTTP flow,
registered both via baresip (the same harness `call-smoke-test.sh` uses),
dialed `*33<B>` from A, and confirmed in the live Asterisk log:
`pbx_spool.c: Attempting call on PJSIP/<B>` -> `dial.c: ... is ringing` ->
`answered` -> the callback correctly re-entered `[<A>@default:1]` and
completed a real bridged call, with zero `SIP/<B>` tokens anywhere in the
log window. This is now `scripts/dialplan-legacy-closure-smoke-test.sh`'s
own core check, reused for every future run.

## 10. SIP/IAX generated-file disposition

The 5 files with no live include chain (`snep-sip.conf`,
`snep-sip-trunks.conf`, `snep-iax2.conf`, `snep-iax2-trunks.conf`,
`snep-iax2-hints.conf`) are **left generating** — `Snep_InterfaceConf`'s
file-writing and its underlying `peers.canal LIKE 'SIP%'`/`'IAX2%'`
queries are unchanged. Rationale: these files/queries are the documented
compatibility path for a legacy peer/trunk that could in principle be
restored from a backup (the parent audit explicitly classifies this
`KEEP_COMPATIBILITY_READ_ONLY`, gated on a proven zero-legacy-data
migration this task does not perform); stopping generation would remove
that compatibility path without the reachability/impact analysis
CLAUDE.md and this task both require before removing compatibility
behavior. What *was* removed: the two AMI calls this same function issued
on every single extension/trunk mutation, confirmed live and
unconditionally to be dead — `sip reload` and `iax2 reload` both return
"No such command" on this build (chan_sip.so entirely absent; chan_iax2.so
present but Not Running, so its CLI commands are unregistered too). The
one reload this function actually needs — `dialplan reload`, for its
hints-file output — is retained.

`snep-sip-hints.conf` itself (the 6th file) keeps generating and keeps its
live include (unchanged) — its own content stays empty today but is a
real, documented compatibility path (BLF hints for a restored legacy
`blf`-enabled peer); the fix in §4 only isolates what comes *after* it in
the include chain, not its own inclusion.

## 11. `Snep_Extensions` disposition

**Removed** (`snep/lib/Snep/Extensions.php` deleted, 329 lines). Exhaustive
repository-wide search (`grep -rn "Snep_Extensions"` across `.php`, `.xml`,
`.ini`) found zero instantiations, zero static calls, zero
`extends`/reflection/autoload references anywhere — the only match was the
class's own definition. `Snep_Extensions_Manager` and
`Snep_ExtensionsGroups_Manager` are different, actively-used classes and
were not touched.

## 12. Files changed

```text
snep/install/etc/asterisk/extensions.conf          (context-bleed fix, SIPAddHeader)
snep/install/etc/asterisk/custom/preagi.conf       (SIP -> PJSIP token)
snep/install/etc/asterisk/snep/snep-features.conf  (callback Channel:)
snep/lib/Snep/InterfaceConf.php                    (removed 2 dead AMI calls)
snep/lib/Snep/Extensions.php                       (deleted, dead class)
scripts/dialplan-legacy-closure-smoke-test.sh      (new regression suite)
Makefile                                            (wired new suite)
scripts/regression.sh                               (wired new suite)
docs/tasks/0028c-pjsip-legacy-runtime-closure.md   (this file)
```

Live container files were also directly patched to match the corrected
templates (`extensions.conf`, `custom/preagi.conf`, `snep-features.conf`
copied into the running `asterisk` container, ownership corrected to
`asterisk:asterisk`) — this dev environment already passed first boot, so
the template fix alone would not have retroactively applied without a
destructive `make reset`; the live copy makes this environment match what
every future first-boot deployment will now get from the corrected
templates, without discarding any container/volume state.

## 13. Production behavior changed

- A same-numbered extension `1234` (customer-editable via
  `custom/preagi.conf`) now actually dials `PJSIP/1003` instead of being
  silently unreachable — this is a **restoration** of previously-broken,
  documented, intended behavior, not a new feature.
- `*33<ext>` callback now actually completes calls (previously always
  failed silently for every real extension) — a **bug fix** to reachable,
  broken, live behavior.
- `[ramais-agentes]`'s Alert-Info header mechanism no longer hard-errors
  if it is ever reached (currently it cannot be, from any live producer).
- Every extension/trunk mutation issues 2 fewer no-op AMI round-trips.
- No change to any currently-working extension/trunk/transport
  provisioning flow, no schema change, no API change.

## 14. Tests added/updated

New: `scripts/dialplan-legacy-closure-smoke-test.sh` (21 checks) — wired
into `make dialplan-legacy-closure-smoke` and `make regression`. Covers:
context-bleed closure, `preagi.conf`'s PJSIP-native example, `SIPAddHeader`
replacement, zero bare `SIP/`/`IAX2/`/`SIPAddHeader(` tokens anywhere in
the live dialplan, `chan_sip` absent/`chan_iax2` not running,
`InterfaceConf`'s dead-reload removal, `Snep_Extensions` removal, and a
full live 2-baresip-endpoint proof of the callback fix (provision via real
HTTP flow, register, dial `*33<ext>`, confirm PJSIP origination + ringing +
answered + zero bare `SIP/` in the log, then hangup). No existing test
(including the legacy-technology security fixtures in
`pjsip-config-security-smoke-test.sh`/`residual-sql-security-smoke-test.sh`)
was modified or removed — those intentionally construct legacy DB rows to
prove read/compatibility/injection boundaries and remain untouched.

## 15. Runtime evidence

```text
$ asterisk -rx "dialplan show hints"
[ Context 'hints' created by 'pbx_config' ]
-= 0 extensions (0 priorities) in 1 context. =-

$ asterisk -rx "dialplan show default" | grep -A3 "'1234'"
  '1234' =>  1. Noop(Saida manual)         [preagi.conf:15]
             2. Dial(PJSIP/1003,60,twg)    [preagi.conf:16]
             3. Hangup()                   [preagi.conf:17]

$ asterisk -rx "dialplan show ramais-agentes"
  4. Set(PJSIP_HEADER(add,Alert-Info)=Bellcore-r2)  [extensions.conf:132]

$ asterisk -rx "dialplan show" | grep -i "SIP/" | grep -v "PJSIP/"
(zero matches)

$ asterisk -rx "module show like chan_"
chan_pjsip.so  Running
chan_iax2.so   Not Running
(no chan_sip.so line)

Live callback proof (real baresip endpoints 1091 -> *331092):
  pbx_spool.c: Attempting call on PJSIP/1092 for 1091@default:1 (Retry 1)
  dial.c: PJSIP/1092-00000001 is ringing
  dial.c: PJSIP/1092-00000001 answered
  [1091@default:1] NoOp("LIGACAO DE 1092 PARA 1091 NO CANAL PJSIP/1092-...")
  core show channels: 2 active channels, 1 active call (then 0 after hangup)
```

## 16-19. Validation gate

- `make lint`: PASS (270 PHP files 0 errors, 31 shell scripts parse clean,
  XML well-formed, `git diff --check` clean).
- `make regression` run 1: PASS — all 24 suites (including the new
  `dialplan-legacy-closure` suite and every pre-existing suite).
- `make regression` run 2: PASS — identical, all 24 suites.
- `git diff --check`: PASS, no whitespace errors.

## 20. Git status at completion

```text
 M Makefile
 M scripts/regression.sh
 M snep/install/etc/asterisk/custom/preagi.conf
 M snep/install/etc/asterisk/extensions.conf
 M snep/install/etc/asterisk/snep/snep-features.conf
 D snep/lib/Snep/Extensions.php
 M snep/lib/Snep/InterfaceConf.php
?? scripts/dialplan-legacy-closure-smoke-test.sh
?? docs/tasks/0028c-pjsip-legacy-runtime-closure.md
```

`.gitignore` and `.claude/skills/` show as modified/untracked in the wider
working tree but are pre-existing, unrelated state from before this task
started (not touched here) — excluded from the change set above and from
the proposed commit.

## 21. Remaining legacy debt (explicitly out of scope here)

1. **Redundant PJSIP reload** (transport/extension/trunk edits each
   trigger multiple full `module reload res_pjsip.so` calls) — already
   tracked separately (TASK-0028V's own finding); explicitly excluded from
   this task's scope by its own instructions.
2. **Orphaned peers/trunk-name collision bug** (`TrunksController`'s
   non-atomic `MAX(name)+1` scheme) — already tracked separately
   (documented during TASK-0028V); explicitly excluded from this task's
   scope by its own instructions.
3. **`InterfaceConf` and the SIP/IAX2 interface-factory classes**
   (`PBX_Interfaces`, `Asterisk/Interface/SIP.php`, `IAX2.php`, etc.)
   remain fully live as a read/compatibility path (§10). Full removal
   requires a proven zero-legacy-data migration, which is TASK-0028's own
   §11 roadmap item and is not part of this task's scope.
4. **`[ramais-agentes]`'s `PJSIP_HEADER(add,Alert-Info)` conversion has no
   live 2-endpoint header-propagation proof** — deferred as disproportionate
   given the context is currently unreachable from any producer (§7). If a
   future feature wires `peers.context` to `ramais-agentes` (e.g. an
   "agent extension" concept), that work should include the live proof
   before shipping.
5. **`DiscarRamal.php`'s AGI-side SIP-only Alert-Info branch has no PJSIP
   equivalent** (§7) — a feature gap, not a legacy-closure defect; only
   worth closing if/when a real product need for distinctive-ring on PJSIP
   agent calls is confirmed.
6. **5 SIP/IAX2 generated files keep being written on every mutation with
   no consumer** (§10) — harmless (confirmed `NOT_INCLUDED`), kept
   generating for compatibility-preservation reasons; a future task with
   explicit sign-off on "zero legacy data, ever" could stop writing them.

## Relationship to the original plan

The original stub (Portuguese, pre-dated the full TASK-0028 audit) framed
this task as depending on "TASK-0028A e TASK-0028B concluídas" and full
data migration. The actual TASK-0028 audit (completed later) found the
*write* surface already fully PJSIP-gated with zero live legacy data, and
scoped this follow-up narrowly to *reachable runtime/config* legacy instead
of data migration — this document implements that narrower, audit-driven
scope, not the original stub's broader one. The stub's acceptance criteria
("chan_sip e chan_iax2 podem ser removidos", "nenhuma migração de dados é
implícita") remain future work, tracked in §21.

## Proposed commit message

```text
fix(dialplan): close reachable SIP/IAX legacy runtime constructs

Fix a context-bleed bug that silently swallowed custom/preagi.conf's
content into an orphaned [hints] context instead of [default];
convert its now-reachable example Dial(SIP/...) and the unconditional,
unregistered SIPAddHeader in [ramais-agentes] to PJSIP-native
equivalents; fix the *33XXXX callback feature's generated .call file
(Channel: SIP/... -> PJSIP/..., proven live end to end with real
PJSIP endpoints -- this one was fully reachable and silently broken
for every extension); remove two confirmed-dead AMI reload calls and
the fully-dead Snep_Extensions writer class. No schema, API, or
currently-working provisioning behavior changed.
```
