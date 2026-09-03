# TASK-0026H — Authentication and default-install hardening (F21-F24, F27)

## Status

Implementation complete. Focused smoke suite (32/32), `make lint`, and two
consecutive `make regression` runs all PASS (§9-11). Pending commit
checkpoint authorization.

## Scope

Re-traces and remediates findings **F21-F24** and **F27** from
`docs/tasks/0026-pre-pilot-security-release-audit.md` against the CURRENT
code, after TASK-0026A-G already landed. Explicitly out of scope (per the
task's own instructions): F25/F26/F28 (deferred to TASK-0026I), MFA,
OAuth/SSO/external identity providers, and broad user-management redesign.

## 1. F21-F24/F27 reconstruction (Phase 1)

| Finding | Current surface | Current behavior | Severity | Status |
|---|---|---|---|---|
| F21 | `AuthController.php:94`, `Snep_Users_Manager::add()`, `UsersController::editAction()`, `Snep_Auth_Manager::getUpdatePass()`, `snep/modules/default/api/index.php:113`, install seed | Every password write/verify used raw unsalted `md5()`; `users.password` was `VARCHAR(45)`, too narrow for `password_hash()` output | MEDIUM-HIGH | remediated |
| F22 | `AuthController::loginAction()` | No lockout counter, no delay, no throttling anywhere in the auth path | MEDIUM | remediated |
| F23 | `AuthController::aleatorio()` | `srand()`/`rand()` for the 6-char password-reset code | LOW | remediated |
| F24 | `Snep_AuthPlugin::preDispatch()` | Bypass check was action-name-only (`redefine`/`recuperation`), no controller check | LOW | remediated |
| F27 | `snep/install/database/system_data.sql:72` | Shipped `admin` / `admin123` (verified MD5 `0192023a7bbd73250516f069df18b500`), no forced-change mechanism | CRITICAL at deploy time | remediated |

### Additional discoveries in the same code being rewritten (not scope creep — same precedent as TASK-0026F)

- **SQL injection in `Snep_Auth_Manager::getUpdatePass()`**: built its
  `UPDATE ... WHERE` clause via raw string interpolation of
  `$data['user']` (`$_POST['username']`, `AuthController::
  recuperationAction()`, unauthenticated). Fixed with `$db->quoteInto()`
  in the same edit that modernized the password write.
- **Plaintext password persisted outside the hash**: `AuthController.php`
  stored the plaintext password in `$_SESSION` via reversible AES
  encryption (`$_SESSION['ENCRYPTION_KEY']` = `md5($password)`,
  `$_SESSION['http_authorization']` = `Snep_Usuario::encrypt(...)`, both
  the ciphertext AND its own decryption key in the same session). A
  full-repository grep confirmed no other code reads either field
  ("Retaining the old verifica.php" — dead legacy carryover). Removed
  rather than carried forward, per this task's own "plaintext must never
  be persisted outside the password hash" invariant.
- **Username-enumeration oracle**: the login-failure branch merged
  "blank username" and "user not found" into the same
  `empty($username) || empty($case)` condition, producing "Please enter
  a username" for an unknown user but "User or password invalid" for a
  known user with a wrong password — two distinguishable messages.
  Fixed: the blank-field message now fires only for a genuinely blank
  submission; unknown-user and wrong-password are indistinguishable.
- **Password hash sent to the browser**: `users/addedit.phtml`'s edit
  form pre-filled the password `<input>` with the raw stored hash value
  on every page load — the reason the old "don't rehash a hash"
  detection was a fragile `strlen()==32` heuristic instead of the
  standard "blank field means unchanged" convention. Fixed alongside the
  hashing migration (§5).

### Architectural finding: `Zend_Auth_Adapter_DbTable` is incompatible with `password_hash()`

Traced before writing any code: `Zend_Auth_Adapter_DbTable::
_authenticateCreateSelect()` builds `SELECT *, (CASE WHEN password = ?
THEN 1 ELSE 0 END) ... WHERE name = ?` — the credential comparison
happens **in SQL**, as a literal equality check. This only ever worked
because `md5($plaintext)` is deterministic. `password_hash()`'s salted,
non-deterministic output can never match via SQL equality — verification
must happen in PHP (`password_verify()`) against a row fetched by
identity alone. Both browser login and the standalone API (which shared
this same adapter class) needed a small custom
`Zend_Auth_Adapter_Interface` implementation instead (§4) — a supported
ZF1 extension point, not a Zend_Auth redesign; `Zend_Auth::
authenticate()`/`getStorage()`/`hasIdentity()`/`clearIdentity()` and
`Zend_Auth_Result`'s own semantics are all reused exactly as before.

## 2. Password representation inventory (Phase 2)

| Path | Before | After |
|---|---|---|
| `AuthController::loginAction()` (browser login) | VERIFY_LEGACY_MD5 (SQL-level, via `Zend_Auth_Adapter_DbTable`) | VERIFY_MODERN + VERIFY_LEGACY_MD5-with-migration (`Snep_Auth_Adapter_Password`) |
| `snep/modules/default/api/index.php` (standalone API) | VERIFY_LEGACY_MD5 (SQL-level) | VERIFY_MODERN + VERIFY_LEGACY_MD5-with-migration (same adapter) |
| `Snep_Users_Manager::add()` (user creation) | WRITE_LEGACY_MD5 | WRITE_MODERN |
| `UsersController::editAction()` (user edit) | WRITE_LEGACY_MD5 (with a `strlen()==32` "don't rehash a hash" guard) | WRITE_MODERN, or NO_PASSWORD (unchanged) when the field is blank |
| `Snep_Auth_Manager::getUpdatePass()` (`recuperationAction()`, password reset) | WRITE_LEGACY_MD5 | WRITE_MODERN |
| `AuthController::aleatorio()` (reset-code generation) | NO_PASSWORD (generates a *code*, not a password) — F23 fixed regardless | NO_PASSWORD, `random_int()` |
| `snep/install/database/system_data.sql` (install seed) | WRITE_LEGACY_MD5 (`admin`/`admin123`) | WRITE_MODERN, generated at bootstrap time — see §8 |
| `docker/bootstrap-admin.php` (new, F27) | n/a | WRITE_MODERN |
| `ConferenceRoomsController.php:179` (`md5($valuePassword)`) | N/A | **NO_PASSWORD** — a conference-room PIN written into Asterisk dialplan config (MeetMe/ConfBridge), never `users.password`. Confirmed by reading the surrounding code (builds `$contentConfe` dialplan text); out of scope, untouched. |

Every WRITE_LEGACY_MD5 path above is now WRITE_MODERN; no path was left
modernizing only login while leaving another write path on MD5.

## 3. Shared password helper (Phase 3) — `Snep_Security_Password`

New file: `snep/lib/Snep/Security/Password.php`. Four small, testable
static methods, used by every password-write and password-verify path
in the application (browser login, the standalone API, user creation,
user editing, password reset) so none of them independently decides what
"a password" looks like:

- `hash($plaintext)` — `password_hash()` with `PASSWORD_DEFAULT` (the
  task's own instruction to prefer the runtime default over hardcoding
  an algorithm/cost).
- `verify($plaintext, $stored)` — dispatches to `password_verify()` for
  a modern stored value, or a `hash_equals()` comparison against
  `md5($plaintext)` for a legacy one. A stored hash (of either kind)
  submitted AS the plaintext can never itself verify: `password_verify()`
  is asymmetric by construction, and the legacy branch only ever compares
  `md5($plaintext)` against `$stored`, never `$stored` against itself.
- `isLegacyMd5($stored)` — true only for a bare 32-hex-character string,
  the one and only format this schema/codebase ever produced pre-task
  (confirmed by tracing every prior write site). Misclassifying an
  unrelated 32-character value here cannot itself grant access — it only
  changes which comparison branch runs, and neither branch trusts the
  value as a credential without an actual match.
- `needsRehash($stored)` — always true for a legacy value; otherwise
  `password_needs_rehash($stored, PASSWORD_DEFAULT)` (Phase 7 — a future
  `PASSWORD_DEFAULT` change migrates existing accounts transparently on
  next login, without forcing a rewrite of every hash now).
- `meetsMinimumLength($plaintext)` / `MIN_LENGTH = 8` — server-side
  enforcement point for every password-SETTING flow (§7).

**72-byte bcrypt truncation, addressed explicitly** (Phase 14: "do not
silently truncate passwords"): `PASSWORD_DEFAULT` (bcrypt today) silently
truncates its input at 72 bytes. `hash()`/`verify()`'s modern branch
pre-hash the plaintext with a fixed-length SHA-256 digest
(`normalize()`) before handing it to `password_hash()`/`password_verify()`
— a long passphrase is never cut short, regardless of which algorithm
`PASSWORD_DEFAULT` resolves to now or in the future. Never applied to
the legacy MD5 comparison branch, which must keep matching the exact
pre-existing `md5($plaintext)` representation.

## 4. `Snep_Auth_Adapter_Password` (Phase 4-6)

New file: `snep/lib/Snep/Auth/Adapter/Password.php`, implementing
`Zend_Auth_Adapter_Interface`. Used by BOTH `AuthController::
loginAction()` and `snep/modules/default/api/index.php` — one shared
password-authentication semantic, per the task's own explicit
requirement.

```
authenticate():
  fetch users row by identity only (name = BINARY ?, parameterized) --
    case-sensitive, absorbing what Snep_Acl::getCaseSensitive() used to
    do as a separate pre-check
  row not found -> FAILURE_IDENTITY_NOT_FOUND
  Snep_Security_Password::verify() false -> FAILURE_CREDENTIAL_INVALID
  verify() true:
    needsRehash()? -> UPDATE users SET password = hash(...) WHERE id = ?
      (parameterized; only THIS row; only after successful verification)
    -> SUCCESS, identity = the submitted username (byte-identical to
       Zend_Auth_Adapter_DbTable's own prior convention, so every other
       Zend_Auth::getInstance()->getIdentity() call site across the app
       keeps working unchanged)
```

Migration never happens on failed password, unknown user, or a
malformed/unrecognized stored value — only after `verify()` itself
already returned true (Phase 4's own explicit invariant).

## 5. Modern account creation/editing (Phase 5)

- `Snep_Users_Manager::add()` — now `Snep_Security_Password::hash()`.
- `UsersController::editAction()` — replaced the `strlen($dados['password'])
  != 32` heuristic with the standard convention: a blank submitted
  password field means "keep the existing hash exactly" (reuses
  `$user['password']`, already fetched); any non-blank value is always a
  real new plaintext to hash. This was only ever a fragile heuristic
  because the edit form pre-filled the password field with the raw
  stored hash (§1) — `users/addedit.phtml` no longer does that; the
  field now renders blank on edit (placeholder: "Leave blank to keep the
  current password"), required on add.
- Server-side minimum length (8 characters, `Snep_Security_Password::
  MIN_LENGTH`) enforced in `UsersController::addAction()`,
  `UsersController::editAction()` (non-blank branch only), and
  `AuthController::recuperationAction()` — the client-side
  `minlength: 8` in `addedit.phtml` is a UX nicety, not the actual
  control.
- Verified live: editing a user's OTHER fields (e.g. email) while
  leaving the password field blank leaves the stored hash byte-identical
  (focused smoke check 11).

## 6. Standalone API compatibility (Phase 6)

`snep/modules/default/api/index.php` now constructs
`Snep_Auth_Adapter_Password($db, $apiUser, $apiPlainPasswd)` instead of
`Zend_Auth_Adapter_DbTable` + `md5()` — the exact same adapter class
`AuthController` uses. One password semantic across both entry points:
a modern account authenticates via `password_verify()`; a legacy MD5
account authenticates and migrates transparently, exactly like browser
login; a stored hash (of either format) submitted as the password never
authenticates. TASK-0026F's own F17-A pass-the-hash coverage was
re-verified against this new adapter (focused smoke check 15) and still
holds — a stored value submitted as the credential still fails closed,
now with `password_verify()`'s own asymmetry as an additional structural
guarantee alongside the original md5-normalization fix.

## 7. Rehash policy (Phase 7)

`Snep_Auth_Adapter_Password::authenticate()` calls `Snep_Security_Password
::needsRehash()` on every successful verification, not just for legacy
MD5 — so a future `PASSWORD_DEFAULT` change (e.g. bcrypt to argon2id)
migrates every account transparently on its own next login, with no
separate migration task ever required. No forced rewrite of a hash that
doesn't need one.

## 8. Login rate limiting (Phase 8-9) — `Snep_Security_LoginThrottle`

New file: `snep/lib/Snep/Security/LoginThrottle.php`, backed by a new
`login_attempts` table (`snep/install/database/schema.sql`) — the
existing MariaDB database, no new runtime dependency.

**Policy** (conservative, pilot-use defaults, both a fixed 15-minute
window):

- `MAX_FAILURES_PER_ACCOUNT = 5`, scoped to the **(source IP, username)**
  pair.
- `MAX_FAILURES_PER_IP = 20`, scoped to the source IP alone, any
  username.

**Why two dimensions, both IP-anchored**: the account-scoped counter is
deliberately keyed by `(ip, username)`, never `username` alone — an
attacker cannot lock out a known/victim account by spraying failed
attempts from many different sources, because a different source's own
failures against that same username don't count toward this pair's
counter. The broader per-IP counter is what actually catches an attacker
spraying many usernames from one source (credential stuffing/scanning).
Verified live (focused smoke check 20): a username throttled at 5+
failures does not block a *different* username's login from the same
source.

**Automatic expiration, no lockout**: both checks only ever count rows
newer than the window — a block lifts on its own the instant the window
elapses, never a permanent lockout. Verified deterministically (focused
smoke check 19) by directly aging `login_attempts.attempted_at` rows
past the window in the database rather than sleeping 15 real minutes.

**Clears on success**: a successful login `DELETE`s that exact
`(ip, username)` pair's own failure rows (Phase 9's "success should
clear/reduce relevant failure state"); the broader per-IP counter is
deliberately left alone, since an unrelated successful login should not
reset a scanning/stuffing signal from that same source.

**Session-independent**: keyed by database rows, never `$_SESSION` — a
fresh cookie jar does not reset the counter (verified live, focused
smoke check 18).

**Bounded storage**: an opportunistic prune (rows older than 2x the
window) runs on every recorded failure — no separate cron/scheduled job.

**Response**: a throttled request never computes a credential
comparison at all (`isThrottled()` is checked before
`Snep_Auth_Adapter_Password` is even constructed) and shows a distinct
"Too many failed login attempts" message — shown identically regardless
of whether the attempted username exists, so it does not itself become a
new enumeration signal.

The standalone API (Basic auth, stateless, no "login attempt" concept in
the same sense) was left out of this rate limiter, per the task's own
"protect the browser login endpoint" framing and the focused-smoke
checklist, which scopes rate-limiting to browser login only.

## 9. Enumeration behavior (Phase 10)

**Before**: `empty($username) || empty($case)` produced "Please enter a
username" for ANY nonexistent username (not just a blank field), while a
real username with a wrong password produced "User or password
invalid" — two distinguishable outcomes, a username oracle.

**After**: the blank-field message fires only when the submitted
username is literally empty; `FAILURE_IDENTITY_NOT_FOUND` and
`FAILURE_CREDENTIAL_INVALID` (from `Snep_Auth_Adapter_Password`) both
produce the exact same "User or password invalid" message and `failure`
CSS class. Verified live: wrong password, unknown user, and
pass-the-hash all render byte-identical response bodies (differing only
in nothing user-visible).

## 10. Default admin credential / F27 (Phase 11-13)

**Chosen model: Option A — generated one-time bootstrap credential.**
Evaluated against this project's actual Docker-first architecture
(`docker-entrypoint-initdb.d` scripts run ONCE, on first volume
initialization only, confirmed via `docker/db-init/00-import-snep-schema.sh`
— there is no existing rolling-migration mechanism to hook a forced-
change gate into cleanly; the app container's own entrypoint, by
contrast, runs on every start and already has DB connectivity guaranteed
by `depends_on: db: condition: service_healthy`). Option B (forced
first-login change) was not chosen: it would need new authorization-gate
machinery (Phase 13's own listed requirements — CSRF still active,
logout still works, no controller bypass) for a problem a random,
sufficiently long, one-time credential surfaced only via container logs
already solves at a much higher trust bar (host-level log access, not a
public HTTP form) with far less code.

**Install seed** (`snep/install/database/system_data.sql`): the `admin`
row's `password` is now the literal sentinel `!SENMA-BOOTSTRAP-PENDING!`
— matches neither `Snep_Security_Password::isLegacyMd5()`'s pattern nor
a `password_hash()` string, so `verify()` rejects it against every
possible submitted plaintext (`password_verify()` returns false for an
unrecognized hash format; live-verified against `admin123`,
`SmokeTest123!`, and the literal sentinel value itself, focused smoke
check 22a). A fresh install has **no usable admin credential at all**
until bootstrap runs.

**Bootstrap** (`docker/bootstrap-admin.php`, new, invoked from
`docker/entrypoint.sh` on every container start): a standalone PHP
script (no Zend/MVC bootstrap needed — a raw PDO connection plus
`Snep_Security_Password`). Idempotent by construction: it only acts
while `admin`'s stored password still exactly equals the sentinel: on
that condition it generates a random 128-bit credential
(`bin2hex(random_bytes(16))`), hashes it with `Snep_Security_Password::
hash()`, `UPDATE`s the row, and prints it once to the container's own
stdout (`docker compose logs app` / `make logs`). Once replaced, every
later invocation (restart, `docker compose up` again, ...) finds a
non-sentinel value and no-ops. Verified live: the sentinel state is
unauthenticatable; running the real bootstrap script replaces it with a
working, printed credential; running it again immediately after prints
nothing further (idempotent) — focused smoke checks 22a-22e.

**Schema**: `users.password` widened from `VARCHAR(45)` to `VARCHAR(255)`
(`snep/install/database/schema.sql`) — required for `password_hash()`
output (bcrypt: 60 chars; headroom for a future, longer
`PASSWORD_DEFAULT`). Applied to the live dev database via a direct
`ALTER TABLE` during this task's own implementation (no rolling-migration
mechanism exists in this project yet — see the note below); a `make
reset` or a fresh volume picks it up automatically from `schema.sql`.

**Deployment note, not fixed here**: this project's `docker-entrypoint-
initdb.d` scripts only ever run against a brand-new database volume.
Anyone with a PRE-EXISTING dev/pilot volume from before this task needs
to apply the same `ALTER TABLE users MODIFY password VARCHAR(255) NOT
NULL;` and the `login_attempts` table creation (§8) by hand, or run
`make reset` for a clean volume. Documented here as operational guidance,
not a code gap this task leaves unaddressed for a fresh install.

`snep/docs/INSTALL_GUIDE.md` (the legacy, Portuguese-language SNEP
manual) updated: its "Usuário: admin / Senha: admin123" line, which would
otherwise now instruct an operator to log in with a credential that
structurally cannot work, replaced with a short note pointing at the
bootstrap log output.

## 11. Dev/test provisioning separation (Phase 12)

No new dev-only provisioning mechanism was needed. Every existing
TASK-0026x smoke script already resets the `admin` fixture's password
itself, at its own start (`UPDATE users SET password=md5('SmokeTest123!')
...`), before logging in — none of them ever relied on the shipped
install-seed default. Since `Snep_Auth_Adapter_Password` migrates ANY
legacy-MD5-seeded account transparently on its first successful login
within that same run, every existing suite continues to work completely
unmodified: each run reseeds `admin` as legacy MD5, the suite's own
first login migrates it to a modern hash for the rest of that run, and
the next run reseeds it as legacy MD5 again — a real, live exercise of
the migration path on every single regression run, not just this task's
own dedicated fixtures. Verified live before writing the new suite
(`authorization-smoke-test.sh`, 17/17, including its own container
restart mid-test) and again via both full `make regression` runs (§10).

Explicit separation, verified statically (focused smoke check 23):
`docker/bootstrap-admin.php` and `docker/entrypoint.sh` — the production
bootstrap path — contain no reference to this project's own documented
dev-only credential string anywhere. The dev/test credential is
provisioned only by each smoke script's own explicit, auditable DB
`UPDATE`, never automatically by any part of the bootstrap path a real
deployment runs.

## 12. Password strength (Phase 14)

Inventoried: the only existing validation was client-side jQuery Validate
(`minlength: 5, maxlength: 32`) on `users/addedit.phtml`, no server-side
enforcement anywhere. Replaced with: client-side `minlength: 8`, no
`maxlength` (removed — see §3's 72-byte truncation note, `hash()` never
truncates); server-side `Snep_Security_Password::meetsMinimumLength()`
(8 characters, byte length) enforced on every password-SETTING flow
(§5). No complexity rules (uppercase/digit/symbol) added, per the task's
own explicit "favor length over arbitrary requirements" instruction —
no existing project/customer requirement was found demanding them.

## 13. Focused smoke — `scripts/auth-hardening-security-smoke-test.sh`

New suite, `make auth-hardening-security-smoke`, built on
`scripts/lib/harness.sh` like every other TASK-0026x security suite.
**Result: PASS, 32/32.** Covers, per Phase 15's checklist:

- **Modern hashing (1-4)**: a user created via the real
  `UsersController::addAction()` HTTP flow is not stored as raw MD5; its
  modern hash verifies a correct login; a wrong password is rejected; the
  stored hash itself submitted as the password is rejected.
- **Legacy migration (5-8)**: a directly-seeded legacy-MD5 fixture
  authenticates with the correct plaintext; its DB representation
  changes to a modern hash immediately afterward; the migrated account
  still logs in on a second attempt (now verified via
  `password_verify()`); a second, untouched legacy fixture attacked with
  a wrong password is confirmed to NOT migrate (stored value unchanged).
- **User-management paths (9-12)**: new-user creation and password
  change (edit) both produce modern hashes; editing a user's other
  fields while leaving the password field blank preserves the existing
  hash byte-for-byte; the redefine/recuperation reset path
  (`AuthController::recuperationAction()`, exercised via a
  directly-seeded `password_recovery` row) also produces a modern hash,
  and the newly-reset password actually works.
- **Standalone API (13-15)**: a modern account authenticates via
  plaintext; a legacy account authenticates AND migrates through the API
  (same adapter, same effect as browser login); pass-the-hash is
  rejected (HTTP 200/`status:error`, matching this endpoint's own
  established convention for a supplied-but-wrong credential — 401 is
  reserved for no credentials supplied at all).
- **Rate limiting (16-20)**: an ordinary failure isn't yet throttled;
  5 failures trigger the limiter; the throttle survives a brand-new
  cookie jar (proving it isn't session-based); deterministically aging
  the recorded failures past the window (direct DB manipulation, no real
  sleep) lifts the throttle; an unrelated username from the same source
  is never blocked by another username's own throttled state, and a
  successful login clears only that exact account's failure history.
- **Default installation (21-23)**: the install seed's actual `INSERT`
  statement (not this task's own explanatory comment, which
  deliberately documents the old value by name) no longer contains the
  `admin123` hash and does contain the bootstrap sentinel; the sentinel
  cannot be logged into with any plaintext tried; re-running the real
  `bootstrap-admin.php` generates a working, printed credential and is
  idempotent on a second run; `docker/entrypoint.sh` is confirmed to
  invoke it; neither the bootstrap script nor the entrypoint references
  the project's dev-only credential string.

The shared `admin` fixture is touched only for check 22 and is
unconditionally restored to the `SmokeTest123!` dev baseline via a
`harness_register_cleanup` (required, not best-effort) — verified: the
cleanup ran and left `admin` at the expected baseline for whichever
suite runs next.

## 14. Canonical validation (Phase 19)

1. `make auth-hardening-security-smoke` — **PASS** (32/32).
2. `make lint` — **PASS**.
3. `make regression` (1st run) — **PASS**, all 20 suites green (19 prior
   + `auth-hardening-security`, placed right after `session-csrf-security`
   and before `authorization-coverage`, same reasoning as every other
   TASK-0026x security suite's own placement comment).
4. `make regression` (2nd run, immediately after, no manual cleanup in
   between) — **PASS**, same 20/20 suites green.

## 15. Health and cleanup (Phase 20)

- `docker compose ps`: `app`, `db`, `asterisk`, `provider` all
  `Up`/healthy.
- Asterisk 22.10.1; `res_pjsip.so` Running; 3 baseline transports intact
  (`tcp`, `udp`, `wss`); ODBC `snep` DSN 1/1 connected; 0 active
  channels.
- PHP Fatal Error count: unchanged across every validation run beyond
  the pre-existing, already-documented `CnlController` upload bug
  (TASK-0026G's own doc, §13) — no fatals attributable to any
  TASK-0026H code path.
- No plaintext credential artifacts: the one credential ever printed in
  plaintext (`docker/bootstrap-admin.php`'s one-time console banner) is
  the INTENDED F27 bootstrap channel, never logged to a file, never
  returned in an HTTP response, never persisted anywhere but that one
  console print and the resulting hash.
- No fixture residue: every `task0026h-*` user/fixture created by the
  focused suite is removed by its own required cleanup; `login_attempts`
  is emptied at both the start and end of the relevant sections; the
  shared `admin` fixture is restored to the `SmokeTest123!` baseline.
- No smoke/regression processes left running.

## 16. Files changed

New:

- `snep/lib/Snep/Security/Password.php`
- `snep/lib/Snep/Security/LoginThrottle.php`
- `snep/lib/Snep/Auth/Adapter/Password.php`
- `docker/bootstrap-admin.php`
- `scripts/auth-hardening-security-smoke-test.sh`
- `docs/tasks/0026h-authentication-default-install-hardening.md` (this
  file)

Modified:

- `snep/install/database/schema.sql` — `users.password` widened to
  `VARCHAR(255)`; new `login_attempts` table.
- `snep/install/database/system_data.sql` — admin seed replaced with the
  bootstrap sentinel.
- `docker/entrypoint.sh` — invokes `bootstrap-admin.php` on every start.
- `docker/app.Dockerfile` — copies `bootstrap-admin.php` into the image.
- `snep/modules/default/controllers/AuthController.php` — modern
  adapter, rate limiting, enumeration fix, dead plaintext-session code
  removed, parameterized identity lookup, `random_int()` in
  `aleatorio()`, minimum-length enforcement on `recuperationAction()`.
- `snep/lib/Snep/Auth/Manager.php` — `getUpdatePass()`: modern hash +
  SQLi fix.
- `snep/lib/Snep/Users/Manager.php` — `add()`: modern hash.
- `snep/modules/default/controllers/UsersController.php` — `editAction()`:
  blank-preserves-hash logic + minimum-length enforcement;
  `addAction()`: minimum-length enforcement.
- `snep/modules/default/views/scripts/users/addedit.phtml` — password
  field no longer pre-filled with the stored hash; validation rules
  updated.
- `snep/modules/default/api/index.php` — shared adapter.
- `snep/lib/Snep/AuthPlugin.php` — F24 controller-scoped fix.
- `snep/docs/INSTALL_GUIDE.md` — default-credential instruction updated.
- `Makefile`, `scripts/regression.sh` — new suite wired in.

## 17. Deferred / residual debt

- F25 (unconditional exception-message disclosure), F26 (X-Powered-By /
  missing security headers), F28 (path traversal in the docs viewer) —
  untouched, explicitly deferred to TASK-0026I per this task's own scope
  boundaries.
- The standalone API has no rate limiting (out of this task's own
  explicit "protect the browser login endpoint" scope — a stateless
  Basic-auth API has a different threat shape; left as a candidate for a
  future task if needed).
- Pre-existing dev/pilot database volumes created before this task need
  a manual `ALTER TABLE`/table-creation step (or `make reset`) to pick up
  the widened `users.password` column and the new `login_attempts`
  table — see §10's deployment note. Not a gap for a fresh install.
- `Snep_Acl::getCaseSensitive()` is now unused (its one caller,
  `AuthController::loginAction()`, was absorbed into
  `Snep_Auth_Adapter_Password`'s own `BINARY` lookup) but was left in
  place rather than deleted, out of caution for a caller this task's own
  repo-wide grep may not have found (e.g. a module outside the audited
  tree). Low-risk future cleanup.
