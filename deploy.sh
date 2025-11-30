#!/usr/bin/env bash
set -euo pipefail

# PlantGuide Deployment Script
# Usage: ./deploy.sh [api|frontend|all]

SERVER="root@134.199.166.0"
API_REMOTE="/opt/plantguide"
FRONTEND_REMOTE="/opt/plantguide-frontend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

deploy_api() {
    log "Building Rust API (debug)..."
    cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust
    cargo build --features api

    log "Stopping API service..."
    ssh $SERVER "systemctl stop plantguide" || true

    log "Deploying API binary..."
    scp target/debug/api_server $SERVER:$API_REMOTE/

    if [ -d "templates" ]; then
        log "Syncing templates..."
        rsync -avz --delete templates/ $SERVER:$API_REMOTE/templates/
    fi

    log "Starting API service..."
    ssh $SERVER "systemctl start plantguide"

    log "API health check..."
    ssh $SERVER "curl -sf http://localhost:3000/health" && log "API OK" || error "API health check failed"
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

    log "Frontend health check..."
    sleep 2
    ssh $SERVER "curl -sf http://localhost:4000/" > /dev/null && log "Frontend OK" || error "Frontend health check failed"
}

case "${1:-all}" in
    api)
        deploy_api
        ;;
    frontend)
        deploy_frontend
        ;;
    all)
        deploy_api
        deploy_frontend
        ;;
    *)
        echo "Usage: $0 [api|frontend|all]"
        exit 1
        ;;
esac

log "Deployment complete!"
