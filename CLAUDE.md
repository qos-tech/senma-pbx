# SENMA PBX — Claude Code Project Guide

## Mission

SENMA PBX is a modernized fork of SNEP 3.07.

The project must evolve incrementally, preserving legacy behavior while moving toward a modern, reproducible and maintainable PBX platform.

The current development strategy is:

```text
Docker-first
↓
PHP 8.4 compatibility
↓
automated smoke validation
↓
Asterisk 22 LTS
↓
PJSIP
↓
architecture modernization
↓
PostgreSQL evaluation/migration
```

Do not treat this project as a rewrite.

Prefer compatibility, observability and controlled migration over broad redesign.

---

## Project identity

- Product name: SENMA PBX
- Repository: `qos-tech/mag-pbx`
- Origin: fork of SNEP 3.07
- License: GPL-3.0-or-later for inherited and derivative code
- Primary development environment: Docker
- Target production operating system: Debian 14
- Target PHP: PHP 8.4+
- Target Asterisk: Asterisk 22 LTS
- Target SIP stack: PJSIP
- Current database: MariaDB/MySQL compatibility
- Future database candidate: PostgreSQL

The project may still contain internal paths, class names, schema names and legacy identifiers using `snep`.

Do not rename those opportunistically.

Rebranding and removal of legacy SNEP naming must be handled in dedicated tasks.

---

## Development principles

1. Preserve existing behavior before modernizing it.

2. Prefer small, reviewable changes over broad rewrites.

3. Do not mix unrelated migration phases in the same task.

4. Never remove original copyright or licensing notices from inherited files.

5. Mark materially modified inherited files according to GPL requirements.

6. Do not introduce new runtime dependencies without documenting why they are needed.

7. Prefer official Debian, PHP, MariaDB and Asterisk packages or images where practical.

8. If Asterisk must be compiled, isolate the build in Docker and pin the exact version.

9. Configuration and secrets must come from environment variables or mounted development configuration.

10. Never commit real credentials.

11. Changes must leave the repository in a reproducible state.

12. Do not fix unrelated legacy bugs opportunistically.

13. When an unrelated bug is discovered, document it as technical debt or a future task.

14. Evidence from the repository and runtime behavior takes precedence over assumptions.

15. Do not trust broad grep results without targeted verification.

---

## Migration phases

### Phase 0 — Repository baseline

Goal:

Preserve the original codebase and establish the SENMA project identity, development conventions and licensing provenance.

Includes:

- project identity
- licensing documentation
- development documentation
- harness setup
- repository conventions

---

### Phase 1 — Docker bootstrap

Goal:

Run the existing application reproducibly in Docker.

The target developer workflow is:

```bash
git clone <repo>
cd mag-pbx
cp .env.example .env
make dev
```

The developer host must not require PHP, MariaDB or Asterisk to be manually installed.

Allowed:

- Dockerfile(s)
- `compose.yaml`
- Makefile
- environment variables
- Apache/PHP runtime configuration
- MariaDB container
- database bootstrap/import scripts
- filesystem permission fixes
- health checks
- entrypoints
- developer documentation
- minimal compatibility fixes strictly required to boot the application

Avoid:

- architectural refactoring
- broad PHP cleanup
- Asterisk migration
- PJSIP conversion
- database redesign
- PostgreSQL migration
- frontend redesign
- global SNEP → SENMA path renaming

Legacy runtime paths such as:

```text
/var/www/html/snep
```

may remain until a dedicated rebranding/filesystem task removes them safely.

---

### Phase 2 — PHP 8.4 compatibility

Goal:

Make the existing SENMA/SNEP application operate under PHP 8.4 while preserving behavior.

This is a compatibility migration, not an architectural rewrite.

Compatibility work should be classified as one of:

```text
A — Syntax/API removed by PHP

B — Runtime semantics changed by PHP

C — Legacy application/data assumption exposed by PHP

D — Legacy database semantics exposed by modern DB behavior
```

Examples:

```text
each() removal
→ A

non-static methods called statically
→ A/B

PHP4-style constructors
→ B

missing runtime/session/database assumptions
→ C

implicit MySQL non-strict defaults
→ D
```

For every compatibility change:

- preserve behavior
- keep the change narrowly scoped
- document the pattern
- validate it in Docker
- avoid opportunistic refactoring

---

### Phase 3 — Automated smoke validation

Goal:

Turn the manually verified application flows into a repeatable regression suite.

Target command:

```bash
make smoke
```

Initial smoke coverage should include:

```text
login
dashboard
extensions
trunks
routes
groups
queues
reports
settings
logout
```

Each flow should validate:

- expected HTTP status or redirect
- meaningful rendered content
- authenticated session behavior
- no PHP Fatal Error
- no unexpected output breaking headers
- relevant logs

