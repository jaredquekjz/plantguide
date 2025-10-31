# TRY ↔ AusTraits Category Mapping (Draft)

Date: 2025-10-14  
Maintainer: Stage 1 QA draft

This worksheet lists the categorical vocabularies used by TRY (enhanced/raw) and AusTraits for overlapping traits. AusTraits values are bucketed via simple keyword rules; please review before finalising the translation tables in code.

## Growth form

**TRY categories:** bamboo graminoid, climber, fern, herbaceous graminoid, herbaceous non-graminoid, herbaceous non-graminoid/shrub, other, shrub, shrub/tree, succulent, tree  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| (other/no direct match) | basal_large |
| climber | basal_large climber, climber, climber climber_herbaceous, climber climber_herbaceous shrub, climber climber_woody shrub, climber fern, climber herb, climber herb shrub (+26 more) |
| fern | climber fern, climber_herbaceous fern, fern, fern herb, fern herb palmoid tree, fern palmoid, fern tussock, lycophyte |
| herbaceous graminoid | climber_herbaceous graminoid, fern tussock, graminoid, graminoid herb, graminoid herb hummock, graminoid herb shrub, graminoid herb tussock, graminoid hummock (+11 more) |
| herbaceous non-graminoid | basal_large herb, climber climber_herbaceous, climber climber_herbaceous shrub, climber herb, climber herb shrub, climber herb subshrub, climber_herbaceous, climber_herbaceous climber_woody (+30 more) |
| shrub | climber climber_herbaceous shrub, climber climber_woody shrub, climber herb shrub, climber herb subshrub, climber shrub, climber shrub subshrub, climber shrub tree, climber subshrub (+30 more) |
| tree | basal_large palmoid, climber shrub tree, climber tree, climber_herbaceous shrub tree, climber_herbaceous tree, climber_woody shrub tree, climber_woody tree, fern herb palmoid tree (+16 more) |


## Woodiness

**TRY categories:** Woody, non-woody, semi-woody, woody  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| Woody | woody |
| non-woody | herbaceous |


## Succulence

**TRY categories:** leaf and stem succulent, leaf rosette and stem succulent, leaf rosette succulent, leaf rosette succulent (tall), leaf succulent, stem succulent, stem succulent (short), stem succulent (tall), succulent  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| not succulent | not_succulent |
| succulent (unspecified) | succulent, succulent_leaves, succulent_stems |


## Leaf type

**TRY categories:** broadleaved, needleleaved, photosynthetic stem, scale-shaped, scale-shaped/needleleaved  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| broadleaved | broadleaf, broadleaf needle |
| leafless / photosynthetic stem | leafless |
| needleleaved | broadleaf needle, needle |
| scale-shaped | scale |


## Habitat adaptation

**TRY categories:** aquatic, aquatic/semiaquatic, semiaquatic, terrestrial  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| (other/no direct match) | hemiepiphyte |
| aquatic | aquatic, aquatic semiaquatic, aquatic terrestrial |
| epiphyte | epiphyte, epiphyte lithophyte, epiphyte lithophyte terrestrial, epiphyte terrestrial |
| lithophyte | epiphyte lithophyte, epiphyte lithophyte terrestrial, hemiepiphyte lithophyte, hemiepiphyte lithophyte terrestrial, lithophyte, lithophyte terrestrial |
| semiaquatic | aquatic semiaquatic, semiaquatic, semiaquatic terrestrial |
| terrestrial | aquatic terrestrial, epiphyte lithophyte terrestrial, epiphyte terrestrial, hemiepiphyte lithophyte terrestrial, lithophyte terrestrial, semiaquatic terrestrial, terrestrial |


## Parasitism type

**TRY categories:** hemiparasitic, holoparasitic, independent, parasitic  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| hemiparasitic | hemiparasitic, hemiparasitic parasitic, hemiparasitic root_parasitic |
| independent / non-parasitic | not_parasitic |
| parasitic (unspecified) | hemiparasitic parasitic, hemiparasitic root_parasitic, not_parasitic, parasitic, root_parasitic, stem_parasitic |
| root parasitic | hemiparasitic root_parasitic, root_parasitic |
| stem parasitic | stem_parasitic |


