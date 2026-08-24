.DEFAULT_GOAL := help
.PHONY: help setup skills skills-dry run run-headless ask dump-config plugin-add doctor clean

CC_PLUGINS ?= ../claude-code-plugins/plugins
PROFILE    ?= web
JOB        ?= list the files in this repo and say what it is
PKG        ?=
export DSH_HOME := $(CURDIR)/dsh-home

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## Install dsh locally and create .env from the template
	npm install
	@test -f .env || (cp .env.example .env && echo "created .env — add your OPENROUTER_API_KEY")

skills: ## Port Claude Code plugin skills into .dsh/skills
	./scripts/port-cc-skills.sh $(CC_PLUGINS)

skills-dry: ## Preview the skill port without writing
	./scripts/port-cc-skills.sh $(CC_PLUGINS) --dry-run

run: ## Start the DSH web UI (opens a browser)
	npx dsh web

run-headless: ## Start the DSH web UI without opening a browser
	npx dsh web --no-open

ask: ## One-shot CLI job, prints the answer and exits (JOB="...")
	npx dsh --profile headless "$(JOB)"

dump-config: ## Print the composed profile tree and exit (needs no API key)
	npx dsh --profile $(PROFILE) --dump-config

plugin-add: ## Add a plugin to a profile (make plugin-add PKG=<pkg> [PROFILE=web])
	@test -n "$(PKG)" || (echo "usage: make plugin-add PKG=<pkg> [PROFILE=web]" && exit 1)
	npx dsh plugin --profile $(PROFILE) add $(PKG)

doctor: ## Check toolchain, key, and skill discovery
	@echo "node       : $$(node -v 2>/dev/null || echo MISSING)"
	@echo "dsh        : $$(npx dsh --version 2>/dev/null || echo 'not installed — run make setup')"
	@echo "DSH_HOME   : $(DSH_HOME)"
	@echo "settings   : $$(test -f dsh-home/settings.yaml && echo present || echo MISSING)"
	@echo "OPENROUTER_API_KEY : $$(test -n "$$OPENROUTER_API_KEY" && echo set || echo 'not set in this shell')"
	@echo "skills     : $$(ls -1 .dsh/skills 2>/dev/null | wc -l) in .dsh/skills"

clean: ## Remove ported skills and node_modules
	rm -rf node_modules .dsh/skills
