# AUDIT-0001 — Legacy runtime audit (SNEP 3.07 under `snep/`)

## Status
Findings only. Read-only audit — no application code was changed while producing this document.
Feeds directly into [TASK-0001 — Docker bootstrap](0001-docker-bootstrap.md).

## Method
Static inspection of the `snep/` tree (source, install docs, install scripts, Asterisk sample
configs) via targeted grep/read passes. No code executed. Evidence is cited as `file:line`;
claims without a citation are absent from this document by design.

---

## 1. PHP version assumptions

- The app was documented and packaged for **PHP 5** on **Debian 8 (Jessie)**:
  `snep/docs/INSTALL_GUIDE.md:57,75` (`apt-get install php5 php5-cgi php5-mysql php5-gd php5-curl
  ... libapache2-mod-php5`).
- **Hard PHP 8.0 blocker in first-party code**: `each()` is called in real controllers, not just
  vendored libraries — `snep/modules/default/controllers/TdmLinksController.php:75,257,293`,
  and similarly in `KhompLinksController.php`, `ErrorsKhompController.php`,
  `ErrorsTdmController.php`. `each()` was removed in PHP 8.0; these code paths currently fatal
  under PHP 8.4.
- `create_function()` (removed in PHP 8.0) appears only in vendored code:
  `snep/lib/Zend/Feed/Element.php`, `snep/lib/linfo/lib/class.OS_Linux.php`. Lower risk, but the
  file must still not be `require`d in a way that triggers a parse/compile fatal.
- Curly-brace string-offset syntax (`$var{0}`, removed PHP 8.0) is present in vendored files
  (`snep/lib/Asterisk/AGI.php`, `snep/lib/Zend/Json/Decoder.php`, `Encoder.php`, others). Not yet
  confirmed absent from first-party `modules/`/`includes/` code — needs a follow-up grep before
  Phase 2 work starts.
- No `composer.json`/`composer.lock` exists for the application itself (only a vendored
  `snep/lib/linfo/composer.json`). There is no formal version constraint anywhere in the repo —
  the only evidence of the target PHP version is the install docs and the removed-function usage
  above, both of which point at PHP 5/early PHP 7.
- `snep/agi/Bootstrap-script.php:20-31` — the AGI entry point (invoked by Asterisk, not Apache)
  uses `declare(ticks=1)` and conditionally calls `pcntl_signal()`. This is a second PHP runtime
  context (CLI) with its own extension needs, distinct from the web request path.

**Docker bootstrap implication**: the current scaffold builds `php:8.4-apache`
(`docker/app.Dockerfile:2`). At minimum, `TdmLinksController.php` and the Khomp/TDM error
controllers will fatal on `each()` if those routes/features are exercised. This is out of scope
for Phase 1 (no refactors), but should be recorded as a known-broken surface area rather than
silently discovered later — see Phase 2 note at the end of this document.

## 2. PHP extensions

- The app's own self-check, `snep/inspectors/PHPExtensions.php:36-39`, declares only
  `pdo_mysql`, `gd`, `json`. This is stale/incomplete — it predates or ignores several extensions
  actually used elsewhere (see below) — treat it as a floor, not the real requirement list.
- Confirmed via actual driver code (§4): **`pdo_mysql`** is the live DB extension
  (`snep/lib/Snep/Db.php:57`); `mysqli` classes exist in vendored Zend
  (`snep/lib/Zend/Db/Adapter/Mysqli.php`) but are dead code for this app.
- `gd` — used by sound/graph features flagged in the inspector; not independently re-verified
  beyond the inspector's own declaration.
- `snep/agi/Bootstrap-script.php:28` — conditionally uses `pcntl_signal`; guarded with
  `function_exists()` so its absence won't fatal, but call termination/signal behavior degrades
  without `pcntl` in the AGI/CLI runtime.
- Install docs (`INSTALL_GUIDE.md:75`) additionally reference **ODBC** (`unixodbc`, `libmyodbc`)
  and **curl** as OS packages. ODBC is consumed by **Asterisk** (`res_odbc`, `cdr_odbc`,
  `cel_odbc`, `func_odbc` — see `snep/install/etc/asterisk/*odbc*.conf`), not by the PHP
  application directly; it is not a PHP-extension requirement for the web container.
