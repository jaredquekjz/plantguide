#!/usr/bin/env Rscript
#' Category Keyword Definitions for Vernacular Derivation
#'
#' @description
#' This module provides keyword mappings for categorizing organisms based on
#' word frequency analysis of their vernacular names. Keywords are grouped
#' into semantic categories (e.g., "oak" → "oak", "oaks").
#'
#' The word frequency algorithm counts occurrences of these keywords in
#' aggregated vernacular names, then assigns the dominant category if it
#' represents ≥10% of total word frequency.
#'
#' @details
#' Two separate keyword sets are maintained:
#' - Plant keywords: Growth forms, tree types, plant families
#' - Animal keywords: Insect orders, arachnids, vertebrates
#'
#' Keywords are lowercase and match tokenized words from vernacular names.
#'
#' @examples
#' keywords <- plant_keywords()
#' keywords$oak  # Returns c('oak', 'oaks')
#'
#' @author Claude Code
#' @date 2025-11-15

# ==============================================================================
# PLANT KEYWORDS
# ==============================================================================

#' Get plant-specific category keywords
#'
#' @description
#' Returns a named list of plant categories and their associated keywords.
#' Categories include growth forms (tree, shrub), specific tree types (oak,
#' maple), and plant families (rose, lily).
#'
#' @return Named list where each element is a character vector of keywords
#'
#' @details
#' Categories are organized hierarchically:
#' 1. Growth forms (tree, shrub, grass, fern, vine, etc.)
#' 2. Common plant families (rose, lily, orchid, daisy, etc.)
#' 3. Specific tree genera (oak, maple, pine, birch, etc.)
#' 4. Other specialized groups (sedge, rush, moss, etc.)
#'
#' Plural and singular forms are included to maximize matching.
#'
#' @export
plant_keywords <- function() {
  list(
    # -------------------------------------------------------------------------
    # Growth Forms
    # -------------------------------------------------------------------------
    # Broad morphological categories

    tree = c('tree', 'trees'),
    shrub = c('shrub', 'shrubs', 'bush', 'bushes'),
    herb = c('herb', 'herbs', 'herbaceous'),
    grass = c('grass', 'grasses'),
    fern = c('fern', 'ferns'),
    vine = c('vine', 'vines', 'climber', 'creeper', 'liana'),
    cactus = c('cactus', 'cacti'),
    palm = c('palm', 'palms'),
    succulent = c('succulent', 'succulents'),

    # -------------------------------------------------------------------------
    # Common Plant Families
    # -------------------------------------------------------------------------
    # Well-known flowering plant groups

    rose = c('rose', 'roses'),
    lily = c('lily', 'lilies'),
    orchid = c('orchid', 'orchids'),
    daisy = c('daisy', 'daisies'),
    aster = c('aster', 'asters'),
    mint = c('mint', 'mints'),
    pea = c('pea', 'peas', 'bean', 'beans', 'legume', 'legumes'),
    mustard = c('mustard', 'mustards', 'cabbage', 'cress'),
    carrot = c('carrot', 'carrots', 'parsley'),
    nightshade = c('nightshade', 'nightshades', 'potato', 'tomato'),
    sunflower = c('sunflower', 'sunflowers'),

    # -------------------------------------------------------------------------
    # Deciduous Trees (Hardwoods)
    # -------------------------------------------------------------------------
    # Temperate broadleaf trees

    oak = c('oak', 'oaks'),
    maple = c('maple', 'maples'),
    birch = c('birch', 'birches'),
    willow = c('willow', 'willows'),
    ash = c('ash'),  # singular only to avoid collision with common word
    elm = c('elm', 'elms'),
    poplar = c('poplar', 'poplars', 'aspen', 'aspens', 'cottonwood'),
    beech = c('beech', 'beeches'),
    hickory = c('hickory', 'hickories'),
    walnut = c('walnut', 'walnuts'),
    cherry = c('cherry', 'cherries'),
    apple = c('apple', 'apples'),
    plum = c('plum', 'plums'),

    # -------------------------------------------------------------------------
    # Coniferous Trees (Softwoods)
    # -------------------------------------------------------------------------
    # Needle-bearing evergreens

    pine = c('pine', 'pines'),
    fir = c('fir', 'firs'),
    spruce = c('spruce'),  # same singular/plural
    cedar = c('cedar', 'cedars'),
    cypress = c('cypress', 'cypresses'),
    juniper = c('juniper', 'junipers'),
    hemlock = c('hemlock', 'hemlocks'),
    larch = c('larch', 'larches', 'tamarack'),

    # -------------------------------------------------------------------------
    # Other Specialized Plant Groups
    # -------------------------------------------------------------------------

    sedge = c('sedge', 'sedges'),
    rush = c('rush', 'rushes'),
    moss = c('moss', 'mosses'),
    liverwort = c('liverwort', 'liverworts'),
    algae = c('algae', 'alga', 'seaweed'),
    bamboo = c('bamboo', 'bamboos'),
    magnolia = c('magnolia', 'magnolias')
  )
}

