#!/usr/bin/env python3
"""
Match trait species from model_data_complete_case_with_myco.csv 
with the complete GBIF matched dataset to maximize species overlap.
"""

import json
import csv
import os
from pathlib import Path
from typing import Dict, List, Set

def normalize_name(name: str) -> str:
    """Normalize species name for matching"""
    if not name:
        return ""
    # Remove extra spaces, lowercase, replace separators
    name = name.lower().strip()
    name = name.replace("-", " ")
    name = name.replace("_", " ")
    # Remove multiple spaces
    name = " ".join(name.split())
    return name

def load_trait_species(trait_file: Path) -> Dict[str, str]:
    """Load trait species and return normalized name mapping"""
    species_map = {}
    
    with open(trait_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            original = row['wfo_accepted_name']
            normalized = normalize_name(original)
            species_map[normalized] = original
    
    return species_map

def load_gbif_matches(gbif_file: Path) -> Dict[str, Dict]:
    """Load GBIF matched species"""
    with open(gbif_file, 'r') as f:
        matches = json.load(f)
    
    # Create normalized name mapping
    gbif_map = {}
    for match in matches:
        if match['match_type'] in ['EXACT', 'FUZZY']:
            # Use scientific name from GBIF match
            original = match['scientific_name']
            normalized = normalize_name(original)
            gbif_map[normalized] = match
            
            # Also try canonical name if available
            if match.get('gbif_canonical_name'):
                canonical_norm = normalize_name(match['gbif_canonical_name'])
                if canonical_norm not in gbif_map:
                    gbif_map[canonical_norm] = match
    
    return gbif_map

def find_gbif_occurrences(species_name: str, gbif_dir: Path) -> str:
    """Check if GBIF occurrence file exists for species"""
    # Convert to slug format used in filenames
    slug = species_name.lower().replace(" ", "-")
    
    # Check in complete dataset
    complete_file = gbif_dir / f"{slug}.csv.gz"
    if complete_file.exists():
        return str(complete_file)
    
    # Check in model species directory  
    model_file = Path(f"/home/olier/ellenberg/data/gbif_occurrences_model_species/{slug}.csv.gz")
    if model_file.exists():
        return str(model_file)
    
    return None

def main():
    # Paths
    trait_file = Path("/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv")
    gbif_matches_file = Path("/home/olier/plantsdatabase/data/Stage_4/gbif_matched/_gbif_matches_compact.json")
    gbif_complete_dir = Path("/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete")
    output_file = Path("/home/olier/ellenberg/artifacts/trait_gbif_matches_complete.json")
    
    print("=== Matching Trait Species with Complete GBIF Dataset ===\n")
    
    # Load data
    print("Loading trait species...")
    trait_species = load_trait_species(trait_file)
    print(f"  Loaded {len(trait_species)} trait species")
    
    print("\nLoading GBIF matches...")
    gbif_matches = load_gbif_matches(gbif_matches_file)
    print(f"  Loaded {len(gbif_matches)} GBIF matched species")
    
    # Match species
    print("\n=== Matching Results ===")
    matched = []
    unmatched = []
    
    for norm_name, original_name in trait_species.items():
        if norm_name in gbif_matches:
            match_info = gbif_matches[norm_name]
            
            # Check for occurrence file
            occurrence_file = find_gbif_occurrences(match_info['scientific_name'], gbif_complete_dir)
            
            matched.append({
                'trait_name': original_name,
                'normalized': norm_name,
                'gbif_match': match_info,
                'occurrence_file': occurrence_file,
                'has_occurrences': occurrence_file is not None
            })
        else:
            unmatched.append({
                'trait_name': original_name,
                'normalized': norm_name
            })
    
    # Summary statistics
    print(f"\nTotal trait species: {len(trait_species)}")
    print(f"Matched with GBIF: {len(matched)} ({100*len(matched)/len(trait_species):.1f}%)")
    print(f"Unmatched: {len(unmatched)} ({100*len(unmatched)/len(trait_species):.1f}%)")
    
    # Check occurrence availability
    with_occurrences = sum(1 for m in matched if m['has_occurrences'])
    print(f"\nMatched species with occurrence files: {with_occurrences}")
    print(f"Matched species without occurrence files: {len(matched) - with_occurrences}")
    
    # Match type breakdown
    exact_matches = sum(1 for m in matched if m['gbif_match']['match_type'] == 'EXACT')
    fuzzy_matches = sum(1 for m in matched if m['gbif_match']['match_type'] == 'FUZZY')
    print(f"\nMatch quality:")
    print(f"  Exact matches: {exact_matches}")
    print(f"  Fuzzy matches: {fuzzy_matches}")
    
    # Save results
    results = {
        'summary': {
            'total_trait_species': len(trait_species),
            'matched': len(matched),
            'unmatched': len(unmatched),
            'with_occurrences': with_occurrences,
            'exact_matches': exact_matches,
            'fuzzy_matches': fuzzy_matches
        },
        'matched_species': matched,
        'unmatched_species': unmatched
    }
    
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: {output_file}")
    
    # Show sample of unmatched
    if unmatched:
        print("\nSample of unmatched species:")
        for species in unmatched[:10]:
            print(f"  - {species['trait_name']}")
        if len(unmatched) > 10:
            print(f"  ... and {len(unmatched) - 10} more")
    
    # Show sample of matched without occurrences
    no_occ = [m for m in matched if not m['has_occurrences']]
    if no_occ:
        print("\nSample of matched species without occurrence files:")
        for species in no_occ[:10]:
            print(f"  - {species['trait_name']} -> {species['gbif_match']['scientific_name']}")
        if len(no_occ) > 10:
            print(f"  ... and {len(no_occ) - 10} more")

if __name__ == "__main__":
    main()