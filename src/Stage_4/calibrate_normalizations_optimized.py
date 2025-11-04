#!/usr/bin/env python3
"""
Calibrate normalization parameters - OPTIMIZED with DuckDB

Uses DuckDB queries instead of pandas filtering for 10-100× speedup.
Uses all 92 phylogenetic eigenvectors.

Output: data/stage4/normalization_params_v3.json
"""

import json
import duckdb
import numpy as np
import pandas as pd
from pathlib import Path
from collections import Counter
from tqdm import tqdm
from scipy.spatial.distance import pdist


def build_climate_compatibility(con, plants_path):
    """Build climate compatibility matrix using vectorized numpy operations."""

    print("\nBuilding climate compatibility matrix...")

    # Load just climate data (faster than full dataset)
    query = f'''
    SELECT
        wfo_taxon_id,
        "wc2.1_30s_bio_1_q05" / 10.0 as temp_min,
        "wc2.1_30s_bio_1_q95" / 10.0 as temp_max,
        "wc2.1_30s_bio_12_q05" as precip_min,
        "wc2.1_30s_bio_12_q95" as precip_max
    FROM read_parquet('{plants_path}')
    WHERE phylo_ev1 IS NOT NULL
    '''
    plants_climate = con.execute(query).fetchdf()

    compatibility = {}
    all_species = plants_climate['wfo_taxon_id'].values

    for idx, plant_a in tqdm(plants_climate.iterrows(), total=len(plants_climate), desc="Computing compatibility"):
        # Vectorized compatibility check
        temp_overlap = (
            np.maximum(plant_a['temp_min'], plants_climate['temp_min']) <
            np.minimum(plant_a['temp_max'], plants_climate['temp_max'])
        )

        precip_overlap = (
            np.maximum(plant_a['precip_min'], plants_climate['precip_min']) <
            np.minimum(plant_a['precip_max'], plants_climate['precip_max'])
        )

        compatible = temp_overlap & precip_overlap & (plants_climate.index != idx)
        compatible_ids = plants_climate.loc[compatible, 'wfo_taxon_id'].tolist()
        compatibility[plant_a['wfo_taxon_id']] = compatible_ids

    # Stats
    compat_counts = [len(v) for v in compatibility.values()]
    print(f"  Mean compatible: {np.mean(compat_counts):.0f}")
    print(f"  Median compatible: {np.median(compat_counts):.0f}")

    return compatibility, all_species


def sample_climate_compatible_guild(n_plants, compatibility, all_species):
    """Sample climate-compatible guild."""
    for _ in range(50):  # Max attempts
        anchor_id = np.random.choice(all_species)
        compatible = compatibility.get(anchor_id, [])

        if len(compatible) >= n_plants - 1:
            others = np.random.choice(compatible, size=n_plants-1, replace=False)
            return [anchor_id] + list(others)

    # Fallback
    return list(np.random.choice(all_species, size=n_plants, replace=False))


