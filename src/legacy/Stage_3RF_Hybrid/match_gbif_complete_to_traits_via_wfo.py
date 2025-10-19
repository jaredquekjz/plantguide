#!/usr/bin/env python3
"""
Match 386K GBIF species with 1,068 trait species via WFO normalization.
Combines approaches from match_gbif_names.py and normalize_eive_to_wfo_EXACT.R
"""

import os
import csv
import json
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple
import subprocess
from tqdm import tqdm

def normalize_name_for_matching(name: str) -> str:
    """
    Normalize species name using WFO-style normalization from R script.
    """
    if not name:
        return ""
    
    # Remove hybrid markers (× and x between words)
    name = re.sub(r'^×\s*', '', name)
    name = re.sub(r'\s*×\s*', ' ', name)
    name = re.sub(r'(^|\s)x(\s+)', ' ', name)
    
    # Convert to lowercase and clean whitespace
    name = name.lower().strip()
    name = re.sub(r'\s+', ' ', name)
    
    # Remove subspecies/variety indicators for broader matching
    # But keep them for a second pass if needed
    base_name = re.sub(r'\s+(subsp\.|var\.|f\.|forma|subspecies|variety).*', '', name)
    
    return base_name

def extract_gbif_species_names(gbif_dir: Path, sample_size: int = None) -> Dict[str, str]:
    """
    Extract all species names from GBIF occurrence files.
    Returns mapping of normalized name -> original filename
    """
    print("Extracting species names from GBIF files...")
    
    # Use find command to get all .csv.gz files
    cmd = f"find {gbif_dir} -name '*.csv.gz' -type f"
    if sample_size:
        cmd += f" | head -{sample_size}"
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    files = result.stdout.strip().split('\n')
    
    species_map = {}
    invalid_count = 0
    
    for filepath in tqdm(files, desc="Processing GBIF files"):
        if not filepath:
            continue
            
        # Extract species name from filename
        filename = os.path.basename(filepath)
        species_name = filename.replace('.csv.gz', '').replace('-', ' ')
        
        # Skip invalid entries
        if species_name.startswith('taxon '):
            invalid_count += 1
            continue
        
        # Normalize for matching
        normalized = normalize_name_for_matching(species_name)
        
        if normalized and len(normalized) > 3:  # Skip very short names
            # Store both normalized and original
            if normalized not in species_map:
                species_map[normalized] = {
                    'original': species_name,
                    'filepath': filepath,
                    'normalized': normalized
                }
    
    print(f"  Extracted {len(species_map)} valid species (skipped {invalid_count} invalid)")
    return species_map

def load_wfo_backbone(wfo_file: Path) -> Dict[str, str]:
    """
    Load WFO backbone for synonym resolution.
    Returns mapping of name -> accepted name
    """
    print("Loading WFO backbone...")
    
    wfo_map = {}
    accepted_names = {}
    
    # Try different encodings
    encodings = ['utf-8', 'latin-1', 'windows-1252', 'iso-8859-1']
    encoding_found = None
    
    for encoding in encodings:
        try:
            with open(wfo_file, 'r', encoding=encoding) as f:
                reader = csv.DictReader(f, delimiter='\t')
                # Test read first line
                next(reader)
                encoding_found = encoding
                print(f"  Using encoding: {encoding}")
                break
        except (UnicodeDecodeError, StopIteration):
            continue
    
    if not encoding_found:
        print("  Warning: Could not determine encoding, using latin-1 with errors='ignore'")
        encoding_found = 'latin-1'
    
    # First pass: load accepted names
    with open(wfo_file, 'r', encoding=encoding_found, errors='ignore') as f:
        reader = csv.DictReader(f, delimiter='\t')
        
        for row in reader:
            sci_name = row.get('scientificName', '').strip()
            if not sci_name:
                continue
                
            normalized = normalize_name_for_matching(sci_name)
            status = row.get('taxonomicStatus', '')
            
            if status == 'Accepted':
                accepted_names[row['taxonID']] = sci_name
                wfo_map[normalized] = sci_name
    
    # Second pass: resolve synonyms
    with open(wfo_file, 'r', encoding=encoding_found, errors='ignore') as f:
        reader = csv.DictReader(f, delimiter='\t')
        
        for row in reader:
            if row.get('taxonomicStatus') == 'Synonym' and row.get('acceptedNameUsageID'):
                sci_name = row.get('scientificName', '').strip()
                accepted_id = row['acceptedNameUsageID']
                
                if accepted_id in accepted_names:
                    normalized = normalize_name_for_matching(sci_name)
                    if normalized not in wfo_map:  # Don't override accepted names
                        wfo_map[normalized] = accepted_names[accepted_id]
    
    print(f"  Loaded {len(wfo_map)} WFO mappings")
    return wfo_map

