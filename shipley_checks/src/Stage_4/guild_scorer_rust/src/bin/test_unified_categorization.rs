//! Test unified taxonomic categorization

use guild_scorer_rust::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};

fn main() {
    println!("=== Testing Unified Categorization ===\n");

    let test_cases = vec![
        ("Aphis fabae", Some(OrganismRole::Herbivore)),
        ("Platycheirus scutatus", Some(OrganismRole::Predator)),
        ("Platycheirus scutatus", Some(OrganismRole::Pollinator)),
        ("Bombus terrestris", Some(OrganismRole::Pollinator)),
        ("Adalia bipunctata", Some(OrganismRole::Predator)),
        ("Aceria fraxini", Some(OrganismRole::Herbivore)),
        ("Apis mellifera", Some(OrganismRole::Pollinator)),
        ("Amara aenea", Some(OrganismRole::Predator)),
        ("Myzus persicae", Some(OrganismRole::Herbivore)),
        ("Cantharis fusca", Some(OrganismRole::Predator)),
    ];

    for (name, role) in test_cases {
        let category = OrganismCategory::from_name(name, role);
        let role_str = match role {
            Some(OrganismRole::Herbivore) => "herbivore",
            Some(OrganismRole::Predator) => "predator",
            Some(OrganismRole::Pollinator) => "pollinator",
            None => "unknown",
        };
        println!("{} ({}) → {}", name, role_str, category.display_name());
    }

    println!("\n✓ All categorization tests completed");
}