def compute_raw_scores_duckdb(guild_ids, con):
    """Compute raw scores using DuckDB queries (FAST - queries in-memory tables)."""

    n_plants = len(guild_ids)
    scores = {}

    # Convert guild_ids to SQL list
    guild_sql = ','.join(f"'{pid}'" for pid in guild_ids)

    # === N1: Pathogen fungi (DuckDB query on in-memory table) ===
    query = f'''
    SELECT pathogenic_fungi, pathogenic_fungi_host_specific
    FROM fungi
    WHERE plant_wfo_id IN ({guild_sql})
    '''
    fungi_df = con.execute(query).fetchdf()

    pathogen_counts = Counter()
    host_specific = set()

    for _, row in fungi_df.iterrows():
        if row['pathogenic_fungi'] is not None and isinstance(row['pathogenic_fungi'], (list, np.ndarray)) and len(row['pathogenic_fungi']) > 0:
            for fungus in row['pathogenic_fungi']:
                pathogen_counts[fungus] += 1

        if row['pathogenic_fungi_host_specific'] is not None and isinstance(row['pathogenic_fungi_host_specific'], (list, np.ndarray)):
            host_specific.update(row['pathogenic_fungi_host_specific'])

    n1_raw = 0
    for fungus, count in pathogen_counts.items():
        if count >= 2:
            overlap_ratio = count / n_plants
            severity = 1.0 if fungus in host_specific else 0.6
            n1_raw += (overlap_ratio ** 2) * severity
    scores['n1_raw'] = n1_raw

    # === N2: Herbivores (DuckDB query on in-memory table) ===
    query = f'''
    SELECT herbivores, flower_visitors, pollinators
    FROM organisms
    WHERE plant_wfo_id IN ({guild_sql})
    '''
    org_df = con.execute(query).fetchdf()

    herbivore_counts = Counter()
    visitor_counts = Counter()

    for _, row in org_df.iterrows():
        if row['herbivores'] is not None and isinstance(row['herbivores'], (list, np.ndarray)) and len(row['herbivores']) > 0:
            for herb in row['herbivores']:
                herbivore_counts[herb] += 1

        for col in ['flower_visitors', 'pollinators']:
            if row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0:
                for vis in row[col]:
                    visitor_counts[vis] += 1

    n2_raw = 0
    for herbivore, count in herbivore_counts.items():
        if count >= 2 and herbivore not in visitor_counts:
            overlap_ratio = count / n_plants
            n2_raw += (overlap_ratio ** 2) * 0.5
    scores['n2_raw'] = n2_raw

    # === N4: CSR conflicts (DuckDB query on in-memory table) ===
    query = f'''
    SELECT C as CSR_C, S as CSR_S
    FROM plants
    WHERE wfo_taxon_id IN ({guild_sql})
    '''
    csr_df = con.execute(query).fetchdf()

    HIGH_C = 60
    HIGH_S = 60
    n4_raw = 0

    high_c_count = (csr_df['CSR_C'] > HIGH_C).sum()
    high_s_count = (csr_df['CSR_S'] > HIGH_S).sum()

    # C-C conflicts
    if high_c_count >= 2:
        n4_raw += high_c_count * (high_c_count - 1) / 2

    # C-S conflicts
    n4_raw += high_c_count * high_s_count * 0.6

    scores['n4_raw'] = n4_raw

    # === P3: Beneficial fungi (DuckDB query on in-memory table) ===
    query = f'''
    SELECT amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi
    FROM fungi
    WHERE plant_wfo_id IN ({guild_sql})
    '''
    benef_df = con.execute(query).fetchdf()

    beneficial_counts = Counter()
    plants_with_beneficial = 0

    for _, row in benef_df.iterrows():
        has_any = False
        for col in ['amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi']:
            if row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0:
                has_any = True
                for fungus in row[col]:
                    beneficial_counts[fungus] += 1

        if has_any:
            plants_with_beneficial += 1

    network_raw = sum(count / n_plants for fungus, count in beneficial_counts.items() if count >= 2)
    coverage_ratio = plants_with_beneficial / n_plants
    p3_raw = network_raw * 0.6 + coverage_ratio * 0.4
    scores['p3_raw'] = p3_raw

    # === P4: Phylogenetic diversity (DuckDB query on in-memory table with ALL 92 EVs) ===
    ev_cols_query = ', '.join([f'phylo_ev{i}' for i in range(1, 93)])
    query = f'''
    SELECT {ev_cols_query}
    FROM plants
    WHERE wfo_taxon_id IN ({guild_sql})
    '''
    phylo_df = con.execute(query).fetchdf()

    if len(phylo_df) >= 2:
        ev_matrix = phylo_df.values
        distances = pdist(ev_matrix, metric='euclidean')
        p4_raw = np.mean(distances)
    else:
        p4_raw = 0.0
    scores['p4_raw'] = p4_raw

    # === P5: Height stratification (DuckDB query on in-memory table) ===
    query = f'''
    SELECT height_m
    FROM plants
    WHERE wfo_taxon_id IN ({guild_sql}) AND height_m IS NOT NULL
    '''
    height_df = con.execute(query).fetchdf()

    if len(height_df) >= 2:
        p5_raw = height_df['height_m'].max() - height_df['height_m'].min()
    else:
        p5_raw = 0.0
    scores['p5_raw'] = p5_raw

    # === P6: Shared pollinators (DuckDB query) ===
    # Already loaded org_df above
    pollinator_counts = Counter()
    for _, row in org_df.iterrows():
        for col in ['flower_visitors', 'pollinators']:
            if row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0:
                for poll in row[col]:
                    pollinator_counts[poll] += 1

    p6_raw = sum((count / n_plants) ** 2 for poll, count in pollinator_counts.items() if count >= 2)
    scores['p6_raw'] = p6_raw

    return scores


