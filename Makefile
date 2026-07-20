# ── UIA Inspector MCP ─────────────────────────────────────────────
# Build, package, and install the VS Code extension that provides
# the UIA Inspector MCP server.
#
# Usage:
#   make          build the extension (default)
#   make package  create a .vsix bundle
#   make install  build, package, and install into VS Code
#   make test     run unit tests
#   make clean    remove build artifacts
# ──────────────────────────────────────────────────────────────────

EXT_DIR      := vscode-uia-mcp
OUT_DIR      := $(EXT_DIR)/out
SRC_DIR      := $(EXT_DIR)/src
PACKAGE_JSON := $(EXT_DIR)/package.json
TSCONFIG     := $(EXT_DIR)/tsconfig.json
VSIX_NAME    := $$(node -e "var p=require('./$(PACKAGE_JSON)');console.log(p.name+'-'+p.version+'.vsix')" 2>/dev/null || echo "vscode-uia-mcp-0.1.0.vsix")

# Marker files (directories have unreliable mtimes across WSL)
# Platform-specific markers because node_modules is shared between
# Windows and WSL on the NTFS mount — esbuild has native binaries
# that differ per platform.
NODE_MARKER  := $(EXT_DIR)/node_modules/.installed-$(shell uname -s | tr '[:upper:]' '[:lower:]')
BUILD_MARKER := $(OUT_DIR)/.built
ESBUILD_CFG  := $(EXT_DIR)/esbuild.config.mjs

# Source & output files for incremental compilation
SRC_FILES    := $(shell find $(SRC_DIR) -name '*.ts' 2>/dev/null)
OUT_MAIN     := $(OUT_DIR)/extension.js
OUT_BRIDGE   := $(OUT_DIR)/mcpBridge.js

# Tools
NPM    := cd $(EXT_DIR) && npm
BUNDLE := cd $(EXT_DIR) && NODE_NO_WARNINGS=DEP0169 node esbuild.config.mjs
VSCE   := cd $(EXT_DIR) && NODE_NO_WARNINGS=DEP0169 npx @vscode/vsce

ENGINE_AHK := $(CURDIR)/UIA_MCP_Engine.ahk

.PHONY: all package install test test-coverage clean deps force-build typecheck validate

# ── Default ──────────────────────────────────────────────────────

all: build

# ── Dependencies (only runs when package.json changes) ────────────

deps: $(NODE_MARKER)

$(NODE_MARKER): $(PACKAGE_JSON)
	$(NPM) install --no-audit --no-fund
	@mkdir -p $(dir $(NODE_MARKER))
	@touch $(NODE_MARKER)

# ── Build ─────────────────────────────────────────────────────────
# esbuild produces both extension.js and mcpBridge.js in one run.
# Always reinstalls node_modules to ensure native binaries match
# the current platform (shared NTFS mount between Windows and WSL).

$(BUILD_MARKER): $(SRC_FILES) $(TSCONFIG) $(PACKAGE_JSON) $(ESBUILD_CFG)
	@echo "==> Installing dependencies..."
	$(NPM) install --no-audit --no-fund
	@echo "==> Bundling with esbuild..."
	$(BUNDLE)
	@touch $(BUILD_MARKER)
	@echo "==> Build complete ($(OUT_DIR))"

$(OUT_MAIN) $(OUT_BRIDGE): $(BUILD_MARKER)
	@:

build: $(OUT_MAIN) $(OUT_BRIDGE)

# ── Type-check only (no emit) ─────────────────────────────────────

typecheck: deps
	cd $(EXT_DIR) && npx tsc --noEmit -p ./

# ── Validate AHK engine (syntax-only, no execution) ──────────────

validate:
	@echo "==> Validating AHK engine..."
	@powershell.exe -NoProfile -ExecutionPolicy Bypass \
		-File 'C:\Scripts\DetectAHKErrorDialog.ps1' \
		-Validate -ScriptPath "$$(wslpath -w $(ENGINE_AHK))" -TimeoutSec 5; \
	case $$? in \
		0) echo "  AHK validate: OK" ;; \
		3) echo "  AHK validate: FAILED (error dialog)" ; exit 1 ;; \
		*) echo "  AHK validate: FAILED" ; exit 1 ;; \
	esac

# ── Force rebuild (skip incremental check) ────────────────────────

force-build:
	@rm -f $(BUILD_MARKER)
	@$(MAKE) build

# ── Package (.vsix) ───────────────────────────────────────────────

package: build
	@echo "==> Creating .vsix package..."
	$(VSCE) package --out ../
	@echo "==> Package: $(VSIX_NAME)"

# ── Install into VS Code (Windows host) ──────────────────────────
# We run under WSL but must install into the Windows VS Code, not
# the WSL remote.  cmd.exe /c invokes the Windows code binary, and
# wslpath converts the Linux .vsix path to its Windows equivalent.

install: package
	@echo "==> Installing $(VSIX_NAME) into Windows VS Code..."
	cmd.exe /c "code --install-extension $$(wslpath -w $(CURDIR)/$(VSIX_NAME)) --force"
	@echo "==> Installed. Reload any open VS Code windows to pick up changes."

# ── Quick dev install ─────────────────────────────────────────────

install-dev: build
	@echo "==> Installing extension in dev mode..."
	cmd.exe /c "code --install-extension $$(wslpath -w $(CURDIR)/$(VSIX_NAME)) --force 2>/dev/null"
	@echo "==> Dev install complete."

# ── Test ──────────────────────────────────────────────────────────

test: deps
	cd $(EXT_DIR) && npx jest --no-coverage

test-coverage: deps
	cd $(EXT_DIR) && npx jest --coverage

# ── Watch (for development) ───────────────────────────────────────

watch: deps
	$(BUNDLE) --watch

# ── Clean ─────────────────────────────────────────────────────────

clean:
	@echo "==> Cleaning..."
	rm -rf $(OUT_DIR)
	rm -f ./*.vsix
	rm -f $(EXT_DIR)/node_modules/.installed-*
	cd $(EXT_DIR) && rm -rf out coverage
	@echo "==> Clean complete."

# ── Help ──────────────────────────────────────────────────────────

help:
	@echo "UIA Inspector MCP — Makefile targets"
	@echo ""
	@echo "  make            Bundle with esbuild (incremental, default)"
	@echo "  make force-build  Force rebuild (skip incremental check)"
	@echo "  make typecheck  Run tsc for type checking (no emit)"
	@echo "  make validate   Validate AHK engine syntax (/iLib, no execution)"
	@echo "  make deps       Install npm dependencies"
	@echo "  make package    Build + create .vsix bundle"
	@echo "  make install    Build + package + install into VS Code"
	@echo "  make install-dev  Install for development (symlink-style)"
	@echo "  make test       Run Jest unit tests"
	@echo "  make test-coverage  Run tests with coverage"
	@echo "  make watch      Watch TypeScript and recompile on change"
	@echo "  make clean      Remove build artifacts"
	@echo "  make help       Show this help"
