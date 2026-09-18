# TASK-0034I-R5 — Queue Management PHP 8 Hardening

**Status:** local implementation checkpoint (see FINAL DECISION in agent report)
**Depends on:** TASK-0034I-R4 / v0.1.0-rc.15 queue runtime
**Does not:** mutate `v0.1.0-rc.15`, deploy, create `v0.1.0-rc.16`, LDAP,
sounds/MOH backlog, recording reports, doctor topology, broad queue redesign

## Pilot evidence (TEXTE-PBX-001 / v0.1.0-rc.15)

HTTP 500 on `/index.php/queues/add` with PHP warnings:

| Location | Warning |
|---|---|
| `queues/addedit.phtml:168` | Trying to access array offset on null (`queue_thankyou`) |
| `queues/addedit.phtml:239` | offset on null (`memberdelay`) |
| `queues/addedit.phtml:246` | offset on null (`weight`) |
| `QueuesController.php:135-137` | Undefined array key `joinempty` / `leavewhenempty` / `reportholdtime` |

Fatal:

```text
Uncaught TypeError: count(): Argument #1 ($value) must be of type Countable|array, false given
QueuesController.php:147
```

Observed form:

```php
$newId = Snep_Queues_Manager::getName($_POST['name']);
if (count($newId) > 1) { ... }
```

## Root causes

1. **ADD never initialized `$this->view->queue`**, but the shared
   `addedit.phtml` indexes `$this->queue[...]` for every field.
2. **ADD never initialized radio view flags** for `joinempty` /
   `leavewhenempty` / `reportholdtime` (only `ringinuseFalse` was set).
3. **POST indexed optional radio keys** via bare `$_POST[...]`.
4. **`getName()` returns `false` when not found** (`$stmt->fetch()`), but
   the controller called `count($newId)`.

## `getName()` contract

`Snep_Queues_Manager::getName($name)`:

| Case | Return |
|---|---|
| no matching row | `false` |
| one matching row | associative array `{id, name}` |
| multiple rows | does not occur via this API (`fetch()`, not `fetchAll()`; name unique) |
| DB failure | Zend_Db exception (not mapped to `false`) |

### Legacy `count($newId) > 1` semantics

This was **not** a multi-row check. It accidentally worked on PHP 7:

- not found: `count(false) === 1` (with warning) → `1 > 1` false → allow create
- found: array has two columns → `count === 2` → reject as duplicate

Under PHP 8, `count(false)` is a TypeError.

**Canonical duplicate check:** `$existing !== false` means the name is taken.

## Fix summary

### Controller (`QueuesController`)

- `defaultQueueFormModel()` — complete ADD defaults (empty strings for
  text/sound fields; radios `joinempty=no`, `leavewhenempty=0`,
  `reportholdtime=0`, `ringinuse=0` matching historical ADD `ringinuse`
  No default).
- `queuePayloadFromRequest()` — `Request::getPost($key, $default)` for
  all fields; no bare optional `$_POST` indexing.
- `applyQueueRadioViewFlags()` — deterministic checked attributes.
- Process POST **before** rendering (success redirects without a second
  render of an empty ADD form).
- Duplicate check: `getName() !== false`.
- Empty strings for nullable integer columns normalized to SQL NULL
  (MariaDB strict mode rejects `''` for int columns — exposed after the
  count(false) fatal was cleared on the same POST path).
- EDIT: reject missing queue (`get()` false) instead of offset-on-false;
  audit log uses `$queue['id']` (pre-existing `$dados['id']` was undefined).
### Manager

- Document the `false` vs array contract on `getName()` (no cast-to-array).

### View

- Unchanged; relies on controller-provided `$this->queue` array.

## Validation

Focused: `make queue-management-php8-smoke` → **PASS**

| Gate | Result |
|---|---|
| `make queue-runtime-smoke` | PASS |
| `make system-status-runtime-smoke` | PASS |
| `make systemstatus-dashboard-smoke` | PASS |
| `make status-detail-ux-smoke` | PASS |
| `make restart-smoke` | PASS |
| `make host-networking-architecture-smoke` | PASS |
| `make lint` | PASS |
| `make regression` #1 | FAIL — sole suite: `doctor-smoke` (release identity DRIFT vs immutable rc.15 manifest / local image state) |
| `make regression` #2 | FAIL — same sole fail; `queue-management-php8-smoke` PASS both runs |
| `git diff --check` | PASS |

**Constraint:** Do not mutate `v0.1.0-rc.15` / `release-manifest.json` to green doctor.

## Release

- `v0.1.0-rc.15` remains **immutable**
- Next RC after merge: **v0.1.0-rc.16**
- TASK-0035E7 remains blocked on pilot soak / subsequent release process

## Files

- `snep/modules/default/controllers/QueuesController.php`
- `snep/lib/Snep/Queues/Manager.php`
- `scripts/queue-management-php8-smoke-test.sh`
- `Makefile` / `scripts/regression.sh`
- this document
