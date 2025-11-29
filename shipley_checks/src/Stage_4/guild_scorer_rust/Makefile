.PHONY: dev build deploy css watch-css clean test

# Development server with auto-reload (requires cargo-watch)
dev:
	cargo watch -x 'run --features api --bin api_server' -w src -w templates

# Build debug binary (faster compilation for development)
build:
	cargo build --features api
	./tailwindcss -i input.css -o assets/css/styles.css --minify

# Deploy to DO server
deploy: build
	scp target/debug/api_server root@134.199.166.0:/opt/plantguide/
	rsync -avz --delete assets/ root@134.199.166.0:/opt/plantguide/assets/
	rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
	ssh root@134.199.166.0 "systemctl restart plantguide"
	@echo "Deployed! Access at http://134.199.166.0"

# Quick deploy assets only (no Rust rebuild)
deploy-assets:
	./tailwindcss -i input.css -o assets/css/styles.css --minify
	rsync -avz --delete assets/ root@134.199.166.0:/opt/plantguide/assets/
	rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
	ssh root@134.199.166.0 "systemctl restart plantguide"
	@echo "Assets deployed!"

# Build CSS only
css:
	./tailwindcss -i input.css -o assets/css/styles.css --minify

# Watch CSS during development
watch-css:
	./tailwindcss -i input.css -o assets/css/styles.css --watch

# Clean build artifacts
clean:
	cargo clean
	rm -f assets/css/styles.css

# Run tests
test:
	cargo test --features api

# Check server status
status:
	ssh root@134.199.166.0 "systemctl status plantguide --no-pager"

# View server logs
logs:
	ssh root@134.199.166.0 "journalctl -u plantguide -f"

# Health check
health:
	curl -s http://134.199.166.0/health | jq .
