//! Unified Taxonomic Categorization
//!
//! Single categorization system used across herbivores, predators, and pollinators.
//! Based on frequency analysis of 16,800 herbivore records, 14,282 predator records,
//! and 29,319 pollinator records.
//!
//! Functional categories preferred over pure taxonomy for clarity to gardeners/farmers.

use serde::{Deserialize, Serialize};

/// Organism role context for categorization
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrganismRole {
    Herbivore,
    Predator,
    Pollinator,
}

/// Unified organism category (35 functional categories)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum OrganismCategory {
    // Universal categories (appear in multiple roles)
    Bumblebees,
    HoneyBees,
    SolitaryBees,
    Hoverflies,
    Butterflies,
    Moths,
    Wasps,
    ParasitoidWasps,
    Ants,
    SoldierBeetles,
    Flies,

    // Herbivore-specific categories
    Aphids,
    ScaleInsects,
    Mites,
    LeafMiners,
    Caterpillars,
    Thrips,
    Whiteflies,
    Leafhoppers,
    Weevils,
    LeafBeetles,
    Beetles,      // General beetles (wood borers, jewel beetles, etc.)
    Psyllids,     // Jumping plant lice

    // Predator-specific categories
    Spiders,
    GroundBeetles,
    RoveBeetles,
    Ladybugs,
    PredatoryBugs,
    Lacewings,
    Bats,
    Birds,
    Harvestmen,
    Earwigs,
    Centipedes,

    // Catch-all categories
    OtherHerbivores,
    OtherPredators,
    OtherPollinators,
    Other,
}

impl OrganismCategory {
    /// Categorize an organism by functional/ecological guild
    ///
    /// # Arguments
    /// * `name` - Organism scientific name
    /// * `role` - Context hint (herbivore, predator, or pollinator) used for fallback only
    pub fn from_name(name: &str, role: Option<OrganismRole>) -> Self {
        let name_lower = name.to_lowercase();

        // ====================================================================
        // UNIVERSAL CATEGORIES (appear in multiple roles)
        // ====================================================================

        // Bumblebees (Bombus) - 3,527 pollinator records
        if name_lower.contains("bombus") {
            return OrganismCategory::Bumblebees;
        }

        // Honey Bees (Apis) - 626 pollinator records
        if name_lower.contains("apis") {
            return OrganismCategory::HoneyBees;
        }

        // Solitary Bees - comprehensive genus coverage
        let solitary_bee_patterns = [
            "andrena", "lasioglossum", "halictus", "osmia", "megachile", "ceratina",
            "hylaeus", "colletes", "eucera", "anthophora", "xylocopa", "nomada",
            "sphecodes", "panurgus", "dasypoda", "melitta", "chelostoma", "heriades",
            "stelis", "coelioxys",
        ];
        if solitary_bee_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::SolitaryBees;
        }

