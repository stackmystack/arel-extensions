COMPOSE_FILE := dev/compose.yaml
DC := docker compose -f $(COMPOSE_FILE)

.PHONY: down rebuild shell stop up

# Stop AND remove containers (clean slate)
down:
	$(DC) down

rebuild:
	$(DC) build --no-cache

# Jump into the container
shell: up
	$(DC) exec arelx bash

# Stop containers without removing them (preserves state)
stop:
	$(DC) stop

# Boot everything and keep it running (daemon mode)
up:
	$(DC) up -d
