# Quack DuckLake Makefile
# A simple interface for building and running the DuckLake local deployment

# Docker Compose command (use modern docker compose instead of docker-compose)
DOCKER_COMPOSE := docker compose

# Default target
.PHONY: help
help: ## Show this help message
	@echo "Quack DuckLake - Local Deployment Commands"
	@echo "=========================================="
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Build targets
.PHONY: build
build: ## Build all Docker images
	@echo "Building DuckLake Docker images..."
	$(DOCKER_COMPOSE) build --no-cache --progress=plain

.PHONY: build-quick
build-quick: ## Build Docker images using cache
	@echo "Building DuckLake Docker images (with cache)..."
	$(DOCKER_COMPOSE) build

# Runtime targets
.PHONY: up
up: ## Start the DuckLake stack in detached mode
	@echo "Starting DuckLake stack..."
	$(DOCKER_COMPOSE) up -d
	@echo "Waiting for services to be ready..."
	@sleep 10
	@echo "DuckLake is ready! Connect with: make shell"

.PHONY: up-logs
up-logs: ## Start the DuckLake stack with logs visible
	@echo "Starting DuckLake stack with logs..."
	$(DOCKER_COMPOSE) up

.PHONY: down
down: ## Stop and remove all containers
	@echo "Stopping DuckLake stack..."
	$(DOCKER_COMPOSE) down

.PHONY: restart
restart: down up ## Restart the entire stack

# Connection and interaction targets
.PHONY: shell
shell: ## Open DuckDB shell in the ducklake-init container
	@echo "Connecting to DuckDB shell..."
	@echo "DuckLake is automatically attached as 'the_ducklake'"
	@echo "Try: SELECT * FROM information_schema.schemata;"
	$(DOCKER_COMPOSE) exec ducklake-init duckdb

.PHONY: psql
psql: ## Connect to PostgreSQL catalog database
	@echo "Connecting to PostgreSQL catalog..."
	$(DOCKER_COMPOSE) exec postgres psql -U ducklake -d ducklake_catalog

.PHONY: minio-console
minio-console: ## Open MinIO console in browser
	@echo "Opening MinIO console..."
	@echo "URL: http://localhost:9000"
	@echo "Username: minioadmin"
	@echo "Password: minioadmin"
	@open http://localhost:9000 2>/dev/null || echo "Open http://localhost:9000 in your browser"

# Status and debugging targets
.PHONY: status
status: ## Show status of all services
	@echo "DuckLake Service Status:"
	@echo "======================="
	$(DOCKER_COMPOSE) ps

.PHONY: logs
logs: ## Show logs from all services
	$(DOCKER_COMPOSE) logs

.PHONY: logs-init
logs-init: ## Show logs from ducklake-init service
	$(DOCKER_COMPOSE) logs ducklake-init

.PHONY: logs-postgres
logs-postgres: ## Show logs from PostgreSQL service
	$(DOCKER_COMPOSE) logs postgres

.PHONY: logs-minio
logs-minio: ## Show logs from MinIO service
	$(DOCKER_COMPOSE) logs minio

.PHONY: health
health: ## Check health of all services
	@echo "Checking service health..."
	@echo "========================="
	@echo -n "PostgreSQL: "
	@$(DOCKER_COMPOSE) exec postgres pg_isready -U ducklake >/dev/null 2>&1 && echo "✓ Healthy" || echo "✗ Unhealthy"
	@echo -n "MinIO: "
	@$(DOCKER_COMPOSE) exec minio curl -I http://localhost:9000/minio/health/live >/dev/null 2>&1 && echo "✓ Healthy" || echo "✗ Unhealthy"
	@echo -n "DuckLake Init: "
	@$(DOCKER_COMPOSE) ps ducklake-init | grep -q "Up" && echo "✓ Running" || echo "✗ Not Running"

