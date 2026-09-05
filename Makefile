.PHONY: dev up down restart logs ps shell db-shell asterisk-cli test smoke authorization-coverage harness-lib-selftest authorization-smoke preauth-security-smoke sql-security-smoke residual-sql-security-smoke shell-security-smoke pjsip-config-security-smoke api-security-smoke api-sql-security-smoke session-csrf-security-smoke auth-hardening-security-smoke disclosure-path-security-smoke legacy-maintenance-exposure-security-smoke cdr-window-selftest call-smoke trunk-smoke pjsip-external-trunk-smoke pjsip-lifecycle-smoke wss-platform-smoke tls-cert-management-smoke pjsip-runtime-status-smoke transport-smoke dialplan-legacy-closure-smoke restart-smoke external-failure-smoke external-content-smoke lint regression doctor reset config

COMPOSE ?= docker compose

dev: doctor up

config:
	$(COMPOSE) config

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app bash

db-shell:
	$(COMPOSE) exec db mariadb -u"$${DB_USER}" -p"$${DB_PASSWORD}" "$${DB_NAME}"

asterisk-cli:
	$(COMPOSE) exec asterisk asterisk -rvvv

test:
	@echo "No automated test suite is wired yet."
	@echo "Add project tests before changing this target to report success."

smoke: up
	@set -a; . ./.env; set +a; bash scripts/smoke-test.sh

# TASK-0026A: static inventory -- every controller/action must be
# resource-registered, a reviewed authenticated-open controller, or a
# resource alias, so no new controller/action can silently fall through
# to an implicit allow. Pure static check, no Docker dependency.
authorization-coverage:
	@bash scripts/authorization-coverage-check.sh

# TASK-0027A: proves scripts/lib/harness.sh's own PASS/FAIL/BLOCKED/
# INCONCLUSIVE state machine and summary printing work on this
# project's actual bash 3.2 host shell, including the empty-row
# "unbound variable" edge case found live and fixed by this task, and
# the bounded container-readiness retry added alongside it. Pure
# self-contained check (fakes $COMPOSE), no Docker dependency.
harness-lib-selftest:
	@bash scripts/harness-lib-selftest.sh

# TASK-0026A: verifies the default-deny authorization boundary using an
# isolated local-dev account.  It performs only harmless GETs and uses the
# existing Users > Permission form for the grant/revoke lifecycle.
authorization-smoke: up
	@set -a; . ./.env; set +a; bash scripts/authorization-smoke-test.sh

preauth-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/preauth-security-smoke-test.sh

# TASK-0026C: proves the F7-F11 SQL-injection boundaries (Extensions,
# Users/Profiles, Trunks, CSV import, Data Export) hold -- SQL-shaped
# values behave as inert literal data through the real, authenticated
# application flows, never a direct database connection. Deliberately
# separate from `make smoke` -- never run implicitly by it.
sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/sql-security-smoke-test.sh

# TASK-0026J: proves the two residual SQL-injection sinks found by
# TASK-0026Z's own closure static sweep -- Snep_InterfaceConf's legacy
# chan_sip/iax2 trunk lookup and CallsReportController's report-filter
# SQL construction -- are closed. Deliberately separate from `make
# smoke` -- never run implicitly by it.
residual-sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/residual-sql-security-smoke-test.sh

# TASK-0026D: proves the F2-F5 shell/command-injection boundaries
# (Sound Files, Music on Hold, System Logs, CNL Update) hold --
# shell-shaped values behave as inert data (or are rejected outright by
# a filename/directory allowlist) through the real, authenticated
# application flows, never a direct shell/exec() call. Deliberately
# separate from `make smoke` -- never run implicitly by it.
shell-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/shell-security-smoke-test.sh

# TASK-0026E: proves the F12-F15 PJSIP/Asterisk configuration-injection
# boundaries (Extensions, Trunks, PJSIP Transports, legacy chan_sip) hold
# -- newline/section/directive-shaped values are rejected before
# persistence, or (F14, already covered by pre-existing TASK-0019/0020
# validation) never accepted in the first place, through the real,
# authenticated application flows. Deliberately separate from
# `make smoke` -- never run implicitly by it.
pjsip-config-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-config-security-smoke-test.sh

# TASK-0026F: proves the F17 standalone-API authentication/service-
# resolution boundaries (snep/modules/default/api/index.php) hold --
# both Basic-auth parsing branches apply the same password
# normalization (no pass-the-hash), and $_GET['service'] only ever
# selects a key into a finite, trusted registry (no path built from
# request data). Deliberately separate from `make smoke` -- never run
# implicitly by it.
api-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/api-security-smoke-test.sh

