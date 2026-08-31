.PHONY: dev up down restart logs ps shell db-shell asterisk-cli test smoke authorization-coverage authorization-smoke preauth-security-smoke call-smoke trunk-smoke transport-smoke restart-smoke external-failure-smoke external-content-smoke lint regression doctor reset config

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

transport-smoke: up
	@set -a; . ./.env; set +a; bash scripts/transport-smoke-test.sh

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
