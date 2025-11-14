#' Unified Taxonomic Categorization
#'
#' Single categorization system used across herbivores, predators, and pollinators.
#' Based on frequency analysis of 16,800 herbivore records, 14,282 predator records,
#' and 29,319 pollinator records.
#'
#' Functional categories preferred over pure taxonomy for clarity to gardeners/farmers.

#' Categorize an organism by functional/ecological guild
#' @param name Organism scientific name
#' @param role Context hint: "herbivore", "predator", or "pollinator" (used for fallback only)
#' @return Category string
categorize_organism <- function(name, role = NULL) {
  name_lower <- tolower(name)

  # ==========================================================================
  # UNIVERSAL CATEGORIES (appear in multiple roles)
  # ==========================================================================

  # Bumblebees (Bombus) - 3,527 pollinator records
  if (grepl("\\bbombus\\b", name_lower)) {
    return("Bumblebees")
  }

  # Honey Bees (Apis) - 626 pollinator records
  if (grepl("\\bapis\\b", name_lower)) {
    return("Honey Bees")
  }

  # Solitary Bees - 1,364 Andrena + 1,207 Lasioglossum + many more
  if (grepl("andrena|lasioglossum|halictus|osmia|megachile|ceratina|hylaeus|colletes|eucera|anthophora|xylocopa|nomada|sphecodes|panurgus|dasypoda|melitta|chelostoma|heriades|stelis|coelioxys", name_lower)) {
    return("Solitary Bees")
  }

  # Hoverflies - 532 Eristalis + 438 Platycheirus + many more
  # Predators as larvae (eat aphids), pollinators as adults
  if (grepl("syrphus|platycheirus|episyrphus|eupeodes|sphaerophoria|melanostoma|eristalis|cheilosia|helophilus|syritta|volucella|rhingia|paragus|pipiza|chrysotoxum|leucozona|scaeva|baccha|xylota|myathropa|ferdinandea|temnostoma|mallota|merodon|neoascia|sericomyia|parhelophilus", name_lower)) {
    return("Hoverflies")
  }

  # Butterflies - pollinators as adults, herbivores as larvae
  # Expanded with common genera from frequency analysis
  if (grepl("papilio|pieris|vanessa|danaus|euploea|colias|lycaena|polyommatus|maculinea|anthocharis|gonepteryx|araschnia|argynnis|boloria|erebia|coenonympha|maniola|melanargia|pararge|pyronia|thymelicus|ochlodes|hesperia|aporia|leptidea|celastrina|satyrium|callophrys|thecla|aricia|plebejus|glaucopsyche|iphiclides|zerynthia|nymphalis|aglais|polygonia|limenitis|apatura|charaxes|neptis|hypochrysops|anthene|arhopala|melanitis|deudorix|mycalesis|curetis|rapala|jamides|nacaduba|lampides|everes|celastrina|eurema|jalmenus", name_lower)) {
    return("Butterflies")
  }

  # Moths - pollinators as adults, herbivores as larvae
  # Note: "Caterpillars" category used when shown as herbivore pests
  # Expanded with Adelidae, Tortricidae, Limacodidae, Noctuidae, Erebidae, Saturniidae genera
  if (grepl("orgyia|acronicta|spodoptera|lymantria|malacosoma|hyalophora|attacus|automeris|biston|ectropis|operophtera|erannis|agriopis|semiothisa|colotois|selenia|ourapteryx|geometra|hemithea|cyclophora|scopula|idaea|rhodometra|macaria|eupithecia|chloroclystis|xanthorhoe|epirrhoe|eulithis|anticlea|mesoleuca|rheumaptera|melanthia|catocala|agrotis|ochropleura|noctua|xestia|diarsia|standfussiana|anaplectoides|graphiphora|eugnorisma|naenia|polia|mamestra|mythimna|orthosia|cerapteryx|tholera|apamea|oligia|mesoligia|photedes|amphipoea|hydraecia|nonagria|archanara|adela|nemophora|parasa|megalopyge|archips|choristoneura|cnephasia|tortricidae|pandemis|hedya|epiphyas|achaea|achatia|acrolepiopsis|amphipyra|antheraea", name_lower)) {
    return("Moths")
  }

  # Wasps - predators + pollinators
  if (grepl("vespula|vespa|polistes|ammophila|pemphredon|passaloecus|psenulus|ectemnius|crossocerus|rhopalum|trypoxylon|philanthus|cerceris|crabro|oxybelus|mellinus|gorytes|nysson|astata|mimesa|spilomena|stigmus|diodontus|ancistrocerus|symmorphus|odynerus|euodynerus", name_lower)) {
    return("Wasps")
  }

  # Parasitoid Wasps - predators only (biocontrol agents)
  if (grepl("aleiodes|ichneumon|ophion|amblyteles|diadegma|cotesia|apanteles|microgaster|dolichogenidea|braconidae|ichneumonidae|chalcididae|pteromalidae|eulophidae|encyrtidae|trichogramma|encarsia|aphidius|praon|lysiphlebus", name_lower)) {
    return("Parasitoid Wasps")
  }

  # Ants - predators + occasional pollinators
  if (grepl("formica|lasius|camponotus|monomorium|oecophylla|paratrechina|tetramorium|anoplolepis|solenopsis|crematogaster|pheidole|myrmica|tapinoma|linepithema|iridomyrmex|polyrhachis|dolichoderus", name_lower)) {
    return("Ants")
  }

  # Soldier Beetles - 116 Cantharis predator records, also pollinators
  if (grepl("cantharis|rhagonycha", name_lower)) {
    return("Soldier Beetles")
  }

  # Flies (various) - some pollinators, some predators, some parasitoids
  if (grepl("empis|sarcophaga|delia|phaonia|lucilia|pollenia|calliphora|bombylius|rhamphomyia|anthomyia|siphona|pegoplata|scathophaga|botanophila|helina|fucellia|thricops|muscidae|tachinidae|asilidae|dolichopodidae", name_lower)) {
    return("Flies")
  }

  # ==========================================================================
  # HERBIVORE-SPECIFIC CATEGORIES
  # ==========================================================================

  # Aphids - 532 Aphis + 267 Myzus + many more
  if (grepl("aphis|myzus|macrosiphum|aulacorthum|uroleucon|brachycaudus|dysaphis|rhopalosiphum|metopolophium|sitobion|acyrthosiphon|cavariella|nasonovia|hyperomyzus|capitophorus|phorodon|pemphigus|eriosoma|prociphilus|tuberolachnus|cinara|lachnus|stomaphis|trama", name_lower)) {
    return("Aphids")
  }

  # Scale Insects - 169 Hemiberlesia + many more
  if (grepl("hemiberlesia|aspidiotus|parlatoria|lindingaspis|leucaspis|coccus|saissetia|lepidosaphes|pseudaulacaspis|aonidiella|chrysomphalus|fiorinia|unaspis|aulacaspis|diaspidiotus|quadraspidiotus|pseudaonidia|pinnaspis|ischnaspis|pulvinaria|protopulvinaria|ceroplastes|parasaissetia|parthenolecanium|eulecanium", name_lower)) {
    return("Scale Insects")
  }

  # Mites - 89 Aceria + others
  if (grepl("aceria|tetranychus|eriophyes|panonychus|oligonychus|bryobia|petrobia|eotetranychus|eutetranychus|brevipalpus|tenuipalpus|phyllocoptruta|epitrimerus|aculops|aculus|calepitrimerus|phytoptus|cecidophyopsis", name_lower)) {
    return("Mites")
  }

  # Leaf Miners - 116 Phytomyza + 96 Liriomyza + more
  if (grepl("phytomyza|liriomyza|agromyza|chromatomyia|cerodontha|napomyza|phytobia|amauromyza|calycomyza|melanagromyza|ophiomyia|tropicomyia", name_lower)) {
    return("Leaf Miners")
  }

  # Caterpillars - used when moth/butterfly larvae shown as herbivore pests
  # Check for common caterpillar-related terms or specific families known as larvae
  # This category is contextual - same genera categorized as "Moths" or "Butterflies" when pollinators
  if (!is.null(role) && role == "herbivore") {
    if (grepl("larva|larvae|caterpillar|tortricidae|noctuidae|geometridae|pyralidae|gelechiidae|gracillariidae|plutella|cydia|grapholita|lobesia|hedya|pandemis|adoxophyes|epiphyas|homona|leguminivora|laspeyresia|pammene|carpocapsa|rhyacionia|epinotia|eucosma|pelochrista|dichrorampha", name_lower)) {
      return("Caterpillars")
    }
  }

  # Thrips
  if (grepl("\\bthrips\\b|frankliniella|scirtothrips|heliothrips|hercinothrips|parthenothrips|selenothrips|dendrothrips|limothrips|chirothrips|kakothrips|megalurothrips|taeniothrips", name_lower)) {
    return("Thrips")
  }

  # Whiteflies - 47 Bemisia + others
  if (grepl("bemisia|trialeurodes|aleurodicus|dialeurodes|aleyrodes|aleurocanthus|parabemisia|neomaskellia|tetraleurodes|aleurotrachelus", name_lower)) {
    return("Whiteflies")
  }

  # Leafhoppers
  if (grepl("empoasca|graphocephala|erythroneura|typhlocyba|scaphoideus|macrosteles|cicadella|evacanthus|edwardsiana|ribautiana|zygina|ribautidelphax|javesella|dicranotropis|delphacodes", name_lower)) {
    return("Leafhoppers")
  }

  # Weevils
  if (grepl("curculio|anthonomus|phyllobius|otiorhynchus|sitona|polydrusus|barypeithes|strophosoma|sciaphilus|eusomus|hypera|apion|ceutorhynchus|nedyus|ceuthorhynchidius|baris|bagous|rhinoncus|rhynchaenus|orchestes|rhamphus|tychius|sibinia|mogulones", name_lower)) {
    return("Weevils")
  }

  # Leaf Beetles (Chrysomelidae)
  if (grepl("chrysomela|phyllotreta|cassida|altica|chaetocnema|longitarsus|psylliodes|aphthona|crepidodera|haltica|galerucella|lochmaea|plagiodera|phratora|agelastica|oulema|lema|crioceris|lilioceris|donacia|plateumaris|macroplea|prasocuris", name_lower)) {
    return("Leaf Beetles")
  }

  # Jewel Beetles (Buprestidae) - wood borers
  if (grepl("agrilus|castiarina|buprestis|chrysobothris|anthaxia|trachys|coraebus|meliboeus|acmaeodera|dicerca", name_lower)) {
    return("Beetles")
  }

  # Leaf-mining moths (Nepticulidae, Gracillariidae) - add to existing stigmella
  if (grepl("stigmella|nepticulidae|gracillaria|phyllocnistis|phyllonorycter|cameraria|caloptilia", name_lower)) {
    return("Leaf Miners")
  }

  # Psyllids (jumping plant lice) - new category for sap-feeders
  if (grepl("glycaspis|heptapsogaster|psylla|cacopsylla|trioza|bactericera|diaphorina|psyllidae", name_lower)) {
    return("Psyllids")
  }

  # Plant Bugs (herbivorous Hemiptera) - sap-feeders and plant tissue feeders
  if (grepl("ambastus|lygus|nezara|eurygaster|dolycoris|elasmostethus|palomena|piezodorus|acrosternum|halyomorpha|pentatomidae|miridae|tingidae|coreidae|alydidae|rhopalidae|scutelleridae", name_lower)) {
    return("Plant Bugs")
  }

  # ==========================================================================
  # PREDATOR-SPECIFIC CATEGORIES
  # ==========================================================================

  # Spiders - 172 Xysticus + 117 Robertus + many more
  if (grepl("xysticus|robertus|araniella|tetragnatha|porrhomma|pardosa|mangora|pisaura|larinioides|agalenatea|allagelena|aculepeira|cicurina|centromerita|dipoena|tibellus|coelotes|salticus|diplostyla|collinsia|sibianor|singa|neottiura|walckenaeria|microlinyphia|tiso|zora|cryptachaea|argenna|clubiona|enoplognatha|myrmarachne|micrargus|plagiognathus|haplodrassus|trogulus|centromerus|erigone|erigonella|meioneta|oedothorax|semljicola|tenuiphantes|micaria|arctosa|diplocephalus|thomisidae|rilaena|dicymbium|eurithia|leptorhoptrum|trichonephila|phidippus|drassyllus|oligolophus|trochosa|alopecosa|philodromus|theridion|oxyopes|cheiracanthium|araneus|agelena|tegenaria|metellina|nuctenea|zygiella|linyphia|neriene|frontinella|lepthyphantes|tapinopa|bathyphantes|stemonyphantes|macrargus|pocadicnemis|agyneta|gongylidium|leptorhoptrum|silometopus|ceratinella|cornicularia|micrargus|gongylidiellum", name_lower)) {
    return("Spiders")
  }

  # Ground Beetles - 484 Amara + 190 Pterostichus + 158 Carabus + 158 Harpalus + many more
  if (grepl("amara|pterostichus|carabus|harpalus|calathus|pseudophonus|notiophilus|agonum|poecilus|nebria|abax|acupalpus|carabidae|anisodactylus|anchomenus|leistus|stomis|loricera|syntomus|limodromus|trechus|cicindela|asaphidion|bembidion|cymindis|badister|panagaeus|chlaenius|oodes|licinus|molops|platynus|synuchus|amblystomus|stenolophus|bradycellus|acupalpus|anthracus|dromius|demetrias|paradromius|philorhizus|microlestes|brachinus|aptinus|pheropsophus|elaphrus|blethisa|patrobus|delta", name_lower)) {
    return("Ground Beetles")
  }

  # Rove Beetles - 156 Philonthus + 114 Ocypus + 81 Quedius + 72 Tasgius + many more
  if (grepl("philonthus|ocypus|quedius|tasgius|platydracus|tachyporus|staphylinidae|staphylinus|lathrobium|carpelimus|gabrius|tachinus|bolitobius|mycetoporus|xantholinus|paederus|sepedophilus|philhygra|atheta|stenus|aleochara|oxypoda|aloconota|dinaraea|oligota|geostiba|hydrosmecta|liogluta|nehemitropia|ocalea|thinonoma|zyras|anotylus|oxytelus|platystethus|astenus|euaesthetus|eusphalerum|medon|rugilus|scopaeus|sunius|cryptobium|lithocharis|lathrobium|lobrathium|tetartopeus|achenium|astenus|domene|leptacinus|othius|baptolinus|heterothops|dinothenarus|gyrohypnus|bisnius|nudobius|erichsonius|cafius|creophilus|hadrotes|ontholestes|philonthus|rabigus|remus|staphylinus|thinobius|trigonodemus", name_lower)) {
    return("Rove Beetles")
  }

  # Ladybugs - biocontrol agents
  if (grepl("adalia|hippodamia|coccinella|harmonia|chilocorus|scymnus|propylea|oenopia|calvia|halyzia|anatis|myzia|vibidia|myrrha|tytthaspis|hyperaspis|clitostethus|stethorus|nephus|rhyzobius|exochomus|brumus|pullus|platynaspis|coccidula|anisosticta|psyllobora|thea|bulaea|illeis|rodolia", name_lower)) {
    return("Ladybugs")
  }

  # Predatory Bugs - 106 Nabis + others
  if (grepl("\\bnabis\\b|anthocoris|orius|deraeocoris|pilophorus|atractotomus|harpocera|malacocoris|orthotylus|plagiognathus|stenodema|notostira|leptopterna|adelphocoris|lygus|poecilocapsus|lygocoris|campylomma|heterocordylus|phylus|phytocoris|hallodapus|reuteroscopus|psallus|macrolophus|dicyphus|cyrtopeltis|nesidiocoris|reduviidae|zelus|sinea|rhynocoris|pirates|empicoris|ploiariola|emesaya|gardena|stenolemus", name_lower)) {
    return("Predatory Bugs")
  }

  # Lacewings - important aphid predators
  if (grepl("chrysoperla|chrysopa|hemerobius|micromus|sympherobius|wesmaelius|megalomus|drepanepteryx|psectra|nineta|italochrysa|cunctochrysa|pseudomallada|mallada|dichochrysa|chrysotropia|nothochrysa|peyerimhoffina|semidalis|coniopteryx|conwentzia|aleuropteryx|parasemidalis|helicoconis", name_lower)) {
    return("Lacewings")
  }

  # Bats - 196 Myotis + 89 Rhinolophus + 59 Eptesicus + 58 Nyctalus + 57 Pipistrellus + more
  if (grepl("myotis|rhinolophus|eptesicus|nyctalus|pipistrellus|plecotus|barbastella|vespertilio|miniopterus|lasiurus|corynorhinus|antrozous|nycticeius|lasionycteris|perimyotis|parastrellus|hypsugo|tadarida|molossus|nyctinomops|eumops|rousettus|pteropus|cynopterus|eonycteris|macroglossus", name_lower)) {
    return("Bats")
  }

  # Birds - 119 Vireo + 44 Setophaga + many more
  if (grepl("vireo|setophaga|turdus|parus|fringilla|anthus|agelaius|cyanistes|empidonax|cardinalis|catharus|baeolophus|tyrannus|coccyzus|sialia|lanius|contopus|dryobates|falco|rhipidura|merops|cracticus|bird|aves|corvus|garrulus|acrocephalus|phylloscopus|sturnus|parkesia|hylocichla|riparia|bubulcus|locustella|petrochelidon|progne|emberiza|stelgidopteryx|pheucticus|cypseloides|luscinia|erithacus|phoenicurus|saxicola|oenanthe|monticola|zoothera|catharus|myadestes|sialia|geothlypis|wilsonia|cardellina|myioborus|basileuterus|oreothlypis|leiothlypis|oporornis|seiurus|mniotilta|protonotaria|helmitheros|limnothlypis|vermivora|piranga|spiza|passerina|pipilo|melospiza|junco|zonotrichia|passerculus|ammodramus|spizella|chondestes|calamospiza|calcarius|plectrophenax", name_lower)) {
    return("Birds")
  }

  # Harvestmen - 49 Opilio + others
  if (grepl("opilio|phalangium|leiobunum|mitopus|nemastoma|dicranopalpus|oligolophus|lacinius|megabunus|rilaena|astrobunus|homalenotus|paranemastoma|carinostoma|trogulus", name_lower)) {
    return("Harvestmen")
  }

  # Earwigs - 42 Forficula + others
  if (grepl("forficula|apterygida|euborellia|doru|labidura|labia|marava|chelidurella|anechura|guanchia", name_lower)) {
    return("Earwigs")
  }

  # Centipedes - 47 Lithobius + others
  if (grepl("lithobius|scolopendra|cryptops|geophilus|haplophilus|pachymerium|stigmatogaster|himantarium|mecistocephalus|scolopocryptops|theatops|newportia|otostigmus|ethmostigmus|rhysida|cormocephalus|asanada|ballophilus|lamyctes|henicopidae|schendylidae", name_lower)) {
    return("Centipedes")
  }

  # ==========================================================================
  # FALLBACK - Role-specific "Other" categories
  # ==========================================================================

  if (!is.null(role)) {
    if (role == "herbivore") return("Other Herbivores")
    if (role == "predator") return("Other Predators")
    if (role == "pollinator") return("Other Pollinators")
  }

  return("Other")
}
