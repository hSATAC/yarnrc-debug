# Verdaccio Docker Management Makefile

# Variables
IMAGE_NAME := verdaccio-local
CONTAINER_NAME := verdaccio-server
PORT := 4873
DOCKER := docker
VOLUME_NAME := verdaccio-storage

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make build    - Build the Docker image"
	@echo "  make run      - Run the container (detached)"
	@echo "  make up       - Build and run"
	@echo "  make stop     - Stop the container"
	@echo "  make restart  - Restart the container"
	@echo "  make logs     - Show container logs"
	@echo "  make shell    - Enter container shell"
	@echo "  make clean    - Stop and remove container"
	@echo "  make purge    - Clean and remove image & volumes"
	@echo "  make status   - Show container status"

# Build Docker image
.PHONY: build
build:
	$(DOCKER) build -t $(IMAGE_NAME) .
	@echo "✓ Image $(IMAGE_NAME) built successfully"

# Run container
.PHONY: run
run:
	@if [ "$$($(DOCKER) ps -aq -f name=$(CONTAINER_NAME))" ]; then \
		echo "Container $(CONTAINER_NAME) already exists. Removing..."; \
		$(DOCKER) rm -f $(CONTAINER_NAME); \
	fi
	$(DOCKER) run -d \
		--name $(CONTAINER_NAME) \
		-p $(PORT):4873 \
		-v $(VOLUME_NAME):/verdaccio/storage \
		-v ./workdir:/workdir \
		--restart unless-stopped \
		$(IMAGE_NAME)
	@echo "✓ Container $(CONTAINER_NAME) is running on port $(PORT)"
	@echo "✓ Registry URL: http://localhost:$(PORT)"

# Build and run
.PHONY: up
up: build run

# Stop container
.PHONY: stop
stop:
	@if [ "$$($(DOCKER) ps -q -f name=$(CONTAINER_NAME))" ]; then \
		$(DOCKER) stop $(CONTAINER_NAME); \
		echo "✓ Container $(CONTAINER_NAME) stopped"; \
	else \
		echo "Container $(CONTAINER_NAME) is not running"; \
	fi

# Restart container
.PHONY: restart
restart: stop run

# Show logs
.PHONY: logs
logs:
	$(DOCKER) logs -f $(CONTAINER_NAME)

# Enter container shell
.PHONY: shell
shell:
	$(DOCKER) exec -it $(CONTAINER_NAME) /bin/sh

# Clean up container
.PHONY: clean
clean: stop
	@if [ "$$($(DOCKER) ps -aq -f name=$(CONTAINER_NAME))" ]; then \
		$(DOCKER) rm $(CONTAINER_NAME); \
		echo "✓ Container $(CONTAINER_NAME) removed"; \
	else \
		echo "Container $(CONTAINER_NAME) does not exist"; \
	fi

# Purge everything
.PHONY: purge
purge: clean
	@if [ "$$($(DOCKER) images -q $(IMAGE_NAME))" ]; then \
		$(DOCKER) rmi $(IMAGE_NAME); \
		echo "✓ Image $(IMAGE_NAME) removed"; \
	fi
	@if [ "$$($(DOCKER) volume ls -q -f name=$(VOLUME_NAME))" ]; then \
		$(DOCKER) volume rm $(VOLUME_NAME); \
		echo "✓ Volume $(VOLUME_NAME) removed"; \
	fi

# Show container status
.PHONY: status
status:
	@echo "=== Container Status ==="
	@if [ "$$($(DOCKER) ps -q -f name=$(CONTAINER_NAME))" ]; then \
		echo "Status: Running ✓"; \
		echo "Port: $(PORT)"; \
		echo "URL: http://localhost:$(PORT)"; \
		$(DOCKER) ps -f name=$(CONTAINER_NAME); \
	else \
		echo "Status: Not running ✗"; \
	fi
	@echo ""
	@echo "=== Image Status ==="
	@if [ "$$($(DOCKER) images -q $(IMAGE_NAME))" ]; then \
		echo "Image: $(IMAGE_NAME) exists ✓"; \
		$(DOCKER) images $(IMAGE_NAME); \
	else \
		echo "Image: $(IMAGE_NAME) does not exist ✗"; \
	fi

# Test registry connection
.PHONY: test
test:
	@echo "Testing registry connection..."
	@curl -s http://localhost:$(PORT)/-/ping && echo "✓ Registry is responding" || echo "✗ Registry is not responding"

