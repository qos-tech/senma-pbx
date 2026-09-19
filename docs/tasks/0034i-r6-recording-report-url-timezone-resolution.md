# TASK-0034I-R6 — Recording Report URL and Timezone Resolution

**Status:** local implementation checkpoint (see FINAL DECISION in agent report)
**Depends on:** TASK-0034I-R5 / `v0.1.0-rc.16` (immutable)
**Does not:** mutate `v0.1.0-rc.16`, change PHP/DB/Asterisk timezone settings,
deploy, create a new RC, broad Calls Report refactoring, LDAP, sounds/MOH

## Pilot evidence (TEXTE-PBX-001 / v0.1.0-rc.16)

Recording generation works:

- MixMonitor writes a valid WAV
- File exists in Asterisk monitor path and app `path_voz` (shared `snep/arquivos`)
- CDR `userfield` matches recording basename
- Direct static URL works: `/arquivos/YYYY-MM-DD/<userfield>.wav`
- Public URL works: `https://sip.teste.qosit.cloud/arquivos/...`
- Apache/NPM serve `Content-Type: audio/x-wav`

Calls Report rendered:

```text
/index.php/arquivos/YYYY-MM-DD/<userfield>.wav
```

Example:

```text
https://sip.teste.qosit.cloud/index.php/arquivos/2026-09-18/1789754744_20260918_1505_1001_1002.wav
```

That path is **not** a static asset. Under the front controller it returns
HTML (`text/html`, often the login page), so play/download fail even when
the WAV exists on disk.

Observed timezone skew on the same call:

| Source | Wall clock |
|---|---|
| Recording filename / directory (`AA/MM/DD` / `date("/Y-m-d")` in AGI) | ~15:05 America/Sao_Paulo |
| CDR `calldate` | ~18:05 (+03:00) |

## Root causes

### 1. Invalid recording URL (front-controller base vs static asset base)

`Snep_Manutencao::arquivoExiste()` (TASK-0012) used:

```php
$baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
return $baseUrl . "/arquivos/...";
```

Under a request served as `/index.php/...`, runtime evidence shows:

```text
getBaseUrl() === "/index.php"
```

So the report emitted `/index.php/arquivos/...`.

TASK-0012 correctly made browser URLs respect deployment base instead of
hardcoded `/snep`, but conflated:

| Concept | Correct source |
|---|---|
| Application / front-controller URL | `Zend_Controller_Front::getBaseUrl()` (may include `index.php`) |
| Static public asset URL (`/arquivos`) | `setup.conf` `path.web` (`$config->system->path->web`) |
| Deployment base path | `path.web` (`""` root, `/subdir` subdirectory) |
| Front-controller script path | `SCRIPT_NAME` / `index.php` — **not** part of static URLs |

Zend's own `Zend_View_Helper_BaseUrl` already strips the script name for
static view assets. Recording URLs must follow the same distinction.

Download bug: `CallsReportController` copied the URL into `file_name`, and
`analytic.phtml` used `file_name` as `href`. Same wrong URL for audio and
download. Downloading `/index.php/arquivos/...` saved HTML as `.wav`.

### 2. Recording directory derived from CDR calendar day only

```php
$data = substr($calldate, 0, 10);
```

Contracts (current evidence + TASK-0027A):

| Layer | Effective timezone |
|---|---|
| Host / container `TZ` env | `America/Sao_Paulo` |
| PHP `date.timezone` ini | `UTC` |
| App/AGI runtime after bootstrap | `date_default_timezone_set(system.timezone)` → `America/Sao_Paulo` |
| MariaDB `NOW()` / SYSTEM | follows container `TZ` (−03) |
| Asterisk process env `TZ` | `America/Sao_Paulo` |
| CDR `calldate` (DATETIME) | empirically **UTC wall clock** (local + 03:00) |
| Recording filename `AA/MM/DD/HH/ii` | AGI PHP `date()` under system timezone → **local** |
| Recording directory `date("/Y-m-d")` | same AGI local date |

Across local midnight, local recording date and UTC CDR date diverge →
`arquivoExiste()` looked in the wrong `YYYY-MM-DD` folder.

## Resolution contract

1. **Public recording URL** = `path.web` + `/arquivos/` + relative path
   - Root: `/arquivos/2026-09-18/<userfield>.wav`
   - Subdir: `/snep/arquivos/...` when `path.web=/snep`
   - Never `/index.php/arquivos/...`
   - Never hardcode hostname

2. **Date candidates** (first existing file wins):
   1. Embedded `YYYYMMDD` in `userfield` when valid (canonical AGI local date)
   2. `substr($calldate, 0, 10)` (historical)
   3. `calldate` interpreted as UTC → system timezone calendar day
      (midnight boundary without a date token)

3. **Still supported:** `.wav` / `.mp3` / `.WAV`, `storage*` trees,
   conference rooms `901–915`, historical userfields without date tokens.

4. **Report fields:** `file_path` = static URL; `file_name` = basename
   (`<userfield>.wav`) for the `download=` attribute.

## Changes

- `snep/lib/Snep/Manutencao.php` — `publicAssetBaseUrl()`,
  `recordingDateCandidates()`, `recordingPublicUrl()`, rewritten
  `arquivoExiste()` / `compactaArquivos()` static URL builder
- `snep/modules/default/controllers/CallsReportController.php` — keep
  `file_name` as basename
- `snep/modules/default/views/scripts/calls-report/analytic.phtml` —
  audio + download `href` use `file_path`
- `scripts/recording-report-url-smoke-test.sh` + Makefile + regression wiring

## Out of scope / follow-up debt

- Aligning CDR write path so `calldate` uses the same timezone as AGI
  recordings (timezone *settings* change) — audited only here
- Broad Calls Report UI redesign
- Mutating immutable `v0.1.0-rc.16`

## Validation

Focused: `make recording-report-url-smoke`
Canonical: `make lint` + two consecutive `make regression`
Do not mutate rc.16 to green doctor release-identity drift under `:dev`.
