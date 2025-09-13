#!/usr/bin/env python3
"""
Filter GBIF occurrences to only the 654 species with sufficient data (≥3 occurrences)
Based on has_sufficient_data flag in species_bioclim_summary.csv
"""
import csv
import os

# Paths
base_dir = '/home/olier/ellenberg/data/bioclim_extractions_bioclim_first'
summary_file = os.path.join(base_dir, 'summary_stats/species_bioclim_summary.csv')
input_file = os.path.join(base_dir, 'all_occurrences_cleaned.csv')
output_file = os.path.join(base_dir, 'all_occurrences_cleaned_654.csv')

print("=" * 60)
print("FILTERING OCCURRENCES TO 654 SPECIES SUBSET")
print("=" * 60)
print()

# Step 1: Load species with sufficient data
keep = set()
species_count = 0

print("Reading species summary...")
with open(summary_file, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        # Check if has_sufficient_data is True
        if str(row.get('has_sufficient_data', '')).strip().lower() in ('true', '1', 't', 'yes', 'y'):
            keep.add(row['species'])
            species_count += 1

print(f"Found {species_count} species with sufficient data (≥3 occurrences)")
print()

# Step 2: Filter occurrences
print("Filtering occurrences...")
print(f"Input: {input_file}")
print(f"Output: {output_file}")
print()

total_rows = 0
kept_rows = 0

with open(input_file, newline='', encoding='utf-8') as fin, \
     open(output_file, 'w', newline='', encoding='utf-8') as fout:
    
    reader = csv.DictReader(fin)
    writer = csv.DictWriter(fout, fieldnames=reader.fieldnames)
    writer.writeheader()
    
    # Process in batches for progress reporting
    for i, row in enumerate(reader):
        total_rows += 1
        
        # Check if species_clean is in our keep set
        if row.get('species_clean') in keep:
            writer.writerow(row)
            kept_rows += 1
        
        # Progress reporting every 500,000 rows
        if (i + 1) % 500000 == 0:
            print(f"  Processed {i+1:,} rows... ({kept_rows:,} kept)")

print()
print("=" * 60)
print("FILTERING COMPLETE")
print("=" * 60)
print(f"Total rows processed: {total_rows:,}")
print(f"Rows kept (654 species): {kept_rows:,}")
print(f"Rows filtered out: {total_rows - kept_rows:,}")
print(f"Retention rate: {kept_rows/total_rows*100:.2f}%")
print()
print(f"Output saved to: {output_file}")
print(f"File size: Check with 'ls -lh {output_file}'")