# ==============================================================================
# ANIMAL KEYWORDS
# ==============================================================================

#' Get animal-specific category keywords
#'
#' @description
#' Returns a named list of animal categories and their associated keywords.
#' Categories primarily cover beneficial organisms (pollinators, predators,
#' herbivores) relevant to plant ecosystems.
#'
#' @return Named list where each element is a character vector of keywords
#'
#' @details
#' Categories are organized by taxonomic/functional groups:
#' 1. Lepidoptera (moths, butterflies)
#' 2. Hymenoptera (bees, wasps, ants)
#' 3. Diptera (flies, mosquitoes, midges)
#' 4. Coleoptera (beetles, weevils, ladybugs)
#' 5. Hemiptera (bugs, aphids, scales)
#' 6. Arachnida (spiders, mites)
#' 7. Other insects (lacewings, crickets, thrips)
#' 8. Vertebrates (birds, bats)
#' 9. Other invertebrates (nematodes)
#'
#' Based on original implementation from Stage 4 plan (lines 353-386).
#'
#' @export
animal_keywords <- function() {
  list(
    # -------------------------------------------------------------------------
    # Lepidoptera
    # -------------------------------------------------------------------------
    # Moths and butterflies (major pollinators and herbivores)

    moth = c('moth', 'moths'),
    butterfly = c('butterfly', 'butterflies', 'swallowtail', 'swallowtails'),
    caterpillar = c('caterpillar', 'caterpillars', 'larva', 'larvae'),

    # -------------------------------------------------------------------------
    # Hymenoptera - Bees
    # -------------------------------------------------------------------------
    # Major pollinators

    bee = c('bee', 'bees', 'honeybee', 'bumblebee', 'sweatbee'),

    # -------------------------------------------------------------------------
    # Hymenoptera - Wasps & Ants
    # -------------------------------------------------------------------------
    # Predators and parasitoids

    wasp = c('wasp', 'wasps', 'hornet', 'yellowjacket'),
    ant = c('ant', 'ants'),
    sawfly = c('sawfly', 'sawflies'),

    # -------------------------------------------------------------------------
    # Diptera
    # -------------------------------------------------------------------------
    # Flies (pollinators and herbivores)

    fly = c('fly', 'flies', 'hoverfly', 'robberfly'),
    midge = c('midge', 'midges', 'gnat', 'gnats'),
    mosquito = c('mosquito', 'mosquitoes'),

    # -------------------------------------------------------------------------
    # Coleoptera
    # -------------------------------------------------------------------------
    # Beetles (diverse roles: pollinators, predators, herbivores)

    beetle = c('beetle', 'beetles'),
    weevil = c('weevil', 'weevils'),
    ladybug = c('ladybug', 'ladybugs', 'ladybird', 'ladybeetle'),

    # -------------------------------------------------------------------------
    # Hemiptera
    # -------------------------------------------------------------------------
    # True bugs (mostly herbivores, some predators)

    bug = c('bug', 'bugs', 'stinkbug', 'shieldbug'),
    aphid = c('aphid', 'aphids', 'plantlouse'),
    scale = c('scale'),  # scale insects
    whitefly = c('whitefly', 'whiteflies'),
    leafhopper = c('leafhopper', 'leafhoppers', 'treehopper', 'treehoppers'),
    psyllid = c('psyllid', 'psyllids', 'jumping plant louse'),

    # -------------------------------------------------------------------------
    # Thysanoptera
    # -------------------------------------------------------------------------

    thrip = c('thrip', 'thrips'),

    # -------------------------------------------------------------------------
    # Arachnida
    # -------------------------------------------------------------------------
    # Predators

    spider = c('spider', 'spiders'),
    mite = c('mite', 'mites'),

    # -------------------------------------------------------------------------
    # Neuroptera
    # -------------------------------------------------------------------------
    # Predators

    lacewing = c('lacewing', 'lacewings'),

    # -------------------------------------------------------------------------
    # Orthoptera
    # -------------------------------------------------------------------------
    # Herbivores

    cricket = c('cricket', 'crickets', 'katydid'),
    grasshopper = c('grasshopper', 'grasshoppers', 'locust'),

    # -------------------------------------------------------------------------
    # Vertebrates
    # -------------------------------------------------------------------------
    # Pollinators and seed dispersers

    bird = c('bird', 'birds'),
    bat = c('bat', 'bats'),

    # -------------------------------------------------------------------------
    # Other Invertebrates
    # -------------------------------------------------------------------------

    leafminer = c('leafminer', 'leafminers'),
    nematode = c('nematode', 'nematodes', 'roundworm'),
    louse = c('louse', 'lice'),
    snail = c('snail', 'snails', 'slug', 'slugs'),
    earthworm = c('earthworm', 'earthworms')
  )
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

#' Get default stopwords for vernacular tokenization
#'
#' @description
#' Returns a character vector of common English words to exclude from
#' word frequency analysis. These words are too generic to be useful
#' for category assignment.
#'
#' @return Character vector of lowercase stopwords
#'
#' @details
#' Stopwords include:
#' - Articles: the, a, an
#' - Conjunctions: and, or
#' - Prepositions: of, in, on, to, from, by, as, at, for, with
#' - Botanical descriptors: leaved, leaf (too generic)
#'
#' @export
default_stopwords <- function() {
  c('the', 'and', 'or', 'of', 'in', 'on', 'a', 'an', 'for', 'with',
    'to', 'from', 'by', 'as', 'at', 'leaved', 'leaf')
}

#' List all available category names
#'
#' @param organism_type Either "plant" or "animal"
#' @return Character vector of category names
#'
#' @examples
#' list_categories("plant")  # c("tree", "shrub", "oak", ...)
#' list_categories("animal") # c("moth", "bee", "beetle", ...)
#'
#' @export
list_categories <- function(organism_type = c("plant", "animal")) {
  organism_type <- match.arg(organism_type)

  keywords <- if (organism_type == "plant") {
    plant_keywords()
  } else {
    animal_keywords()
  }

  names(keywords)
}

#' Get total number of keywords
#'
#' @param organism_type Either "plant" or "animal"
#' @return Integer count of unique keywords
#'
#' @examples
#' count_keywords("plant")  # Total unique keywords for plants
#' count_keywords("animal") # Total unique keywords for animals
#'
#' @export
count_keywords <- function(organism_type = c("plant", "animal")) {
  organism_type <- match.arg(organism_type)

  keywords <- if (organism_type == "plant") {
    plant_keywords()
  } else {
    animal_keywords()
  }

  length(unique(unlist(keywords)))
}