# Data management targets
.PHONY: clean-data
clean-data: ## Remove all persistent data (WARNING: destructive!)
	@echo "WARNING: This will delete all data in PostgreSQL and MinIO!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Stopping services..."; \
		$(DOCKER_COMPOSE) down; \
		echo "Removing data directories..."; \
		rm -rf data/pgdata/* data/minio/*; \
		echo "Data cleaned!"; \
	else \
		echo "Cancelled."; \
	fi

.PHONY: backup-data
backup-data: ## Create a backup of all data
	@echo "Creating backup of DuckLake data..."
	@timestamp=$$(date +%Y%m%d_%H%M%S); \
	backup_dir="backup_$$timestamp"; \
	mkdir -p "$$backup_dir"; \
	cp -r data "$$backup_dir/"; \
	tar -czf "$$backup_dir.tar.gz" "$$backup_dir"; \
	rm -rf "$$backup_dir"; \
	echo "Backup created: $$backup_dir.tar.gz"

.PHONY: restore-data
restore-data: ## Restore data from a backup (specify BACKUP_FILE=filename.tar.gz)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Please specify BACKUP_FILE=filename.tar.gz"; \
		exit 1; \
	fi
	@echo "Restoring data from $(BACKUP_FILE)..."
	@$(DOCKER_COMPOSE) down
	@rm -rf data/pgdata/* data/minio/*
	@tar -xzf $(BACKUP_FILE)
	@backup_dir=$$(basename $(BACKUP_FILE) .tar.gz); \
	cp -r "$$backup_dir/data/"* data/; \
	rm -rf "$$backup_dir"
	@echo "Data restored! Use 'make up' to start services."

# Development targets
.PHONY: dev-setup
dev-setup: build up ## Complete development setup (build + start)
	@echo "Development environment ready!"
	@echo "Next steps:"
	@echo "  - Connect to DuckDB: make shell"
	@echo "  - View MinIO console: make minio-console"
	@echo "  - Check logs: make logs"

.PHONY: demo
demo: up ## Start stack and run demo query
	@echo "Running demo query..."
	@sleep 15  # Wait for services to be fully ready
	@echo "Loading gene data into DuckLake..."
	@$(DOCKER_COMPOSE) exec ducklake-init duckdb -c " \
		CREATE OR REPLACE TABLE the_ducklake.gene AS \
		SELECT * FROM read_csv_auto( \
			'https://storage.googleapis.com/public-download-files/hgnc/tsv/tsv/non_alt_loci_set.txt', \
			HEADER => TRUE, \
			DELIM => '\t', \
			SAMPLE_SIZE => 100000 \
		); \
		SELECT 'Demo table created with ' || COUNT(*) || ' rows' as result FROM the_ducklake.gene; \
	"
	@echo "Demo complete! Connect with 'make shell' and try: SELECT * FROM gene LIMIT 10;"

# Maintenance targets
.PHONY: pull
pull: ## Pull latest Docker images
	@echo "Pulling latest Docker images..."
	$(DOCKER_COMPOSE) pull

.PHONY: prune
prune: ## Clean up unused Docker resources
	@echo "Cleaning up unused Docker resources..."
	docker system prune -f
	docker volume prune -f

.PHONY: reset
reset: down clean-data build up ## Complete reset: stop, clean data, rebuild, start

# Information targets
.PHONY: info
info: ## Show connection information and URLs
	@echo "DuckLake Connection Information:"
	@echo "==============================="
	@echo "DuckDB Shell:       make shell"
	@echo "PostgreSQL:         make psql"
	@echo "MinIO Console:      http://localhost:9000 (admin/minioadmin)"
	@echo "PostgreSQL Port:    localhost:5432"
	@echo "MinIO S3 API:       http://localhost:9000"
	@echo ""
	@echo "Environment Variables:"
	@echo "  POSTGRES_DB:       ducklake_catalog"
	@echo "  POSTGRES_USER:     ducklake"
	@echo "  BUCKET:            ducklake"
	@echo "  S3_ENDPOINT:       minio:9000"

.PHONY: test-connection
test-connection: ## Test DuckLake connection and basic functionality
	@echo "Testing DuckLake connection..."
	@$(DOCKER_COMPOSE) exec ducklake-init duckdb -c " \
		SELECT 'DuckLake connection successful!' as status; \
		SELECT COUNT(*) as schema_count FROM information_schema.schemata; \
		SHOW TABLES; \
	"

# Make sure help is the default target
.DEFAULT_GOAL := help
