.PHONY: dev up down restart logs ps shell db-shell asterisk-cli test smoke call-smoke trunk-smoke transport-smoke lint doctor reset config

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

call-smoke: up
	@set -a; . ./.env; set +a; bash scripts/call-smoke-test.sh

trunk-smoke: up
	@set -a; . ./.env; set +a; bash scripts/trunk-smoke-test.sh

transport-smoke: up
	@set -a; . ./.env; set +a; bash scripts/transport-smoke-test.sh

lint:
	@echo "No lint pipeline is wired yet."
	@echo "Add PHP/static analysis tooling during the PHP modernization phase."

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
