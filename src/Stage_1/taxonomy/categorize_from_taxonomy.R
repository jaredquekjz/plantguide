#!/usr/bin/env Rscript

#' Categorize organisms using taxonomy database
#' Priority 1: Common name matching
#' Priority 2: Family-based categorization
#' Priority 3: Return NA (to be handled by genus patterns)

library(arrow)
library(dplyr)

# Load enriched taxonomy data (will use progress for now, final when complete)
taxonomy_file <- if(file.exists("data/taxonomy/organism_taxonomy_enriched.parquet")) {
  "data/taxonomy/organism_taxonomy_enriched.parquet"
} else {
  "data/taxonomy/taxonomy_enrichment_progress.parquet"
}

cat(sprintf("Loading taxonomy from: %s\n", taxonomy_file))
taxonomy_db <- arrow::read_parquet(taxonomy_file)

cat(sprintf("Loaded %d organisms\n", nrow(taxonomy_db)))
cat(sprintf("  With common names: %d (%.1f%%)\n",
            sum(!is.na(taxonomy_db$common_names)),
            100 * sum(!is.na(taxonomy_db$common_names)) / nrow(taxonomy_db)))
cat(sprintf("  With family: %d (%.1f%%)\n\n",
            sum(!is.na(taxonomy_db$family)),
            100 * sum(!is.na(taxonomy_db$family)) / nrow(taxonomy_db)))

#' Priority 1: Common name → Functional category
#' Based on keywords in common names
categorize_by_common_name <- function(common_names) {
  if (is.na(common_names)) return(NA)

  common_lower <- tolower(common_names)

  # Exact matches first (most specific)
  if (grepl("\\bhoneybee\\b|\\bhoney bee\\b", common_lower)) return("Honey Bees")
  if (grepl("\\bbumblebee\\b|\\bbumble bee\\b", common_lower)) return("Bumblebees")

  # Partial matches (broader)
  if (grepl("\\bmoth\\b|\\bmoths\\b", common_lower)) return("Moths")
  if (grepl("\\bbutterfly\\b|\\bbutterflies\\b|\\bswallowtail\\b", common_lower)) return("Butterflies")
  if (grepl("\\bbee\\b|\\bbees\\b", common_lower)) return("Solitary Bees")  # After honey/bumble

  if (grepl("\\bhoverfly\\b|\\bhover fly\\b|\\bflower fly\\b", common_lower)) return("Hoverflies")
  if (grepl("\\bmosquito\\b|\\bmosquitoes\\b", common_lower)) return("Flies")
  if (grepl("\\bfly\\b|\\bflies\\b", common_lower)) return("Flies")

  if (grepl("\\bwasp\\b|\\bwasps\\b", common_lower)) return("Wasps")
  if (grepl("\\bant\\b|\\bants\\b", common_lower)) return("Ants")

  if (grepl("\\baphid\\b|\\baphids\\b", common_lower)) return("Aphids")
  if (grepl("\\bscale\\b.*\\binsect", common_lower)) return("Scale Insects")
  if (grepl("\\bmite\\b|\\bmites\\b", common_lower)) return("Mites")
  if (grepl("\\bwhitefly\\b|\\bwhite fly\\b", common_lower)) return("Whiteflies")
  if (grepl("\\bleafhopper\\b|\\btreehopper\\b", common_lower)) return("Leafhoppers")
  if (grepl("\\bthrip\\b|\\bthrips\\b", common_lower)) return("Thrips")

  if (grepl("\\bweevil\\b|\\bweevils\\b", common_lower)) return("Weevils")
  if (grepl("\\bladybug\\b|\\bladybird\\b|\\blady beetle\\b", common_lower)) return("Ladybugs")
  if (grepl("\\bbeetle\\b|\\bbeetles\\b", common_lower)) return("Beetles")

  if (grepl("\\bspider\\b|\\bspiders\\b", common_lower)) return("Spiders")
  if (grepl("\\blacewing\\b|\\blacewings\\b", common_lower)) return("Lacewings")

  if (grepl("\\bbat\\b|\\bbats\\b", common_lower)) return("Bats")
  if (grepl("\\bbird\\b|\\bbirds\\b", common_lower)) return("Birds")

  return(NA)  # No match
}

