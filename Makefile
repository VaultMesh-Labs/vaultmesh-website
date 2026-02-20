SHELL := /usr/bin/env bash

.PHONY: build deploy verify clean

build:
	./build.sh

deploy:
	./deploy.sh

verify:
	@echo "Local:"
	@cat dist/MANIFEST.sha256
	@echo "Remote MANIFEST.sha256 digest:"
	@ssh $${REMOTE_HOST:-root@49.13.217.227} "sha256sum /srv/web/vaultmesh/MANIFEST.sha256 2>/dev/null || shasum -a 256 /srv/web/vaultmesh/MANIFEST.sha256"

clean:
	@find dist -mindepth 1 -delete 2>/dev/null || true
	@rmdir dist 2>/dev/null || true
