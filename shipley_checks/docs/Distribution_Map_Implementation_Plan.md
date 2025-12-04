# Distribution Map Implementation Plan

**Goal**: Apple Maps-style species distribution map with smooth heatmap shading ("British Empire" aesthetic)

**Location**: Hero element below "In the Wild" (S2) header, above Light requirements

---

## Design Philosophy

| Apple Reference | Our Application |
|-----------------|-----------------|
| Apple Maps terrain shading | Smooth gradient density cloud |
| Health app gradients | Emerald fade from core → edge |
| Weather app minimalism | No grid lines, no legends |
| Dark mode aesthetic | Ocean: `#1a1a2e`, Land: `#2d2d3a` |

**Visual Target**:
- Smooth heatmap cloud showing species range
- Dense core areas: bright emerald (#34d399)
- Edge/sparse areas: fade to transparent
- Gaussian blur for organic "fuzzy" boundaries
- Dark base map (land + ocean silhouette only)
- No country borders, no political boundaries

---

## Architecture: Pre-rendered Heatmaps

### Why Pre-rendered?

| Consideration | Decision |
|---------------|----------|
| 11,711 species | Pre-generate all at build time |
| Instant loading | Static WebP images, no JS computation |
| Consistent quality | R generates identical styling |
| Storage | ~16KB × 11,711 = ~187MB (acceptable for R2 CDN) |

### Output Format

- **Resolution**: 960×480 pixels (2:1 aspect, standard web map)
- **Format**: WebP (quality 80, ~12-20KB each)
- **Location**: `photos.olier.ai/maps/{wfo_taxon_id}.webp`
- **Fallback**: Lazy-load with blur-up placeholder

---

## Phase 1: R Data Extraction & Heatmap Generation

### Script: `generate_distribution_heatmaps.R`

**Location**: `shipley_checks/src/Stage_4/Phase_10_distribution/`

**Dependencies**:
```r
library(arrow)
library(terra)
library(ggplot2)
library(sf)
library(rnaturalearth)
library(smoothr)  # For density smoothing
```

### Step 1: Load Occurrence Data

```r
# Load GBIF occurrences for encyclopedia species
library(arrow)
library(dplyr)

# Encyclopedia species list
encyclopedia <- read_parquet(
"shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
) %>% select(wfo_taxon_id) %>% distinct()

# GBIF occurrences
occurrences <- read_parquet("data/gbif/occurrence_plantae_wfo.parquet") %>%
  filter(wfo_taxon_id %in% encyclopedia$wfo_taxon_id) %>%
  filter(!is.na(decimalLatitude), !is.na(decimalLongitude)) %>%
  select(wfo_taxon_id, decimalLatitude, decimalLongitude)
```

### Step 2: Generate Kernel Density Heatmap

```r
library(ggplot2)
library(rnaturalearth)
library(sf)

# Base map (land silhouette only)
world <- ne_countries(scale = "medium", returnclass = "sf")

# Color palette (Apple-inspired)
ocean_color <- "#1a1a2e"
land_color <- "#2d2d3a"
heat_low <- "#064e3b"    # Dark emerald (sparse)
heat_high <- "#34d399"   # Bright emerald (dense)

generate_heatmap <- function(species_id, points_df, output_dir) {

  species_points <- points_df %>%
    filter(wfo_taxon_id == species_id)

  if (nrow(species_points) < 5) {
    return(NULL)  # Skip species with too few points
  }

  p <- ggplot() +
    # Ocean background
    theme_void() +
    theme(
      plot.background = element_rect(fill = ocean_color, color = NA),
      panel.background = element_rect(fill = ocean_color, color = NA)
    ) +
    # Land silhouette
    geom_sf(data = world, fill = land_color, color = NA) +
    # Density heatmap layer
    stat_density_2d(
      data = species_points,
      aes(x = decimalLongitude, y = decimalLatitude, fill = after_stat(level)),
      geom = "polygon",
      alpha = 0.7,
      bins = 10
    ) +
    scale_fill_gradient(low = heat_low, high = heat_high, guide = "none") +
    # Map bounds
    coord_sf(
      xlim = c(-180, 180),
      ylim = c(-60, 85),  # Exclude Antarctica
      expand = FALSE
    )

  # Save as WebP
  output_path <- file.path(output_dir, paste0(species_id, ".webp"))
  ggsave(
    output_path,
    plot = p,
    width = 9.6,
    height = 4.8,
    dpi = 100,
    device = "png"  # Convert to WebP post-process
  )

  return(output_path)
}
```

### Step 3: Batch Processing

```r
library(parallel)
library(pbapply)

output_dir <- "shipley_checks/stage4/distribution_maps"
dir.create(output_dir, showWarnings = FALSE)

species_list <- unique(occurrences$wfo_taxon_id)

# Parallel processing (use 8 cores)
cl <- makeCluster(8)
clusterExport(cl, c("occurrences", "world", "generate_heatmap",
                     "ocean_color", "land_color", "heat_low", "heat_high"))
clusterEvalQ(cl, {
  library(ggplot2)
  library(sf)
  library(dplyr)
})

results <- pblapply(species_list, function(sp) {
  generate_heatmap(sp, occurrences, output_dir)
}, cl = cl)

stopCluster(cl)
```

### Step 4: Convert PNG to WebP

```bash
# Post-process with cwebp for optimal compression
cd shipley_checks/stage4/distribution_maps

for f in *.png; do
  cwebp -q 80 "$f" -o "${f%.png}.webp"
  rm "$f"
done
```

---

## Phase 2: Upload to R2 CDN

```bash
# Sync to R2 bucket under /maps/ prefix
rclone sync shipley_checks/stage4/distribution_maps/ \
  r2:plantphotos/maps/ \
  --transfers 32 \
  --progress
```

**URL pattern**: `https://photos.olier.ai/maps/wfo-0000615437.webp`

---

## Phase 3: Frontend Integration

### Component: `DistributionMap.astro`

**Location**: `plantguide-frontend/src/components/encyclopedia/`

```astro
---
interface Props {
  wfoId: string;
  scientificName: string;
}

const { wfoId, scientificName } = Astro.props;
const mapUrl = `https://photos.olier.ai/maps/${wfoId}.webp`;
---

<div class="distribution-map-container">
  <img
    src={mapUrl}
    alt={`Global distribution of ${scientificName}`}
    class="distribution-map"
    loading="eager"
    decoding="async"
    onerror="this.style.display='none'"
  />
</div>

<style>
  .distribution-map-container {
    border-radius: 1rem;
    overflow: hidden;
    background: #1a1a2e;
    margin-bottom: 1.5rem;
  }

  .distribution-map {
    width: 100%;
    height: auto;
    display: block;
  }
</style>
```

### Integration in S2-Requirements.astro

```astro
<!-- Add after section header, before Light card -->
<h2 class="text-4xl md:text-5xl font-light text-primary px-2">In the Wild</h2>

<!-- Distribution Map Hero -->
<DistributionMap wfoId={wfoId} scientificName={scientificName} />

<!-- Light Card continues below -->
{data.light && (
  ...
)}
```

---

## Performance Budget

| Component | Size | Notes |
|-----------|------|-------|
| Heatmap WebP | 12-20KB | Per species, CDN cached |
| First paint | <100ms | Image eager-loaded |
| Total storage | ~187MB | 11,711 × 16KB avg |

---

## Implementation Phases

### Phase 1: R Pipeline (4 hours)
- [ ] Create `shipley_checks/src/Stage_4/Phase_10_distribution/`
- [ ] Write `generate_distribution_heatmaps.R`
- [ ] Test on 100 species sample
- [ ] Run full batch (11,711 species, ~2-3 hours)
- [ ] Convert to WebP

### Phase 2: R2 Upload (30 min)
- [ ] Sync to `photos.olier.ai/maps/`
- [ ] Verify CDN caching headers
- [ ] Test sample URLs

### Phase 3: Frontend (1 hour)
- [ ] Create `DistributionMap.astro`
- [ ] Integrate into S2-Requirements
- [ ] Add error handling (missing maps)
- [ ] Test responsive sizing

### Phase 4: Polish (30 min)
- [ ] Verify all 11,711 maps render
- [ ] Add subtle border/shadow
- [ ] Caption: "Distribution based on GBIF occurrence records"

---

## Alternative: Bandwidth Optimization

If 187MB storage is a concern, consider:

1. **On-demand generation**: Generate maps server-side on first request, cache permanently
2. **Lower resolution**: 480×240 (~4KB per image)
3. **SVG with blur filter**: Vector paths + CSS blur (more complex)

Current plan uses pre-generation for simplicity and guaranteed instant loading.

---

## Data Source Attribution

```
Distribution data: GBIF.org (2024) GBIF Occurrence Download
https://doi.org/10.15468/dl.xxxxxx
```

Add to page footer citations.
