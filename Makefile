SHELL := /usr/bin/env bash

.PHONY: build deploy deploy-edge verify guard sot-lock sot-guard host-split-lock ui-skin-lock where clean

build:
	./scripts/build.sh

deploy:
	./deploy.sh

deploy-edge:
	@bash scripts/deploy_edge.sh

verify:
	@echo "Local:"
	@cat dist/MANIFEST.sha256
	@echo "Remote MANIFEST.sha256 digest:"
	@ssh $${REMOTE_HOST:-root@49.13.217.227} "sha256sum /srv/web/vaultmesh/MANIFEST.sha256 2>/dev/null || shasum -a 256 /srv/web/vaultmesh/MANIFEST.sha256"

guard:
	@bash scripts/nav_footer_guard.sh

sot-lock:
	@bash scripts/sot_guard.sh --repo

sot-guard:
	@bash scripts/sot_guard.sh --repo

host-split-lock:
	@bash scripts/host_split_guard.sh --config deploy/edge/etc/caddy/Caddyfile

ui-skin-lock:
	@bash scripts/ui_skin_guard.sh --repo
	@./scripts/build.sh >/dev/null
	@bash scripts/ui_skin_guard.sh --dist

where:
	@bash scripts/where_is_vaultmesh.sh

clean:
	@find dist -mindepth 1 -delete 2>/dev/null || true
	@rmdir dist 2>/dev/null || true
