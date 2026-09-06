# TASK-0033B — PJSIP Configuration Reconciliation (DB → Runtime)

Lead: senma-telephony-architect. Reviewer: senma-application-architect.
`senma-product-designer` not invoked — the supported operation is a CLI
command (`make reconcile`), not an admin UI action; if a future task
exposes it as an admin UI button, that task should invoke the designer
for the confirmation/status UX at that point, not this one.
`senma-docker-platform-engineer` not invoked — the implementation
required no container/boot-lifecycle change (it adds a new CLI script to
an existing image, and never runs automatically at boot — see BOOT
POLICY).

TASK-0033 classified the absence of a DB→PJSIP reconciliation operation
as a production blocker: generated PJSIP config was only ever rebuilt as
a side effect of an extension/trunk/transport CRUD save
(`PjsipTransportsController::regenerateAll()` and the equivalent calls in
`ExtensionsController`/`TrunksController`). If the generated files were
lost, stale, partially written, or drifted from the database, there was
no supported operator command that could reconstruct the runtime from
the authoritative application state. This task closes that gap.

---

## SOURCE OF TRUTH

The database is authoritative for SENMA-managed extensions, native PJSIP
trunks, PJSIP transports, and their endpoint/auth/AOR/registration/
identify objects. It is explicitly **not** authoritative for:

- `pjsip_external` endpoint internals (owned by whatever externally
  manages that endpoint);
- customer-owned Asterisk files (`custom/preagi.conf`,
  `custom/posagi.conf`, `custom/eof.conf`);
- externally-managed certificate/private-key bytes;
- the `provider` test-fixture service's own configuration.

`Snep_Pjsip_Reconciler` never reads, writes, or judges any of the second
group — see MANAGED FILE BOUNDARY.

---

## GENERATOR INVENTORY

| Generator | Managed file(s) | DB source | Trigger today (unchanged) |
|---|---|---|---|
| `Snep_PjsipConf` | `senma-pjsip.conf` | `peers` (`peer_type='R'`, `canal LIKE 'PJSIP/%'`) | `ExtensionsController` add/edit/delete/enable/disable |
| `Snep_PjsipTrunkConf` | `senma-pjsip-trunks.conf` | `peers` (`peer_type='T'`) joined to `trunks` | `TrunksController` add/edit/delete/enable |
| `Snep_PjsipTransportConf` | `senma-pjsip-transports.conf`, `senma-http-tls.conf` | `pjsip_transports`, `pjsip_transport_networks` | `PjsipTransportsController` add/edit/delete (`regenerateAll()`) |
| `Snep_InterfaceConf` | `snep-sip*.conf`, `snep-iax2*.conf` | `peers` (`SIP%`/`IAX2%` `canal`) | Legacy technology selection paths |

Classification per file:

