#!/usr/bin/env Rscript
# Extract and create family wood density lookup table from medfateconversion.mmd

library(data.table)

# Manually create the family wood density table from medfateconversion.mmd Table A.15
# This is based on medfate:::trait_family_means

family_wood_density <- data.table(
  Family = c(
    "Acanthaceae", "Achariaceae", "Acoraceae", "Actinidiaceae", "Adoxaceae",
    "Aextoxicaceae", "Aizoaceae", "Akaniaceae", "Alismataceae", "Altingiaceae",
    "Amaranthaceae", "Amaryllidaceae", "Amphorogynaceae", "Anacardiaceae", "Anisophylleaceae",
    "Annonaceae", "Aphloiaceae", "Apiaceae", "Apocynaceae", "Aptandraceae",
    "Aquifoliaceae", "Araceae", "Araliaceae", "Araucariaceae", "Arecaceae",
    "Aristolochiaceae", "Asparagaceae", "Asphodelaceae", "Aspleniaceae", "Asteraceae",
    "Asteropeiaceae", "Atherospermataceae", "Athyriaceae", "Austrobaileyaceae", "Balanopaceae",
    "Balsaminaceae", "Begoniaceae", "Berberidaceae", "Betulaceae", "Bignoniaceae",
    "Bixaceae", "Blechnaceae", "Bonnetiaceae", "Boraginaceae", "Brassicaceae",
    "Bromeliaceae", "Brunelliaceae", "Bruniaceae", "Burseraceae", "Buxaceae",
    "Cabombaceae", "Cactaceae", "Calceolariaceae", "Calophyllaceae", "Calycanthaceae",
    "Calyceraceae", "Campanulaceae", "Cannabaceae", "Cannaceae", "Canellaceae",
    "Capparaceae", "Caprifoliaceae", "Cardiopteridaceae", "Caricaceae", "Caryocaraceae",
    "Caryophyllaceae", "Casuarinaceae", "Celastraceae", "Cephalotaxaceae", "Cercidiphyllaceae",
    "Chenopodiaceae", "Chloranthaceae", "Chrysobalanaceae", "Cistaceae", "Cleomaceae",
    "Clethraceae", "Clusiaceae", "Cochlospermaceae", "Colchicaceae", "Combretaceae",
    "Commelinaceae", "Connaraceae", "Convolvulaceae", "Cordiaceae", "Coriariaceae",
    "Cornaceae", "Corylaceae", "Crassulaceae", "Cucurbitaceae", "Cunoniaceae",
    "Cupressaceae", "Cyatheaceae", "Cyclanthaceae", "Cyperaceae", "Cyrillaceae",
    "Daphniphyllaceae", "Dennstaedtiaceae", "Diapensiaceae", "Dichapetalaceae", "Dicksoniaceae",
    "Dilleniaceae", "Dioscoreaceae", "Dipterocarpaceae", "Dryopteridaceae", "Ebenaceae",
    "Ehretiaceae", "Elaeagnaceae", "Elaeocarpaceae", "Elatinaceae", "Ephedraceae",
    "Equisetaceae", "Ericaceae", "Erythroxylaceae", "Escalloniaceae", "Euphorbiaceae",
    "Eupomatiaceae", "Fabaceae", "Fagaceae", "Flacourtiaceae", "Fouquieriaceae",
    "Garryaceae", "Gentianaceae", "Geraniaceae", "Gesneriaceae", "Ginkgoaceae",
    "Goodeniaceae", "Grossulariaceae", "Gunneraceae", "Hamamelidaceae", "Hernandiaceae",
    "Himantandraceae", "Humiriaceae", "Hydrangeaceae", "Hypericaceae", "Icacinaceae",
    "Iridaceae", "Iteaceae", "Ixonanthaceae", "Juglandaceae", "Juncaceae",
    "Juncaginaceae", "Krameriaceae", "Lamiaceae", "Lauraceae", "Lecythidaceae",
    "Lentibulariaceae", "Linaceae", "Loganiaceae", "Loranthaceae", "Lythraceae",
    "Magnoliaceae", "Malpighiaceae", "Malvaceae", "Marantaceae", "Marcgraviaceae",
    "Melastomataceae", "Meliaceae", "Melianthaceae", "Menispermaceae", "Metteniusaceae",
    "Monimiaceae", "Montiaceae", "Moraceae", "Moringaceae", "Musaceae",
    "Myricaceae", "Myristicaceae", "Myrtaceae", "Nelumbonaceae", "Nyctaginaceae",
    "Nymphaeaceae", "Nyssaceae", "Ochnaceae", "Olacaceae", "Oleaceae",
    "Onagraceae", "Onocleaceae", "Orchidaceae", "Orobanchaceae", "Osmundaceae",
    "Oxalidaceae", "Paeoniaceae", "Pandanaceae", "Papaveraceae", "Passifloraceae",
    "Paulowniaceae", "Pentaphylacaceae", "Peraceae", "Phrymaceae", "Phyllanthaceae",
    "Phytolaccaceae", "Pinaceae", "Piperaceae", "Pittosporaceae", "Plantaginaceae",
    "Platanaceae", "Plumbaginaceae", "Poaceae", "Podocarpaceae", "Polemoniaceae",
    "Polygalaceae", "Polygonaceae", "Polypodiaceae", "Pontederiaceae", "Portulacaceae",
    "Potamogetonaceae", "Primulaceae", "Proteaceae", "Pteridaceae", "Putranjivaceae",
    "Quillajaceae", "Ranunculaceae", "Resedaceae", "Restionaceae", "Rhamnaceae",
    "Rhizophoraceae", "Rosaceae", "Rubiaceae", "Ruppiaceae", "Rutaceae",
    "Sabiaceae", "Salicaceae", "Salviniaceae", "Santalaceae", "Sapindaceae",
    "Sapotaceae", "Sarraceniaceae", "Saururaceae", "Saxifragaceae", "Schisandraceae",
    "Schoepfiaceae", "Scrophulariaceae", "Selaginellaceae", "Simaroubaceae", "Smilacaceae",
    "Solanaceae", "Stachyuraceae", "Staphyleaceae", "Stemonaceae", "Styracaceae",
    "Surianaceae", "Symplocaceae", "Tamaricaceae", "Taxaceae", "Theaceae",
    "Thelypteridaceae", "Thymelaeaceae", "Tropaeolaceae", "Typhaceae", "Ulmaceae",
    "Urticaceae", "Verbenaceae", "Violaceae", "Vitaceae", "Vochysiaceae",
    "Winteraceae", "Xanthorrhoeaceae", "Xyridaceae", "Zingiberaceae", "Zosteraceae",
    "Zygophyllaceae"
  ),
  WoodDensity = c(
    0.5684693, 0.6052036, NA, 0.4092320, 0.5157416,
    0.5666667, NA, 0.5547825, NA, 0.6010948,
    0.6315739, NA, 0.6097400, 0.5685583, 0.6734780,
    0.5642062, 0.6205200, 0.2561785, 0.5683635, 0.7076756,
    0.5579305, NA, 0.4142687, 0.4641456, 0.5913967,
    0.2900000, 0.4254258, 0.3951990, NA, 0.4822337,
    0.7554862, 0.4767621, NA, NA, 0.7348976,
    NA, NA, 0.7028850, 0.5381493, 0.6256030,
    0.3546357, NA, 0.8400000, 0.4987559, 0.4516377,
    NA, 0.3112500, 0.5636500, 0.5205008, 0.7314511,
    NA, 0.2990000, 0.6500000, 0.6635152, 0.4936842,
    NA, 0.5176235, 0.5276519, NA, 0.4925522,
    0.5036786, 0.5279206, 0.5522260, 0.3166225, 0.7233333,
    0.4635476, 0.6322871, 0.5979677, 0.3847500, 0.5833333,
    0.5844074, 0.5094327, 0.7033652, 0.7033308, 0.5055000,
    0.5588325, 0.6370833, 0.3565217, NA, 0.6172844,
    NA, 0.5838000, 0.3650000, 0.5685294, 0.4900000,
    0.5589233, 0.5420000, 0.5094400, 0.3320000, 0.5451389,
    0.4518750, NA, NA, NA, 0.5600000,
    0.4966667, NA, 0.4200000, 0.5533550, NA,
    0.5468548, 0.7220000, 0.5875714, 0.5470454, NA,
    0.5993500, 0.4200000, 0.5535436, 0.4675000, 0.5255733,
    0.5537619, 0.5400000, 0.5526853, 0.5769577, 0.5627619,
    0.5850000, 0.6550000, 0.4827273, 0.4613472, 0.3985000,
    0.4235000, 0.3838500, 0.5330000, 0.4700000, 0.5451667,
    0.4850000, 0.7100000, 0.7150000, 0.6183520, 0.5824444,
    NA, 0.5466667, 0.6200000, 0.5537273, NA,
    NA, 0.5500000, 0.4883106, 0.5741107, 0.6407407,
    NA, 0.3725000, 0.5400000, 0.4400000, 0.4640526,
    0.5304545, 0.5400000, 0.4802352, NA, 0.4900000,
    0.5308780, 0.5973200, 0.5600000, 0.3666667, 0.5433333,
    0.5252083, NA, 0.4663600, 0.2700000, NA,
    0.5270370, 0.5438424, 0.5968813, NA, 0.5100000,
    NA, 0.5683333, 0.5787115, 0.5842917, 0.5616809,
    0.4275500, NA, NA, NA, NA,
    0.4200000, 0.4700000, 0.4810000, NA, 0.5200000,
    0.3825000, 0.6100000, 0.6133333, 0.3000000, 0.5452614,
    0.4816429, 0.4361062, 0.4275789, 0.5233333, 0.5227500,
    0.5816667, 0.5130667, 0.5066167, 0.3920000, 0.4616000,
    0.5226129, 0.5069643, NA, 0.4716905, 0.7200000,
    0.5460370, 0.3875000, NA, 0.4940238, 0.7100000,
    0.5400000, 0.6166667, 0.5212879, 0.7800000, 0.6080000,
    0.5000000, 0.4831429, 0.5523378, NA, 0.6044000,
    0.4857500, 0.4854655, 0.5044773, 0.7050000, 0.5599219,
    0.5037500, 0.5043594, NA, 0.5566250, 0.5713022,
    0.6301632, NA, NA, 0.4909091, 0.4900000,
    0.6200000, 0.4683103, NA, 0.5525000, 0.3050000,
    0.4753077, 0.5530769, 0.5700000, NA, 0.5458000,
    0.4383333, 0.5857368, 0.4400000, 0.4467500, 0.5650833,
    NA, 0.6251875, 0.4550000, NA, 0.5472222,
    0.5128846, 0.5419512, 0.4761379, 0.4618343, 0.5330000,
    0.4967800, NA, NA, NA, NA,
    0.7238696
  )
)