- The image also needs external CLI binaries the app shells out to at runtime (see §6):
  **`sox`**, **`unzip`**, and (only if voice-synthesis features are used) `festival`/`swift`
  (Cepstral) binaries referenced in `snep/lib/Asterisk/AGI.php:1246,1300`.

## 3. Apache requirements

- `snep/install/snep.apache2:2-3` hardcodes `Alias /snep "/var/www/html/snep"` and
  `<Directory "/var/www/html/snep">` with **Apache 2.2 access-control syntax**
  (`Order deny,allow` / `Allow from 127.0.0.0/255.0.0.0 192.168.0.0/255.255.0.0
  201.47.74.147/255.255.255.255` / `Deny from all`, lines 5-8). This syntax is invalid/no-op
  under Apache 2.4+ (needs `Require ip ...`) and additionally bakes in an environment-specific
  public IP allowlist that should not be reused.
- Same block sets `php_value` directives at the Apache vhost level (`output_buffering 4096`,
  `memory_limit 128M`, `upload_max_filesize 5M`, `max_execution_time 90`) — this requires
  `mod_php` (confirmed: the current scaffold's `php:8.4-apache` base image is mod_php-based, so
  this is compatible), not php-fpm.
- `snep/includes/.htaccess:1-4` denies direct web access to `*.conf` files via
  `Order Deny,Allow` (also Apache 2.2 syntax). **This is the only thing preventing
  `includes/setup.conf` — which contains plaintext DB credentials — from being served as a
  static file.** It relies on `AllowOverride All` being honored, which the current
  `docker/apache-mag.conf:6` vhost does grant. This `.htaccess` should be treated as
  security-load-bearing and preserved/ported, not dropped as legacy cruft. **However, its
  `Order`/`Deny` directives require `mod_access_compat` on Apache 2.4+, and
  `docker/app.Dockerfile` currently only runs `a2enmod rewrite`** — without `mod_access_compat`
  enabled, Apache 2.4 (the base of `php:8.4-apache`) will not honor (and may error on) these
  directives, silently reopening `setup.conf` to direct HTTP access. This is a concrete Phase 1
  gap, not just a later-phase concern.
- `INSTALL_GUIDE.md:80` references a `php-cgi` deployment mode (`register_argc_argv` in
  `php5/cgi/php.ini`) as an alternative to mod_php — historical, not required by the current
  scaffold.
- Only 4 `.htaccess` files exist under `snep/` total (`snep/includes/.htaccess` plus three inside
  vendored `snep/lib/linfo/`), none doing URL rewriting. No evidence the app relies on
  `mod_rewrite` for routing despite `path.modrewrite` existing (empty) as a config key in
  `setup.conf:41`.

## 4. Database drivers and configuration

- **Driver**: `snep/lib/Snep/Db.php:52-58` — `Snep_Db::getInstance()` hardcodes
  `Zend_Db::factory('Pdo_Mysql', $config)` with
  `PDO::MYSQL_ATTR_USE_BUFFERED_QUERY`. `pdo_mysql` is the one real runtime driver.
- **Config source**: `snep/includes/setup.conf` (INI, `[ambiente]` section) —
  `db.host = "127.0.0.1"`, `db.username = "snep"`, `db.password = "sneppass"`,
  `db.dbname = "snep"` (lines 3-6), loaded via `Snep_Config::getConfig()->ambiente->db`.
  **Plaintext credentials committed in a file the app also expects to be writable** (see §2 in
  the Permissions inspector, `snep/inspectors/Permissions.php:56` lists
  `includes/setup.conf` as required `exists`+`writable`+`readable` — the settings UI
  (`snep/modules/default/controllers/ParametersController.php:239-240`) writes recording-path
  settings back into this same file).
- **This file conflates DB config and filesystem-path config**: alongside DB credentials it also
  hardcodes `path.base = "/var/www/html/snep"`, `path.voz`/`path.voz_bkp`,
  `path.log = "/var/log/snep/"`, and Asterisk paths (`/etc/asterisk`,
  `/var/lib/asterisk/sounds`, `/var/lib/asterisk/moh`) — lines 20-21, 33-38. Any Docker path
  change (current scaffold uses `/var/www/html/mag`, not `/var/www/html/snep`) requires
  templating/patching this file, not just setting `.env` vars — the app has no environment-variable
  based configuration path today, which is a direct tension with CLAUDE.md's "config from env
  vars" rule and will need a compatibility shim (e.g. generate `setup.conf` from `.env` at
  container entrypoint) rather than an application code change.
