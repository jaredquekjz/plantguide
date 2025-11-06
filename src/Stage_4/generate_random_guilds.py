"""
Generate 1000 random guilds for comprehensive Faith's PD testing
"""
import pandas as pd
import random
import csv

# Load species mapping
mapping_df = pd.read_csv('data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv')
# Filter out NaN values
all_tips = mapping_df['tree_tip'].dropna().tolist()

print(f"Total species available: {len(all_tips)}")

# Generate 1000 random guilds with varying sizes
random.seed(42)  # Reproducible
guilds = []

# Distribution of guild sizes (realistic)
# - 100 guilds with 2-5 species (small)
# - 300 guilds with 6-10 species (small-medium)
# - 400 guilds with 11-20 species (medium)
# - 150 guilds with 21-30 species (large)
# - 50 guilds with 31-40 species (very large)

size_distribution = (
    [(2, 5)] * 100 +
    [(6, 10)] * 300 +
    [(11, 20)] * 400 +
    [(21, 30)] * 150 +
    [(31, 40)] * 50
)

for i, (min_size, max_size) in enumerate(size_distribution):
    guild_size = random.randint(min_size, max_size)
    guild_species = random.sample(all_tips, guild_size)
    guilds.append({
        'guild_id': i,
        'guild_size': guild_size,
        'species': ';;'.join(guild_species)  # Use ;; as delimiter since | is in tip names
    })

# Save to CSV
guilds_df = pd.DataFrame(guilds)
guilds_df.to_csv('data/stage4/test_guilds_1000.csv', index=False)

print(f"Generated {len(guilds)} guilds")
print(f"\nGuild size distribution:")
print(guilds_df['guild_size'].describe())
print(f"\nSaved to: data/stage4/test_guilds_1000.csv")
