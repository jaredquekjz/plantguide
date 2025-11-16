#!/usr/bin/env Rscript
#' Generate Comprehensive Functional Categories for Organism Classification
#'
#' Creates a curated list of BROAD, DISTINCT functional categories
#' for vector-based classification. Avoids overlapping subcategories
#' to facilitate clear semantic matching.
#'
#' Output:
#'   - data/taxonomy/functional_categories.parquet
#'
#' Author: Claude Code
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Generating Functional Categories\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

OUTPUT_FILE <- "/home/olier/ellenberg/data/taxonomy/functional_categories.parquet"

# ============================================================================
# Category Generation
# ============================================================================

cat("Generating functional categories...\n\n")

# Create comprehensive category list with BROAD, DISTINCT categories
# Avoid overlapping subcategories (e.g., just "bees", not 10 types of bees)
functional_categories <- tribble(
  ~category, ~kingdom, ~functional_group,

  # ==========================================================================
  # INSECTS - POLLINATORS
  # ==========================================================================
  "bees", "Animalia", "pollinator",
  "butterflies", "Animalia", "pollinator",
  "moths", "Animalia", "pollinator",
  "hoverflies", "Animalia", "pollinator",
  "flies", "Animalia", "pollinator",

  # ==========================================================================
  # INSECTS - HERBIVORES
  # ==========================================================================
  "aphids", "Animalia", "herbivore",
  "caterpillars", "Animalia", "herbivore",
  "beetles", "Animalia", "herbivore",
  "weevils", "Animalia", "herbivore",
  "leafhoppers", "Animalia", "herbivore",
  "scale insects", "Animalia", "herbivore",
  "thrips", "Animalia", "herbivore",
  "sawflies", "Animalia", "herbivore",
  "grasshoppers", "Animalia", "herbivore",
  "locusts", "Animalia", "herbivore",
  "katydids", "Animalia", "herbivore",
  "crickets", "Animalia", "herbivore",

  # ==========================================================================
  # INSECTS - PREDATORS
  # ==========================================================================
  "ladybugs", "Animalia", "predator",
  "lacewings", "Animalia", "predator",
  "ground beetles", "Animalia", "predator",
  "assassin bugs", "Animalia", "predator",
  "dragonflies", "Animalia", "predator",
  "damselflies", "Animalia", "predator",
  "mantises", "Animalia", "predator",

  # ==========================================================================
  # INSECTS - DECOMPOSERS
  # ==========================================================================
  "termites", "Animalia", "decomposer",
  "dung beetles", "Animalia", "decomposer",
  "carrion beetles", "Animalia", "decomposer",

  # ==========================================================================
  # INSECTS - OTHER
  # ==========================================================================
  "ants", "Animalia", "other_insect",
  "wasps", "Animalia", "other_insect",
  "cicadas", "Animalia", "other_insect",
  "mayflies", "Animalia", "other_insect",
  "caddisflies", "Animalia", "other_insect",
  "stoneflies", "Animalia", "other_insect",
  "earwigs", "Animalia", "other_insect",
  "cockroaches", "Animalia", "other_insect",
  "stick insects", "Animalia", "other_insect",

  # ==========================================================================
  # BIRDS
  # ==========================================================================
  "songbirds", "Animalia", "bird",
  "warblers", "Animalia", "bird",
  "sparrows", "Animalia", "bird",
  "finches", "Animalia", "bird",
  "thrushes", "Animalia", "bird",
  "wrens", "Animalia", "bird",
  "chickadees", "Animalia", "bird",
  "nuthatches", "Animalia", "bird",
  "vireos", "Animalia", "bird",
  "tanagers", "Animalia", "bird",

  "raptors", "Animalia", "bird",
  "hawks", "Animalia", "bird",
  "eagles", "Animalia", "bird",
  "owls", "Animalia", "bird",
  "falcons", "Animalia", "bird",

  "waterfowl", "Animalia", "bird",
  "ducks", "Animalia", "bird",
  "geese", "Animalia", "bird",
  "swans", "Animalia", "bird",

  "woodpeckers", "Animalia", "bird",
  "hummingbirds", "Animalia", "bird",
  "swifts", "Animalia", "bird",
  "swallows", "Animalia", "bird",
  "corvids", "Animalia", "bird",
  "crows", "Animalia", "bird",
  "ravens", "Animalia", "bird",
  "jays", "Animalia", "bird",

  # ==========================================================================
  # MAMMALS
  # ==========================================================================
  "bats", "Animalia", "mammal",
  "microbats", "Animalia", "mammal",
  "megabats", "Animalia", "mammal",

  "rodents", "Animalia", "mammal",
  "mice", "Animalia", "mammal",
  "rats", "Animalia", "mammal",
  "voles", "Animalia", "mammal",
  "squirrels", "Animalia", "mammal",
  "chipmunks", "Animalia", "mammal",
  "gophers", "Animalia", "mammal",

  "rabbits", "Animalia", "mammal",
  "hares", "Animalia", "mammal",
  "deer", "Animalia", "mammal",
  "foxes", "Animalia", "mammal",
  "badgers", "Animalia", "mammal",
  "weasels", "Animalia", "mammal",
  "minks", "Animalia", "mammal",
  "shrews", "Animalia", "mammal",
  "hedgehogs", "Animalia", "mammal",

  # ==========================================================================
  # REPTILES & AMPHIBIANS
  # ==========================================================================
  "lizards", "Animalia", "reptile",
  "geckos", "Animalia", "reptile",
  "skinks", "Animalia", "reptile",
  "iguanas", "Animalia", "reptile",
  "anoles", "Animalia", "reptile",

  "snakes", "Animalia", "reptile",
  "vipers", "Animalia", "reptile",
  "colubrids", "Animalia", "reptile",

  "turtles", "Animalia", "reptile",
  "tortoises", "Animalia", "reptile",

  "frogs", "Animalia", "amphibian",
  "toads", "Animalia", "amphibian",
  "treefrogs", "Animalia", "amphibian",
  "newts", "Animalia", "amphibian",
  "salamanders", "Animalia", "amphibian",

  # ==========================================================================
  # ARACHNIDS & MYRIAPODS
  # ==========================================================================
  "spiders", "Animalia", "arachnid",
  "orb weavers", "Animalia", "arachnid",
  "jumping spiders", "Animalia", "arachnid",
  "wolf spiders", "Animalia", "arachnid",
  "tarantulas", "Animalia", "arachnid",
  "crab spiders", "Animalia", "arachnid",

  "ticks", "Animalia", "arachnid",
  "mites", "Animalia", "arachnid",
  "scorpions", "Animalia", "arachnid",
  "harvestmen", "Animalia", "arachnid",

  "centipedes", "Animalia", "myriapod",
  "millipedes", "Animalia", "myriapod",

  # ==========================================================================
  # MOLLUSKS & ANNELIDS
  # ==========================================================================
  "snails", "Animalia", "mollusk",
  "slugs", "Animalia", "mollusk",

  "earthworms", "Animalia", "annelid",

  # ==========================================================================
  # PLANTS - TREES
  # ==========================================================================
  "oaks", "Plantae", "tree",
  "maples", "Plantae", "tree",
  "birches", "Plantae", "tree",
  "willows", "Plantae", "tree",
  "poplars", "Plantae", "tree",
  "ashes", "Plantae", "tree",
  "elms", "Plantae", "tree",
  "beeches", "Plantae", "tree",
  "chestnuts", "Plantae", "tree",
  "walnuts", "Plantae", "tree",
  "hickories", "Plantae", "tree",
  "lindens", "Plantae", "tree",
  "sycamores", "Plantae", "tree",
  "planes", "Plantae", "tree",
  "tulip trees", "Plantae", "tree",
  "magnolias", "Plantae", "tree",

  "pines", "Plantae", "tree",
  "spruces", "Plantae", "tree",
  "firs", "Plantae", "tree",
  "cedars", "Plantae", "tree",
  "junipers", "Plantae", "tree",
  "cypresses", "Plantae", "tree",
  "hemlocks", "Plantae", "tree",
  "larches", "Plantae", "tree",
  "yews", "Plantae", "tree",
  "redwoods", "Plantae", "tree",
  "sequoias", "Plantae", "tree",

  # ==========================================================================
  # PLANTS - SHRUBS
  # ==========================================================================
  "roses", "Plantae", "shrub",
  "hollies", "Plantae", "shrub",
  "viburnums", "Plantae", "shrub",
  "rhododendrons", "Plantae", "shrub",
  "azaleas", "Plantae", "shrub",
  "heaths", "Plantae", "shrub",
  "heathers", "Plantae", "shrub",
  "blueberries", "Plantae", "shrub",
  "huckleberries", "Plantae", "shrub",
  "cranberries", "Plantae", "shrub",
  "dogwoods", "Plantae", "shrub",
  "sumacs", "Plantae", "shrub",
  "elderberries", "Plantae", "shrub",
  "boxwoods", "Plantae", "shrub",
  "lilacs", "Plantae", "shrub",
  "hydrangeas", "Plantae", "shrub",
  "spireas", "Plantae", "shrub",
  "barberries", "Plantae", "shrub",
  "currants", "Plantae", "shrub",

  # ==========================================================================
  # PLANTS - HERBACEOUS
  # ==========================================================================
  "grasses", "Plantae", "herbaceous",
  "sedges", "Plantae", "herbaceous",
  "rushes", "Plantae", "herbaceous",
  "wildflowers", "Plantae", "herbaceous",
  "asters", "Plantae", "herbaceous",
  "goldenrods", "Plantae", "herbaceous",
  "sunflowers", "Plantae", "herbaceous",
  "coneflowers", "Plantae", "herbaceous",
  "black-eyed susans", "Plantae", "herbaceous",
  "daisies", "Plantae", "herbaceous",
  "lupines", "Plantae", "herbaceous",
  "clovers", "Plantae", "herbaceous",
  "vetches", "Plantae", "herbaceous",
  "milkweeds", "Plantae", "herbaceous",
  "thistles", "Plantae", "herbaceous",
  "dandelions", "Plantae", "herbaceous",
  "plantains", "Plantae", "herbaceous",
  "buttercups", "Plantae", "herbaceous",
  "violets", "Plantae", "herbaceous",
  "geraniums", "Plantae", "herbaceous",
  "phlox", "Plantae", "herbaceous",
  "primroses", "Plantae", "herbaceous",
  "irises", "Plantae", "herbaceous",
  "lilies", "Plantae", "herbaceous",

  # ==========================================================================
  # PLANTS - FERNS & VINES
  # ==========================================================================
  "ferns", "Plantae", "fern",
  "horsetails", "Plantae", "fern",
  "clubmosses", "Plantae", "fern",

  "grapes", "Plantae", "vine",
  "ivies", "Plantae", "vine",
  "clematis", "Plantae", "vine",
  "hops", "Plantae", "vine",
  "morning glories", "Plantae", "vine",
  "bindweeds", "Plantae", "vine",

  # ==========================================================================
  # PLANTS - FRUITS & VEGETABLES
  # ==========================================================================
  "apples", "Plantae", "fruit",
  "pears", "Plantae", "fruit",
  "cherries", "Plantae", "fruit",
  "plums", "Plantae", "fruit",
  "peaches", "Plantae", "fruit",
  "apricots", "Plantae", "fruit",
  "crabapples", "Plantae", "fruit",
  "mulberries", "Plantae", "fruit",
  "strawberries", "Plantae", "fruit",
  "blackberries", "Plantae", "fruit",
  "raspberries", "Plantae", "fruit",

  "tomatoes", "Plantae", "vegetable",
  "peppers", "Plantae", "vegetable",
  "eggplants", "Plantae", "vegetable",
  "squashes", "Plantae", "vegetable",
  "pumpkins", "Plantae", "vegetable",
  "melons", "Plantae", "vegetable",
  "beans", "Plantae", "vegetable",
  "peas", "Plantae", "vegetable",
  "lettuce", "Plantae", "vegetable",
  "spinach", "Plantae", "vegetable",
  "cabbage", "Plantae", "vegetable",
  "kale", "Plantae", "vegetable",
  "onions", "Plantae", "vegetable",
  "garlic", "Plantae", "vegetable",

  # ==========================================================================
  # PLANTS - HERBS
  # ==========================================================================
  "mints", "Plantae", "herb",
  "sages", "Plantae", "herb",
  "thymes", "Plantae", "herb",
  "oreganos", "Plantae", "herb",
  "basils", "Plantae", "herb",
  "rosemarys", "Plantae", "herb",
  "lavenders", "Plantae", "herb",

  # ==========================================================================
  # PLANTS - AQUATIC & OTHER
  # ==========================================================================
  "water lilies", "Plantae", "aquatic",
  "lotuses", "Plantae", "aquatic",
  "cattails", "Plantae", "aquatic",
  "bulrushes", "Plantae", "aquatic",
  "pondweeds", "Plantae", "aquatic",
  "milfoils", "Plantae", "aquatic",
  "duckweeds", "Plantae", "aquatic",
  "hyacinths", "Plantae", "aquatic",

  "mosses", "Plantae", "bryophyte",
  "sphagnum", "Plantae", "bryophyte",
  "liverworts", "Plantae", "bryophyte",

  "lichens", "Plantae", "lichen",
  "algae", "Plantae", "algae",
  "seaweeds", "Plantae", "algae",

  "cacti", "Plantae", "succulent",
  "succulents", "Plantae", "succulent",

  "palms", "Plantae", "palm",
  "bamboos", "Plantae", "grass"
)

