#!/usr/bin/env python3
"""
Stage 4.4: Compute Complete Compatibility Matrix

Computes all pairwise plant compatibility scores with organism evidence for frontend explanations.
Uses Python multiprocessing for parallelization.

Usage:
    python src/Stage_4/04_compute_compatibility_matrix.py
    python src/Stage_4/04_compute_compatibility_matrix.py --test --cores 8
"""

import argparse
import duckdb
import pandas as pd
from multiprocessing import Pool, cpu_count
from pathlib import Path
from datetime import datetime
import time

# Global variables for worker processes
profiles_dict = None
benefit_matrix = None
benefit_details_dict = None
fungal_dict = None  # NEW: fungal guild profiles

def init_worker(profiles, benefits, details, fungal_profiles):
    """Initialize worker process with shared data."""
    global profiles_dict, benefit_matrix, benefit_details_dict, fungal_dict
    profiles_dict = profiles
    benefit_matrix = benefits
    benefit_details_dict = details
    fungal_dict = fungal_profiles  # NEW

def compute_compatibility(pair):
    """Compute compatibility score for a plant pair with organism evidence."""
    plant_a, plant_b = pair

    # Get organism profiles
    prof_a = profiles_dict.get(plant_a, {'pollinators': set(), 'herbivores': set(), 'pathogens': set()})
    prof_b = profiles_dict.get(plant_b, {'pollinators': set(), 'herbivores': set(), 'pathogens': set()})

    # Extract organism intersections for frontend explanations
    shared_poll = prof_a['pollinators'] & prof_b['pollinators']
    shared_herb = prof_a['herbivores'] & prof_b['herbivores']
    shared_path = prof_a['pathogens'] & prof_b['pathogens']

    # Component 1: Shared pollinators (positive, +0.15)
    union_poll = prof_a['pollinators'] | prof_b['pollinators']
    shared_pollinators_score = len(shared_poll) / len(union_poll) if len(union_poll) > 0 else 0.0

    # Component 2: Predators of B's pests from A (positive, +0.25)
    predators_a_helps_b = benefit_matrix.get((plant_a, plant_b), 0)
    max_help_b = len(prof_b['herbivores']) if len(prof_b['herbivores']) > 0 else 1
    help_b_score = min(predators_a_helps_b / max_help_b, 1.0)

    # Component 3: Predators of A's pests from B (positive, +0.25)
    predators_b_helps_a = benefit_matrix.get((plant_b, plant_a), 0)
    max_help_a = len(prof_a['herbivores']) if len(prof_a['herbivores']) > 0 else 1
    help_a_score = min(predators_b_helps_a / max_help_a, 1.0)

    # Component 4: Herbivore diversification (positive, +0.10)
    union_herb = prof_a['herbivores'] | prof_b['herbivores']
    herbivore_diversity = 1 - (len(shared_herb) / len(union_herb) if len(union_herb) > 0 else 0)

    # Component 5: Pathogen diversification (positive, +0.20)
    union_path = prof_a['pathogens'] | prof_b['pathogens']
    pathogen_diversity = 1 - (len(shared_path) / len(union_path) if len(union_path) > 0 else 0)

    # Component 6: Shared herbivores (negative, -0.25)
    shared_herbivores_score = len(shared_herb) / len(union_herb) if len(union_herb) > 0 else 0.0

    # Component 7: Shared pathogens (negative, -0.40)
    shared_pathogens_score = len(shared_path) / len(union_path) if len(union_path) > 0 else 0.0

    # Component 8: Pollinator competition (negative, -0.05)
    pollinator_competition = shared_pollinators_score

    # === FUNGAL GUILD COMPONENTS (NEW) ===

    # Get fungal guild profiles
    fungi_a = fungal_dict.get(plant_a, {
        'pathogenic_fungi': set(),
        'pathogenic_host_specific': set(),
        'amf_fungi': set(),
        'emf_fungi': set(),
        'biocontrol_fungi': set(),
        'endophytic_fungi': set(),
        'saprotrophic_fungi': set(),
        'trichoderma_count': 0,
        'beauveria_metarhizium_count': 0
    })
    fungi_b = fungal_dict.get(plant_b, {
        'pathogenic_fungi': set(),
        'pathogenic_host_specific': set(),
        'amf_fungi': set(),
        'emf_fungi': set(),
        'biocontrol_fungi': set(),
        'endophytic_fungi': set(),
        'saprotrophic_fungi': set(),
        'trichoderma_count': 0,
        'beauveria_metarhizium_count': 0
    })

    # Component 9: Pathogenic Fungi (NEGATIVE, host-specific vs generalist weighting)
    shared_path_fungi = fungi_a['pathogenic_fungi'] & fungi_b['pathogenic_fungi']
    shared_path_host_specific = fungi_a['pathogenic_host_specific'] & fungi_b['pathogenic_host_specific']
    union_path_fungi = fungi_a['pathogenic_fungi'] | fungi_b['pathogenic_fungi']

    host_specific_weight = len(shared_path_host_specific) / len(union_path_fungi) if union_path_fungi else 0.0
    generalist_weight = (len(shared_path_fungi) - len(shared_path_host_specific)) / len(union_path_fungi) if union_path_fungi else 0.0

    pathogenic_fungi_score = -0.50 * host_specific_weight - 0.30 * generalist_weight

    # Component 10: Mycorrhizal Fungi (POSITIVE, +0.20)
    shared_myc = (fungi_a['amf_fungi'] | fungi_a['emf_fungi']) & (fungi_b['amf_fungi'] | fungi_b['emf_fungi'])
    union_myc = (fungi_a['amf_fungi'] | fungi_a['emf_fungi']) | (fungi_b['amf_fungi'] | fungi_b['emf_fungi'])
    mycorrhizae_score = 0.20 * (len(shared_myc) / len(union_myc) if union_myc else 0.0)

    # Component 11: Biocontrol Fungi (POSITIVE, +0.15)
    shared_biocontrol = fungi_a['biocontrol_fungi'] & fungi_b['biocontrol_fungi']
    union_biocontrol = fungi_a['biocontrol_fungi'] | fungi_b['biocontrol_fungi']
    biocontrol_score = 0.15 * (len(shared_biocontrol) / len(union_biocontrol) if union_biocontrol else 0.0)

    # Component 12: Endophytic Fungi (POSITIVE, +0.15) - NEW
    shared_endophytic = fungi_a['endophytic_fungi'] & fungi_b['endophytic_fungi']
    union_endophytic = fungi_a['endophytic_fungi'] | fungi_b['endophytic_fungi']
    endophytic_score = 0.15 * (len(shared_endophytic) / len(union_endophytic) if union_endophytic else 0.0)

    # Component 13: Saprotrophic Fungi (POSITIVE, +0.10) - NEW
    shared_saprotroph = fungi_a['saprotrophic_fungi'] & fungi_b['saprotrophic_fungi']
    union_saprotroph = fungi_a['saprotrophic_fungi'] | fungi_b['saprotrophic_fungi']
    saprotrophic_score = 0.10 * (len(shared_saprotroph) / len(union_saprotroph) if union_saprotroph else 0.0)

    # Component 14: Trichoderma Multi-Guild (POSITIVE, +0.10) - NEW
    trichoderma_score = 0.0
    if fungi_a['trichoderma_count'] > 0 and fungi_b['trichoderma_count'] > 0:
        trichoderma_score = 0.10

    # Component 15: Beauveria/Metarhizium Enhanced (POSITIVE, +0.25) - ENHANCED
    beauveria_score = 0.0
    if fungi_a['beauveria_metarhizium_count'] > 0 and fungi_b['beauveria_metarhizium_count'] > 0:
        beauveria_score = 0.25  # Was +0.15 biocontrol only, now +0.15 biocontrol + 0.10 endophyte

    # Component 16: Synergy Multiplier - NEW
    # Count how many guilds are present for BOTH plants
    guilds_a = sum([
        len(fungi_a['amf_fungi'] | fungi_a['emf_fungi']) > 0,
        len(fungi_a['endophytic_fungi']) > 0,
        len(fungi_a['biocontrol_fungi']) > 0,
        len(fungi_a['saprotrophic_fungi']) > 0
    ])
    guilds_b = sum([
        len(fungi_b['amf_fungi'] | fungi_b['emf_fungi']) > 0,
        len(fungi_b['endophytic_fungi']) > 0,
        len(fungi_b['biocontrol_fungi']) > 0,
        len(fungi_b['saprotrophic_fungi']) > 0
    ])

    # Apply synergy multiplier only if BOTH plants have complete networks
    min_guilds = min(guilds_a, guilds_b)
    if min_guilds >= 4:
        synergy_multiplier = 1.30
    elif min_guilds == 3:
        synergy_multiplier = 1.20
    elif min_guilds == 2:
        synergy_multiplier = 1.10
    else:
        synergy_multiplier = 1.00

    # === FINAL COMPATIBILITY SCORE ===

    # Calculate base components
    non_fungal = (
        0.15 * shared_pollinators_score +
        0.25 * help_b_score +
        0.25 * help_a_score +
        0.10 * herbivore_diversity +
        0.20 * pathogen_diversity -
        0.25 * shared_herbivores_score -
        0.40 * shared_pathogens_score -
        0.05 * pollinator_competition
    )

    # Separate positive and negative fungal components
    positive_fungal = max(0, mycorrhizae_score + biocontrol_score + endophytic_score +
                          saprotrophic_score + trichoderma_score + beauveria_score)
    negative_fungal = min(0, pathogenic_fungi_score)

    # Apply synergy multiplier ONLY to positive fungal components
    compatibility = non_fungal + (positive_fungal * synergy_multiplier) + negative_fungal

    # Prepare evidence for frontend (limit to top 10 per category for readability)
    evidence = {
        'shared_pollinator_list': sorted(list(shared_poll))[:10],
        'shared_herbivore_list': sorted(list(shared_herb))[:10],
        'shared_pathogen_list': sorted(list(shared_path))[:10],
        'beneficial_predators_a_to_b': benefit_details_dict.get((plant_a, plant_b), [])[:10],
        'beneficial_predators_b_to_a': benefit_details_dict.get((plant_b, plant_a), [])[:10],
        # Fungal evidence
        'shared_pathogenic_fungi': sorted(list(shared_path_fungi))[:10],
        'shared_mycorrhizae': sorted(list(shared_myc))[:10],
        'shared_biocontrol': sorted(list(shared_biocontrol))[:10],
        'shared_endophytic': sorted(list(shared_endophytic))[:10],
        'shared_saprotrophic': sorted(list(shared_saprotroph))[:10],
    }

    # Store component scores
    components = {
        'shared_pollinators': shared_pollinators_score,
        'predators_a_helps_b': help_b_score,
        'predators_b_helps_a': help_a_score,
        'herbivore_diversity': herbivore_diversity,
        'pathogen_diversity': pathogen_diversity,
        'shared_herbivores': shared_herbivores_score,
        'shared_pathogens': shared_pathogens_score,
        'pollinator_competition': pollinator_competition,
        # Fungal components
        'pathogenic_fungi': pathogenic_fungi_score,
        'mycorrhizae': mycorrhizae_score,
        'biocontrol': biocontrol_score,
        'endophytic': endophytic_score,
        'saprotrophic': saprotrophic_score,
        'trichoderma': trichoderma_score,
        'beauveria_metarhizium': beauveria_score,
        'synergy_multiplier': synergy_multiplier
    }

    # Store counts
    counts = {
        'shared_pollinator_count': len(shared_poll),
        'shared_herbivore_count': len(shared_herb),
        'shared_pathogen_count': len(shared_path),
        'beneficial_predator_count_a_to_b': predators_a_helps_b,
        'beneficial_predator_count_b_to_a': predators_b_helps_a,
        # Fungal counts
        'shared_pathogenic_fungi_count': len(shared_path_fungi),
        'shared_mycorrhizae_count': len(shared_myc),
        'shared_biocontrol_count': len(shared_biocontrol),
        'shared_endophytic_count': len(shared_endophytic),
        'shared_saprotrophic_count': len(shared_saprotroph),
        'guilds_a': guilds_a,
        'guilds_b': guilds_b
    }

    return (plant_a, plant_b, compatibility, components, evidence, counts)

