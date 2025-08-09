#!/usr/bin/env Rscript
# Apply wood density proxies based on growth form and other traits

library(data.table)

cat("======================================================\n")
cat("APPLYING WOOD DENSITY PROXIES FOR EIVE SPECIES\n")
cat("======================================================\n\n")

# Load data
eive_data <- readRDS("data/output/eive_all_traits_by_id.rds")
species_traits <- eive_data[!is.na(TraitID) & TraitID != ""]

# Extract key traits with their ACTUAL values
cat("Extracting trait values...\n")

# Wood density (direct measurements)
wood_direct <- species_traits[TraitID == 4, .(
  AccSpeciesID, AccSpeciesName, 
  wood_density = as.numeric(StdValue)
)][!is.na(wood_density)]
wood_direct <- wood_direct[, .(wood_density = mean(wood_density)), by = AccSpeciesID]

# Growth form (text categories)
growth_form <- species_traits[TraitID == 42, .(
  AccSpeciesID, AccSpeciesName,
  growth_form = tolower(trimws(OrigValueStr))
)][nzchar(growth_form)]
growth_form <- unique(growth_form[, .(AccSpeciesID, growth_form)])

# Woodiness
woodiness <- species_traits[TraitID == 38, .(
  AccSpeciesID, AccSpeciesName,
  woodiness = tolower(trimws(OrigValueStr))
)][nzchar(woodiness)]
woodiness <- unique(woodiness[, .(AccSpeciesID, woodiness)])

# Leaf type
leaf_type <- species_traits[TraitID == 43, .(
  AccSpeciesID, AccSpeciesName,
  leaf_type = tolower(trimws(OrigValueStr))
)][nzchar(leaf_type)]
leaf_type <- unique(leaf_type[, .(AccSpeciesID, leaf_type)])

cat(sprintf("Direct wood density: %d species\n", nrow(wood_direct)))
cat(sprintf("Growth form data: %d species\n", nrow(growth_form)))
cat(sprintf("Woodiness data: %d species\n", nrow(woodiness)))
cat(sprintf("Leaf type data: %d species\n", nrow(leaf_type)))

# Analyze growth form categories
cat("\n======================================================\n")
cat("GROWTH FORM CATEGORIES\n")
cat("======================================================\n")
gf_table <- table(growth_form$growth_form)
gf_sorted <- sort(gf_table, decreasing = TRUE)
cat("Top 30 growth forms:\n")
for(i in 1:min(30, length(gf_sorted))) {
  cat(sprintf("  %4d: %s\n", gf_sorted[i], names(gf_sorted)[i]))
}

# Map growth forms to wood density defaults
cat("\n======================================================\n")
cat("MAPPING GROWTH FORMS TO WOOD DENSITY\n")
cat("======================================================\n")

# Create mapping function
map_growth_form_to_density <- function(gf) {
  gf <- tolower(trimws(gf))
  
  # Trees (highest density)
  if(grepl("tree|arbre", gf)) return(0.65)
  if(grepl("phanerophyte", gf)) return(0.65)
  if(gf %in% c("p", "ph", "phan", "mp", "megaphanerophyte")) return(0.65)
  
  # Shrubs (medium-high density)
  if(grepl("shrub|bush|nanophanerophyte", gf)) return(0.55)
  if(gf %in% c("np", "n", "nanophan", "ch", "chamaephyte")) return(0.55)
  if(grepl("dwarf", gf)) return(0.55)
  
  # Woody herbs/subshrubs (medium density)
  if(grepl("suffrutescent|subshrub|woody.*herb", gf)) return(0.45)
  
  # Herbaceous (low density)
  if(grepl("herb|forb|grass|graminoid", gf)) return(0.35)
  if(gf %in% c("h", "hemicryptophyte", "g", "geophyte", "t", "therophyte")) return(0.35)
  if(grepl("annual|biennial|perennial.*herb", gf)) return(0.35)
  
  # Aquatic/succulent (very low density)
  if(grepl("aquatic|hydrophyte|floating", gf)) return(0.25)
  if(grepl("succulent|cactus", gf)) return(0.30)
  
  # Climbers/vines (variable, use medium)
  if(grepl("climb|vine|liana", gf)) return(0.50)
  
  # Default for unknown
  return(0.45)
}

# Apply mapping
growth_form[, wood_density_proxy := sapply(growth_form, map_growth_form_to_density)]

# Similarly for woodiness
map_woodiness_to_density <- function(w) {
  w <- tolower(trimws(w))
  if(grepl("woody|wood", w)) return(0.55)
  if(grepl("non.?woody|herbaceous", w)) return(0.35)
  if(grepl("semi.?woody", w)) return(0.45)
  return(0.45)
}

woodiness[, wood_density_proxy := sapply(woodiness, map_woodiness_to_density)]

# Combine all sources
cat("\nCombining wood density sources...\n")

# Start with all species
all_species <- unique(species_traits[, .(AccSpeciesID, AccSpeciesName)])

# Add direct measurements
all_species <- merge(all_species, wood_direct, by = "AccSpeciesID", all.x = TRUE)

# Add growth form proxies
gf_proxy <- growth_form[, .(AccSpeciesID, gf_proxy = wood_density_proxy)]
all_species <- merge(all_species, gf_proxy, by = "AccSpeciesID", all.x = TRUE)

# Add woodiness proxies
wood_proxy <- woodiness[, .(AccSpeciesID, wood_proxy = wood_density_proxy)]
all_species <- merge(all_species, wood_proxy, by = "AccSpeciesID", all.x = TRUE)

# Combine: use direct > growth form > woodiness > default
all_species[, final_wood_density := ifelse(!is.na(wood_density), wood_density,
                                           ifelse(!is.na(gf_proxy), gf_proxy,
                                                 ifelse(!is.na(wood_proxy), wood_proxy,
                                                       0.45)))]  # Global default

all_species[, source := ifelse(!is.na(wood_density), "measured",
                               ifelse(!is.na(gf_proxy), "growth_form",
                                     ifelse(!is.na(wood_proxy), "woodiness",
                                           "default")))]

# Summary
cat("\n======================================================\n")
cat("WOOD DENSITY COVERAGE SUMMARY\n")
cat("======================================================\n")

coverage_table <- all_species[, .N, by = source]
setorder(coverage_table, -N)
total <- nrow(all_species)

for(i in 1:nrow(coverage_table)) {
  cat(sprintf("%15s: %5d species (%5.1f%%)\n", 
              coverage_table$source[i], 
              coverage_table$N[i],
              100 * coverage_table$N[i] / total))
}

cat(sprintf("\nTOTAL SPECIES: %d\n", total))
cat(sprintf("Species with any wood density value: %d (100%%)\n", total))

# Save results
output_file <- "data/output/eive_wood_density_complete.csv"
fwrite(all_species[, .(AccSpeciesID, AccSpeciesName, wood_density = final_wood_density, source)], 
       output_file)
cat(sprintf("\nComplete wood density dataset saved to: %s\n", output_file))

# Statistics
cat("\n======================================================\n")
cat("WOOD DENSITY STATISTICS BY SOURCE\n")
cat("======================================================\n")

stats <- all_species[, .(
  mean = mean(final_wood_density),
  sd = sd(final_wood_density),
  min = min(final_wood_density),
  max = max(final_wood_density),
  n = .N
), by = source]

print(stats)