A flow that requires Asterisk may be explicitly marked as expected-to-fail until the Asterisk container exists, but this must be documented.

---

### Phase 4 — Asterisk container

Goal:

Introduce Asterisk into the Docker development topology as a dedicated service.

Target topology:

```text
app
db
asterisk
```

Asterisk must not run inside the application container.

Shared data must use explicit Docker volumes rather than legacy cross-tree symlink assumptions where practical.

Do not introduce PJSIP migration yet unless the task explicitly targets it.

---

### Phase 5 — Asterisk 22 compatibility

Goal:

Make legacy telephony behavior operate against Asterisk 22 LTS.

Focus areas include:

- AMI
- CLI commands
- configuration files
- AGI
- dialplan
- spool paths
- recordings
- queues
- voicemail
- runtime permissions

Preserve behavior before modernizing architecture.

---

### Phase 6 — PJSIP

Goal:

Remove `chan_sip` assumptions and implement native PJSIP provisioning.

Treat these concepts explicitly:

```text
endpoint
auth
aor
registration
identify
transport
```

Do not simply map `sip.conf` sections mechanically.

Preserve the user-facing abstraction of:

```text
extension
trunk
route
```

while allowing the internal telephony layer to manage the PJSIP objects required by Asterisk.

---

### Phase 7 — Architecture modernization

Goal:

Progressively isolate:

```text
web
telephony
persistence
background jobs
reporting
configuration
```

Prefer modular boundaries before considering distributed microservices.

Do not begin architectural redesign while compatibility work is still incomplete.

---

### Phase 8 — PostgreSQL evaluation/migration

Only begin after database access is sufficiently isolated.

Do not migrate PostgreSQL merely by translating SQL syntax.

Evaluate:

- schema design
- constraints
- indexes
- JSON usage
- IP/network types
- transactions
- reporting requirements
- migration strategy

---

## Makefile as public interface

Treat the Makefile as the primary developer interface.

Expected commands:

```bash
make dev
make up
make down
make restart
make logs
make ps
make shell
make db-shell
make test
make smoke
make lint
make doctor
make reset
```

If a command does not exist yet, implement it during the relevant task.

Do not teach developers arbitrary one-off Docker commands when an equivalent Makefile command should exist.

---

## Docker rules

- Prefer Docker Compose v2.
- Use named volumes for persistent development data.
- Keep application source bind-mounted for development unless proven problematic.
- Add health checks to stateful/runtime services where practical.
- Use explicit service names.
- Never use `latest` image tags.
- Pin major/minor versions at minimum.
- Pin exact Asterisk versions.
- Do not commit `.env`.
- Commit `.env.example`.
- Entry points must be idempotent.
- Database initialization must be deterministic.
- Database initialization must either be idempotent or clearly guarded.
- Do not silently mutate host configuration.
- Do not disable database strict mode globally to hide legacy bugs.
- Prefer explicit compatibility fixes over permissive global runtime settings.

---

## Validation rules

A task is not complete because:

```text
docker build
```

succeeds.

Before claiming Docker/runtime work is complete, run the closest applicable checks:

```bash
docker compose config
make doctor
make up
make ps
```

Then validate the actual application endpoint and inspect logs.

When available:

```bash
make test
make smoke
make lint
```

For PHP compatibility work:

- run `php -l` on touched PHP files
- exercise the affected runtime flow
- inspect Apache/PHP logs
- confirm no new fatal errors were introduced

Do not rely solely on static analysis.

---

## Legacy-code investigation rules

Before changing an unfamiliar subsystem:

1. Trace how it is currently used.

2. Identify call sites.

3. Identify configuration files.

4. Identify SQL/table dependencies.

5. Identify filesystem assumptions.

6. Identify ownership/permission assumptions.

7. Identify shell commands.

8. Identify Asterisk interfaces.

9. Determine whether the behavior belongs to:
   - application logic
   - installation/runtime environment
   - telephony integration
   - legacy compatibility

10. Apply the smallest behavior-preserving fix.

11. Record unrelated debt separately.

---

## Static analysis rules

Never perform broad mechanical conversions without semantic verification.

Examples:

### `each()`

Before converting:

```php
each()
```

verify there is no dependency on:

```php
reset()
next()
prev()
current()
key()
```

or array-pointer side effects.

### Static method migration

Before changing:

```php
SomeClass::method()
```

verify whether the method uses:

```php
$this
```

or other instance state.

For mixed classes:

- classify methods individually
- stateless methods may become static
- stateful methods must remain instance methods
- fix incorrect static call sites instead

Do not blanket-convert mixed classes.

### PHP4-style constructors