        // Hoverflies - predators as larvae (eat aphids), pollinators as adults
        let hoverfly_patterns = [
            "syrphus", "platycheirus", "episyrphus", "eupeodes", "sphaerophoria",
            "melanostoma", "eristalis", "cheilosia", "helophilus", "syritta",
            "volucella", "rhingia", "paragus", "pipiza", "chrysotoxum",
            "leucozona", "scaeva", "baccha", "xylota", "myathropa",
        ];
        if hoverfly_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Hoverflies;
        }

        // Butterflies - pollinators as adults, herbivores as larvae
        // Expanded with common genera from frequency analysis
        let butterfly_patterns = [
            "papilio", "pieris", "vanessa", "danaus", "euploea", "colias",
            "lycaena", "polyommatus", "maculinea", "anthocharis", "gonepteryx",
            "araschnia", "argynnis", "boloria", "erebia", "coenonympha",
            "maniola", "melanargia", "pararge", "pyronia", "thymelicus",
            "charaxes", "neptis", "hypochrysops", "anthene", "arhopala",
            "melanitis", "deudorix", "mycalesis", "curetis", "rapala",
        ];
        if butterfly_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Butterflies;
        }

        // Moths - pollinators as adults, herbivores as larvae
        // Note: "Caterpillars" category used when shown as herbivore pests
        // Expanded with Adelidae, Tortricidae, Limacodidae genera
        let moth_patterns = [
            "orgyia", "acronicta", "spodoptera", "lymantria", "malacosoma",
            "hyalophora", "attacus", "automeris", "biston", "ectropis",
            "operophtera", "erannis", "agriopis", "semiothisa", "colotois",
            "selenia", "ourapteryx", "geometra", "hemithea", "cyclophora",
            "adela", "nemophora", "parasa", "megalopyge", "archips",
            "choristoneura", "cnephasia", "tortricidae", "pandemis", "hedya",
        ];
        if moth_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Moths;
        }

        // Wasps - predators + pollinators
        let wasp_patterns = [
            "vespula", "vespa", "polistes", "ammophila", "pemphredon",
            "passaloecus", "psenulus", "ectemnius", "crossocerus", "rhopalum",
            "trypoxylon", "philanthus", "cerceris", "crabro", "oxybelus",
        ];
        if wasp_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Wasps;
        }

        // Parasitoid Wasps - predators only (biocontrol agents)
        let parasitoid_patterns = [
            "aleiodes", "ichneumon", "ophion", "amblyteles", "diadegma",
            "cotesia", "apanteles", "microgaster", "dolichogenidea", "braconidae",
            "ichneumonidae", "chalcididae", "pteromalidae", "eulophidae",
            "encyrtidae", "trichogramma", "encarsia", "aphidius", "praon",
        ];
        if parasitoid_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::ParasitoidWasps;
        }

        // Ants - predators + occasional pollinators
        let ant_patterns = [
            "formica", "lasius", "camponotus", "monomorium", "oecophylla",
            "paratrechina", "tetramorium", "anoplolepis", "solenopsis",
            "crematogaster", "pheidole", "myrmica", "tapinoma", "linepithema",
        ];
        if ant_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Ants;
        }

        // Soldier Beetles - predators + pollinators
        if name_lower.contains("cantharis") || name_lower.contains("rhagonycha") {
            return OrganismCategory::SoldierBeetles;
        }

        // Flies (various) - some pollinators, some predators
        let fly_patterns = [
            "empis", "sarcophaga", "delia", "phaonia", "lucilia",
            "pollenia", "calliphora", "bombylius", "rhamphomyia", "anthomyia",
            "siphona", "pegoplata", "scathophaga", "botanophila", "helina",
        ];
        if fly_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Flies;
        }

        // ====================================================================
        // HERBIVORE-SPECIFIC CATEGORIES
        // ====================================================================

        // Aphids
        let aphid_patterns = [
            "aphis", "myzus", "macrosiphum", "aulacorthum", "uroleucon",
            "brachycaudus", "dysaphis", "rhopalosiphum", "metopolophium",
            "sitobion", "acyrthosiphon", "cavariella", "nasonovia",
        ];
        if aphid_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Aphids;
        }

        // Scale Insects
        let scale_patterns = [
            "hemiberlesia", "aspidiotus", "parlatoria", "lindingaspis",
            "leucaspis", "coccus", "saissetia", "lepidosaphes",
            "pseudaulacaspis", "aonidiella", "chrysomphalus", "fiorinia",
        ];
        if scale_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::ScaleInsects;
        }

        // Mites
        let mite_patterns = [
            "aceria", "tetranychus", "eriophyes", "panonychus", "oligonychus",
            "bryobia", "petrobia", "eotetranychus", "eutetranychus",
            "brevipalpus", "tenuipalpus", "phyllocoptruta",
        ];
        if mite_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Mites;
        }

        // Leaf Miners
        let leafminer_patterns = [
            "phytomyza", "liriomyza", "agromyza", "chromatomyia", "cerodontha",
            "napomyza", "phytobia", "amauromyza", "calycomyza",
        ];
        if leafminer_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::LeafMiners;
        }

        // Caterpillars - contextual (moth/butterfly larvae shown as herbivore pests)
        if role == Some(OrganismRole::Herbivore) {
            let caterpillar_patterns = [
                "larva", "larvae", "caterpillar", "tortricidae", "noctuidae",
                "geometridae", "pyralidae", "gelechiidae", "plutella", "cydia",
                "grapholita", "lobesia", "hedya", "pandemis", "adoxophyes",
            ];
            if caterpillar_patterns.iter().any(|&p| name_lower.contains(p)) {
                return OrganismCategory::Caterpillars;
            }
        }

        // Thrips
        if name_lower.contains("thrips") || name_lower.contains("frankliniella") {
            return OrganismCategory::Thrips;
        }

        // Whiteflies
        let whitefly_patterns = [
            "bemisia", "trialeurodes", "aleurodicus", "dialeurodes",
            "aleyrodes", "aleurocanthus",
        ];
        if whitefly_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Whiteflies;
        }

        // Leafhoppers
        let leafhopper_patterns = [
            "empoasca", "graphocephala", "erythroneura", "typhlocyba",
            "scaphoideus", "macrosteles", "cicadella",
        ];
        if leafhopper_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Leafhoppers;
        }

        // Weevils
        let weevil_patterns = [
            "curculio", "anthonomus", "phyllobius", "otiorhynchus", "sitona",
            "polydrusus", "barypeithes", "strophosoma", "hypera", "apion",
            "ceutorhynchus",
        ];
        if weevil_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Weevils;
        }

        // Leaf Beetles (Chrysomelidae)
        let leafbeetle_patterns = [
            "chrysomela", "phyllotreta", "cassida", "altica", "chaetocnema",
            "longitarsus", "psylliodes", "aphthona", "galerucella", "lochmaea",
        ];
        if leafbeetle_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::LeafBeetles;
        }

        // Jewel Beetles (Buprestidae) - wood borers
        let jewelbeetle_patterns = [
            "agrilus", "castiarina", "buprestis", "chrysobothris", "anthaxia",
        ];
        if jewelbeetle_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Beetles;
        }

        // Leaf-mining moths (Nepticulidae, Gracillariidae)
        if name_lower.contains("stigmella") || name_lower.contains("gracillaria") {
            return OrganismCategory::LeafMiners;
        }

        // Psyllids (jumping plant lice) - sap-feeders
        let psyllid_patterns = [
            "glycaspis", "heptapsogaster", "psylla", "cacopsylla", "trioza",
            "psyllidae",
        ];
        if psyllid_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Psyllids;
        }

        // ====================================================================
        // PREDATOR-SPECIFIC CATEGORIES
        // ====================================================================

        // Spiders - comprehensive genus coverage
        let spider_patterns = [
            "xysticus", "robertus", "araniella", "tetragnatha", "porrhomma",
            "pardosa", "mangora", "pisaura", "larinioides", "agalenatea",
            "allagelena", "aculepeira", "cicurina", "centromerita", "dipoena",
            "tibellus", "coelotes", "salticus", "araneus", "agelena",
            "spider", "araneae",
        ];
        if spider_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Spiders;
        }

        // Ground Beetles - comprehensive including Amara (484 matches!), Harpalus (158)
        let groundbeetle_patterns = [
            "amara", "pterostichus", "carabus", "harpalus", "calathus",
            "pseudophonus", "notiophilus", "agonum", "poecilus", "nebria",
            "abax", "carabidae", "anisodactylus", "leistus", "trechus",
            "cicindela", "bembidion",
        ];
        if groundbeetle_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::GroundBeetles;
        }

        // Rove Beetles - comprehensive
        let rovebeetle_patterns = [
            "philonthus", "ocypus", "quedius", "tasgius", "platydracus",
            "tachyporus", "staphylinidae", "staphylinus", "lathrobium",
            "gabrius", "tachinus", "mycetoporus", "xantholinus", "paederus",
            "atheta", "stenus", "aleochara", "oxypoda",
        ];
        if rovebeetle_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::RoveBeetles;
        }

        // Ladybugs - biocontrol agents
        let ladybug_patterns = [
            "adalia", "hippodamia", "coccinella", "harmonia", "chilocorus",
            "scymnus", "propylea", "oenopia", "calvia", "halyzia",
            "coccinellidae", "ladybug",
        ];
        if ladybug_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Ladybugs;
        }

        // Predatory Bugs
        let predatorybug_patterns = [
            "nabis", "anthocoris", "orius", "deraeocoris", "pilophorus",
            "atractotomus", "campylomma", "reduviidae", "zelus", "sinea",
        ];
        if predatorybug_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::PredatoryBugs;
        }

        // Lacewings - important aphid predators
        let lacewing_patterns = [
            "chrysoperla", "chrysopa", "hemerobius", "micromus",
            "sympherobius", "wesmaelius", "coniopteryx",
        ];
        if lacewing_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Lacewings;
        }

        // Bats
        let bat_patterns = [
            "myotis", "rhinolophus", "eptesicus", "nyctalus", "pipistrellus",
            "plecotus", "barbastella", "vespertilio", "miniopterus", "lasiurus",
            "bat", "chiroptera",
        ];
        if bat_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Bats;
        }

        // Birds
        let bird_patterns = [
            "vireo", "setophaga", "turdus", "parus", "fringilla", "anthus",
            "cyanistes", "empidonax", "cardinalis", "catharus", "corvus",
            "garrulus", "acrocephalus", "phylloscopus", "sturnus",
            "bird", "aves",
        ];
        if bird_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Birds;
        }

        // Harvestmen
        let harvestmen_patterns = ["opilio", "phalangium", "leiobunum", "opiliones"];
        if harvestmen_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Harvestmen;
        }

        // Earwigs
        let earwig_patterns = ["forficula", "apterygida", "dermaptera", "earwig"];
        if earwig_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Earwigs;
        }

        // Centipedes
        let centipede_patterns = ["lithobius", "scolopendra", "chilopoda", "centipede"];
        if centipede_patterns.iter().any(|&p| name_lower.contains(p)) {
            return OrganismCategory::Centipedes;
        }

        // ====================================================================
        // FALLBACK - Role-specific "Other" categories
        // ====================================================================

        match role {
            Some(OrganismRole::Herbivore) => OrganismCategory::OtherHerbivores,
            Some(OrganismRole::Predator) => OrganismCategory::OtherPredators,
            Some(OrganismRole::Pollinator) => OrganismCategory::OtherPollinators,
            None => OrganismCategory::Other,
        }
    }

    /// Get display name for this category
    pub fn display_name(&self) -> &str {
        match self {
            OrganismCategory::Bumblebees => "Bumblebees",
            OrganismCategory::HoneyBees => "Honey Bees",
            OrganismCategory::SolitaryBees => "Solitary Bees",
            OrganismCategory::Hoverflies => "Hoverflies",
            OrganismCategory::Butterflies => "Butterflies",
            OrganismCategory::Moths => "Moths",
            OrganismCategory::Wasps => "Wasps",
            OrganismCategory::ParasitoidWasps => "Parasitoid Wasps",
            OrganismCategory::Ants => "Ants",
            OrganismCategory::SoldierBeetles => "Soldier Beetles",
            OrganismCategory::Flies => "Flies",
            OrganismCategory::Aphids => "Aphids",
            OrganismCategory::ScaleInsects => "Scale Insects",
            OrganismCategory::Mites => "Mites",
            OrganismCategory::LeafMiners => "Leaf Miners",
            OrganismCategory::Caterpillars => "Caterpillars",
            OrganismCategory::Thrips => "Thrips",
            OrganismCategory::Whiteflies => "Whiteflies",
            OrganismCategory::Leafhoppers => "Leafhoppers",
            OrganismCategory::Weevils => "Weevils",
            OrganismCategory::LeafBeetles => "Leaf Beetles",
            OrganismCategory::Beetles => "Beetles",
            OrganismCategory::Psyllids => "Psyllids",
            OrganismCategory::Spiders => "Spiders",
            OrganismCategory::GroundBeetles => "Ground Beetles",
            OrganismCategory::RoveBeetles => "Rove Beetles",
            OrganismCategory::Ladybugs => "Ladybugs",
            OrganismCategory::PredatoryBugs => "Predatory Bugs",
            OrganismCategory::Lacewings => "Lacewings",
            OrganismCategory::Bats => "Bats",
            OrganismCategory::Birds => "Birds",
            OrganismCategory::Harvestmen => "Harvestmen",
            OrganismCategory::Earwigs => "Earwigs",
            OrganismCategory::Centipedes => "Centipedes",
            OrganismCategory::OtherHerbivores => "Other Herbivores",
            OrganismCategory::OtherPredators => "Other Predators",
            OrganismCategory::OtherPollinators => "Other Pollinators",
            OrganismCategory::Other => "Other",
        }
    }
}