# Save the family wood density table
output_file <- "src/Stage_3_Trait_Approximation/data/family_wood_density.csv"
fwrite(family_wood_density, output_file)
cat(sprintf("Family wood density table saved to: %s\n", output_file))
cat(sprintf("Total families with wood density values: %d\n", sum(!is.na(family_wood_density$WoodDensity))))

# Check which of our families are in the table
try_families <- fread("data/output/try_species_families.csv")
unique_families <- unique(try_families$family[!is.na(try_families$family)])

matched_families <- unique_families[unique_families %in% family_wood_density$Family]
unmatched_families <- unique_families[!unique_families %in% family_wood_density$Family]

cat(sprintf("\n=== FAMILY MATCHING ===\n"))
cat(sprintf("TRY families matched in medfate table: %d out of %d (%.1f%%)\n",
            length(matched_families), length(unique_families), 
            100*length(matched_families)/length(unique_families)))

if(length(unmatched_families) > 0) {
  cat("\nFamilies not in medfate table (will use default 0.652):\n")
  for(i in 1:min(20, length(unmatched_families))) {
    # Count species in this family
    n_species <- sum(try_families$family == unmatched_families[i], na.rm=TRUE)
    cat(sprintf("  %-25s: %d species\n", unmatched_families[i], n_species))
  }
  if(length(unmatched_families) > 20) {
    cat(sprintf("  ... and %d more families\n", length(unmatched_families) - 20))
  }
}

# Calculate coverage
species_with_family_wd <- sum(try_families$family %in% matched_families, na.rm=TRUE)
cat(sprintf("\nSpecies with family wood density values: %d (%.1f%%)\n",
            species_with_family_wd, 100*species_with_family_wd/nrow(try_families)))