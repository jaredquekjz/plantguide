# API Server Deployment Guide

## Quick Start (Docker)

### Build and run locally:
```bash
docker-compose up --build
```

API will be available at `http://localhost:3000`

### Test endpoints:
```bash
# Health check
curl http://localhost:3000/health

# Search plants
curl "http://localhost:3000/api/plants/search?min_light=7.0&limit=10"

# Get plant by ID
curl http://localhost:3000/api/plants/wfo-0000649953
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATA_DIR` | `/app/data` | Path to Phase 7 parquets |
| `CLIMATE_TIER` | `tier_3_humid_temperate` | Default climate tier for guild scorer |
| `PORT` | `3000` | Server port |
| `RUST_LOG` | `info` | Log level (trace, debug, info, warn, error) |

## Production Deployment

### Option 1: Google Cloud Run (Serverless)

```bash
# Build and push image
gcloud builds submit --tag gcr.io/PROJECT_ID/plant-api

# Deploy
gcloud run deploy plant-api \
  --image gcr.io/PROJECT_ID/plant-api \
  --platform managed \
  --region us-central1 \
  --memory 1Gi \
  --cpu 2 \
  --max-instances 10 \
  --allow-unauthenticated
```

**Cost**: Free tier covers ~2M requests/month

### Option 2: Hetzner VPS (Dedicated)

1. **Provision VPS** (CX11: 2 vCPU, 2GB RAM, €4.15/month)

2. **Setup**:
```bash
# SSH to VPS
ssh root@your-server-ip

# Install Docker
curl -fsSL https://get.docker.com | sh

# Clone repo
git clone https://github.com/jaredquekjz/plantguide.git
cd plantguide/shipley_checks/src/Stage_4/guild_scorer_rust

# Run with systemd
sudo cp plant-api.service /etc/systemd/system/
sudo systemctl enable plant-api
sudo systemctl start plant-api
```

3. **Nginx reverse proxy** (optional):
```nginx
server {
    listen 80;
    server_name api.plantguide.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Cost**: ~€50/year for VPS + domain

### Option 3: Fly.io (Global Edge)

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Launch app
fly launch

# Deploy
fly deploy
```

**Cost**: Free tier covers 3 VMs with 256MB RAM each

## Performance Tuning

### Memory Settings

Default: 1GB RAM is sufficient for ~10K concurrent connections

For higher load:
```yaml
# docker-compose.yml
deploy:
  resources:
    limits:
      memory: 2G
    reservations:
      memory: 1G
```

### CPU Settings

Default: 2 vCPU cores

For CPU-bound workloads (guild scoring):
```yaml
deploy:
  resources:
    limits:
      cpus: '4'
```

### Cache Settings

Moka cache is configured in code (10K entries, 5min TTL).

To adjust:
- Edit `src/api_server.rs` → `Cache::builder()`
- Rebuild image

## Monitoring

### Logs

```bash
# Docker Compose
docker-compose logs -f

# Cloud Run
gcloud logging read "resource.type=cloud_run_revision"

# Systemd
journalctl -u plant-api -f
```

### Metrics

Health endpoint includes timestamp:
```bash
curl http://localhost:3000/health
# {"status":"healthy","timestamp":"2024-11-24T10:00:00Z"}
```

Add Prometheus/Grafana for production monitoring (future Phase 11).

## Troubleshooting

### Container won't start

Check logs:
```bash
docker-compose logs api
```

Common issues:
- Phase 7 data not found → ensure `DATA_DIR` points to correct path
- Port already in use → change `PORT` environment variable
- Out of memory → increase memory limits

### Slow queries

Enable debug logging:
```bash
RUST_LOG=debug docker-compose up
```

Check DataFusion query plans in logs.

### Connection refused

Verify container is running:
```bash
docker-compose ps
```

Check firewall rules:
```bash
sudo ufw allow 3000/tcp
```

## Security

### Production Checklist

- [ ] Change CORS policy from permissive to specific origins
- [ ] Add rate limiting (use `ConcurrencyLimitLayer`)
- [ ] Enable HTTPS (use Caddy or nginx with Let's Encrypt)
- [ ] Restrict `/health` endpoint to internal network
- [ ] Add authentication for sensitive endpoints
- [ ] Set up firewall rules
- [ ] Regular security updates (rebuild image monthly)

## Scaling

### Horizontal Scaling

Load balancer + multiple instances:
```bash
docker-compose up --scale api=3
```

### Vertical Scaling

Increase resources per instance:
- 4 vCPU, 4GB RAM → ~50K req/s
- 8 vCPU, 8GB RAM → ~100K req/s

### Database Considerations

Current: File-based (Phase 7 parquets)

For write-heavy workloads, consider:
- PostgreSQL with PostGIS
- ClickHouse (OLAP)
- Keep DataFusion for read-only queries

## Cost Estimates

| Platform | Configuration | Monthly Cost | Req/s Capacity |
|----------|---------------|--------------|----------------|
| **Cloud Run** | 1GB, 2 vCPU, auto-scale | $0-40 | 10K-50K |
| **Hetzner CX11** | 2GB, 2 vCPU, dedicated | €4.15 | 20K-30K |
| **Hetzner CX21** | 4GB, 2 vCPU, dedicated | €6.00 | 40K-60K |
| **Fly.io** | 3× 256MB VMs, edge | Free-$10 | 5K-15K |

**Recommendation**: Start with Cloud Run free tier, migrate to Hetzner CX11 when sustained load exceeds free tier.