- **Bootstrap order** (`INSTALL_GUIDE.md:229-237`): `database.sql` → `schema.sql` →
  `system_data.sql` → `core-cnl.sql` → `modules/billing/install/schema.sql` →
  `modules/loguser/install/schema.sql`. **`modules/loguser/` does not exist in this checkout**
  (confirmed: `snep/modules/` only contains `billing`, `callback`, `default`, `ivr`,
  `portability`) — the documented install procedure references a module that is missing from
  this repository snapshot. Needs a decision: drop the step, or the module needs to be sourced
  from elsewhere.
- **`database.sql:29,31`** issues its own `CREATE DATABASE`/`GRANT ALL PRIVILEGES ... TO
  'snep'@'localhost' ...` statements. This conflicts with the current Docker topology two ways:
  (a) the official `mariadb` image already provisions the database/user from
  `MARIADB_DATABASE`/`MARIADB_USER`/`MARIADB_PASSWORD` (as `compose.yaml`'s `db` service already
  does), so re-running `database.sql` verbatim is redundant at best; (b) the grant is scoped to
  `'snep'@'localhost'` only, which will refuse connections from the `app` container (a different
  host on the `mag` network, connecting as `db.DB_HOST`). If `database.sql` is ever wired into
  `docker-entrypoint-initdb.d`, only `schema.sql`/`system_data.sql`/`core-cnl.sql` (structure and
  data) are needed — the `CREATE DATABASE`/`GRANT` statements should be left to the image's own
  env-var provisioning.
- Schema dumps use `ENGINE=InnoDB` throughout (56 occurrences across
  `snep/install/database/*.sql` and module schema files) and no `DEFINER=` clauses were found —
  both favorable for MariaDB 10.11 compatibility, no adjustment expected there.
- Additional per-module schema exists at `snep/modules/billing/install/schema.sql` and
  `snep/modules/portability/install/routes.sql` (+ `update/1.1/update.sql`), not mentioned in
  `INSTALL_GUIDE.md`'s load order — worth reconciling when the import script is written.
- A one-off migration script, `snep/install/database/update/betha/convert-data-rc3.php`, connects
  to the DB independently and issues raw ALTER/SELECT/INSERT statements — old data-fixup tooling,
  not part of the base install path.

## 5. Schema/import scripts

Full inventory of `snep/install/database/`:

| File | Purpose (from header/content) |
|---|---|
| `database.sql` | Creates the `snep` database/user (base bootstrap). |
| `schema.sql` | Core table definitions. |
| `system_data.sql` | Seed/reference data. |
| `core-cnl.sql` | Dumped via `mysqldump 10.13, Distrib 5.1.73` — CNL (call number/routing?) reference data; note this is a raw `mysqldump` output from MySQL 5.1, so it may carry old dump-header directives (`SET` statements, charset assumptions) worth a compatibility check when the import script is written. |
| `update/3.01/update.sql` … `update/3.07/update.sql` | Sequential version-to-version migrations (3.01 through 3.07); `update/3.01/` also has `updateCallerid.php`, a PHP-driven data migration using deprecated `mysql_*` functions. |
| `update/betha/schema-betha-rc1/rc2/rc3.sql` + `convert-data-rc3.php` | A separate "betha" branch/fork migration path, not part of the mainline 3.0x sequence. |

Module-level schema (not folded into the documented install order):
- `snep/modules/billing/install/schema.sql`
- `snep/modules/portability/install/routes.sql` (+ `install/sounds/portabilityError.gsm`,
  `install/update/1.1/update.sql`)

**Missing**: `modules/loguser/install/schema.sql`, referenced by `INSTALL_GUIDE.md:237`, has no
corresponding module directory in this repo (see §4).

**Addendum (found during TASK-0001 implementation, not caught by this audit pass):**
`core-cnl.sql` inserts into `core_cnl_state`, `core_cnl_prefix` and `core_cnl_city` — none of
which have a `CREATE TABLE` anywhere in this checkout (only
`install/database/update/3.01/` and `3.06/` create them, and this same `INSTALL_GUIDE.md`'s own
fresh-install steps never run that update chain). `modules/portability/install/routes.sql` has
the identical problem: it inserts into `regras_negocio`, which is likewise never created in this
checkout. Both would abort an automated import partway through. See
`docs/tasks/0001-docker-bootstrap.md` for the resulting decision (both excluded from the Docker
bootstrap DB init chain, reference/lookup data left unseeded for now).