#' Priority 2: Family → Functional category
#' Pre-defined family mappings based on taxonomic knowledge
categorize_by_family <- function(family) {
  if (is.na(family)) return(NA)

  # Lepidoptera - Moths
  moth_families <- c("Noctuidae", "Geometridae", "Erebidae", "Tortricidae", "Sphingidae",
                     "Pyralidae", "Crambidae", "Gelechiidae", "Adelidae", "Saturniidae",
                     "Lasiocampidae", "Notodontidae", "Lymantriidae", "Arctiidae", "Zygaenidae",
                     "Sesiidae", "Limacodidae", "Gracillariidae", "Nepticulidae", "Coleophoridae",
                     "Depressariidae", "Pterophoridae")

  # Lepidoptera - Butterflies
  butterfly_families <- c("Nymphalidae", "Lycaenidae", "Pieridae", "Papilionidae",
                          "Hesperiidae", "Riodinidae")

  # Hymenoptera - Bees
  bee_families <- c("Apidae", "Halictidae", "Andrenidae", "Megachilidae", "Colletidae",
                    "Melittidae", "Stenotritidae")

  # Hymenoptera - Wasps
  wasp_families <- c("Vespidae", "Sphecidae", "Crabronidae", "Pompilidae", "Tiphiidae",
                     "Scoliidae", "Mutillidae")

  # Hymenoptera - Parasitoids
  parasitoid_families <- c("Braconidae", "Ichneumonidae", "Chalcididae", "Pteromalidae",
                           "Eulophidae", "Encyrtidae", "Aphelinidae", "Trichogrammatidae")

  # Hymenoptera - Sawflies
  sawfly_families <- c("Tenthredinidae", "Argidae", "Cimbicidae", "Diprionidae")

  # Other Hymenoptera
  if (family == "Formicidae") return("Ants")
  if (family %in% c("Cynipidae", "Figitidae")) return("Gall Wasps")

  # Diptera
  if (family == "Syrphidae") return("Hoverflies")
  if (family %in% c("Culicidae", "Ceratopogonidae")) return("Flies")
  if (family %in% c("Muscidae", "Tachinidae", "Calliphoridae", "Anthomyiidae",
                    "Sarcophagidae", "Fanniidae")) return("Flies")
  if (family == "Bombyliidae") return("Flies")
  if (family %in% c("Agromyzidae", "Cecidomyiidae")) return("Leaf Miners")
  if (family == "Tephritidae") return("Fruit Flies")
  if (family %in% c("Chloropidae", "Drosophilidae")) return("Flies")

  # Coleoptera
  if (family == "Curculionidae") return("Weevils")
  if (family %in% c("Chrysomelidae", "Galerucidae")) return("Leaf Beetles")
  if (family == "Buprestidae") return("Beetles")
  if (family %in% c("Carabidae", "Cicindelidae")) return("Ground Beetles")
  if (family == "Staphylinidae") return("Rove Beetles")
  if (family == "Coccinellidae") return("Ladybugs")
  if (family == "Cantharidae") return("Soldier Beetles")
  if (family %in% c("Cerambycidae", "Scarabaeidae", "Elateridae")) return("Beetles")

  # Hemiptera - Herbivores
  if (family %in% c("Aphididae", "Lachnidae", "Pemphigidae", "Eriosomatidae")) return("Aphids")
  if (family %in% c("Diaspididae", "Coccidae", "Pseudococcidae")) return("Scale Insects")
  if (family %in% c("Psyllidae", "Triozidae")) return("Psyllids")
  if (family %in% c("Cicadellidae", "Delphacidae", "Cicadidae", "Membracidae")) return("Leafhoppers")
  if (family == "Aleyrodidae") return("Whiteflies")
  if (family %in% c("Miridae", "Pentatomidae", "Lygaeidae", "Coreidae",
                    "Alydidae", "Rhopalidae")) return("Plant Bugs")

  # Hemiptera - Predators
  if (family %in% c("Nabidae", "Anthocoridae", "Reduviidae")) return("Predatory Bugs")

  # Acari
  if (family %in% c("Eriophyidae", "Tetranychidae", "Tenuipalpidae")) return("Mites")

  # Thysanoptera
  if (family %in% c("Thripidae", "Phlaeothripidae")) return("Thrips")

  # Neuroptera
  if (family %in% c("Chrysopidae", "Hemerobiidae")) return("Lacewings")

  # Orthoptera
  if (family %in% c("Acrididae", "Tettigoniidae", "Gryllidae")) return("Grasshoppers & Crickets")

  # Araneae
  if (grepl("idae$", family)) {
    # Most spider families end in -idae, categorize as Spiders
    # But check it's actually order Araneae from taxonomy_db
    spider_check <- taxonomy_db %>% filter(family == !!family) %>% head(1)
    if (nrow(spider_check) > 0 && !is.na(spider_check$order) && spider_check$order == "Araneae") {
      return("Spiders")
    }
  }

  # Vertebrates
  if (family %in% c("Vespertilionidae", "Rhinolophidae", "Molossidae")) return("Bats")

  # Use broader categorizations based on family groupings
  if (family %in% moth_families) return("Moths")
  if (family %in% butterfly_families) return("Butterflies")
  if (family %in% bee_families) return("Solitary Bees")  # Will be refined by genus later
  if (family %in% wasp_families) return("Wasps")
  if (family %in% parasitoid_families) return("Parasitoid Wasps")
  if (family %in% sawfly_families) return("Sawflies")

  return(NA)  # No match
}

#' Main categorization function
#' Tries Priority 1, then Priority 2, returns NA if both fail
categorize_organism_taxonomy <- function(organism_name) {
  # Lookup organism in taxonomy database
  organism_data <- taxonomy_db %>% filter(organism_name == !!organism_name)

  if (nrow(organism_data) == 0) return(NA)

  # Priority 1: Common name
  category <- categorize_by_common_name(organism_data$common_names[1])
  if (!is.na(category)) {
    return(list(category = category, source = "common_name"))
  }

  # Priority 2: Family
  category <- categorize_by_family(organism_data$family[1])
  if (!is.na(category)) {
    return(list(category = category, source = "family"))
  }

  # Priority 3: Return NA (will use genus patterns)
  return(list(category = NA, source = "none"))
}

# Test categorization
cat("\n=== Testing categorization ===\n\n")
test_organisms <- c("Apis mellifera", "Aedes impiger", "Bombus terrestris",
                    "Papilio machaon", "Coccinella septempunctata")

for (org in test_organisms) {
  result <- categorize_organism_taxonomy(org)
  cat(sprintf("%-30s → %-20s (source: %s)\n", org,
              ifelse(is.na(result$category), "NOT FOUND", result$category),
              result$source))
}

cat("\n✓ Categorization functions ready\n")