## Carnivory type

**TRY categories:** carnivorous, detritivorous  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| carnivorous | carnivorous |
| nutrient mining | nutrient_mining |
| saprophytic | saprophyte |


## Mycorrhiza type

**TRY categories:** (n/a in enhanced table)  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| (other/no direct match) | cluster_roots, dauciform_root, fine_roots long_root_hairs, hemiparasitic_root, long_root_hairs, proteoid_root, root_hairs, sand-binding (+1 more) |
| arbuscular (AM) | arbuscular_mycorrhizal, arbuscular_mycorrhizal cluster_roots, arbuscular_mycorrhizal dauciform_root sand-binding, arbuscular_mycorrhizal ectomycorrhizal, arbuscular_mycorrhizal ectomycorrhizal proteoid_root, arbuscular_mycorrhizal hemiparasitic_root, arbuscular_mycorrhizal non_mycorrhizal, arbuscular_mycorrhizal proteoid_root (+1 more) |
| carnivorous root | carnivorous, carnivorous fine_roots long_root_hairs, carnivorous non_mycorrhizal |
| ectomycorrhizal (ECM) | arbuscular_mycorrhizal ectomycorrhizal, arbuscular_mycorrhizal ectomycorrhizal proteoid_root, ectomycorrhizal |
| ericoid | ericoid_mycorrhizal |
| mycorrhizal (unspecified) | arbuscular_mycorrhizal, arbuscular_mycorrhizal cluster_roots, arbuscular_mycorrhizal dauciform_root sand-binding, arbuscular_mycorrhizal ectomycorrhizal, arbuscular_mycorrhizal ectomycorrhizal proteoid_root, arbuscular_mycorrhizal hemiparasitic_root, arbuscular_mycorrhizal non_mycorrhizal, arbuscular_mycorrhizal proteoid_root (+8 more) |
| non-mycorrhizal | arbuscular_mycorrhizal, arbuscular_mycorrhizal cluster_roots, arbuscular_mycorrhizal dauciform_root sand-binding, arbuscular_mycorrhizal ectomycorrhizal, arbuscular_mycorrhizal ectomycorrhizal proteoid_root, arbuscular_mycorrhizal hemiparasitic_root, arbuscular_mycorrhizal non_mycorrhizal, arbuscular_mycorrhizal proteoid_root (+8 more) |
| orchid | orchid_mycorrhizal |
| parasitic root | parasitic_root |


## Photosynthesis pathway

**TRY categories:** (n/a in enhanced table)  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| C3 | c3, c3 c4, c3 cam, c3-c4, c3-cam |
| C4 | c3 c4, c3-c4, c4, c4-cam |
| CAM | c3 cam, c3-cam, c4-cam, cam, facultative_cam |
| unknown | unknown |


## Leaf phenology

**TRY categories:** (n/a in enhanced table)  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| deciduous | deciduous, deciduous evergreen, drought_deciduous, evergreen facultative_drought_deciduous, facultative_drought_deciduous, semi_deciduous |
| drought-deciduous | drought_deciduous, evergreen facultative_drought_deciduous, facultative_drought_deciduous |
| evergreen | deciduous evergreen, evergreen, evergreen facultative_drought_deciduous |
| facultative evergreen | evergreen facultative_drought_deciduous, facultative_drought_deciduous |
| semi-deciduous | semi_deciduous |


## Frost tolerance

**TRY categories:** (n/a in enhanced table)  
**AusTraits terms grouped by suggested mapping:**  
| Proposed bucket | AusTraits values (sample) |
|---|---|
| frost intolerant | intolerant |
| long duration snow (months) | days months not_applicable weeks, days months weeks |
| medium duration snow (weeks) | days months not_applicable weeks, days months weeks, days not_applicable weeks, days weeks, weeks |
| no snow exposure recorded | days months not_applicable weeks, days not_applicable weeks, not_applicable |
| short duration snow (days) | days, days months not_applicable weeks, days months weeks, days not_applicable weeks, days weeks |