def main():
    """Main calibration workflow."""

    print("="*80)
    print("NORMALIZATION CALIBRATION - OPTIMIZED WITH DUCKDB")
    print("="*80)

    con = duckdb.connect()

    # Paths
    plants_path = 'model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet'
    organisms_path = 'data/stage4/plant_organism_profiles.parquet'
    fungi_path = 'data/stage4/plant_fungal_guilds_hybrid.parquet'

    print("\nLoading parquet files into DuckDB tables...")
    print(f"  Plants: {plants_path}")
    print(f"  Organisms: {organisms_path}")
    print(f"  Fungi: {fungi_path}")

    # Load parquet files into in-memory DuckDB tables ONCE
    con.execute(f"CREATE TABLE plants AS SELECT * FROM read_parquet('{plants_path}')")
    con.execute(f"CREATE TABLE organisms AS SELECT * FROM read_parquet('{organisms_path}')")
    con.execute(f"CREATE TABLE fungi AS SELECT * FROM read_parquet('{fungi_path}')")

    print("✓ All data loaded into DuckDB tables")

    # Build compatibility
    compatibility, all_species = build_climate_compatibility(con, plants_path)

    # Generate guilds
    print("\n" + "="*80)
    print("GENERATING 100,000 CALIBRATION GUILDS")
    print("="*80)

    guilds = []

    # 80,000 climate-compatible
    print("\nSampling 80,000 climate-compatible guilds...")
    for _ in tqdm(range(80000), desc="Climate-compatible"):
        guild = sample_climate_compatible_guild(5, compatibility, all_species)
        guilds.append(guild)

    # 10,000 pure random
    print("\nSampling 10,000 pure random guilds...")
    for _ in tqdm(range(10000), desc="Pure random"):
        guild = list(np.random.choice(all_species, size=5, replace=False))
        guilds.append(guild)

    # 5,000 low phylo diversity (same family)
    print("\nSampling 5,000 low-diversity guilds...")
    families_query = '''
    SELECT family, LIST(wfo_taxon_id) as species
    FROM plants
    WHERE phylo_ev1 IS NOT NULL
    GROUP BY family
    HAVING COUNT(*) >= 5
    '''
    families_df = con.execute(families_query).fetchdf()

    for _ in tqdm(range(5000), desc="Low diversity"):
        family_row = families_df.sample(1).iloc[0]
        species_list = family_row['species']
        guild = list(np.random.choice(species_list, size=5, replace=False))
        guilds.append(guild)

    # 5,000 additional random
    print("\nSampling 5,000 additional random guilds...")
    for _ in tqdm(range(5000), desc="Additional"):
        guild = list(np.random.choice(all_species, size=5, replace=False))
        guilds.append(guild)

    print(f"\nTotal guilds: {len(guilds):,}")

    # Compute raw scores with DuckDB
    print("\n" + "="*80)
    print("COMPUTING RAW SCORES (with DuckDB optimization)")
    print("="*80)

    raw_scores = {
        'n1_raw': [], 'n2_raw': [], 'n4_raw': [],
        'p3_raw': [], 'p4_raw': [], 'p5_raw': [], 'p6_raw': []
    }

    for guild in tqdm(guilds, desc="Computing scores"):
        try:
            scores = compute_raw_scores_duckdb(guild, con)
            for key in raw_scores:
                raw_scores[key].append(scores[key])
        except Exception as e:
            print(f"\nError scoring guild: {e}")

    # Compute percentiles
    print("\n" + "="*80)
    print("COMPUTING NORMALIZATION PARAMETERS")
    print("="*80)

    params = {}

    component_names = {
        'n1_raw': 'N1: Pathogen Fungi',
        'n2_raw': 'N2: Herbivores',
        'n4_raw': 'N4: CSR Conflicts',
        'p3_raw': 'P3: Beneficial Fungi',
        'p4_raw': 'P4: Phylogenetic Diversity (92 EVs)',
        'p5_raw': 'P5: Height Stratification',
        'p6_raw': 'P6: Shared Pollinators'
    }

    for key, name in component_names.items():
        scores_array = np.array(raw_scores[key])

        params[key.replace('_raw', '')] = {
            'method': 'percentile',
            'p5': float(np.percentile(scores_array, 5)),
            'p25': float(np.percentile(scores_array, 25)),
            'p50': float(np.percentile(scores_array, 50)),
            'p75': float(np.percentile(scores_array, 75)),
            'p95': float(np.percentile(scores_array, 95)),
            'mean': float(np.mean(scores_array)),
            'std': float(np.std(scores_array)),
            'n_samples': len(scores_array)
        }

        print(f"\n{name}:")
        print(f"  Percentiles: {params[key.replace('_raw', '')]['p5']:.4f}, {params[key.replace('_raw', '')]['p25']:.4f}, {params[key.replace('_raw', '')]['p50']:.4f}, {params[key.replace('_raw', '')]['p75']:.4f}, {params[key.replace('_raw', '')]['p95']:.4f}")

    # Save
    output_path = Path('data/stage4/normalization_params_v3.json')
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w') as f:
        json.dump(params, f, indent=2)

    print(f"\n✓ Saved: {output_path}")

    print("\n" + "="*80)
    print("CALIBRATION COMPLETE")
    print("="*80)
    print(f"\nCalibration based on {len(guilds):,} guilds (10× larger sample)")
    print(f"Key improvement: P4 now uses all 92 eigenvectors")
    print(f"DuckDB optimization: In-memory tables for fast filtering")


if __name__ == '__main__':
    main()
