# =============================================================================
# Makefile - Linux Shell Portfolio
# =============================================================================

SHELL       := /bin/bash
SCRIPT_DIR  := scripts
TEST_DIR    := tests
SCRIPTS     := $(shell find $(SCRIPT_DIR) -name "*.sh" -type f)

.PHONY: all setup lint test validate clean help

# ─── Default ──────────────────────────────────────────────────────────────────
all: setup validate lint

# ─── Help ─────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "╔══════════════════════════════════════════╗"
	@echo "║   Linux Shell Portfolio - Makefile       ║"
	@echo "╚══════════════════════════════════════════╝"
	@echo ""
	@echo "  make setup      - Make scripts executable"
	@echo "  make lint       - Run shellcheck linting"
	@echo "  make validate   - Check bash syntax"
	@echo "  make test       - Run test suite"
	@echo "  make clean      - Clean generated files"
	@echo "  make list       - List all scripts"
	@echo ""

# ─── Setup ────────────────────────────────────────────────────────────────────
setup:
	@echo "→ Setting up scripts..."
	@find $(SCRIPT_DIR) -name "*.sh" -exec chmod +x {} \;
	@mkdir -p /tmp/health_reports /tmp/health_check_logs
	@echo "✓ Setup complete. $(words $(SCRIPTS)) scripts ready."

# ─── Lint ─────────────────────────────────────────────────────────────────────
lint:
	@echo "→ Running shellcheck..."
	@if command -v shellcheck &>/dev/null; then \
		errors=0; \
		for script in $(SCRIPTS); do \
			echo "  Checking: $$script"; \
			shellcheck -S warning "$$script" || errors=$$((errors+1)); \
		done; \
		if [ $$errors -eq 0 ]; then \
			echo "✓ All scripts passed linting"; \
		else \
			echo "✗ $$errors script(s) have issues"; \
			exit 1; \
		fi \
	else \
		echo "⚠ shellcheck not found. Install: apt install shellcheck"; \
	fi

# ─── Validate Syntax ──────────────────────────────────────────────────────────
validate:
	@echo "→ Validating bash syntax..."
	@errors=0; \
	for script in $(SCRIPTS); do \
		if bash -n "$$script" 2>/dev/null; then \
			echo "  ✓ $$script"; \
		else \
			echo "  ✗ $$script - SYNTAX ERROR"; \
			errors=$$((errors+1)); \
		fi \
	done; \
	if [ $$errors -eq 0 ]; then \
		echo "✓ All scripts have valid syntax"; \
	else \
		echo "✗ $$errors script(s) have syntax errors"; \
		exit 1; \
	fi

# ─── Tests ────────────────────────────────────────────────────────────────────
test:
	@echo "→ Running test suite..."
	@chmod +x $(TEST_DIR)/test_scripts.sh
	@bash $(TEST_DIR)/test_scripts.sh

# ─── List Scripts ─────────────────────────────────────────────────────────────
list:
	@echo ""
	@echo "Available Scripts:"
	@echo "────────────────────────────────────────────"
	@for script in $(SCRIPTS); do \
		desc=$$(grep "# Description:" "$$script" | head -1 | cut -d: -f2 | xargs); \
		printf "  %-45s %s\n" "$$script" "$$desc"; \
	done
	@echo ""

# ─── Clean ────────────────────────────────────────────────────────────────────
clean:
	@echo "→ Cleaning generated files..."
	@rm -rf /tmp/health_reports /tmp/health_check_logs
	@find . -name "*.log" -not -path "./.git/*" -delete 2>/dev/null || true
	@find . -name "*.html" -not -path "./.git/*" -delete 2>/dev/null || true
	@echo "✓ Clean complete"
