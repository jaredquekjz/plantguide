#!/bin/bash
# Local development script - starts both Rust API and Astro frontend

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Kill any existing processes on ports 3000 and 4000
echo -e "${YELLOW}Stopping existing services...${NC}"
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:4000 | xargs kill -9 2>/dev/null || true
sleep 1

# Start Rust API in background
echo -e "${GREEN}Starting Rust API on port 3000...${NC}"
DATA_DIR=shipley_checks/stage4 cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml --features api --bin api_server > /tmp/rust-api.log 2>&1 &
RUST_PID=$!

# Wait for Rust API to be ready
echo -n "Waiting for API"
for i in {1..30}; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Start Astro frontend
echo -e "${GREEN}Starting Astro frontend on port 4000...${NC}"
cd /home/olier/plantguide-frontend
npm run dev -- --host > /tmp/astro-dev.log 2>&1 &
ASTRO_PID=$!
sleep 3

echo ""
echo -e "${GREEN}Both services running:${NC}"
echo "  Astro frontend: http://localhost:4000 (or http://192.168.1.103:4000)"
echo "  Rust API:       http://localhost:3000"
echo ""
echo "Logs:"
echo "  tail -f /tmp/rust-api.log"
echo "  tail -f /tmp/astro-dev.log"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop both services${NC}"

# Trap to kill both on exit
trap "kill $RUST_PID $ASTRO_PID 2>/dev/null; exit" INT TERM

# Wait
wait