def load_trait_species(trait_file: Path) -> Dict[str, str]:
    """
    Load trait species (already WFO-normalized).
    Returns mapping of normalized name -> original name
    """
    print("Loading trait species...")
    
    species_map = {}
    with open(trait_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            original = row['wfo_accepted_name']
            normalized = normalize_name_for_matching(original)
            species_map[normalized] = original
    
    print(f"  Loaded {len(species_map)} trait species")
    return species_map

def match_species(gbif_species: Dict, trait_species: Dict, wfo_map: Dict) -> Tuple[List, List]:
    """
    Match GBIF species with trait species using WFO normalization.
    """
    print("\nMatching species...")
    
    matched = []
    unmatched_traits = []
    
    # Track which trait species we've matched
    matched_traits = set()
    
    # First pass: direct matching
    for trait_norm, trait_orig in trait_species.items():
        if trait_norm in gbif_species:
            matched.append({
                'trait_name': trait_orig,
                'trait_normalized': trait_norm,
                'gbif_name': gbif_species[trait_norm]['original'],
                'gbif_file': gbif_species[trait_norm]['filepath'],
                'match_type': 'direct'
            })
            matched_traits.add(trait_norm)
    
    print(f"  Direct matches: {len(matched)}")
    
    # Second pass: match via WFO synonyms
    initial_matches = len(matched)
    
    for trait_norm, trait_orig in trait_species.items():
        if trait_norm in matched_traits:
            continue
            
        # Check if trait name has WFO synonyms that match GBIF
        if trait_norm in wfo_map:
            wfo_accepted = normalize_name_for_matching(wfo_map[trait_norm])
            if wfo_accepted in gbif_species:
                matched.append({
                    'trait_name': trait_orig,
                    'trait_normalized': trait_norm,
                    'gbif_name': gbif_species[wfo_accepted]['original'],
                    'gbif_file': gbif_species[wfo_accepted]['filepath'],
                    'match_type': 'wfo_synonym'
                })
                matched_traits.add(trait_norm)
    
    print(f"  WFO synonym matches: {len(matched) - initial_matches}")
    
    # Third pass: check GBIF names against WFO for trait species
    initial_matches = len(matched)
    
    # Create reverse mapping of GBIF species through WFO
    gbif_to_wfo = {}
    for gbif_norm in gbif_species:
        if gbif_norm in wfo_map:
            wfo_accepted = normalize_name_for_matching(wfo_map[gbif_norm])
            if wfo_accepted not in gbif_to_wfo:
                gbif_to_wfo[wfo_accepted] = gbif_norm
    
    for trait_norm, trait_orig in trait_species.items():
        if trait_norm in matched_traits:
            continue
            
        if trait_norm in gbif_to_wfo:
            gbif_norm = gbif_to_wfo[trait_norm]
            matched.append({
                'trait_name': trait_orig,
                'trait_normalized': trait_norm,
                'gbif_name': gbif_species[gbif_norm]['original'],
                'gbif_file': gbif_species[gbif_norm]['filepath'],
                'match_type': 'wfo_resolved'
            })
            matched_traits.add(trait_norm)
    
    print(f"  WFO-resolved matches: {len(matched) - initial_matches}")
    
    # Collect unmatched
    for trait_norm, trait_orig in trait_species.items():
        if trait_norm not in matched_traits:
            unmatched_traits.append({
                'trait_name': trait_orig,
                'trait_normalized': trait_norm
            })
    
    return matched, unmatched_traits

def main():
    # Configuration
    gbif_dir = Path("/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete")
    trait_file = Path("/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv")
    wfo_file = Path("/home/olier/ellenberg/data/classification.csv")
    output_file = Path("/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json")
    
    print("=== Matching GBIF Complete Dataset with Trait Species via WFO ===\n")
    
    # For testing, use a sample; for production, set to None
    SAMPLE_SIZE = None  # Process ALL files to find European species
    
    # Extract GBIF species
    gbif_species = extract_gbif_species_names(gbif_dir, sample_size=SAMPLE_SIZE)
    
    # Load WFO backbone
    wfo_map = load_wfo_backbone(wfo_file)
    
    # Load trait species
    trait_species = load_trait_species(trait_file)
    
    # Match species
    matched, unmatched = match_species(gbif_species, trait_species, wfo_map)
    
    # Summary
    print("\n=== Results ===")
    print(f"Total trait species: {len(trait_species)}")
    print(f"Matched with GBIF: {len(matched)} ({100*len(matched)/len(trait_species):.1f}%)")
    print(f"Unmatched: {len(unmatched)} ({100*len(unmatched)/len(trait_species):.1f}%)")
    
    # Match type breakdown
    match_types = {}
    for m in matched:
        mt = m['match_type']
        match_types[mt] = match_types.get(mt, 0) + 1
    
    print("\nMatch types:")
    for mt, count in match_types.items():
        print(f"  {mt}: {count}")
    
    # Save results
    results = {
        'summary': {
            'total_trait_species': len(trait_species),
            'gbif_species_processed': len(gbif_species),
            'matched': len(matched),
            'unmatched': len(unmatched),
            'match_types': match_types,
            'sample_size': SAMPLE_SIZE
        },
        'matched_species': matched,
        'unmatched_species': unmatched
    }
    
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: {output_file}")
    
    # Show samples
    if unmatched:
        print("\nSample unmatched trait species:")
        for sp in unmatched[:10]:
            print(f"  - {sp['trait_name']}")
        if len(unmatched) > 10:
            print(f"  ... and {len(unmatched)-10} more")
    
    print("\nNote: Processing first 50K GBIF files as a test.")
    print("Set SAMPLE_SIZE=None to process all 386K files (will take longer).")

if __name__ == "__main__":
    main()