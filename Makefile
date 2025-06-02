.PHONY: deps test lint format ci dev-install dev-clean dev

NVIM ?= nvim
NVIM_INIT := tests/minimal_init.lua
RUNTIME := $(HOME)/.local/share/nvim/site/pack/vendor/start

RUNTIME     := $(HOME)/.local/share/nvim/site/pack/vendor/start
DEV_DIR     := $(HOME)/.config/nvim/pack/dev/start/ntop.nvim

install-stylua:
	@echo " # Linux/macOS via Cargo (recommended)"
	@echo " cargo install stylua --locked"
	@echo " # Homebrew (macOS)"
	@echo " brew install stylua"
	@echo " # Manual"
	@echo " curl -sSL https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux.zip -o stylua.zip"
	@echo " unzip stylua.zip && chmod +x stylua && sudo mv stylua /usr/local/bin"

install-deps:
	@echo "→ Installing LuaRocks packages (busted, luassert)"
	@luarocks install --local --server=https://luarocks.org busted || true
	@luarocks install --local --server=https://luarocks.org luassert || true
	@echo "→ Ensuring plenary.nvim is installed"
	@[ -d "$(RUNTIME)/plenary.nvim" ] || \
	  (mkdir -p "$(RUNTIME)" && \
	   git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$(RUNTIME)/plenary.nvim")

test:
	@echo "→ Running Plenary‑Busted tests"
	@$(NVIM) --headless -u $(NVIM_INIT) \
	  -c "PlenaryBustedDirectory tests/ { minimal_init = '$(NVIM_INIT)' }" +qall

lint:
	@echo "→ Linting Lua with stylua (check‑only)"
	@stylua --check lua/

format:
	@echo "→ Formatting Lua with stylua (in‑place)"
	@stylua lua/

ci: deps test

dev-install: dev-clean
	@echo "→ Installing to $(DEV_DIR)"
	@mkdir -p $$(dirname "$(DEV_DIR)")
	@rsync -a --delete --exclude='.git' ./ "$(DEV_DIR)"

dev-clean:
	@echo "→ Removing $(DEV_DIR) (if present)"
	@rm -rf "$(DEV_DIR)"

dev: deps dev-install
