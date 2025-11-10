#!/usr/bin/env python3
"""
Stage 4.2b: Extract Insect-Fungal Parasite Network

Extracts entomopathogenic fungus → insect/mite relationships from full GloBI dataset
to enable specific biological control matching in guild compatibility scoring.

This data supports Herbivore Control (P1) via specific entomopathogenic fungi:
- Plant B hosts fungus X → Fungus X parasitizes herbivore Y → Herbivore Y attacks Plant A
- Therefore: Plant B provides fungal biocontrol benefit to Plant A

Usage:
    python src/Stage_4/02b_extract_insect_fungal_parasites.py
"""

import duckdb
from pathlib import Path
from datetime import datetime

def extract_insect_fungal_parasites():
    """Extract entomopathogenic fungus → insect relationships from full GloBI."""

    output_dir = Path('shipley_checks/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.2b: Extract Insect-Fungal Parasite Network (11,711 Plants)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    GLOBI_PATH = 'data/stage1/globi_interactions_original.parquet'

    print("Extracting fungus → insect/mite parasitic relationships from GloBI...")
    print("  (Scanning 20M+ rows - may take 2-3 minutes)")
    print()

    result = con.execute(f"""
        SELECT
            targetTaxonName as herbivore,
            targetTaxonFamilyName as herbivore_family,
            targetTaxonOrderName as herbivore_order,
            targetTaxonClassName as herbivore_class,
            LIST(DISTINCT sourceTaxonName) as entomopathogenic_fungi,
            COUNT(DISTINCT sourceTaxonName) as fungal_parasite_count
        FROM read_parquet('{GLOBI_PATH}')
        WHERE sourceTaxonKingdomName = 'Fungi'
          AND targetTaxonKingdomName = 'Animalia'
          AND targetTaxonClassName IN ('Insecta', 'Arachnida')
          AND interactionTypeName IN ('pathogenOf', 'parasiteOf', 'parasitoidOf', 'hasHost', 'kills')
        GROUP BY targetTaxonName, targetTaxonFamilyName, targetTaxonOrderName, targetTaxonClassName
        HAVING COUNT(DISTINCT sourceTaxonName) > 0
        ORDER BY fungal_parasite_count DESC
    """).fetchdf()

    print(f"  ✓ Extracted {len(result):,} herbivores with fungal parasites")
    print()

    # Save
    output_file = output_dir / 'insect_fungal_parasites_11711.parquet'
    print(f"Saving to {output_file}...")
    result.to_parquet(output_file, compression='zstd', index=False)
    print(f"  ✓ Saved")
    print()

    # Summary
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    # Get unique fungi count separately (UNNEST in subquery)
    unique_fungi_count = con.execute("""
        SELECT COUNT(DISTINCT fungus) as unique_fungi
        FROM (
            SELECT UNNEST(entomopathogenic_fungi) as fungus
            FROM result
        )
    """).fetchone()[0]

    stats = con.execute("""
        SELECT
            COUNT(*) as total_herbivores,
            SUM(fungal_parasite_count) as total_relationships,
            AVG(fungal_parasite_count) as avg_fungi_per_herbivore,
            MAX(fungal_parasite_count) as max_fungi_per_herbivore
        FROM result
    """).fetchone()

    total_herb, total_rel, avg_fungi, max_fungi = stats

    print(f"Total herbivores: {total_herb:,}")
    print(f"Total fungus-herbivore relationships: {total_rel:,}")
    print(f"Unique entomopathogenic fungi: {unique_fungi_count:,}")
    print(f"Average fungi per herbivore: {avg_fungi:.1f}")
    print(f"Max fungi per herbivore: {max_fungi}")
    print()

    # Breakdown by class
    print("Breakdown by taxonomic class:")
    by_class = con.execute("""
        SELECT
            herbivore_class,
            COUNT(*) as herbivore_count,
            SUM(fungal_parasite_count) as relationship_count
        FROM result
        GROUP BY herbivore_class
        ORDER BY herbivore_count DESC
    """).fetchdf()
    print(by_class.to_string(index=False))
    print()

    # Top 10 most parasitized herbivores
    print("Top 10 most parasitized herbivores:")
    top = con.execute("""
        SELECT
            herbivore,
            herbivore_order,
            fungal_parasite_count,
            entomopathogenic_fungi[1:3] as example_fungi
        FROM result
        ORDER BY fungal_parasite_count DESC
        LIMIT 10
    """).fetchdf()
    print(top.to_string(index=False))
    print()

    # Key pest coverage (examples)
    print("Coverage of key agricultural pests:")
    pests = [
        'Tetranychus urticae',  # Spider mite
        'Planococcus citri',    # Mealybug
        'Spodoptera litura',    # Armyworm
        'Myzus persicae',       # Green peach aphid
        'Bemisia tabaci'        # Whitefly
    ]

    pest_coverage = con.execute("""
        SELECT
            herbivore,
            fungal_parasite_count,
            entomopathogenic_fungi[1:3] as example_fungi
        FROM result
        WHERE herbivore IN (SELECT UNNEST(?))
        ORDER BY fungal_parasite_count DESC
    """, [pests]).fetchdf()

    if len(pest_coverage) > 0:
        print(pest_coverage.to_string(index=False))
    else:
        print("  - None of the example pests found")
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    extract_insect_fungal_parasites()
