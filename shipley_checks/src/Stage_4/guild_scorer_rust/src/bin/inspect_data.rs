use guild_scorer_rust::GuildScorer;
use std::collections::HashMap;

fn main() -> anyhow::Result<()> {
    // Initialize scorer (which loads data)
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")?;
    let data = scorer.data();

    println!("\n=== INSPECTING DATA FOR FUNGI-INSECT MATCHES ===\n");

    // 1. Get known parasites: Herbivore -> [Fungi]
    let parasites = &data.insect_parasites;
    println!("Found {} known insect-fungal parasite relationships.", parasites.len());

    // 2. Build reverse map: Fungus -> [Herbivores]
    let mut fungus_to_herbs: HashMap<String, Vec<String>> = HashMap::new();
    for (herb, fungi) in parasites {
        for f in fungi {
            fungus_to_herbs.entry(f.clone()).or_default().push(herb.clone());
        }
    }
    
    // DEBUG: Print some fungus keys
    println!("Sample known fungi: {:?}", fungus_to_herbs.keys().take(5).collect::<Vec<_>>());

    // 3. Scan plants for Fungi
    // We need to find a plant that has one of these fungi
    // Since we can't easily iterate the LazyFrame without collecting, we'll use the EAGER dataframe `data.fungi`
    // (The code has `pub fungi: DataFrame`)
    
    use polars::prelude::*;
    let fungi_df = &data.fungi;
    
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;
    let entomo_col = fungi_df.column("entomopathogenic_fungi")?;
    
    // We need to iterate rows. 
    // Note: In Phase 0-4 parquet, this might be a List column or String column.
    // The loading code handles both, but returns a DataFrame. 
    // Let's check the schema or just try to iterate.
    
    let mut found_count = 0;
    
    // Helper to extract strings from column value
    fn get_strings(val: AnyValue) -> Vec<String> {
        match val {
            AnyValue::List(series) => {
                series.str().unwrap().into_iter().flatten().map(|s| s.to_string()).collect()
            },
            AnyValue::String(s) => {
                 s.split('|').map(|x| x.to_string()).filter(|x| !x.is_empty()).collect()
            },
            _ => vec![],
        }
    }
    
    // DEBUG: Print first 5 rows of entomo_col
    println!("Inspecting first 5 rows of fungi data:");
    let mut non_empty_count = 0;
    
    for idx in 0..fungi_df.height() {
        let val = entomo_col.get(idx)?;
        let s = get_strings(val);
        
        if !s.is_empty() {
            non_empty_count += 1;
            if non_empty_count <= 5 {
                println!("  Row {} (Plant {}): {:?}", idx, plant_ids.get(idx).unwrap(), s);
            }
            
            // Check for match immediately
            for fungus in s {
                let fungus_lower = fungus.to_lowercase();
                
                // DEBUG: Print if we find a fungus that is in our lookup
                if fungus_to_herbs.contains_key(&fungus_lower) {
                    println!("  -> Fungus '{}' IS in lookup!", fungus_lower);
                } else if non_empty_count <= 5 {
                    println!("  -> Fungus '{}' NOT in lookup", fungus_lower);
                }

                if let Some(herbs) = fungus_to_herbs.get(&fungus_lower) {
                     // Found a potential match!
                     let target_herb = &herbs[0];
                     
                     // Now find a plant with this herbivore
                     let org_df = &data.organisms;
                     let org_plant_ids = org_df.column("plant_wfo_id")?.str()?;
                     let herbivores_col = org_df.column("herbivores")?;
                     
                     for o_idx in 0..org_df.height() {
                        let o_val = herbivores_col.get(o_idx)?;
                        let herbs_on_plant = get_strings(o_val);
                        
                        if herbs_on_plant.contains(&target_herb.to_string()) {
                            let herb_plant_id = org_plant_ids.get(o_idx).unwrap();
                            
                            println!("!!! MATCH FOUND !!!");
                            println!("Herbivore: {}", target_herb);
                            println!("Fungus: {}", fungus_lower);
                            println!("Plant A (Vulnerable): {}", herb_plant_id);
                            println!("Plant B (Protective): {}", plant_ids.get(idx).unwrap());
                            
                            found_count += 1;
                            if found_count >= 5 {
                                return Ok(());
                            }
                            break; // Next herbivore plant
                        }
                     }
                }
            }
        }
    }
    
    println!("Total non-empty rows in fungi_df: {}", non_empty_count);
    
    
    // Remove the old loop since we integrated it above
    if found_count == 0 {
        println!("No matches found in the loaded data.");
    }

    Ok(())
}