Before replacing:

```php
function ClassName()
```

with:

```php
__construct()
```

search for explicit calls to:

```php
$obj->ClassName()
```

and preserve behavior accordingly.

---

## Known runtime boundary

Until the Asterisk service exists in Docker, some application flows may fail because they directly depend on Asterisk configuration or AMI.

Examples discovered so far include application areas such as:

```text
queues
system status
```

A failure caused purely by the documented absence of Asterisk is not automatically a PHP compatibility failure.

Always distinguish:

```text
PHP/runtime regression
```

from:

```text
expected no-Asterisk limitation
```

using logs and stack traces.

---

## Git discipline

Use focused branches such as:

```text
chore/docker-bootstrap
fix/docker-permissions
chore/php-runtime
refactor/php84-compat
test/http-smoke
feat/asterisk-container
feat/pjsip-extensions
feat/pjsip-trunks
```

Keep commits conceptually narrow.

Do not rewrite unrelated legacy code while solving infrastructure or compatibility tasks.

---

## Commit policy

Do not create commits automatically unless explicitly instructed.

However, every completed and validated task or migration batch must reach a commit checkpoint before the next task begins.

The workflow must be:

```text
task
↓
implementation
↓
validation
↓
report
↓
commit checkpoint
↓
next task
```

When a task is complete:

1. Stop development.
2. Report the validated result.
3. Report the working-tree status.
4. Propose a thematic commit split.
5. Wait for authorization if commit creation was not explicitly requested.

Do not begin the next task while validated changes remain uncommitted unless explicitly authorized.

Prefer small thematic commits.

Typical commit categories:

```text
chore:
fix:
refactor:
test:
docs:
feat:
```

Examples:

```text
chore: bootstrap Docker development environment

fix: restore PHP 8.4 runtime compatibility

fix: eliminate PHP 8.4 static-call incompatibilities

test: add HTTP smoke validation

feat: add Asterisk development container

feat: add PJSIP extension provisioning

docs: document PHP 8.4 migration findings
```

When multiple logical changes are mixed in one file, use:

```bash
git add -p
```

to separate hunks when practical.

Never silently commit:

```text
.env
credentials
logs
generated runtime files
database volumes
temporary files
Claude local session state
```

Before proposing a commit, inspect:

```bash
git status
git diff --stat
git diff
```

---

## Bug and technical-debt policy

When a pre-existing bug unrelated to the current migration task is discovered:

- do not fix it opportunistically
- document it
- create or propose a dedicated future task

Example:

```text
Snep_Trunks_Manager::getTrunkLog()
```

contains a suspected legacy backtick/shell-execution bug.

That should be handled by a dedicated legacy-bugfix task rather than being mixed into PHP 8.4 compatibility work.

Likewise, orphan SQL scripts, missing optional modules and legacy schema inconsistencies should be tracked separately unless they block the current milestone.

---

## Documentation structure

Significant architectural decisions:

```text
docs/decisions/
```

Active implementation tasks:

```text
docs/tasks/
```

Compatibility investigations should include:

- exact files
- representative line references where practical
- affected flows
- before/after behavior
- validation performed
- unresolved items
- confidence level when findings are incomplete

Correct documentation when later evidence disproves an earlier assumption.

Do not preserve known-wrong findings for historical consistency.

---

## Definition of Done — Docker bootstrap

Docker bootstrap is complete when a developer on a clean machine with Docker can run:

```bash
git clone <repo>
cd mag-pbx
cp .env.example .env
make dev
```

and obtain:

- application container running
- database container healthy
- application reachable from the host
- database initialized deterministically
- persistent development data stored in named volumes
- logs available through `make logs`
- application shell available through `make shell`
- database shell available through `make db-shell`
- teardown through `make down`
- destructive reset clearly separated through `make reset`
- documented prerequisites
- no manually installed PHP/MariaDB/Asterisk requirement on the host

---

## Definition of Done — migration batch

A migration batch is complete only when:

- implementation is finished
- touched files pass syntax checks
- relevant flows are exercised
- logs are inspected
- no unexplained new fatal errors exist
- documentation is updated
- unresolved issues are recorded
- working tree is reviewed
- a commit checkpoint is reached before additional scope begins

---

## Current operating rule

The project is currently in the PHP 8.4 compatibility stage.

Do not begin:

```text
curly-brace migration
Asterisk containerization
Asterisk 22 migration
PJSIP
PostgreSQL
frontend redesign
global filesystem rebranding
architecture redesign
```

unless the active task explicitly authorizes that scope.

At every task boundary:

```text
STOP
VALIDATE
DOCUMENT
CHECK GIT STATUS
COMMIT CHECKPOINT
THEN CONTINUE
```
