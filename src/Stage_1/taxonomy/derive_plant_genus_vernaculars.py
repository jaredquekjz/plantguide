#!/usr/bin/env python3
"""Derive plant genus vernacular categories from species-level data"""

import duckdb
import re
from collections import Counter
import pandas as pd

print("=== Deriving Plant Genus Vernacular Names ===\n")

con = duckdb.connect()

# Get all PLANTS with genus + vernacular names
data = con.execute("""
    SELECT
        p.genus,
        p.scientific_name as plant_name,
        p.inat_all_vernaculars as vernacular_names
    FROM read_parquet('/home/olier/ellenberg/data/taxonomy/plants_vernacular_final.parquet') p
    WHERE p.genus IS NOT NULL
      AND p.inat_all_vernaculars IS NOT NULL
""").fetchdf()

print(f"Plant species with genus + vernacular names: {len(data):,}\n")

# Group by genus and derive category
genus_categories = {}

for genus in data['genus'].unique():
    if not genus or str(genus) == 'nan':
        continue

    # Get all vernacular names for this genus
    genus_data = data[data['genus'] == genus]
    n_species_with_vern = len(genus_data)

    # Combine all vernacular names
    all_vernaculars = ' '.join(genus_data['vernacular_names'].dropna().astype(str))

    # Tokenize into words (English-focused)
    words = re.findall(r'\b[a-zA-Z]{3,}\b', all_vernaculars.lower())

    # Remove common stopwords
    stopwords = {'the', 'and', 'or', 'of', 'in', 'on', 'a', 'an', 'for', 'with',
                 'to', 'from', 'by', 'as', 'at', 'leaved', 'leaf'}
    words = [w for w in words if w not in stopwords]

    # Count word frequencies
    word_freq = Counter(words)

    if len(word_freq) == 0:
        continue

    # Get top 10 most common words
    top_words = word_freq.most_common(10)

    # Plant-specific category keywords
    category_keywords = {
        # Growth forms
        'tree': ['tree', 'trees'],
        'shrub': ['shrub', 'shrubs', 'bush', 'bushes'],
        'herb': ['herb', 'herbs', 'herbaceous'],
        'grass': ['grass', 'grasses'],
        'fern': ['fern', 'ferns'],
        'vine': ['vine', 'vines', 'climber', 'creeper'],
        'cactus': ['cactus', 'cacti'],
        'palm': ['palm', 'palms'],
        'succulent': ['succulent', 'succulents'],

        # Common plant groups
        'rose': ['rose', 'roses'],
        'lily': ['lily', 'lilies'],
        'orchid': ['orchid', 'orchids'],
        'daisy': ['daisy', 'daisies'],
        'aster': ['aster', 'asters'],
        'mint': ['mint', 'mints'],
        'pea': ['pea', 'peas', 'bean', 'beans', 'legume'],
        'mustard': ['mustard', 'mustards', 'cabbage'],
        'carrot': ['carrot', 'carrots', 'parsley'],
        'nightshade': ['nightshade', 'nightshades', 'potato', 'tomato'],
        'sunflower': ['sunflower', 'sunflowers'],

        # Trees
        'oak': ['oak', 'oaks'],
        'maple': ['maple', 'maples'],
        'pine': ['pine', 'pines'],
        'fir': ['fir', 'firs'],
        'spruce': ['spruce'],
        'cedar': ['cedar', 'cedars'],
        'birch': ['birch', 'birches'],
        'willow': ['willow', 'willows'],
        'ash': ['ash'],
        'elm': ['elm', 'elms'],
        'poplar': ['poplar', 'poplars', 'aspen'],
        'beech': ['beech', 'beeches'],
        'hickory': ['hickory', 'hickories'],
        'walnut': ['walnut', 'walnuts'],
        'cherry': ['cherry', 'cherries'],
        'apple': ['apple', 'apples'],
        'plum': ['plum', 'plums'],

        # Other
        'sedge': ['sedge', 'sedges'],
        'rush': ['rush', 'rushes'],
        'moss': ['moss', 'mosses'],
        'liverwort': ['liverwort', 'liverworts'],
        'algae': ['algae', 'alga', 'seaweed'],
    }

    # Find dominant category
    category_scores = {}
    for category, keywords in category_keywords.items():
        score = sum(word_freq.get(kw, 0) for kw in keywords)
        if score > 0:
            category_scores[category] = score

    if category_scores:
        dominant_category = max(category_scores, key=category_scores.get)
        dominant_score = category_scores[dominant_category]
        total_words = sum(word_freq.values())

        # Only keep if dominant category has at least 10% of total word frequency
        if dominant_score / total_words >= 0.10:
            genus_categories[genus] = {
                'genus': genus,
                'n_species_with_vernaculars': n_species_with_vern,
                'dominant_category': dominant_category,
                'dominant_score': dominant_score,
                'total_word_count': total_words,
                'category_percentage': 100 * dominant_score / total_words,
                'top_10_words': ', '.join([f"{w}({c})" for w, c in top_words]),
                'derived_vernacular': f"{dominant_category}s" if not dominant_category.endswith('s') else dominant_category,
            }

# Convert to dataframe
genus_df = pd.DataFrame.from_dict(genus_categories, orient='index')
genus_df = genus_df.sort_values('n_species_with_vernaculars', ascending=False)

print(f"Plant genera with derived vernaculars: {len(genus_df):,}\n")

print("=== Top 50 Plant Genera by Species Coverage ===")
print(genus_df.head(50)[['genus', 'n_species_with_vernaculars', 'dominant_category',
                          'category_percentage']].to_string(index=False, max_colwidth=80))

# Save
output_file = '/home/olier/ellenberg/data/taxonomy/plant_genus_vernaculars_derived.parquet'
genus_df.to_parquet(output_file, index=False)
print(f"\n✓ Saved to: {output_file}")

# Calculate potential coverage increase
uncategorized_plants = con.execute("""
    SELECT COUNT(*) as n
    FROM read_parquet('/home/olier/ellenberg/data/taxonomy/plants_vernacular_final.parquet')
    WHERE vernacular_source = 'uncategorized'
""").fetchone()[0]

plants_in_derived_genera = con.execute("""
    SELECT COUNT(*) as n
    FROM read_parquet('/home/olier/ellenberg/data/taxonomy/plants_vernacular_final.parquet') p
    WHERE p.vernacular_source = 'uncategorized'
      AND p.genus IN (SELECT genus FROM read_parquet(?))
""", [output_file]).fetchone()[0]

print(f"\n=== Potential Coverage Impact ===")
print(f"Currently uncategorized plants: {uncategorized_plants:,}")
print(f"Would be covered by derived genera: {plants_in_derived_genera:,} ({100*plants_in_derived_genera/uncategorized_plants:.1f}%)")