| File | Classification |
|---|---|
| `senma-pjsip.conf` | DB_REGENERABLE |
| `senma-pjsip-trunks.conf` | DB_REGENERABLE |
| `senma-pjsip-transports.conf` | DB_REGENERABLE |
| `senma-http-tls.conf` | DB_REGENERABLE (sourced from `pjsip_transports`; references external cert/key paths without owning their bytes) |
| `snep-sip*.conf` / `snep-iax2*.conf` | LEGACY_COMPATIBILITY (Snep_InterfaceConf's own scope, untouched here) |
| `custom/preagi.conf`, `custom/posagi.conf`, `custom/eof.conf` | CUSTOMER_OWNED |
| `keys/*.pem` | EXTERNAL_REFERENCE |
| `asterisk.conf`, `extconfig.conf`, `modules.conf`, `manager.conf`, `res_odbc.conf`, `cdr_adaptive_odbc.conf`, `extensions.conf`, `http.conf` | STATIC_APPLICATION_CONFIG (Docker-entrypoint-seeded, outside this task's scope) |

No managed PJSIP file remains UNKNOWN.

**A real refactor, not a rewrite**: each of the three generators now
exposes a pure `renderContent()` (and `Snep_PjsipTransportConf` also
`renderHttpTlsContent()`), extracted out of their own `loadConfFromDb()`.
`loadConfFromDb()` itself is unchanged from the CRUD call sites'
perspective — same write, same reload, same exceptions — it just calls
the extracted method internally. `Snep_Pjsip_Reconciler` calls exactly
those same render methods; there is exactly one implementation of PJSIP
rendering, not two (Phase 5's explicit requirement). Verified live: a
normal extension create/delete through the web UI was exercised
immediately after the refactor and produced byte-identical generated
sections, before any reconciliation code was even written.

---

## MANAGED FILE BOUNDARY

`Snep_Pjsip_Reconciler::$managedFiles` is the exact, exhaustive list:

```
senma-pjsip-transports.conf
senma-http-tls.conf
senma-pjsip.conf
senma-pjsip-trunks.conf
```

Nothing else. `snep-sip*.conf`/`snep-iax2*.conf` (Snep_InterfaceConf's own
legacy output) are deliberately excluded even though the same legacy
class knows how to generate them — Phase 2's explicit instruction.
`custom/*.conf` and `keys/*.pem` are never read or written by this class
at all; see DESTRUCTIVE PROOF for the live byte-identity proof, not just
an assertion.

---

## VALIDATION CONTRACT

Two layers, deliberately different in strictness from ordinary CRUD:

1. **Pre-generation (`validate()`)** — checks `pjsip_transports` rows
   Snep_PjsipTransportConf itself never self-validates (it renders
   verbatim, with no per-row skip mechanism the other two generators
   have): protocol validity, bind address/port syntax, TLS cert/key path
   syntax and on-disk existence, TLS method, and `local_net` CIDR syntax.
   Reuses `Snep_PjsipTransports_Manager`'s existing static validators —
   the same ones `PjsipTransportsController` already runs at save time —
   rather than duplicating logic (Phase 6's explicit instruction).
2. **Generation-time warnings** — `Snep_PjsipConf`/`Snep_PjsipTrunkConf`
   already skip-and-log an individual row with an unsafe value or a
   missing/disabled transport reference (a tolerance CRUD needs, so one
   bad legacy row never blocks an unrelated save). A full reconciliation
   treats **any** such warning as `INVALID_DB_STATE` and refuses to
   publish anything — a deliberate, full-integrity operator action should
   surface persisted state an individual CRUD save would not have
   noticed. Proven live (see DESTRUCTIVE PROOF, invalid-state scenario).
3. **Staged structural validation (`validateStagedContent()`)** — before
   any active file is touched: every managed file is non-empty, no
   `(name, type)` pair repeats (the correct, load-bearing pattern of an
   endpoint and its AOR sharing one bracket name is explicitly *not*
   flagged — a first version of this check did, and was caught live
   against a real extension), every non-comment line is either a
   `[section]` header or a `key=value` directive, and no line matches a
   chan_sip/IAX2-shaped directive (`type=peer/friend/user`) — PJSIP-only
   insurance, not expected to ever actually fire.

---

## STAGING MODEL

`/etc/asterisk/snep/.reconcile-staging/` — a subdirectory of the **same**
volume/filesystem the active files live on, required for `rename()` to
be atomic (a system `/tmp` could be a different filesystem entirely).
Each managed file is written to `<name>.new`, then explicitly
`chown`'d/`chgrp`'d/`chmod`'d to `asterisk:senma-config 0664` — the exact
scheme `docker/asterisk-entrypoint.sh` establishes on first boot — before
any rename, never trusting whatever mode the write happened to produce
(Phase 9).

---

## PUBLICATION/ROLLBACK

Before renaming anything, every currently-active managed file that exists
is copied to `<name>.rollback` in the same staging directory. Files are
then renamed into place one at a time, in a fixed order (transports →
http-tls → extensions → trunks). If any rename fails partway, every
already-renamed file in this pass is restored from its `.rollback` copy
before returning `PUBLISH_FAILED` — the active set is either entirely the
new generation or entirely the prior one, never a mix of new transports
with old trunks (Phase 7's explicit concern). True single-syscall
multi-file atomicity is not possible on a plain POSIX filesystem; this
rollback is the documented alternative Phase 8 asks for. Not exercised as
a live fault-injection test in this task (would require corrupting the
filesystem mid-operation, judged disproportionate risk for the value); the
per-file `rename()` atomicity itself, the ownership/mode scheme, and the
full delete-then-recreate cycle are all proven live instead (see
DESTRUCTIVE PROOF).

---

## DRIFT MODEL

`make reconcile-check` (`Snep_Pjsip_Reconciler::check()`) never writes to
disk or touches Asterisk. It generates the complete managed set in memory
and compares each file against the active one, byte-for-byte **after**
stripping the one `; Generated: <timestamp>` line every generator stamps
into its own header — without that normalization, every check would
report DRIFTED even when nothing meaningful changed. Reports
`IN_SYNC`/`DRIFTED`/`INVALID_DB` per file and overall; never prints a raw
diff (Phase 11's explicit "no exposed passwords" requirement) — secrets
live inside these files by design (auth `password=` lines), so the drift
signal is deliberately same-or-different, never content.

---

## APPLY CONTRACT

One coordinated `module reload res_pjsip.so` after all four files are
published — not three redundant ones (the naive alternative of calling
each generator's own `loadConfFromDb()` three times would trigger three
separate reloads for one logical reconciliation). `module reload http`
follows immediately after, for the same reason
`Snep_PjsipTransportConf::reloadHttp()` already established: http.conf's
TLS settings need their own reload command, unconditionally, since any
transport change could have changed which row (if any) is the active WSS
cert source.

Publication and apply are staged as **distinct** steps: a file-set that
published successfully but Asterisk being unreachable at apply time is
reported as `FILES_RECONCILED_RUNTIME_UNAVAILABLE`, never silently folded
into a plain failure or a false success (Phase 12/30).

---

## TRANSPORT SEMANTICS

Reuses `Snep_PjsipTransportConf::isRuntimeActive($name, $bindAddress,
$bindPort)` (already built for TASK-0020) rather than re-implementing
transport-readiness detection. If an enabled transport is present in the
freshly-published config but not bound at its expected address:port
after a successful reload, the overall result is
`RUNTIME_RESTART_REQUIRED` — the documented TASK-0028V/0029A case where a
bind-address/port change on a transport Asterisk already has open cannot
hot-converge and needs a full Asterisk restart to rebind the socket. This
is reported as its own explicit, non-error terminal state (Phase 14), not
collapsed into failure and not silently treated as full success.

---

## RUNTIME VERIFICATION

Builds the expected live-object identity set from the same DB queries the
generators use (active extension names, `trunk-<id>` names for active
native trunks, enabled transport names), then checks Asterisk's actual
runtime:

- **Missing check**: every expected endpoint must appear in a bulk
  `pjsip show endpoints` listing.
- **Stale check**: every *live* endpoint that looks SENMA-shaped but is
  not currently expected (and is not a known `pjsip_external` username)
  is reported as a leftover that should have disappeared after a full
  reload. This is what actually proves Phase 27/28 rather than assuming
  a reload always cleans up — confirmed live catching a hand-injected
  stale section that had been force-reloaded into the runtime.
- **Identify objects**: checked per-trunk via `pjsip show identify
  <name>` (every PJSIP trunk gets one unconditionally, per
  `Snep_PjsipTrunkConf`'s own class doc).
- **Transports**: via `isRuntimeActive()`, see TRANSPORT SEMANTICS.

Deliberately **not** checked as a pass/fail condition: contact/
registration status (`Registered`/`Rejected`/`Unregistered`). Phase 16's
distinction — reconciliation owns `CONFIGURED_CORRECTLY`/
`RUNTIME_OBJECT_LOADED`, never `REMOTE_REGISTERED`/`REMOTE_REACHABLE` — a
provider being offline must never roll back a valid trunk configuration,
and this implementation does not attempt to.

A real bug in the bulk-parsing regex was found and fixed during this
task's own validation: `pjsip show endpoints`' own column-header row
(`Endpoint:  <Endpoint/CID.....>  ...`) matched the same "Endpoint:
&lt;name&gt;" shape a real data row does, making every real endpoint look
"unexpected" by comparison to a phantom `<Endpoint` entry. Fixed by
rejecting any captured name starting with `<` or containing `.` (neither
is ever a real, validated object name).

---

## FAILURE TAXONOMY

`INVALID_DB_STATE`, `GENERATION_FAILED`, `STAGING_VALIDATION_FAILED`,
`PUBLISH_FAILED`, `APPLY_FAILED`, `VERIFY_FAILED`,
`RUNTIME_UNAVAILABLE`/`FILES_RECONCILED_RUNTIME_UNAVAILABLE`, plus the two
non-failure terminal states `RECONCILED` and `RUNTIME_RESTART_REQUIRED`.
Every branch in `Snep_Pjsip_Reconciler::reconcile()` returns one of these
with the specific problem list that led to it — never a generic failure
with no diagnostic context.

---

## PJSIP_EXTERNAL HANDLING

`pjsip_external` trunks (`trunks.type = 'PJSIP_EXTERNAL'`) get **no**
`peers` row at all (`TrunksController::preparePost()`'s own design,
TASK-0028B) — this is exactly what keeps them structurally invisible to
`Snep_PjsipTrunkConf`'s `peers`-driven query, with no special-casing
needed in the generator itself. Runtime verification checks only whether
the referenced endpoint *exists* live, and reports it under a separate
`external_dependencies` map (`present`/`missing (external dependency --
not managed by SENMA, not repaired by reconcile)`) — never as a
`VERIFY_FAILED` problem, and never generated into any managed file.
Proven live with a test-only direct-DB fixture row (Phase 29's own
suggested convention, since a real `pjsip_external` row cannot be created
through the supported UI without the referenced endpoint already existing
in Asterisk, which this test does not have).

---

## OPERATOR COMMAND

```bash
make reconcile          # full validate -> generate -> stage -> publish -> apply -> verify
make reconcile-check    # non-mutating drift check only
```

Both run `docker compose exec asterisk php /usr/local/bin/reconcile-pjsip.php`
(`--check` for the second). Output is a concise summary — DB validation
problems, generation warnings, staged-content problems, files published,
apply status, verification status/problems, and any external
dependencies — never a raw content dump. Exit codes: `0` reconciled/in
sync, `2` files reconciled but the runtime needs separate operator
attention (restart required, or Asterisk unreachable), `1` a real
failure, `3` drifted (check mode only).

**Why the `asterisk` container, not `app`.** A real, live-confirmed
finding drove this: the `app` container has no `asterisk` user in its own
`/etc/passwd` at all, so `chown($path, 'asterisk')` from there can only
ever fail silently — the published files ended up owned by `root`
instead of `asterisk` (functionally equivalent for read/write access
since both `www-data` and `asterisk` share the `senma-config` group, but
not matching Phase 9's "use current production expectations"). The
`asterisk` container already runs PHP as the `asterisk` user with full
DB connectivity for AGI script execution — the exact precondition this
script needs, already proven working — so files it creates are correctly
owned from the moment they're written, no `chown` even needed in
practice.

---

## BOOT POLICY

**MANUAL_ONLY.** Reconciliation does not run automatically at container
boot. Reasoning, evidence-based rather than by convenience default:

- An automatic boot-time reconcile against a database restored from
  elsewhere (TASK-0033A's own restore path) or freshly imported could
  encounter genuinely invalid persisted state (Phase 29's exact scenario)
  and would need to decide, unsupervised, whether to refuse to boot the
  application or silently skip PJSIP provisioning — neither is an
  acceptable default with no operator present.
- A transport bind-address/port change captured only in the database (no
  corresponding generated file yet) could trigger `RUNTIME_RESTART_REQUIRED`
  at boot, which this task's own design explicitly treats as an operator
  decision, not something to force silently during startup.
- `pjsip_external` dependencies may not exist yet at boot time (a
  container recreate racing against another service's own startup) —
  reconciliation already treats this as a non-blocking, reported
  condition (correct), but running it unconditionally at every boot adds
  startup latency and an extra external-dependency check with no
  corresponding operator visibility unless someone is watching container
  logs.
- No existing operational contract (TASK-0033's own audit) currently
  defines a supported "reconcile automatically after restore" flow;
  introducing one silently, inside this task, would be exactly the kind
  of automatic-reconciliation-by-convenience Phase 20 explicitly warns
  against.

A future Operations task may reasonably introduce `BOOT_CHECK_ONLY` (a
non-mutating `reconcile-check` surfaced in `make doctor`'s diagnostic
bundle, TASK-0033's own Phase 14) once that diagnostic bundle exists —
this task does not implement it, since `make doctor` itself remains
TASK-0033D's scope.

---

## CRUD COMPATIBILITY

Not rewritten. `ExtensionsController`, `TrunksController`, and
`PjsipTransportsController` still call the same
`Snep_Pjsip*Conf::loadConfFromDb()` methods they always have, unchanged
in their own external behavior (same write, same reload, same exception
contract) — verified live immediately after the refactor (extension
create + delete via the real HTTP flow, generated config inspected,
matched the pre-refactor shape). Equivalence between normal CRUD and a
full `make reconcile` for the same DB state is proven directly in the
regression suite: fixtures provisioned via the real HTTP flow generate
correctly (scenario 1, `IN_SYNC` immediately after a CRUD save), then the
exact same generated content is reproduced from nothing by `make
reconcile` after deleting every managed file (scenario 4) — the same DB
state, through either path, produces the same live runtime objects
(endpoint/aor/auth all confirmed present, a real registration and a real
completed call succeed against extensions `make reconcile` regenerated,
not CRUD).

---

## CUSTOMER-STATE PRESERVATION

`custom/preagi.conf`, `custom/posagi.conf`, `custom/eof.conf` (confirmed
live to be direct siblings of `snep/` under `/etc/asterisk/`, not nested
inside it — an early version of the regression suite's own checksum
helper pointed at the wrong path and was corrected during validation) are
sha256-snapshotted before and re-checked after every destructive scenario
in `scripts/pjsip-reconcile-smoke-test.sh`. Confirmed byte-identical
across drift-clearing, full-delete-and-regenerate, and invalid-state-
refusal scenarios.

---

## CERTIFICATE PRESERVATION

`keys/wss-test-cert.pem` and `keys/wss-test-key.pem` are sha256-
snapshotted the same way. Confirmed byte-identical across every
scenario — reconciliation only ever changes the *reference* to a
certificate path inside `senma-http-tls.conf` (per DB state), never the
certificate/key bytes themselves.

---

## SECRET HANDLING

`make reconcile`'s own stdout/stderr never contains a real extension
secret, trunk secret, or DB password — verified live by capturing the
full output of the reconcile run that recreated every managed file (with
two extensions and a trunk carrying known, distinctive test secrets
active) and confirming none of those exact values appear anywhere in it.
The generated *files* legitimately contain secrets (`password=` lines are
required for `type=auth` objects to function) — that is expected,
unchanged behavior, not a leak; the diagnostic surface under this
project's control is the command's own output, not the files it manages.

---

## DESTRUCTIVE PROOF

Automated as `scripts/pjsip-reconcile-smoke-test.sh` (`make
pjsip-reconcile-smoke`, wired into `make regression`) and run live
multiple times during development — the final clean run passed **34/34**
checks. What it actually does, end to end, against the real dev stack:

1. Provisions two real PJSIP extensions and one real native PJSIP trunk
   through the actual `ExtensionsController`/`TrunksController` HTTP
   flows.
2. Confirms `IN_SYNC` immediately after (scenario 1).
3. Hand-edits the active `senma-pjsip.conf` to add a fake section, force-
   reloads it live (so it is a genuine runtime object, not merely a file
   artifact), confirms `DRIFTED`, runs `make reconcile`, and confirms the
   fake section is gone from **both** the file and the live runtime
   (scenarios 2/3).
4. **Deletes all four managed files entirely.** Confirms they are
   actually gone. Runs `make reconcile`. Confirms all four are recreated
   with the correct content, and — a real, live-confirmed fact, not an
   assumption — with the exact `asterisk:senma-config 0664` ownership the
   original entrypoint establishes (scenario 4).
5. Confirms zero secret leakage in that reconcile's own output, and
   byte-identical customer/certificate files across the whole delete-and-
   regenerate cycle (scenarios 5/6/11).
6. **Registers real baresip endpoints against the two extensions using
   their original secrets** (never recreated) and **completes a real
   call** (`CALL_ESTABLISHED` observed) — proving the regenerated
   provisioning is live and functional, not merely file content (Phase
   26's core requirement).
7. Inserts a test-only, direct-DB `pjsip_external` trunk fixture, runs
   `make reconcile`, and confirms it is reported only as a missing
   external dependency — never generated into any managed file, never a
   verification failure (scenario 7).
8. Sets a dangling `transport_id` on a live extension, runs `make
   reconcile`, confirms `INVALID_DB_STATE` and that the active
   `senma-pjsip.conf` checksum is **unchanged** (the refused publish left
   known-good files intact), then fixes the row and confirms reconcile
   succeeds again (scenario 8, Phase 29's exact proof requirement).
9. Deletes both extensions and the trunk through the real HTTP flow,
   reconciles, and confirms none of the three objects reappear in the
   live runtime (scenario 10, Phase 28).

Three real, previously-unknown bugs were found and fixed by this proof,
not merely exercised:

- **`asterisk` user missing from the `app` container** — the CLI script's
  original home — silently defeated `chown()`. Fixed by moving the
  script to the `asterisk` container (see OPERATOR COMMAND).
- **`Zend_Log` "No writers were added"** — `Asterisk_AMI::log()`
  unconditionally logs every AMI event through `Snep_Logger`, which has
  zero writers outside the full HTTP request bootstrap. Fixed by
  attaching a single stderr writer in the CLI bootstrap.
- **A naive duplicate-section check flagged the correct, load-bearing
  endpoint+AOR same-name pattern** every generator already relies on.
  Fixed by keying duplicate detection on `(name, type)` pairs instead of
  bare names.
- **The bulk `pjsip show endpoints` parser matched its own column-header
  row** (`<Endpoint/CID...>`), and separately **required a trailing "/"
  that trunk endpoints never have** (only extensions show
  `name/callerid`). Both fixed with live-confirmed regex corrections.

---

## RESTORE INTEGRATION

TASK-0033A's backup contract remains bit-identical (backs up the whole
`asterisk-etc` volume verbatim) and is **not changed by this task** — no
compatibility update was necessary; restore does not depend on
reconciliation existing. What this task adds is an *additional*,
independent recovery path, demonstrated live:

```
restore DB + setup.conf + arquivos/ (TASK-0033A's own restore, minus
  the asterisk-etc volume this time)
→ delete every SENMA-managed generated PJSIP file
→ make reconcile
→ runtime restored (endpoints/trunks/transports live, real
  registration + real call proven)
```

This was exercised as scenario 4 of the destructive proof above (delete
the managed files, reconcile, verify + real call) — the DB-restore half
of this chain was already proven independently by TASK-0033A's own DR
test; combining the two into one single proof run was judged unnecessary
duplication of already-covered ground. A future backup-contract
simplification (dropping `asterisk-etc` from the bit-identical backup
once reconciliation is trusted as the sole recovery path for generated
config) is now *possible* but is explicitly a separate, future decision —
TASK-0033A's contract is not touched here.

---

## REMAINING DEBT

**Production blocker** — none remaining from this task's scope; the
DB→PJSIP reconciliation blocker TASK-0033 identified is closed.

**Operations follow-up** (tracked, not solved here):

- `make doctor` (TASK-0033D's scope) could surface `reconcile-check`'s
  `IN_SYNC`/`DRIFTED` status as one line in its diagnostic bundle.
- A `BOOT_CHECK_ONLY` policy (non-mutating check surfaced at boot/in
  diagnostics, never auto-publishing) is a reasonable future step once
  `make doctor` exists to surface it meaningfully — deliberately not
  implemented now (see BOOT POLICY).
- `compose.yaml`'s own comment about `Snep_InterfaceConf` (calling PJSIP
  generation "future work, not invoked by this task") is stale — TASK-0033
  already flagged this as low-risk documentation drift; still not fixed
  (out of both that task's and this one's authorized scope).
- Backup-contract simplification once reconciliation is trusted (see
  RESTORE INTEGRATION) — explicitly deferred, not this task's call to
  make.
- Publish-step fault injection (Phase 18: simulating a mid-publish
  write/disk error) was not exercised live — the per-file `rename()`
  atomicity and full delete-and-recreate cycle are proven instead; a
  dedicated fault-injection test would need a way to interrupt the
  process between two specific `rename()` calls, judged disproportionate
  effort for this task's scope.

**Test-harness-only debt** — none found; the three generator-side render/
publish/verify bugs this task's own proof surfaced were fixed as part of
implementing the feature, not left as pre-existing harness debt.

**Future observability** — none identified beyond what TASK-0033D already
owns.