# ============================================================================
# Validation
# ============================================================================

cat("Validating categories...\n")

# Check for duplicates
dups <- functional_categories %>%
  count(category) %>%
  filter(n > 1)

if (nrow(dups) > 0) {
  cat("WARNING: Duplicate categories found:\n")
  print(as.data.frame(dups))
  stop("Please remove duplicate categories before proceeding.")
}

cat("  ✓ No duplicate categories\n\n")

# ============================================================================
# Summary Statistics
# ============================================================================

cat("Category breakdown:\n")

summary_stats <- functional_categories %>%
  group_by(kingdom, functional_group) %>%
  summarise(count = n(), .groups = "drop") %>%
  arrange(kingdom, desc(count))

print(as.data.frame(summary_stats))

cat("\n")
cat(sprintf("Total categories: %d\n", nrow(functional_categories)))
cat(sprintf("  Animalia: %d\n", sum(functional_categories$kingdom == "Animalia")))
cat(sprintf("  Plantae: %d\n", sum(functional_categories$kingdom == "Plantae")))

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(functional_categories, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d functional categories\n",
            nrow(functional_categories)))

# ============================================================================
# Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n", sep = "")
cat(sprintf("Total categories: %d\n", nrow(functional_categories)))
cat(sprintf("Animalia: %d\n", sum(functional_categories$kingdom == "Animalia")))
cat(sprintf("Plantae: %d\n", sum(functional_categories$kingdom == "Plantae")))
cat("\nOutput file: ", OUTPUT_FILE, "\n", sep = "")
cat(rep("=", 80), "\n\n", sep = "")