def compute_compatibility_matrix(test_mode=False, n_cores=None):
    """Compute full pairwise compatibility matrix with multiprocessing."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.4: Compute Compatibility Matrix")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if test_mode:
        print("TEST MODE: Using test data")
    print()

    # Determine number of cores
    if n_cores is None:
        n_cores = cpu_count()
    print(f"Using {n_cores} cores for parallel computation")
    print()

    con = duckdb.connect()

    # Load required data
    suffix = '_test' if test_mode else ''

    profiles_file = output_dir / f'plant_organism_profiles{suffix}.parquet'
    benefits_file = output_dir / f'cross_plant_benefits{suffix}.parquet'
    details_file = output_dir / f'cross_plant_benefit_details{suffix}.parquet'
    fungal_file = output_dir / f'plant_fungal_guilds_hybrid{suffix}.parquet'  # HYBRID approach

    if not all([profiles_file.exists(), benefits_file.exists(), details_file.exists(), fungal_file.exists()]):
        print("ERROR: Required files not found!")
        print("Run scripts 01, 01_hybrid, 02, and 03 first")
        print(f"Missing files:")
        if not profiles_file.exists(): print(f"  - {profiles_file}")
        if not benefits_file.exists(): print(f"  - {benefits_file}")
        if not details_file.exists(): print(f"  - {details_file}")
        if not fungal_file.exists(): print(f"  - {fungal_file}")
        return

    print("Step 1: Loading data into memory...")
    print(f"  - Plant profiles: {profiles_file}")
    print(f"  - Cross-plant benefits: {benefits_file}")
    print(f"  - Benefit details: {details_file}")
    print(f"  - Fungal guilds: {fungal_file}")  # NEW

    # Load plant profiles
    profiles_df = con.execute(f"""
        SELECT plant_wfo_id, pollinators, herbivores, pathogens
        FROM read_parquet('{profiles_file}')
    """).fetchdf()

    # Convert to dict for fast lookup
    profiles = {}
    for _, row in profiles_df.iterrows():
        poll_raw = row['pollinators']
        herb_raw = row['herbivores']
        path_raw = row['pathogens']

        profiles[row['plant_wfo_id']] = {
            'pollinators': set(poll_raw) if poll_raw is not None and len(poll_raw) > 0 else set(),
            'herbivores': set(herb_raw) if herb_raw is not None and len(herb_raw) > 0 else set(),
            'pathogens': set(path_raw) if path_raw is not None and len(path_raw) > 0 else set()
        }

    print(f"  - Loaded profiles for {len(profiles):,} plants")

    # Load fungal guild profiles (NEW)
    fungal_df = con.execute(f"""
        SELECT plant_wfo_id,
               pathogenic_fungi, pathogenic_fungi_host_specific,
               amf_fungi, emf_fungi,
               mycoparasite_fungi, entomopathogenic_fungi,
               endophytic_fungi, saprotrophic_fungi,
               trichoderma_count, beauveria_metarhizium_count
        FROM read_parquet('{fungal_file}')
    """).fetchdf()

    # Convert to dict for fast lookup
    fungal_profiles = {}
    for _, row in fungal_df.iterrows():
        # Combine biocontrol into single set
        biocontrol_raw = set()
        if row['mycoparasite_fungi'] is not None and len(row['mycoparasite_fungi']) > 0:
            biocontrol_raw.update(row['mycoparasite_fungi'])
        if row['entomopathogenic_fungi'] is not None and len(row['entomopathogenic_fungi']) > 0:
            biocontrol_raw.update(row['entomopathogenic_fungi'])

        fungal_profiles[row['plant_wfo_id']] = {
            'pathogenic_fungi': set(row['pathogenic_fungi']) if row['pathogenic_fungi'] is not None and len(row['pathogenic_fungi']) > 0 else set(),
            'pathogenic_host_specific': set(row['pathogenic_fungi_host_specific']) if row['pathogenic_fungi_host_specific'] is not None and len(row['pathogenic_fungi_host_specific']) > 0 else set(),
            'amf_fungi': set(row['amf_fungi']) if row['amf_fungi'] is not None and len(row['amf_fungi']) > 0 else set(),
            'emf_fungi': set(row['emf_fungi']) if row['emf_fungi'] is not None and len(row['emf_fungi']) > 0 else set(),
            'biocontrol_fungi': biocontrol_raw,
            'endophytic_fungi': set(row['endophytic_fungi']) if row['endophytic_fungi'] is not None and len(row['endophytic_fungi']) > 0 else set(),
            'saprotrophic_fungi': set(row['saprotrophic_fungi']) if row['saprotrophic_fungi'] is not None and len(row['saprotrophic_fungi']) > 0 else set(),
            'trichoderma_count': row['trichoderma_count'],
            'beauveria_metarhizium_count': row['beauveria_metarhizium_count']
        }

    print(f"  - Loaded fungal guilds for {len(fungal_profiles):,} plants")

    # Load benefits matrix
    benefits_df = con.execute(f"""
        SELECT plant_a, plant_b, beneficial_predator_count
        FROM read_parquet('{benefits_file}')
    """).fetchdf()

    benefit_matrix = {}
    for _, row in benefits_df.iterrows():
        benefit_matrix[(row['plant_a'], row['plant_b'])] = row['beneficial_predator_count']

    print(f"  - Loaded {len(benefit_matrix):,} benefit relationships")

    # Load benefit details
    details_df = con.execute(f"""
        SELECT plant_a, plant_b, beneficial_details
        FROM read_parquet('{details_file}')
    """).fetchdf()

    benefit_details = {}
    for _, row in details_df.iterrows():
        benefit_details[(row['plant_a'], row['plant_b'])] = row['beneficial_details']

    print(f"  - Loaded {len(benefit_details):,} benefit detail records")
    print()

    # Generate all unique pairs (upper triangle)
    plant_ids = list(profiles.keys())
    pairs = [(plant_ids[i], plant_ids[j])
             for i in range(len(plant_ids))
             for j in range(i+1, len(plant_ids))]

    print(f"Step 2: Computing {len(pairs):,} pairwise compatibilities...")
    print(f"  - This will take approximately {len(pairs) * 0.002 / n_cores / 60:.1f} minutes")
    print()

    start_time = time.time()

    # Parallel computation
    with Pool(n_cores, initializer=init_worker, initargs=(profiles, benefit_matrix, benefit_details, fungal_profiles)) as pool:
        results = pool.map(compute_compatibility, pairs, chunksize=1000)

    elapsed = time.time() - start_time
    print(f"  - Computation completed in {elapsed/60:.1f} minutes")
    print(f"  - Average time per pair: {elapsed/len(pairs)*1000:.2f} ms")
    print()

    # Convert to DataFrame with all fields
    print("Step 3: Converting results to DataFrame...")
    results_df = pd.DataFrame([
        {
            'plant_a_wfo': r[0],
            'plant_b_wfo': r[1],
            'compatibility_score': r[2],
            # Component scores
            **{f'component_{k}': v for k, v in r[3].items()},
            # Evidence (organism lists)
            **r[4],
            # Counts
            **r[5]
        }
        for r in results
    ])

    print(f"  - Created DataFrame with {len(results_df):,} rows and {len(results_df.columns)} columns")
    print()

    # Step 4: Save
    output_file = output_dir / f'compatibility_matrix_full{suffix}.parquet'
    print(f"Step 4: Saving to {output_file}...")
    results_df.to_parquet(output_file, compression='zstd', index=False)

    file_size_mb = output_file.stat().st_size / 1e6
    print(f"  - Saved {len(results_df):,} compatibility scores with organism evidence")
    print(f"  - File size: {file_size_mb:.1f} MB")
    print()

    # Summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    stats = con.execute("""
        SELECT
            COUNT(*) as total_pairs,
            AVG(compatibility_score) as mean_score,
            STDDEV(compatibility_score) as std_score,
            MIN(compatibility_score) as min_score,
            MAX(compatibility_score) as max_score,
            PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY compatibility_score) as q25,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY compatibility_score) as median,
            PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY compatibility_score) as q75
        FROM results_df
    """).fetchone()

    print(f"Compatibility Scores:")
    print(f"  - Total pairs: {stats[0]:,}")
    print(f"  - Mean: {stats[1]:.3f}")
    print(f"  - Std Dev: {stats[2]:.3f}")
    print(f"  - Min: {stats[3]:.3f}")
    print(f"  - Max: {stats[4]:.3f}")
    print(f"  - Quartiles: {stats[5]:.3f}, {stats[6]:.3f}, {stats[7]:.3f}")
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Compute compatibility matrix with multiprocessing')
    parser.add_argument('--test', action='store_true', help='Run in test mode')
    parser.add_argument('--cores', type=int, default=None, help='Number of cores to use (default: all)')

    args = parser.parse_args()

    compute_compatibility_matrix(test_mode=args.test, n_cores=args.cores)