# TASK-0026F1: proves the SQL-injection boundaries discovered during
# TASK-0026F's own reconnaissance (ContactsService, CSV_ExportDataService,
# CallsReportService, RankingReportService, ServicesReportService) hold --
# SQL-shaped values behave as inert literal data through the real,
# authenticated standalone API dispatcher, never a direct database
# connection. Deliberately separate from `make smoke` -- never run
# implicitly by it.
api-sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/api-sql-security-smoke-test.sh

# TASK-0026G: proves the F18-F20 session-fixation/cookie/CSRF boundaries
# hold -- the session id changes on login and the pre-login id cannot
# access an authenticated page afterward, logout invalidates the session,
# the session cookie carries HttpOnly/SameSite/Secure-when-HTTPS, and
# authenticated state-changing POSTs are rejected without a valid
# session-bound CSRF token (missing, invalid, or from a foreign session)
# while GETs and the standalone Basic-auth API remain unaffected.
# Deliberately separate from `make smoke` -- never run implicitly by it.
session-csrf-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/session-csrf-security-smoke-test.sh

# TASK-0026H: proves the F21-F24/F27 authentication-hardening boundaries
# hold -- modern password_hash() storage on every write path, legacy MD5
# accounts migrate transparently on successful login, a stored hash can
# never itself authenticate (pass-the-hash), the standalone API uses the
# same password semantics as browser login, failed logins are rate-
# limited (per-account+source and per-source, both auto-expiring), wrong
# password and unknown user are indistinguishable, and a fresh install no
# longer ships an operational admin/admin123 credential. Deliberately
# separate from `make smoke` -- never run implicitly by it.
auth-hardening-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/auth-hardening-security-smoke-test.sh

# TASK-0026I: exercises the F25/F26/F28 information-disclosure and
# contained-path-traversal findings -- error.phtml's now-gated exception
# message, expose_php/raw-SQL-in-JSON disclosure, and DocsController's
# allowlist-based path containment (including a symlink-escape proof).
# Deliberately separate from `make smoke` -- never run implicitly by it.
disclosure-path-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/disclosure-path-security-smoke-test.sh

# TASK-0026S: proves snep/install/ (one-time installer/schema-migration
# assets, including the DB-mutating convert-data-rc3.php/updateCallerid.php
# scripts) cannot be invoked over HTTP -- GET/POST both blocked at the
# web-server layer (snep/install/.htaccess), the whole subtree equally
# contained (not just the one known script), no schema/data mutation, no
# source/path/SQL-error disclosure in the blocked response, the ordinary
# application still works, and filesystem/CLI availability (Docker
# bind-mount, php -l) is preserved. Deliberately separate from `make
# smoke` -- never run implicitly by it.
legacy-maintenance-exposure-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/legacy-maintenance-exposure-security-smoke-test.sh

# TASK-0027A: deterministic, fixed-timestamp proof of
# harness_cdr_report_window() (lib/harness.sh) -- the timezone-safe CDR
# report-window logic call-smoke/trunk-smoke depend on. Never reads the
# wall clock, so it exercises the local-midnight/UTC-divergence boundary
# on demand instead of only when the real clock happens to cross it.
cdr-window-selftest: up
	@set -a; . ./.env; set +a; bash scripts/cdr-window-selftest.sh

call-smoke: up
	@set -a; . ./.env; set +a; bash scripts/call-smoke-test.sh

trunk-smoke: up
	@set -a; . ./.env; set +a; bash scripts/trunk-smoke-test.sh

# TASK-0028X: proves pjsip_external outbound dial-string generation --
# PBX_Trunks::get() now dispatches PJSIP_EXTERNAL trunks to
# PBX_Asterisk_Interface_PJSIP (same as native "pjsip"), producing
# "PJSIP/<destination>@<endpoint>" instead of the previously-generated,
# structurally-wrong "PJSIP/<endpoint>/<destination>". See
# docs/tasks/0028x-pjsip-external-dialstring-fix.md. Deliberately
# separate from trunk-smoke -- a different trunk technology/fixture.
pjsip-external-trunk-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-external-trunk-smoke-test.sh

transport-smoke: up
	@set -a; . ./.env; set +a; bash scripts/transport-smoke-test.sh

# TASK-0028Y: registrationless PJSIP trunk (reverse_auth=0), qualify
# "specify"/NAT auto_* runtime proof, trunk update (reverse_auth),
# extension update beyond transport_id, and full delete-cleanup proof
# (generated config + live Asterisk + DB, not just HTTP 302) for both
# trunk and extension. See
# docs/tasks/0028y-pjsip-parameter-regression-closure.md. Deliberately
# separate from trunk-smoke/call-smoke -- a different fixture profile
# (no live call, no baresip/provider dependency).
pjsip-lifecycle-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-lifecycle-smoke-test.sh

