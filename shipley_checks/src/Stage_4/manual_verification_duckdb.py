#!/usr/bin/env python3
"""
Manual Verification of Organism Counts Using DuckDB

Direct SQL queries of source parquet files to confirm report counts.
This provides independent verification of the R scorer and verification script.

Usage:
    python manual_verification_duckdb.py

Output:
    Console output showing organism counts for all test guilds
"""

import duckdb

con = duckdb.connect()

# Test guilds
guilds = {
    'Forest Garden': [
        'wfo-0000832453', 'wfo-0000649136', 'wfo-0000642673',
        'wfo-0000984977', 'wfo-0000241769', 'wfo-0000092746',
        'wfo-0000690499'
    ],
    'Competitive Clash': [
        'wfo-0000757278', 'wfo-0000944034', 'wfo-0000186915',
        'wfo-0000421791', 'wfo-0000418518', 'wfo-0000841021',
        'wfo-0000394258'
    ],
    'Stress Tolerant': [
        'wfo-0000721951', 'wfo-0000955348', 'wfo-0000901050',
        'wfo-0000956222', 'wfo-0000777518', 'wfo-0000349035',
        'wfo-0000209726'
    ]
}

print("="*80)
print("MANUAL VERIFICATION OF ORGANISM COUNTS USING DUCKDB")
print("="*80)

for guild_name, plant_ids in guilds.items():
    print(f"\n{'='*80}")
    print(f"GUILD: {guild_name}")
    print(f"{'='*80}")
    print(f"Plants: {len(plant_ids)}")
    print(f"Plant IDs: {', '.join(plant_ids)}")

    # Convert to SQL list format
    plant_ids_sql = "('" + "','".join(plant_ids) + "')"

    # ========================================================================
    # M5: BENEFICIAL FUNGI VERIFICATION
    # ========================================================================
    print(f"\n{'-'*80}")
    print("M5: BENEFICIAL FUNGI (AMF + EMF + Endophytic + Saprotrophic)")
    print(f"{'-'*80}")

    # Query fungal data
    fungal_query = f"""
    SELECT
        plant_wfo_id,
        amf_fungi,
        emf_fungi,
        endophytic_fungi,
        saprotrophic_fungi
    FROM read_parquet('shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet')
    WHERE plant_wfo_id IN {plant_ids_sql}
    ORDER BY plant_wfo_id
    """

    fungal_data = con.execute(fungal_query).fetchall()

    # Manual counting logic (matches R scorer)
    organism_counts = {}
    total_unique = set()

    for row in fungal_data:
        plant_id, amf, emf, endo, sapro = row
        plant_organisms = set()

        # Collect all fungi for this plant
        for fungi_list in [amf, emf, endo, sapro]:
            if fungi_list is not None:
                for fungus in fungi_list:
                    if fungus is not None and fungus != '':
                        plant_organisms.add(fungus)
                        total_unique.add(fungus)

        # Count each organism's occurrence across plants
        for org in plant_organisms:
            organism_counts[org] = organism_counts.get(org, 0) + 1

    # Filter for shared (count >= 2)
    shared_fungi = {org: count for org, count in organism_counts.items() if count >= 2}

    print(f"Total unique beneficial fungi: {len(total_unique)}")
    print(f"Shared fungi (2+ plants): {len(shared_fungi)}")

    if len(shared_fungi) > 0:
        print(f"\nShared fungi breakdown (first 10):")
        for i, (org, count) in enumerate(sorted(shared_fungi.items(), key=lambda x: -x[1])[:10]):
            print(f"  {org}: {count} plants")

    # ========================================================================
    # M7: POLLINATOR VERIFICATION
    # ========================================================================
    print(f"\n{'-'*80}")
    print("M7: POLLINATORS (pollinators + flower_visitors)")
    print(f"{'-'*80}")

    # Query organism data
    organism_query = f"""
    SELECT
        plant_wfo_id,
        pollinators,
        flower_visitors
    FROM read_parquet('shipley_checks/stage4/plant_organism_profiles_11711.parquet')
    WHERE plant_wfo_id IN {plant_ids_sql}
    ORDER BY plant_wfo_id
    """

    organism_data = con.execute(organism_query).fetchall()

    # Manual counting logic (matches R scorer)
    pollinator_counts = {}
    total_unique_poll = set()

    for row in organism_data:
        plant_id, pollinators, visitors = row
        plant_pollinators = set()

        # Collect all pollinators for this plant
        for poll_list in [pollinators, visitors]:
            if poll_list is not None:
                for pollinator in poll_list:
                    if pollinator is not None and pollinator != '':
                        plant_pollinators.add(pollinator)
                        total_unique_poll.add(pollinator)

        # Count each organism's occurrence across plants
        for org in plant_pollinators:
            pollinator_counts[org] = pollinator_counts.get(org, 0) + 1

    # Filter for shared (count >= 2)
    shared_pollinators = {org: count for org, count in pollinator_counts.items() if count >= 2}

    print(f"Total unique pollinators: {len(total_unique_poll)}")
    print(f"Shared pollinators (2+ plants): {len(shared_pollinators)}")

    if len(shared_pollinators) > 0:
        print(f"\nShared pollinator breakdown:")
        for org, count in sorted(shared_pollinators.items(), key=lambda x: -x[1]):
            print(f"  {org}: {count} plants")

print(f"\n{'='*80}")
print("VERIFICATION COMPLETE")
print(f"{'='*80}\n")

con.close()
