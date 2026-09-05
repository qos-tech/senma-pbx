# TASK-0028X — Fix pjsip_external outbound dial-string defect

## Status

Resolved. Confirmed defect fixed, root-caused, and proven live end to end
against a real `pjsip_external` trunk and a real, independently-registered
PJSIP endpoint. A second, unrelated, pre-existing bug was discovered while
building the regression coverage this task required (see "Related but
separately-fixed defect" below) and fixed as its own narrowly-scoped change,
per explicit user direction after being surfaced mid-task.

Originates from the completed PJSIP Completeness Architecture Review
(TASK-0028W), which identified that `pjsip_external` trunks never reach
`PBX_Asterisk_Interface_PJSIP::getDialStringForDestination()`.

## Confirmed defect

`pjsip_external` (TASK-0028B) is a documented, supported trunk mode: a trunk
referencing a PJSIP endpoint an administrator already configured directly in
Asterisk, outside SENMA. Inbound behavior was already correct and was out of
scope for this task.

Outbound dial-string generation was wrong: a `pjsip_external` trunk produced

```text
PJSIP/<endpoint>/<destination>
```

instead of chan_pjsip's correct

```text
PJSIP/<destination>@<endpoint>
```

## Call path traced

```text
DiscarTronco::execute() (snep/modules/default/actions/DiscarTronco.php:265,377)
  -> PBX_Trunks::get($trunkId)                       (snep/lib/PBX/Trunks.php)
       -> tech dispatch on trunks.type
       -> builds a PBX_Asterisk_Interface_* object
  -> $tronco->getInterface()->getDialStringForDestination($dst_number, $postfix)
  -> $asterisk->exec_dial($destiny, ...)
```

`PBX_Trunks::get()`'s dispatch (before this fix) only special-cased
`$tech == "PJSIP"` (the SENMA-provisioned, registration-based trunk model,
TASK-0014/0015). `pjsip_external` persists `trunks.type` as the literal
string `"PJSIP_EXTERNAL"` (`TrunksController::preparePost()`'s
`pjsip_external` branch, `TrunksController.php:647,649`) — a different
string, matched by none of the existing branches, so it fell through to the
final `else`:

```php
$interface = new PBX_Asterisk_Interface_VIRTUAL(array("channel" => $rawTrunk->channel, "channel_regex" => $rawTrunk->channel));
```

`PBX_Asterisk_Interface_VIRTUAL` does not override `getDialStringForDestination()`,
so it inherits the abstract base class's default (`PBX_Asterisk_Interface::getDialStringForDestination()`),
which reproduces chan_sip's historical `"Peer/exten"` concatenation:

```php
public function getDialStringForDestination($destination, $postfix = "") {
    return $this->getCanal() . "/" . $destination . $postfix;
}
```

`getCanal()` here returns `$this->config['channel']`, which
`TrunksController::preparePost()` set to `'PJSIP/' . $endpoint` — so the
result was `"PJSIP/<endpoint>" . "/" . $destination` =
`PJSIP/<endpoint>/<destination>`, exactly the documented defect.

## Root cause

`PBX_Trunks::get()`'s tech dispatch never had a branch for
`"PJSIP_EXTERNAL"`. It is a distinct string from `"PJSIP"` (the two
technologies are deliberately persisted differently by
`TrunksController::preparePost()`), so a `pjsip_external` trunk silently
fell through to the generic `VIRTUAL` fallback that pre-dates PJSIP entirely,
inheriting chan_sip-shaped dial semantics that have no valid meaning for
chan_pjsip.

## Why inbound is unaffected

`PBX_Interfaces::getChannelOwner()` (`snep/lib/PBX/Interfaces.php`) matches
an inbound Asterisk channel name against `trunks.id_regex` **read directly
from the database row**, before ever calling `PBX_Trunks::get()`:

```php
foreach ($trunk_ifaces as $interface) {
    if(preg_match("#^{$interface['id_regex']}$#i", $channel)) {
        return PBX_Trunks::get($interface['id']);
    }
}
```

`PBX_Trunks::get()` is only called **after** a match is already found, to
build the returned `Snep_Trunk` object. This task's fix only changes which
`PBX_Asterisk_Interface_*` subclass that call constructs — it never touches
`id_regex` or the regex match itself. Proven directly (not just by
inference) in the regression coverage below: a synthetic inbound channel
name is resolved via the real `PBX_Interfaces::getChannelOwner()` call path
both before and after touching this trunk technology.

## Endpoint-name handling: no hidden assumption found

Native `"PJSIP"` trunks derive their PJSIP object name from `trunks.id`
(`"trunk-" . $rawTrunk->id`, a SENMA-generated identity —
`PBX_Trunks.php`'s existing `PJSIP` branch, TASK-0014 §10/TASK-0015 §4).
`pjsip_external` is different on purpose: the externally-managed endpoint's
own name is persisted directly in `trunks.username`
(`TrunksController.php`'s `pjsip_external` branch: `'username' => $endpoint`),
validated once at creation time against the live Asterisk runtime via AMI
(`externalPjsipEndpointExists()`). The new `PJSIP_EXTERNAL` branch added by
this fix reads `$rawTrunk->username` directly (never `"trunk-" . $rawTrunk->id`)
— matching `channel`/`id_regex`, both already `'PJSIP/' . $endpoint`. No
other hidden assumption was found: `secret`/`host` are carried into the
interface config for structural parity with the native `PJSIP` branch but
are not read by `PBX_Asterisk_Interface_PJSIP::getCanal()` or
`getDialStringForDestination()`, so their values (unset for `pjsip_external`)
are inert.

## Root cause (regression-coverage blocker) — related but separately-fixed defect

While building this task's required regression coverage, item 1 ("a
supported pjsip_external trunk can be created/configured" through the real
UI/HTTP flow) was found to be **unconditionally impossible**: every attempt
to create a `pjsip_external` trunk was rejected with "O endpoint PJSIP
externo não existe no runtime ativo do Asterisk", even against a real,
live, already-existing endpoint.

Root cause: `TrunksController::externalPjsipEndpointExists()`
(`TrunksController.php:944`, TASK-0028B, unrelated to this task's own
defect) matched AMI's `pjsip show endpoint <name>` output against

```php
'/^Endpoint:\s+' . preg_quote($endpoint, '/') . '\\//mi'
```

Two compounding bugs in that pattern, both confirmed live via AMI against a
real endpoint:

1. The real CLI/AMI output line is indented with a leading space
   (`" Endpoint:  <name>/<cid>"`), which the un-anchored-for-whitespace
   `^Endpoint:` (with the `/m` flag) never matches, regardless of the
   endpoint's name or configuration.
2. The trailing `\/` required a literal `"/"` immediately after the name,
   present only when the endpoint has a configured `callerid`
   (`" Endpoint:  <name>/<cid>"`); a callerid-less endpoint's line reads
   `" Endpoint:  <name>   <state>"` with no slash at all.

Effect: this check rejected **every** real endpoint, always — the
`pjsip_external` trunk-creation feature (TASK-0028B) was completely unusable
through the UI since it shipped. This is a defect in the *creation-time
validator*, entirely independent of `PBX_Trunks::get()`'s *dial-time*
interface dispatch (this task's own confirmed defect) — a trunk row that
already existed (e.g. seeded before this bug, or created directly) would
still have hit the dial-string defect regardless of whether this validator
worked.

This was surfaced to the user mid-task (via `AskUserQuestion`) rather than
silently fixed or silently left blocking the required regression proof. The
user chose: fix it narrowly, as its own separately-scoped change (not mixed
into the dial-string fix), to unblock real end-to-end regression coverage.

Fix (`TrunksController.php:944-960`):

```php
return preg_match('/^\s*Endpoint:\s+' . preg_quote($endpoint, '/') . '(?:\/|\s)/mi', $data) === 1;
```

`^\s*Endpoint:` tolerates the real leading indentation; `(?:\/|\s)` after
the endpoint name accepts either real form (with or without a configured
callerid) while still requiring a boundary there, so a name that is merely a
prefix of a different endpoint's name cannot false-positive match. Verified
against both real captured forms and a decoy partial-name case before
applying.

## Changes

### Production

- `snep/lib/PBX/Trunks.php` — added a dedicated `PJSIP_EXTERNAL` branch to
  `PBX_Trunks::get()`'s tech dispatch, reusing the existing
  `PBX_Asterisk_Interface_PJSIP` class (no new dial-string formatting logic
  duplicated). This is the confirmed-defect fix.
- `snep/modules/default/controllers/TrunksController.php` —
  `externalPjsipEndpointExists()`'s regex fixed (see above). Unrelated to
  the dial-string defect; fixed as its own change per explicit user
  direction, since it otherwise unconditionally blocked this task's
  required live regression proof.

### Test

- `scripts/pjsip-external-trunk-smoke-test.sh` — new regression suite (see
  below).
- `scripts/pjsip-external-trunk-check.php` — new small bootstrap CLI helper
  (same pattern as `scripts/trunk-smoke-route.php`), used by the suite above
  for two direct, non-HTTP, non-log-parsing proofs:
  `PBX_Trunks::get()->getInterface()->getDialStringForDestination()` and
  `PBX_Interfaces::getChannelOwner()`.
- `Makefile` — new `pjsip-external-trunk-smoke` target (+ `.PHONY` entry).
- `scripts/regression.sh` — new suite wired in immediately after
  `trunk-smoke`.

### Documentation

- This file.

## Regression coverage

`make pjsip-external-trunk-smoke` (also runs as part of `make regression`,
immediately after `trunk-smoke`), against a running `make dev` Docker
environment, using SENMA's own real HTTP flow (not raw SQL) to create the
trunk:

1. **Supported trunk can be created/configured** — POSTs to the real
   `TrunksController::addAction()`, `technology=pjsip_external`, against a
   real PJSIP endpoint (`task0028x-ext-endpoint`) installed directly into
   the live, volume-backed `/etc/asterisk/pjsip.conf` inside the running
   `asterisk` container (never the git-tracked
   `docker/asterisk-config/pjsip.conf` source) — models exactly what
   TASK-0028B's contract describes: an endpoint SENMA never generates.
   Validated live via AMI (`externalPjsipEndpointExists()`, now fixed).
   Persisted row checked directly against the pjsip_external contract
   (`type=PJSIP_EXTERNAL`, `trunktype=T`, `channel=id_regex=PJSIP/<endpoint>`,
   `username=<endpoint>`, **no** `peers` row).
2. **Outbound routing resolves to the correct interface** — proven directly
   via `scripts/pjsip-external-trunk-check.php dialstring`, the exact call
   `DiscarTronco::execute()` itself makes:
   `PBX_Trunks::get($id)->getInterface()` is `PBX_Asterisk_Interface_PJSIP`.
3. **Dial string is exactly `PJSIP/<destination>@<endpoint>`** — same direct
   check, using a destination digit string deliberately different from the
   endpoint name, so the proof is not the degenerate case where the two
   coincide.
4. **The broken `PJSIP/<endpoint>/<destination>` form does not appear** —
   asserted absent both in that direct check's output and in the real
   call's Asterisk log trace.
5. **A real outbound call reaches a live PJSIP external endpoint** — a
   SENMA-provisioned caller extension (via a disposable baresip container,
   same pattern as `call-smoke-test.sh`/`trunk-smoke-test.sh`) places a real
   call through the trunk; a second, independent baresip container
   (registered directly to the fixture endpoint installed in step 1)
   answers it. `CALL_ANSWERED`/`CALL_ESTABLISHED` events observed, then a
   real `cdr_adaptive_odbc` CDR row (`disposition=ANSWERED`,
   `dstchannel LIKE PJSIP/<endpoint>-%`).
6. **Inbound `id_regex`/`getChannelOwner()` still resolves this trunk** —
   proven directly via `scripts/pjsip-external-trunk-check.php channelowner`,
   the exact call `PBX_Asterisk_AGI_Request` itself makes (with the trailing
   `-<numeric suffix>` already stripped, matching that call site's own
   `strrpos()`-based normalization, TASK-0016) — not inferred merely from
   "the code wasn't touched".
7. **Existing registered PJSIP trunk regression still passes** — satisfied
   by `trunk-smoke-test.sh` (native `pjsip` trunk, both directions)
   continuing to pass in the same `make regression` run; not re-proven here.

### Fixture note: destination == endpoint name for the live call

`TEST_DESTINATION` (the digits the caller dials) is set equal to
`EXTERNAL_ENDPOINT` (the fixture endpoint's name) for the live-call phase
only. Confirmed live via `pjsip set logger on`: baresip (acting as the
external endpoint) answers an INVITE only when its Request-URI user matches
its own configured account name exactly, rejecting any other value with a
real SIP `404 Not Found` — a real, single-line SIP UA's own behavior, not a
SENMA or Asterisk defect (Asterisk's `[default]` dialplan itself routes any
dialed string here regardless, via `extensions.conf`'s catch-all `_.,`
pattern — confirmed live with an alphanumeric destination too). Item 2/3/4
above are already proven with **distinct** destination/endpoint values via
the direct, non-HTTP check; this live call's job is narrower — proving a
real call reaches a real endpoint — and does not depend on the two values
differing.

## Validation

- Real outbound call proof: `make pjsip-external-trunk-smoke` — PASS, 19/19
  checks, twice consecutively (see below).
- Resulting live dial string (Asterisk log,
  `DiscarTronco::execute()`'s own log line): `PJSIP/task0028x-ext-endpoint@task0028x-ext-endpoint`
  (destination == endpoint for this specific run, see fixture note above;
  the direct check separately proves `PJSIP/604@task0028x-ext-endpoint` for
  a distinct destination).
- Inbound-preservation evidence: `scripts/pjsip-external-trunk-check.php channelowner`
  resolved `PJSIP/task0028x-ext-endpoint` to the correct `Snep_Trunk`;
  `trunk-smoke-test.sh` (native trunk, inbound direction) — PASS, 23/23
  checks.
- Target regression: `make pjsip-external-trunk-smoke` — PASS (twice
  consecutively); `make trunk-smoke` — PASS.
- `make lint` — PASS (270 PHP files/0 syntax errors, 32 shell scripts,
  3 resources.xml, `git diff --check` clean).
- `make regression` run 1 — see checkpoint comment/PR for the full matrix.
- `make regression` run 2 — see checkpoint comment/PR for the full matrix.
- `git diff --check` — PASS (no whitespace errors).
- `git status --short` — see checkpoint.

Live-restoration proof: `/etc/asterisk/pjsip.conf` inside the running
`asterisk` container diffed byte-for-byte identical to
`docker/asterisk-config/pjsip.conf` after every `pjsip-external-trunk-smoke`
run, including after two consecutive runs.

## Remaining debt

None pulled in from this task's own findings beyond what is documented
above. TASK-0028Y/0028Z/0029A/0029B findings (if any) are out of scope here
and not referenced.

## Recommendation

APPROVE_WITH_CONSTRAINTS — the `externalPjsipEndpointExists()` fix, while
narrowly scoped and verified, was outside this task's original stated
scope; it is called out explicitly here (and was surfaced to the user
before being applied) so a reviewer can evaluate it as a distinct change
from the confirmed dial-string defect fix, and split the commit
accordingly.