# Configure npm/yarn to use this registry
.PHONY: npm-config
npm-config:
	@echo "To use this registry with npm:"
	@echo "  npm set registry http://localhost:$(PORT)"
	@echo ""
	@echo "To use this registry with yarn:"
	@echo "  yarn config set registry http://localhost:$(PORT)"
	@echo ""
	@echo "To reset to default:"
	@echo "  npm set registry https://registry.npmjs.org/"
	@echo "  yarn config set registry https://registry.yarnpkg.com"

# Clear all caches for clean testing
.PHONY: clear-cache
clear-cache:
	@echo "=== Clearing all caches ==="
	@echo "1. Clearing Yarn Berry cache..."
	@rm -rf ~/.yarn/berry/cache
	@echo "   ✓ Yarn cache cleared"
	@echo ""
	@echo "2. Clearing Verdaccio storage..."
	@$(DOCKER) exec $(CONTAINER_NAME) rm -rf /verdaccio/storage/data/* 2>/dev/null || true
	@echo "   ✓ Verdaccio storage cleared"
	@echo ""
	@echo "3. Clearing local project cache..."
	@rm -rf workdir/.yarn 2>/dev/null || true
	@rm -rf workdir/node_modules 2>/dev/null || true
	@rm -f workdir/yarn.lock 2>/dev/null || true
	@rm -f workdir/.pnp.* 2>/dev/null || true
	@echo "   ✓ Project cache cleared"
	@echo ""
	@echo "✓ All caches cleared successfully"

# Clean test environment (clear cache + restart registry)
.PHONY: clean-test
clean-test: clear-cache restart
	@echo "✓ Test environment reset complete"
	@echo "Registry is ready for fresh testing at http://localhost:$(PORT)"

# Install test package with fresh download
.PHONY: test-install
test-install:
	@echo "=== Testing package installation ==="
	@if [ ! -f workdir/package.json ]; then \
		echo "Initializing test project in workdir..."; \
		cd workdir && yarn init -y; \
	fi
	@echo "Testing with package"
	@cd workdir && yarn install --verbose
	@echo "✓ Package installed successfully"

# Full test cycle: clear everything and install
.PHONY: test-cycle
test-cycle: clear-cache
	@echo "=== Starting full test cycle ==="
	@echo ""
	@echo "Step 1: Clearing all caches (completed)"
	@echo ""
	@if [ ! -f workdir/package.json ]; then \
		echo "Initializing test project in workdir..."; \
		cd workdir && yarn init -y; \
		echo ""; \
	fi
	@echo "Step 2: Installing test package..."
	@cd workdir && yarn install
	@echo ""
	@echo "Step 3: Checking Verdaccio logs..."
	@$(DOCKER) logs $(CONTAINER_NAME) --tail 10 | grep -E "(GET|POST|PUT)" || true
	@echo ""
	@echo "✓ Test cycle complete"

# Monitor network traffic during installation
.PHONY: test-with-monitor
test-with-monitor:
	@echo "=== Monitoring registry traffic ==="
	@echo "Starting log monitor in background..."
	@$(DOCKER) logs -f $(CONTAINER_NAME) 2>&1 | grep --line-buffered -E "(requested|making request)" &
	@sleep 1
	@echo ""
	@echo "Installing package..."
	@cd workdir && yarn install
	@echo ""
	@echo "✓ Installation complete (check logs above for network activity)"

# Show cache status
.PHONY: cache-status
cache-status:
	@echo "=== Cache Status ==="
	@echo ""
	@echo "1. Yarn Berry cache:"
	@if [ -d ~/.yarn/berry/cache ]; then \
		echo "   Location: ~/.yarn/berry/cache"; \
		echo "   Size: $$(du -sh ~/.yarn/berry/cache 2>/dev/null | cut -f1)"; \
		echo "   Files: $$(find ~/.yarn/berry/cache -type f 2>/dev/null | wc -l | tr -d ' ')"; \
	else \
		echo "   Cache directory does not exist"; \
	fi
	@echo ""
	@echo "2. Verdaccio storage:"
	@$(DOCKER) exec $(CONTAINER_NAME) sh -c "du -sh /verdaccio/storage/data 2>/dev/null | cut -f1" 2>/dev/null || echo "   Not accessible"
	@echo ""
	@echo "3. Project cache:"
	@if [ -d workdir/.yarn ]; then \
		echo "   .yarn exists: $$(du -sh workdir/.yarn 2>/dev/null | cut -f1)"; \
	else \
		echo "   No .yarn directory"; \
	fi
	@if [ -d workdir/node_modules ]; then \
		echo "   node_modules exists: $$(du -sh workdir/node_modules 2>/dev/null | cut -f1)"; \
	else \
		echo "   No node_modules directory"; \
	fi