# TASK-0028Z: Asterisk built-in HTTP server + WSS platform enablement --
# proves http.conf/TLS-cert persistence, a real TLS+WebSocket handshake
# at /ws, a real SIP REGISTER over that WebSocket, and restart/recreate
# convergence. Restarts/recreates the asterisk container itself
# (deliberately, Phase 9 of the task) -- run in isolation from other
# stateful suites, same as every other suite in this list.
wss-platform-smoke: up
	@set -a; . ./.env; set +a; bash scripts/wss-platform-smoke-test.sh

# TASK-0029A: TLS/WSS transport certificate management -- validation,
# generated-config correctness, live TLS handshake/fingerprint proof,
# rotation, mismatched cert/key runtime-apply failure behavior, and
# restart persistence. Restarts the asterisk container (same "run in
# isolation" reasoning as wss-platform-smoke above).
tls-cert-management-smoke: up
	@set -a; . ./.env; set +a; bash scripts/tls-cert-management-smoke-test.sh

# TASK-0029B: PJSIP runtime status visibility -- extension/trunk
# CONFIGURED-vs-LIVE status, real reachable/unreachable/rejected proof,
# pjsip_external existence proof, and the AMI-down-never-fabricates-
# Offline contract. Stops/restarts the asterisk container (Part C) --
# same "run in isolation" reasoning as the other restart-using suites.
pjsip-runtime-status-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-runtime-status-smoke-test.sh

# TASK-0028C: proves the reachable SIP/IAX-era dialplan/config constructs
# closed by that task stay closed (context bleed, SIPAddHeader, callback
# .call generation) -- see docs/tasks/0028c-pjsip-legacy-runtime-closure.md.
dialplan-legacy-closure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/dialplan-legacy-closure-smoke-test.sh

# TASK-0021: restarts the dev Asterisk container multiple times, including
# while a real call is active. Deliberately separate from `make smoke` --
# never run implicitly by it.
restart-smoke: up
	@set -a; . ./.env; set +a; bash scripts/restart-smoke-test.sh

# TASK-0024: deterministically simulates vendor-API failure (DNS,
# refused, blackhole, TLS, HTTP 500, malformed/empty payload) using only
# controlled local/reserved targets -- never the real vendor. Deliberately
# separate from `make smoke` -- never run implicitly by it.
external-failure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/external-failure-smoke-test.sh

# TASK-0025: proves vendor-controlled content (notifications, version
# check, changelog, announce) cannot inject active HTML/JavaScript into
# rendered SENMA pages. Uses only controlled local fixtures, never the
# real vendor. Deliberately separate from `make external-failure-smoke`
# (that suite tests availability, this one tests content) -- never run
# implicitly by `make smoke`.
external-content-smoke: up
	@set -a; . ./.env; set +a; bash scripts/external-content-smoke-test.sh

# TASK-0027: php -l across snep/ (inside the app container), bash -n
# across scripts/, XML well-formedness for resources.xml, and
# git diff --check. Lightweight, reproducible, no external framework.
lint: up
	@set -a; . ./.env; set +a; bash scripts/lint.sh

# TASK-0027: the one canonical release-regression gate -- runs the full
# supported suite serially, in a fixed dependency-respecting order, and
# never treats BLOCKED/INCONCLUSIVE as PASS. See
# docs/tasks/0027-regression-harness-reliability.md.
regression: up
	@set -a; . ./.env; set +a; bash scripts/regression.sh

doctor:
	@command -v docker >/dev/null || (echo "docker is required" && exit 1)
	@docker compose version >/dev/null || (echo "Docker Compose v2 is required" && exit 1)
	@test -f .env || (echo ".env missing: run 'cp .env.example .env'" && exit 1)
	@$(COMPOSE) config >/dev/null
	@echo "MAG development prerequisites look OK."
	@if $(COMPOSE) ps asterisk 2>/dev/null | grep -q asterisk; then \
		if $(COMPOSE) exec -T asterisk asterisk -rx "core show version" >/dev/null 2>&1; then \
			echo "asterisk: CLI responsive."; \
		else \
			echo "asterisk: container is up but CLI is not responding yet."; \
		fi; \
	fi

reset:
	@echo "WARNING: this removes MAG development containers and volumes."
	@printf "Type RESET to continue: "; read answer; test "$$answer" = "RESET"
	$(COMPOSE) down -v --remove-orphans
