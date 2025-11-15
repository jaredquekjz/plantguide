#!/usr/bin/env Rscript
#' Generate Comprehensive Functional Categories for Vector Matching
#'
#' Creates a curated list of 200-500 functional categories based on easily
#' recognizable ecological/functional groups. These categories serve as
#' classification targets for the vector-based Pipeline B.
#'
#' Output: data/taxonomy/functional_categories.parquet
#'
#' Author: Claude Code
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(tibble)
})

cat("=" , rep("=", 78), "\n", sep = "")
cat("Generating Comprehensive Functional Categories\n")
cat("=" , rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

DATA_DIR <- "/home/olier/ellenberg/data/taxonomy"
OUTPUT_FILE <- file.path(DATA_DIR, "functional_categories.parquet")

# ============================================================================
# Category Generation
# ============================================================================

cat("Generating functional categories...\n\n")

# Create comprehensive category list
functional_categories <- tribble(
  ~category, ~kingdom, ~functional_group,

  # ==========================================================================
  # INSECTS - POLLINATORS (~45 categories)
  # ==========================================================================
  "bees", "Animalia", "pollinator",
  "honeybees", "Animalia", "pollinator",
  "honey bees", "Animalia", "pollinator",
  "bumblebees", "Animalia", "pollinator",
  "bumble bees", "Animalia", "pollinator",
  "solitary bees", "Animalia", "pollinator",
  "mason bees", "Animalia", "pollinator",
  "carpenter bees", "Animalia", "pollinator",
  "leafcutter bees", "Animalia", "pollinator",
  "leafcutting bees", "Animalia", "pollinator",
  "mining bees", "Animalia", "pollinator",
  "digger bees", "Animalia", "pollinator",
  "sweat bees", "Animalia", "pollinator",
  "orchid bees", "Animalia", "pollinator",
  "cuckoo bees", "Animalia", "pollinator",

  "butterflies", "Animalia", "pollinator",
  "swallowtails", "Animalia", "pollinator",
  "swallowtail butterflies", "Animalia", "pollinator",
  "whites", "Animalia", "pollinator",
  "sulfurs", "Animalia", "pollinator",
  "blues", "Animalia", "pollinator",
  "hairstreaks", "Animalia", "pollinator",
  "coppers", "Animalia", "pollinator",
  "brush-footed butterflies", "Animalia", "pollinator",
  "admirals", "Animalia", "pollinator",
  "fritillaries", "Animalia", "pollinator",
  "monarchs", "Animalia", "pollinator",
  "skippers", "Animalia", "pollinator",

  "moths", "Animalia", "pollinator",
  "hawk moths", "Animalia", "pollinator",
  "sphinx moths", "Animalia", "pollinator",
  "silk moths", "Animalia", "pollinator",
  "tiger moths", "Animalia", "pollinator",
  "tussock moths", "Animalia", "pollinator",
  "owlet moths", "Animalia", "pollinator",
  "geometrid moths", "Animalia", "pollinator",
  "geometer moths", "Animalia", "pollinator",

  "hoverflies", "Animalia", "pollinator",
  "syrphid flies", "Animalia", "pollinator",
  "flower flies", "Animalia", "pollinator",
  "bee flies", "Animalia", "pollinator",
  "long-tongued flies", "Animalia", "pollinator",
  "tachinid flies", "Animalia", "pollinator",

  # ==========================================================================
  # INSECTS - HERBIVORES (~50 categories)
  # ==========================================================================
  "aphids", "Animalia", "herbivore",
  "greenflies", "Animalia", "herbivore",
  "blackflies", "Animalia", "herbivore",
  "woolly aphids", "Animalia", "herbivore",
  "root aphids", "Animalia", "herbivore",

  "caterpillars", "Animalia", "herbivore",
  "leafminers", "Animalia", "herbivore",
  "leaf miners", "Animalia", "herbivore",
  "leafrollers", "Animalia", "herbivore",
  "leaf rollers", "Animalia", "herbivore",
  "cutworms", "Animalia", "herbivore",
  "armyworms", "Animalia", "herbivore",
  "loopers", "Animalia", "herbivore",
  "inchworms", "Animalia", "herbivore",

  "beetles", "Animalia", "herbivore",
  "weevils", "Animalia", "herbivore",
  "leaf beetles", "Animalia", "herbivore",
  "flea beetles", "Animalia", "herbivore",
  "longhorn beetles", "Animalia", "herbivore",
  "long-horned beetles", "Animalia", "herbivore",
  "bark beetles", "Animalia", "herbivore",
  "ambrosia beetles", "Animalia", "herbivore",
  "cucumber beetles", "Animalia", "herbivore",
  "colorado potato beetles", "Animalia", "herbivore",
  "japanese beetles", "Animalia", "herbivore",
  "june beetles", "Animalia", "herbivore",
  "chafers", "Animalia", "herbivore",

  "leafhoppers", "Animalia", "herbivore",
  "planthoppers", "Animalia", "herbivore",
  "treehoppers", "Animalia", "herbivore",
  "sharpshooters", "Animalia", "herbivore",
  "spittlebugs", "Animalia", "herbivore",
  "froghoppers", "Animalia", "herbivore",

  "whiteflies", "Animalia", "herbivore",
  "scale insects", "Animalia", "herbivore",
  "mealybugs", "Animalia", "herbivore",
  "mealybug", "Animalia", "herbivore",
  "armored scales", "Animalia", "herbivore",
  "soft scales", "Animalia", "herbivore",

  "thrips", "Animalia", "herbivore",
  "sawflies", "Animalia", "herbivore",
  "leafcutter ants", "Animalia", "herbivore",
  "leaf-cutting ants", "Animalia", "herbivore",
  "tent caterpillars", "Animalia", "herbivore",
  "webworms", "Animalia", "herbivore",
  "bagworms", "Animalia", "herbivore",
  "gall wasps", "Animalia", "herbivore",
  "gall midges", "Animalia", "herbivore",

  # ==========================================================================
  # INSECTS - PREDATORS (~35 categories)
  # ==========================================================================
  "ladybugs", "Animalia", "predator",
  "lady beetles", "Animalia", "predator",
  "ladybirds", "Animalia", "predator",
  "ladybird beetles", "Animalia", "predator",

  "lacewings", "Animalia", "predator",
  "green lacewings", "Animalia", "predator",
  "brown lacewings", "Animalia", "predator",
  "antlions", "Animalia", "predator",

  "ground beetles", "Animalia", "predator",
  "carabid beetles", "Animalia", "predator",
  "rove beetles", "Animalia", "predator",
  "staphylinid beetles", "Animalia", "predator",
  "tiger beetles", "Animalia", "predator",
  "soldier beetles", "Animalia", "predator",
  "fireflies", "Animalia", "predator",
  "lightning bugs", "Animalia", "predator",

  "assassin bugs", "Animalia", "predator",
  "ambush bugs", "Animalia", "predator",
  "damsel bugs", "Animalia", "predator",
  "nabid bugs", "Animalia", "predator",
  "minute pirate bugs", "Animalia", "predator",
  "big-eyed bugs", "Animalia", "predator",
  "stink bugs", "Animalia", "predator",

  "parasitic wasps", "Animalia", "predator",
  "parasitoid wasps", "Animalia", "predator",
  "braconid wasps", "Animalia", "predator",
  "ichneumon wasps", "Animalia", "predator",
  "chalcid wasps", "Animalia", "predator",
  "trichogramma wasps", "Animalia", "predator",

  "robber flies", "Animalia", "predator",
  "hover fly larvae", "Animalia", "predator",
  "mantises", "Animalia", "predator",
  "praying mantises", "Animalia", "predator",
  "mantids", "Animalia", "predator",

  # ==========================================================================
  # INSECTS - DECOMPOSERS (~12 categories)
  # ==========================================================================
  "termites", "Animalia", "decomposer",
  "subterranean termites", "Animalia", "decomposer",
  "drywood termites", "Animalia", "decomposer",

  "dung beetles", "Animalia", "decomposer",
  "scarab beetles", "Animalia", "decomposer",
  "tumblebugs", "Animalia", "decomposer",

  "carrion beetles", "Animalia", "decomposer",
  "burying beetles", "Animalia", "decomposer",
  "sexton beetles", "Animalia", "decomposer",

  "springtails", "Animalia", "decomposer",
  "silverfish", "Animalia", "decomposer",
  "booklice", "Animalia", "decomposer",

  # ==========================================================================
  # INSECTS - OTHER FUNCTIONAL GROUPS (~35 categories)
  # ==========================================================================
  "ants", "Animalia", "other_insect",
  "carpenter ants", "Animalia", "other_insect",
  "fire ants", "Animalia", "other_insect",
  "harvester ants", "Animalia", "other_insect",

  "wasps", "Animalia", "other_insect",
  "yellowjackets", "Animalia", "other_insect",
  "paper wasps", "Animalia", "other_insect",
  "hornets", "Animalia", "other_insect",
  "mud daubers", "Animalia", "other_insect",
  "potter wasps", "Animalia", "other_insect",

  "crickets", "Animalia", "other_insect",
  "grasshoppers", "Animalia", "other_insect",
  "locusts", "Animalia", "other_insect",
  "katydids", "Animalia", "other_insect",
  "bush crickets", "Animalia", "other_insect",

  "cicadas", "Animalia", "other_insect",
  "periodical cicadas", "Animalia", "other_insect",

  "dragonflies", "Animalia", "other_insect",
  "damselflies", "Animalia", "other_insect",
  "mayflies", "Animalia", "other_insect",
  "caddisflies", "Animalia", "other_insect",
  "stoneflies", "Animalia", "other_insect",
  "dobsonflies", "Animalia", "other_insect",
  "alderflies", "Animalia", "other_insect",

  "earwigs", "Animalia", "other_insect",
  "cockroaches", "Animalia", "other_insect",
  "walkingsticks", "Animalia", "other_insect",
  "stick insects", "Animalia", "other_insect",

  "fleas", "Animalia", "other_insect",
  "lice", "Animalia", "other_insect",
  "true bugs", "Animalia", "other_insect",
  "water bugs", "Animalia", "other_insect",
  "water striders", "Animalia", "other_insect",

  # ==========================================================================
  # BIRDS (~25 categories)
  # ==========================================================================
  "songbirds", "Animalia", "bird",
  "warblers", "Animalia", "bird",
  "wood-warblers", "Animalia", "bird",
  "sparrows", "Animalia", "bird",
  "finches", "Animalia", "bird",
  "thrushes", "Animalia", "bird",
  "robins", "Animalia", "bird",
  "bluebirds", "Animalia", "bird",
  "wrens", "Animalia", "bird",
  "chickadees", "Animalia", "bird",
  "titmice", "Animalia", "bird",
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
  "magpies", "Animalia", "bird",

  # ==========================================================================
  # MAMMALS (~18 categories)
  # ==========================================================================
  "bats", "Animalia", "mammal",
  "microbats", "Animalia", "mammal",
  "megabats", "Animalia", "mammal",
  "fruit bats", "Animalia", "mammal",

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
  "moles", "Animalia", "mammal",
  "shrews", "Animalia", "mammal",
  "hedgehogs", "Animalia", "mammal",

  # ==========================================================================
  # REPTILES & AMPHIBIANS (~15 categories)
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
  "tree frogs", "Animalia", "amphibian",
  "newts", "Animalia", "amphibian",
  "salamanders", "Animalia", "amphibian",

  # ==========================================================================
  # OTHER INVERTEBRATES (~15 categories)
  # ==========================================================================
  "spiders", "Animalia", "arachnid",
  "orb weavers", "Animalia", "arachnid",
  "orb-weaver spiders", "Animalia", "arachnid",
  "jumping spiders", "Animalia", "arachnid",
  "wolf spiders", "Animalia", "arachnid",
  "tarantulas", "Animalia", "arachnid",
  "crab spiders", "Animalia", "arachnid",

  "mites", "Animalia", "arachnid",
  "ticks", "Animalia", "arachnid",
  "scorpions", "Animalia", "arachnid",
  "harvestmen", "Animalia", "arachnid",
  "daddy longlegs", "Animalia", "arachnid",

  "centipedes", "Animalia", "myriapod",
  "millipedes", "Animalia", "myriapod",

  "snails", "Animalia", "mollusk",
  "slugs", "Animalia", "mollusk",

  "earthworms", "Animalia", "annelid",

  # ==========================================================================
  # PLANTS - TREES (DECIDUOUS) (~30 categories)
  # ==========================================================================
  "oaks", "Plantae", "tree",
  "white oaks", "Plantae", "tree",
  "red oaks", "Plantae", "tree",
  "live oaks", "Plantae", "tree",

  "maples", "Plantae", "tree",
  "sugar maples", "Plantae", "tree",
  "red maples", "Plantae", "tree",
  "silver maples", "Plantae", "tree",
  "norway maples", "Plantae", "tree",

  "birches", "Plantae", "tree",
  "paper birches", "Plantae", "tree",
  "river birches", "Plantae", "tree",

  "willows", "Plantae", "tree",
  "weeping willows", "Plantae", "tree",
  "pussy willows", "Plantae", "tree",

  "poplars", "Plantae", "tree",
  "aspens", "Plantae", "tree",
  "cottonwoods", "Plantae", "tree",

  "ashes", "Plantae", "tree",
  "elms", "Plantae", "tree",
  "beeches", "Plantae", "tree",
  "chestnuts", "Plantae", "tree",
  "hickories", "Plantae", "tree",
  "walnuts", "Plantae", "tree",
  "alders", "Plantae", "tree",
  "lindens", "Plantae", "tree",
  "basswoods", "Plantae", "tree",
  "sycamores", "Plantae", "tree",
  "plane trees", "Plantae", "tree",
  "tulip trees", "Plantae", "tree",
  "magnolias", "Plantae", "tree",

  # ==========================================================================
  # PLANTS - TREES (CONIFEROUS) (~15 categories)
  # ==========================================================================
  "pines", "Plantae", "tree",
  "white pines", "Plantae", "tree",
  "red pines", "Plantae", "tree",
  "yellow pines", "Plantae", "tree",
  "pitch pines", "Plantae", "tree",
  "scots pines", "Plantae", "tree",

  "spruces", "Plantae", "tree",
  "norway spruces", "Plantae", "tree",
  "blue spruces", "Plantae", "tree",

  "firs", "Plantae", "tree",
  "balsam firs", "Plantae", "tree",

  "cedars", "Plantae", "tree",
  "junipers", "Plantae", "tree",
  "cypresses", "Plantae", "tree",
  "hemlocks", "Plantae", "tree",
  "larches", "Plantae", "tree",
  "yews", "Plantae", "tree",
  "redwoods", "Plantae", "tree",
  "sequoias", "Plantae", "tree",

  # ==========================================================================
  # PLANTS - SHRUBS (~20 categories)
  # ==========================================================================
  "roses", "Plantae", "shrub",
  "wild roses", "Plantae", "shrub",

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
  "privets", "Plantae", "shrub",
  "boxwoods", "Plantae", "shrub",
  "lilacs", "Plantae", "shrub",
  "hydrangeas", "Plantae", "shrub",
  "spireas", "Plantae", "shrub",
  "barberries", "Plantae", "shrub",

  # ==========================================================================
  # PLANTS - HERBACEOUS (~30 categories)
  # ==========================================================================
  "grasses", "Plantae", "herbaceous",
  "prairie grasses", "Plantae", "herbaceous",
  "lawn grasses", "Plantae", "herbaceous",
  "foxtails", "Plantae", "herbaceous",
  "barnyard grasses", "Plantae", "herbaceous",
  "bluegrasses", "Plantae", "herbaceous",
  "ryegrasses", "Plantae", "herbaceous",

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
  "buttercups", "Plantae", "herbaceous",
  "violets", "Plantae", "herbaceous",
  "geraniums", "Plantae", "herbaceous",
  "phlox", "Plantae", "herbaceous",
  "primroses", "Plantae", "herbaceous",
  "irises", "Plantae", "herbaceous",
  "lilies", "Plantae", "herbaceous",
  "orchids", "Plantae", "herbaceous",

  # ==========================================================================
  # PLANTS - FERNS & ALLIES (~8 categories)
  # ==========================================================================
  "ferns", "Plantae", "fern",
  "wood ferns", "Plantae", "fern",
  "bracken ferns", "Plantae", "fern",
  "maidenhair ferns", "Plantae", "fern",
  "lady ferns", "Plantae", "fern",

  "horsetails", "Plantae", "fern",
  "clubmosses", "Plantae", "fern",
  "spike mosses", "Plantae", "fern",

  # ==========================================================================
  # PLANTS - VINES & CLIMBERS (~8 categories)
  # ==========================================================================
  "grapes", "Plantae", "vine",
  "wild grapes", "Plantae", "vine",
  "ivies", "Plantae", "vine",
  "clematis", "Plantae", "vine",
  "honeysuckles", "Plantae", "vine",
  "morning glories", "Plantae", "vine",
  "bindweeds", "Plantae", "vine",
  "Virginia creeper", "Plantae", "vine",

  # ==========================================================================
  # PLANTS - FRUITS (~15 categories)
  # ==========================================================================
  "apples", "Plantae", "fruit",
  "crabapples", "Plantae", "fruit",

  "strawberries", "Plantae", "fruit",
  "wild strawberries", "Plantae", "fruit",

  "raspberries", "Plantae", "fruit",
  "blackberries", "Plantae", "fruit",

  "cherries", "Plantae", "fruit",
  "plums", "Plantae", "fruit",
  "peaches", "Plantae", "fruit",
  "pears", "Plantae", "fruit",

  "currants", "Plantae", "fruit",
  "gooseberries", "Plantae", "fruit",
  "mulberries", "Plantae", "fruit",
  "serviceberries", "Plantae", "fruit",

  # ==========================================================================
  # PLANTS - VEGETABLES & HERBS (~15 categories)
  # ==========================================================================
  "tomatoes", "Plantae", "vegetable",
  "peppers", "Plantae", "vegetable",
  "cucumbers", "Plantae", "vegetable",
  "squashes", "Plantae", "vegetable",
  "pumpkins", "Plantae", "vegetable",
  "melons", "Plantae", "vegetable",

  "beans", "Plantae", "vegetable",
  "peas", "Plantae", "vegetable",
  "lettuce", "Plantae", "vegetable",
  "spinach", "Plantae", "vegetable",
  "carrots", "Plantae", "vegetable",
  "onions", "Plantae", "vegetable",
  "garlic", "Plantae", "vegetable",

  "mints", "Plantae", "herb",
  "sages", "Plantae", "herb",
  "thymes", "Plantae", "herb",
  "oreganos", "Plantae", "herb",
  "basils", "Plantae", "herb",
  "rosemarys", "Plantae", "herb",

  # ==========================================================================
  # PLANTS - AQUATIC (~8 categories)
  # ==========================================================================
  "water lilies", "Plantae", "aquatic",
  "lotus", "Plantae", "aquatic",
  "cattails", "Plantae", "aquatic",
  "bulrushes", "Plantae", "aquatic",
  "pondweeds", "Plantae", "aquatic",
  "water milfoils", "Plantae", "aquatic",
  "duckweeds", "Plantae", "aquatic",
  "water hyacinths", "Plantae", "aquatic",

  # ==========================================================================
  # PLANTS - OTHER (~10 categories)
  # ==========================================================================
  "mosses", "Plantae", "bryophyte",
  "sphagnum mosses", "Plantae", "bryophyte",
  "liverworts", "Plantae", "bryophyte",

  "lichens", "Plantae", "lichen",

  "algae", "Plantae", "algae",
  "seaweeds", "Plantae", "algae",

  "cacti", "Plantae", "succulent",
  "succulents", "Plantae", "succulent",

  "palms", "Plantae", "tree",
  "bamboos", "Plantae", "grass"
)

# ============================================================================
# Validation and Summary
# ============================================================================

cat("Validation:\n")
cat(sprintf("  Total categories: %d\n", nrow(functional_categories)))

# Count by kingdom
kingdom_counts <- functional_categories %>%
  count(kingdom, name = "n_categories") %>%
  arrange(desc(n_categories))

cat("\nCategories by kingdom:\n")
print(as.data.frame(kingdom_counts), row.names = FALSE)

# Count by functional group
group_counts <- functional_categories %>%
  count(functional_group, name = "n_categories") %>%
  arrange(desc(n_categories))

cat("\nCategories by functional group:\n")
print(as.data.frame(group_counts), row.names = FALSE)

# Check for duplicates
duplicates <- functional_categories %>%
  group_by(category) %>%
  filter(n() > 1) %>%
  arrange(category)

if (nrow(duplicates) > 0) {
  cat("\nWARNING: Found duplicate categories:\n")
  print(as.data.frame(duplicates), row.names = FALSE)
} else {
  cat("\n✓ No duplicate categories found\n")
}

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(functional_categories, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d functional categories\n", nrow(functional_categories)))

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
