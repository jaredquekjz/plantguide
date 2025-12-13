#!/usr/bin/env bash
set -euo pipefail

# PlantGuide Deployment Script
# Usage: ./deploy.sh [api|frontend|all] [--release] ["commit message"]
#
# Examples:
#   ./deploy.sh api "Fix scoring bug"
#   ./deploy.sh api --release "Production hotfix"
#   ./deploy.sh all "Update everything"

SERVER="root@134.199.166.0"
API_REMOTE="/opt/plantguide"
FRONTEND_REMOTE="/opt/plantguide-frontend"
RUST_DIR="shipley_checks/src/Stage_4/guild_scorer_rust"

# Parse arguments
RELEASE_MODE=false
COMMIT_MSG=""
TARGET="all"

for arg in "$@"; do
    case "$arg" in
        --release)
            RELEASE_MODE=true
            ;;
        api|frontend|all)
            TARGET="$arg"
            ;;
        *)
            # Anything else is the commit message
            COMMIT_MSG="$arg"
            ;;
    esac
done

# Cloudflare Access credentials for smoke tests
CF_ACCESS_CLIENT_ID="0b88a14e6379b4865e41e40801ce18c2.access"
CF_ACCESS_CLIENT_SECRET="dbb8714dbcc3204c04b4aa23a7ce3198f7ae35d9659aa85278fdf63bc0a4c07a"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Git commit and push (requires commit message)
git_commit() {
    if [ -z "$COMMIT_MSG" ]; then
        error "Commit message required. Usage: ./deploy.sh api \"Your commit message\""
    fi

    log "Committing changes..."
    git add "$RUST_DIR/"
    if git diff --cached --quiet; then
        warn "No changes to commit in $RUST_DIR"
    else
        git commit -m "$COMMIT_MSG"
        log "Pushing to remote..."
        git push
    fi
}

deploy_api() {
    cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust

    if [ "$RELEASE_MODE" = true ]; then
        log "Building Rust API (release - this may take a few minutes)..."
        cargo build --features api --release
        BINARY_PATH="target/release/api_server"
    else
        log "Building Rust API (debug)..."
        cargo build --features api
        BINARY_PATH="target/debug/api_server"
    fi

    log "Stopping API service..."
    ssh $SERVER "systemctl stop plantguide" || true

    log "Deploying API binary..."
    scp $BINARY_PATH $SERVER:$API_REMOTE/api_server

    if [ -d "templates" ]; then
        log "Syncing templates..."
        rsync -avz --delete templates/ $SERVER:$API_REMOTE/templates/
    fi

    log "Starting API service..."
    ssh $SERVER "systemctl start plantguide"

    log "API health check (waiting for startup)..."
    for i in 1 2 3 4 5 6; do
        sleep 2
        if ssh $SERVER "curl -sf http://localhost:3000/health" 2>/dev/null; then
            log "API OK (attempt $i)"
            return 0
        fi
        log "Waiting for API... (attempt $i/6)"
    done
    error "API health check failed after 12 seconds"
}

deploy_frontend() {
    log "Building Astro frontend..."
    cd /home/olier/plantguide-frontend
    npm run build

    log "Stopping frontend service..."
    ssh $SERVER "systemctl stop plantguide-frontend" || true

    log "Deploying frontend..."
    rsync -avz --delete dist/ $SERVER:$FRONTEND_REMOTE/dist/

    log "Starting frontend service..."
    ssh $SERVER "systemctl start plantguide-frontend"

    log "Frontend health check (internal)..."
    sleep 2
    ssh $SERVER "curl -sf http://localhost:4000/" > /dev/null && log "Internal OK" || error "Internal health check failed"

    log "Frontend smoke test (via Cloudflare)..."
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        "https://olier.ai/guide/wfo-0000003942")
    [ "$STATUS" = "200" ] && log "Smoke test OK" || warn "Smoke test returned HTTP $STATUS"
}

case "$TARGET" in
    api)
        git_commit
        deploy_api
        ;;
    frontend)
        deploy_frontend
        ;;
    all)
        git_commit
        deploy_api
        deploy_frontend
        ;;
esac

log "Deployment complete!"