## 6. Filesystem paths and writable directories

Representative hardcoded-path hits in first-party code (excludes vendored `snep/lib/Zend`,
`snep/lib/linfo`); the bulk of raw `/var/www/html/snep` string matches across the tree (682
total) are gettext `.po`/`.mo` source-reference comments, not real path assumptions — the
structurally meaningful hits are:

- `snep/includes/setup.conf:12-13,42` — `path_voz`, `path_voz_bkp`, `path.base`.
- `snep/install/snep.apache2:2-3` — Apache `Alias`/`Directory`.
- `snep/install/etc/asterisk/voicemail.conf:67` —
  `externnotify=/var/www/html/snep/agi/voicemail-notify.php` (Asterisk calls back into the app
  by absolute path when a voicemail arrives).
- `snep/modules/default/controllers/DocsController.php:66` —
  `file_get_contents('/var/www/html/snep/docs/'. ...)` (in-app docs viewer reads from a hardcoded
  absolute path, independent of `path.base`).
- `snep/scripts/backup/backup.sh:64` — `dir_snep=/var/www/html/snep` (third-party community
  backup script, hardcoded).
- `snep/install/database/update/betha/convert-data-rc3.php` — path reference inside the one-off
  betha migration script.

**Directories the app expects to write to** (from `snep/inspectors/Permissions.php:56-58`, the
app's own self-check, plus corroborating code):
- `includes/setup.conf` itself (config UI rewrites it — `ParametersController.php:239-240`).
- `sounds/moh` and `sounds/<lang>` relative to `path.base`.
- `path_voz` / `path_voz_bkp` (call recordings, read+write — `snep/lib/Snep/Manutencao.php:108,181,183`).
- `path.log` (`/var/log/snep/`, referenced by `snep/inspectors/Logs.php:63` and
  `snep/modules/default/api/index.php:18`).
- `/tmp` — used directly for transient files: recording temp files
  (`snep/lib/PBX/Rule.php:152`), ad-hoc log dumps (`snep/lib/Snep/Log.php:79`), and per-upload
  `tmp`/`backup` subdirectories under the sound-file directories
  (`snep/lib/Snep/SoundFiles/Manager.php:170-172`, `snep/modules/default/controllers/SoundFilesController.php`,
  `MusicOnHoldController.php:308-318`).
- `AST_SPOOL_DIR . '/tmp/'` (`snep/lib/Asterisk/AGI.php:26`) — Asterisk's own spool tmp dir,
  written to by the AGI PHP-CLI runtime, not the web runtime.
- `snep/inspectors/Sounds.php:81-82` — beyond requiring each sound directory itself, the inspector
  fails unless a `backup/` and a `tmp/` subfolder already exist under it.
- `snep/lib/Snep/InterfaceConf.php:47,50,53` — checks `is_writable()` on the extension/trunk/hint
  Asterisk config files before writing to them (these resolve to paths under `/etc/asterisk`,
  see §9's symlink-farm note), i.e. another first-party code path that assumes local filesystem
  write access into Asterisk's own config tree, not just AMI.
- `snep/lib/PBX/Relatorio/Chamadas.php:108` and
  `snep/modules/default/controllers/ConferenceRoomsController.php:102` — runtime writability
  checks on report/conference config files, same pattern as above.

**Docker bootstrap implication**: `path.base`/`path_voz`/`path.log` all need to resolve inside
the container at whatever DocumentRoot is chosen (currently `/var/www/html/mag`, not
`/var/www/html/snep`) and be writable by the web server user — this is a `setup.conf` templating
problem, not a code change.

## 7. Cron/background processes

- **No cron job is shipped/installed automatically anywhere in the repo.** The only cron
  reference is a suggestion printed by `snep/scripts/backup/backup.sh` (`-r` flag,
  around line 120): it tells the operator to manually add
  `00 23 * * * /var/www/html/snep/scripts/backup-snep/<script> -bkp` to root's crontab. This is
  third-party community tooling (author credited in the script header), not part of core SNEP.
- No `pcntl_fork`, `proc_open`, `nohup`, or explicit backgrounding (`&` at end of a shelled-out
  command) was found in first-party code.
- The closest thing to a background/long-running process is the **AGI runtime**
  (`snep/agi/Bootstrap-script.php`), which Asterisk spawns per-call over stdin/stdout (not cron,
  not a daemon the app manages itself) — see §8.

## 8. Shell/sudo calls

No `sudo` invocation exists anywhere in `snep/` (app or scripts) — all install-time root actions
in `INSTALL_GUIDE.md` are written assuming the operator is already root, not via `sudo` escalation
from within a script. Runtime `exec()`/`shell_exec()`/`popen()` call sites in first-party code
(excludes vendored Zend/linfo):

| File:line | Command | Notes |
|---|---|---|
| `snep/lib/Asterisk/AGI.php:1246` | `{festival text2wave} -F ... -o $fname.wav $fname.txt` | Optional TTS feature; requires `festival` binary in the image only if used. |
| `snep/lib/Asterisk/AGI.php:1300` | `{cepstral swift} -p ... -o $fname.wav -f $fname.txt` | Optional TTS (Cepstral, commercial); same caveat. |
| `snep/lib/Snep/Log.php:83` | dynamic `$cmd` | Log-export helper. |
| `snep/lib/Snep/SoundFiles/Manager.php:170-172,398` | `mkdir {dir}`, `mkdir {dir}/tmp`, `mkdir {dir}/backup`, `rm -rf {dir}` | Shells out for directory management instead of using PHP's `mkdir()`/`rmdir()` — **`rm -rf` built from a config-derived path string**, worth a closer look before Phase 2 (not a Phase 1 concern; not modifying). |
| `snep/lib/Snep/Locale.php:222-230` (`setExtensionsLanguage()`) | `sed` + `chown --reference` + `chmod --reference` + `mv` directly against `/etc/asterisk/extensions.conf`, followed by an AMI `dialplan reload` (via `PBX_Asterisk_AMI`, §9) | Edits Asterisk's dialplan file on local disk, then asks Asterisk (over AMI) to reload it — combines filesystem coupling and AMI coupling in one call. |
| `snep/modules/default/controllers/SoundFilesController.php:141,145,228,233,236,288,317` | `sox ...`, `cp ...`, `rm -f ...`, `mv ...` | Sound upload pipeline; **requires `sox` in the container image** (not currently installed by `docker/app.Dockerfile`). |
| `snep/modules/default/controllers/MusicOnHoldController.php:311,315,318,395,397` | `mv`, `sox`, `rm` | Same — MOH upload pipeline, also needs `sox`. |
| `snep/modules/default/controllers/SystemstatusController.php:85,89,94,97,102,157,158` | `mysql -V`, `cat /etc/slackware-version`, `cat /etc/redhat-release`, `cat /etc/issue`, `uname -sr`, `cat /proc/cpuinfo` | Read-only system-status page; the Slackware/RedHat checks show the app was written to be distro-agnostic at the UI layer even though install docs assume Debian only. |
| `snep/modules/default/controllers/SystemstatusController.php:286` | `popen("$cur_path/$program $params", 'r')` | Runs an arbitrary configured program — path/params come from app config, not request input, but worth flagging as a `popen` sink. |
| `snep/modules/default/controllers/ConferenceRoomsController.php:54,62,70` | `cat /etc/asterisk/snep/snep-authconferences.conf \| grep ...`, similar for `snep-conferences.conf` | **Confirms the web app reads Asterisk config files directly off the local filesystem** — app and Asterisk are assumed co-located on the same host/filesystem, not networked. Relevant to the eventual Asterisk-container decision (ADR-0001 notes Asterisk is deliberately excluded from the first topology). |
| `snep/modules/default/controllers/CnlController.php:88` | `unzip {$_fileName} -d /tmp` | **Requires `unzip`** in the container image (not currently installed). |
| `snep/agi/padlock.php:35` and others | `$asterisk->exec(...)` | Not a shell call — this is the AGI protocol's `EXEC` command sent to Asterisk over the AGI channel, unrelated to PHP's `exec()`. Included here only to flag the naming collision found during grep. |

**Docker bootstrap implication**: `sox` and `unzip` are used by real upload/conversion
controllers and are not currently installed by `docker/app.Dockerfile:6-9` (which installs
`bash ca-certificates curl git libicu-dev libzip-dev mariadb-client unzip` — **`unzip` is already
present**, but `sox` is not). Recommend adding `sox` when those features need to work; `festival`/
`swift` only if TTS is required.

## 9. Asterisk dependencies

- **Two separate integration surfaces**:
  1. **AMI** (Asterisk Manager Interface, TCP) — **three** AMI-related classes exist, not two:
     - `snep/includes/AMI.php` (community class, header at lines 1-30 states: *"This class is
       only tested on asterisk 1.6.x and 1.8.x, but will most likely work on most asterisk
       versions below asterisk 13"* — direct, explicit evidence that this integration was never
       validated against Asterisk 13+, let alone the target Asterisk 22 LTS). Usage is narrow:
       only `snep/includes/ip_status_queues.php` references it.
     - `snep/lib/Asterisk/AMI.php` defines the base `Asterisk_AMI` class (a fork of the
       `phpagi-asmanager` library).
     - `snep/lib/PBX/Asterisk/AMI.php:30` defines `PBX_Asterisk_AMI extends Asterisk_AMI`, a
       singleton (`::getInstance()`), and **this is the AMI implementation actually used
       throughout first-party code** — `AsteriskInfo.php`, `PBX/Interfaces.php`,
       `PBX/Khomp/Info.php`, `Snep/InterfaceConf.php`, `Snep/Locale.php`,
       `SystemstatusController.php`, `ConferenceRoomsController.php`, `CallbackAction.php` all
       call it. Host/credentials come from `setup.conf:7-9` (`ip_sock`/`user_sock`/`pass_sock`,
       currently `127.0.0.1`/`snep`/`sneppass` — will need to resolve to an Asterisk service
       address once one exists).
     - AMI is invoked for specific live actions (e.g. `dialplan reload`, peer status), not as a
       startup gate — `snep/Bootstrap.php` does not check AMI connectivity before the web app
       boots. Only AMI-backed features degrade/error without Asterisk reachable; the web UI
       itself is expected to boot regardless, consistent with ADR-0001 excluding Asterisk from
       the first Docker topology.
  2. **AGI** (Asterisk Gateway Interface, spawned per-call via stdin/stdout) —
     `snep/lib/Asterisk/AGI.php` plus the per-feature scripts in `snep/agi/*.php`
     (`agenda.php`, `dnd.php`, `followme.php`, `padlock.php`, `peer_services.php`, etc.),
     entered through `snep/agi/Bootstrap-script.php`.
- **Filesystem coupling via symlinks (legacy install)** —
  `snep/docs/INSTALL_GUIDE.md:178-185,225-226` documents a symlink farm binding the app and
  Asterisk to the same filesystem: `/etc/apache2/sites-enabled/001-snep` →
  `/var/www/html/snep/install/snep.apache2`; `/var/spool/asterisk/monitor` →
  `/var/www/html/snep/arquivos` (**Asterisk's call-recording spool is symlinked directly into the
  app's own webroot** — recordings Asterisk writes and recordings the PHP app serves are the same
  files); and `/var/lib/asterisk/moh` / `/var/lib/asterisk/sounds/pt_BR` symlinked in similarly.
  This is the clearest evidence in the repo that a future Asterisk container will need a shared
  volume with the app for `arquivos/` (recordings) and the sounds/MOH trees, not just AMI/AGI
  network reachability. Out of scope for Phase 1 (no Asterisk container yet); recorded for
  Phase 3/4.
- Sample Asterisk configs are vendored under `snep/install/etc/asterisk/` (39 files) including
  `chan_dahdi.conf`, `khomp.conf` (proprietary Khomp hardware boards), `h323.conf`, `res_odbc.conf`,
  `cdr_odbc.conf`, `cel_odbc.conf` — these describe an Asterisk 13-era feature set and are not
  validated against Asterisk 22's config schema.
- `snep/install/etc/asterisk/extconfig.conf:33-37` wires `queue_log`, `queues`, `queue_members`,
  and `voicemail` to load from MySQL via ODBC realtime (uncommented); `iaxusers`/`iaxpeers`/
  `sipusers`/`sippeers`/`meetme` realtime lines are present but **commented out by default**
  (lines 29-32) — i.e., realtime SIP peer storage is supported but not the default; static
  `sip.conf`-style peers are the default path (see §10).
- `snep/install/etc/asterisk/voicemail.conf:67` sets `externnotify` to call back into the PHP app
  by absolute path (`/var/www/html/snep/agi/voicemail-notify.php`) — Asterisk invokes PHP
  directly as a CLI subprocess on voicemail events.
- The app reads Asterisk's own config files directly off disk at runtime (see §8,
  `ConferenceRoomsController.php`), reinforcing that app and Asterisk are assumed to share a
  filesystem, not just a network (AMI) or process (AGI) boundary.

**Phase 3 implication**: the explicit "below asterisk 13" compatibility ceiling in
`AMI.php`'s own docblock is the single clearest piece of evidence in the repo that AMI/AGI
behavior needs re-validation before Asterisk 22 is introduced — record this, do not act on it
during Phase 1.

## 10. chan_sip dependencies

- `snep/scripts/migra_peers.sh` (lines ~30-45) **generates classic `chan_sip`-syntax peer
  stanzas** directly: `type=friend`, `host=dynamic`, `nat=force_rport`, `dtmfmode=rfc2833`,
  `disallow=all` / `allow=ulaw` / `allow=alaw` — this is `chan_sip` config syntax, not PJSIP
  (which uses `endpoint`/`aor`/`auth` sections with different key names). This script migrates
  DB-stored peers (`select name,secret from peers`) into static `sip.conf` stanzas.
- `snep/scripts/disable_realtime.sh` exists specifically to toggle **realtime SIP/IAX peers**
  off in `extconfig.conf` (`sed -i 's/^sippeers/;sippeers/g' ...`) — confirms both realtime-SIP
  and static-`sip.conf` deployment modes have existed for this app historically.
- `snep/includes/AMI.php:194-216` — `get_sippeer()` calls AMI action `"Peer" => $sippeers_name`,
  i.e., queries Asterisk for `chan_sip`-style peer status via AMI, not PJSIP's `PJSIPShowEndpoint`
  action family.
- No PJSIP-specific config (`pjsip.conf`, `pjsip_wizard.conf`) or PJSIP AMI actions were found
  anywhere in the repo — this is a `chan_sip`-only codebase today, consistent with CLAUDE.md
  Phase 4 being a separate, not-yet-started milestone.
- The `chan_sip` assumption is not confined to install scripts — it's baked into the controller
  layer's data model: `snep/modules/default/controllers/TrunksController.php:526` hardcodes
  `array("sip", "iax2", "snepsip", "snepiax2")` as the set of trunk technologies;
  `snep/modules/default/controllers/ExtensionsController.php:569,587,681` gate provisioning
  branches on `$techType == 'sip' || $techType == 'iax2'`, and `:1034,1063` write peer data under
  a literal `$data["sip"]` key. There is no technology-abstraction layer to extend — Phase 4 will
  need new branches/templates alongside the existing `sip`/`iax2` ones, not a drop-in adapter.

## 11. Absolute `/var/www/html/snep` references

Total raw string matches across `snep/`: **682**. After excluding gettext `.po`/`.mo` files
(which embed source-reference comments like `#: /var/www/html/snep/...:123` as a side effect of
how the translation catalogs were built, not real path logic), the count of files with a genuine
runtime/install-time dependency on the literal path is **11**:

1. `snep/includes/setup.conf` — `path.base`, `path_voz`, `path_voz_bkp` (config, see §4/§6).
2. `snep/install/snep.apache2` — Apache `Alias`/`Directory` (see §3).
3. `snep/install/etc/asterisk/voicemail.conf` — `externnotify` callback path (see §9).
4. `snep/modules/default/controllers/DocsController.php:66` — hardcoded docs-viewer path,
   independent of `path.base` (a real bug relative to the rest of the app's config-driven paths).
5. `snep/scripts/backup/backup.sh` — `dir_snep=/var/www/html/snep` (third-party script).
6. `snep/install/database/update/betha/convert-data-rc3.php` — one-off migration script.
7-11. `snep/docs/INSTALL_GUIDE.md`, `snep/docs/REALTIME_DISABLE.md`, `snep/docs/TRANSLATION.md`,
   `snep/modules/billing/README.md`, `snep/modules/ivr/README.md` — documentation only, no
   runtime effect.

Of these, **items 1-4 are the ones that actually need to change (or be made
configurable/templated) for the app to run correctly at a different DocumentRoot** such as the
current scaffold's `/var/www/html/mag`. Item 4 in particular bypasses the app's own
`path.base` config entirely and would silently serve stale/missing docs at a different mount
point — worth flagging as a real (pre-existing) bug rather than a Docker-migration artifact.

## 12. Debian-specific assumptions

- `INSTALL_GUIDE.md:57` states the install is "baseado em Linux Debian, versão 8 (Jessie)" and
  explicitly warns that other distros/versions require manual adjustment of the Apache directory
  layout and user/group.
- Package management throughout the install doc is `apt-get` (`INSTALL_GUIDE.md:63,69,75`, and
  `TRANSLATION.md:13`, `REGISTER_ERROR.md:24`) — no distro-neutral package abstraction.
- Service management uses SysV-style `/etc/init.d/` + `update-rc.d` (`INSTALL_GUIDE.md:83,128-130`)
  rather than systemd — consistent with a Jessie-era (pre-systemd-default) target, though Jessie
  itself shipped systemd by default; the doc predates that transition or targets an
  init-script-compatible setup either way.
- `www-data` (Debian/Ubuntu's default Apache user) is hardcoded in
  `snep/scripts/copia_audio.sh:21` (`chown -R www-data.www-data ...`) — would need adjustment on
  a distro using a different default user (e.g. `apache` on RHEL-family).
- Ironically, `snep/modules/default/controllers/SystemstatusController.php:89-97` (§8) contains
  live checks for Slackware and RedHat release files alongside Debian, suggesting some intent for
  cross-distro support at the UI level that was never carried through to the install
  documentation or scripts.

---

## Summary for Docker bootstrap (Phase 1) scope

Findings that materially affect the current Docker scaffold, in priority order:

1. **`setup.conf` must be generated/templated from `.env` at container entrypoint** — it is the
   single source of DB credentials, `path.base`, and Asterisk paths, has no env-var alternative,
   and must remain writable by the web server user (§4, §6).
2. **DocumentRoot mismatch**: scaffold uses `/var/www/html/mag`; legacy code/config assumes
   `/var/www/html/snep` in `setup.conf`, `snep.apache2`, `voicemail.conf`, and
   `DocsController.php` (§11). Options: mount at `/var/www/html/snep` to avoid touching legacy
   assumptions (matches CLAUDE.md's "preserve behavior before modernizing"), or template all four
   locations — recommend the former for Phase 1.
3. **Missing container packages**: `sox` (sound upload/conversion features, §6/§8) is not
   installed by `docker/app.Dockerfile`; `unzip` already is.
4. **`snep/includes/.htaccess` must be preserved, and needs `mod_access_compat`** — it's the
   only barrier keeping `setup.conf` credentials from being served as a static file over HTTP,
   but its `Order`/`Deny` syntax is not honored by Apache 2.4+ unless `mod_access_compat` is
   enabled, which `docker/app.Dockerfile` does not currently do (§3).
5. **`modules/loguser/` referenced by the documented install order does not exist in this repo**
   (§4/§5) — needs a decision before an automated import script can faithfully reproduce
   `INSTALL_GUIDE.md`'s procedure.
6. **`each()` in `TdmLinksController.php` and Khomp/TDM error controllers will fatal under PHP
   8.4** (§1) if those code paths are exercised — out of scope to fix under Phase 1, but should
   be tracked explicitly rather than discovered by a developer hitting a 500 error.
7. **`database.sql`'s `CREATE DATABASE`/`GRANT ... TO 'snep'@'localhost'` statements should not
   be used verbatim for container DB initialization** — they duplicate and partially conflict
   with the official `mariadb` image's own `MARIADB_DATABASE`/`MARIADB_USER`/`MARIADB_PASSWORD`
   provisioning already relied on in `compose.yaml`, and the `localhost`-only grant would refuse
   connections from the `app` container in any case. Only `schema.sql`/`system_data.sql`/
   `core-cnl.sql` (structure/data) are needed for the deterministic DB init this milestone
   requires (§4/§5).

Findings that are explicitly **out of scope for Phase 1** and recorded here only for later
phases: the AMI compatibility ceiling below Asterisk 13 (§9, → Phase 3), the `chan_sip`-only
realtime/static peer model (§10, → Phase 4), and the PHP 8 removed-syntax inventory beyond the
one confirmed blocker above (§1, → Phase 2).
