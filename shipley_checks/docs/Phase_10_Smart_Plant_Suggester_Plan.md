# Phase 10: Smart Plant Suggester Implementation Plan

## Executive Summary

**Goal**: Build a real-time plant suggestion engine that recommends optimal plants to add to an existing guild based on target metrics (M1-M7), using graph algorithms and parallel optimization.

**Challenge**: Given 11,711 plant candidates and 7 complex metrics, suggest the best next plant in <200ms without exhaustive search.

**Solution**: Multi-stage filtering + incremental computation + graph-based optimization + parallel evaluation using Rust's Rayon and Petgraph.

**Target Performance**: <200ms for top-10 suggestions, <500ms for top-50 with full explanations.

## Background: The Optimization Problem

### Problem Statement

**Input**:
- Current guild: N plants (typically 5-15)
- Target metric: One of M1-M7 to optimize
- User location: Köppen climate tier (1-6)
- Constraints: EIVE ranges, CSR balance, specific requirements

**Output**:
- Top-K plant suggestions (typically 10-50)
- Score for each suggestion
- Explanation of why each plant improves the guild

**Naive complexity**: O(C × M) where:
- C = 11,711 candidates
- M = 50-100ms per full metric evaluation
- Total: ~10 minutes (unacceptable)

### Key Insight: Climate Tiering Reduces Search Space

**Köppen climate tiers** (6 tiers):

| Tier | Name | Estimated Plants | % of Database |
|------|------|------------------|---------------|
| tier_1 | Tropical | ~800 | 7% |
| tier_2 | Mediterranean | ~2,500 | 21% |
| tier_3 | Humid Temperate | ~4,500 | 38% |
| tier_4 | Continental | ~2,000 | 17% |
| tier_5 | Boreal/Polar | ~600 | 5% |
| tier_6 | Arid | ~1,400 | 12% |

**Impact**: Filtering by user's climate tier reduces search space from 11,711 to ~600-4,500 plants (2-8× reduction).

**Additional constraint**: Guild members' shared climate compatibility further filters candidates:
- Example: If guild has plants from tier_2 + tier_3, candidates must overlap both
- This typically reduces to ~1,500-2,500 viable candidates

**Effective search space**: ~2,000 plants (5× smaller than naive approach)

## Architecture Overview

### Data Structures

```
┌─────────────────────────────────────────────────────────┐
│              SmartPlantSuggester                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────┐  ┌──────────────────────────┐  │
│  │  PhyloGraph       │  │  InteractionGraph        │  │
│  │  (Petgraph)       │  │  (Petgraph)              │  │
│  │                   │  │                          │  │
│  │  Nodes: Taxa      │  │  Nodes: Plants+Organisms │  │
│  │  Edges: Branch len│  │  Edges: Interactions     │  │
│  └───────────────────┘  └──────────────────────────┘  │
│                                                         │
│  ┌───────────────────┐  ┌──────────────────────────┐  │
│  │  NutrientGraph    │  │  SpatialIndex (KDTree)   │  │
│  │  (Petgraph)       │  │                          │  │
│  │                   │  │  6D EIVE space           │  │
│  │  Nodes: Plants    │  │  Fast radius queries     │  │
│  │  Edges: N flow    │  │                          │  │
│  └───────────────────┘  └──────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  ClimateIndex (HashMap)                         │  │
│  │  tier -> [plant_ids]                            │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  GuildState Cache                               │  │
│  │  Pre-computed guild statistics                  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Algorithmic Strategy: Four-Stage Pipeline

```
Stage 1: Climate Filtering (1ms)
  Input: 11,711 plants
  Filter: Köppen tier compatibility
  Output: ~2,000 candidates

Stage 2: Constraint Pruning (10ms, parallel)
  Input: ~2,000 candidates
  Filter: EIVE ranges, CSR balance, morphology
  Output: ~500-1,000 viable candidates

Stage 3: Coarse Scoring (50ms, parallel)
  Input: ~500-1,000 candidates
  Method: Fast approximate metrics
  Output: Top 100 candidates

Stage 4: Fine Scoring (100ms, parallel)
  Input: Top 100 candidates
  Method: Full metric computation + explanations
  Output: Top K with detailed scores

Total: ~160ms (target <200ms ✓)
```

## Phase 10 Sub-Phases

### Phase 10.1: Phylogenetic Graph (Petgraph)

**Purpose**: Enable fast phylogenetic distance queries and incremental Faith's PD computation.

**Data Structure**:
```rust
use petgraph::graph::{Graph, NodeIndex};
use petgraph::algo::dijkstra;
use std::collections::HashMap;

pub struct PhyloGraph {
    // Directed graph: root → tips
    graph: Graph<TaxonName, BranchLength>,

    // Fast lookup: plant_id → node in tree
    plant_nodes: HashMap<PlantId, NodeIndex>,

    // Fast lookup: node → subtree tips (memoized)
    subtree_cache: HashMap<NodeIndex, Vec<PlantId>>,

    // Precomputed: all pairwise distances (11711² would be too large)
    // Instead: LCA (Lowest Common Ancestor) lookup table
    lca_table: LCATable,
}

impl PhyloGraph {
    /// Load from Newick tree file (Phase 1 output)
    pub fn from_newick(path: &str) -> Result<Self> {
        // Parse Newick format
        // Build Petgraph representation
        // Precompute LCA table
        // Build plant_nodes lookup
    }

    /// Fast: Phylogenetic distance between two plants
    pub fn phylo_distance(&self, plant1: PlantId, plant2: PlantId) -> f64 {
        let node1 = self.plant_nodes[&plant1];
        let node2 = self.plant_nodes[&plant2];

        // Find LCA (Lowest Common Ancestor)
        let lca = self.lca_table.query(node1, node2);

        // Distance = branch length from node1 to LCA + node2 to LCA
        self.path_length(node1, lca) + self.path_length(node2, lca)
    }

    /// Incremental: Faith's PD if we add one plant to existing guild
    pub fn incremental_faiths_pd(
        &self,
        guild: &[PlantId],
        candidate: PlantId,
    ) -> f64 {
        // Current guild Faith's PD (cached)
        let base_pd = self.faiths_pd(guild);

        // Find minimum branch length from candidate to ANY guild member
        let min_distance = guild.iter()
            .map(|p| self.phylo_distance(*p, candidate))
            .min_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(0.0);

        // New Faith's PD ≈ base + min_distance (approximation)
        // For exact calculation, need to recompute subtree coverage
        base_pd + min_distance * 0.5  // Heuristic: ~50% of branch is new
    }

    /// Exact: Faith's PD for a guild (sum of unique branch lengths)
    pub fn faiths_pd(&self, guild: &[PlantId]) -> f64 {
        let nodes: Vec<NodeIndex> = guild.iter()
            .map(|p| self.plant_nodes[p])
            .collect();

        // Find all branches covered by these tips
        let covered_branches = self.branches_spanning(nodes);

        // Sum branch lengths
        covered_branches.iter()
            .map(|edge| self.graph[*edge])
            .sum()
    }

    /// Helper: All branches in subtree spanning given nodes
    fn branches_spanning(&self, nodes: Vec<NodeIndex>) -> Vec<EdgeIndex> {
        // Find minimum spanning tree over these nodes
        // Return all edges in that tree
        // (Uses Petgraph MST algorithms)
    }
}
```

**Input**: Newick phylogenetic tree from Phase 1 (11,711 tips)

**Output**: Fast distance queries (0.01ms) and incremental PD (0.5ms vs 50ms full computation)

**Performance**:
- Construction: ~2 seconds at startup (one-time cost)
- Memory: ~50MB (tree structure + LCA table)
- Distance query: O(log N) with LCA = ~0.01ms
- Incremental PD: ~0.5ms (vs 50ms for full recomputation)

**Petgraph advantage**: Built-in algorithms (Dijkstra, MST, DFS) eliminate custom graph code.

### Phase 10.2: Organism Interaction Network (Petgraph)

**Purpose**: Model plant-organism interactions as a network to evaluate ecosystem benefits (M4).

**Data Structure**:
```rust
use petgraph::graph::Graph;
use petgraph::Direction;

pub struct InteractionGraph {
    // Bipartite graph: Plants ↔ Organisms
    graph: Graph<Entity, InteractionType>,

    // Fast lookups
    plant_nodes: HashMap<PlantId, NodeIndex>,
    organism_nodes: HashMap<OrganismName, NodeIndex>,
}

#[derive(Debug, Clone)]
pub enum Entity {
    Plant(PlantId),
    Organism(OrganismName),
}

#[derive(Debug, Clone, Copy)]
pub enum InteractionType {
    Pollination,
    Herbivory,
    FlowerVisitation,
    Predation,
    Parasitism,
    Pathogenesis,
}

impl InteractionGraph {
    /// Load from Phase 7 organisms_searchable.parquet
    pub fn from_parquet(path: &str) -> Result<Self> {
        // Read 276,601 interaction rows
        // Build bipartite graph
        // Create lookup tables
    }

    /// Evaluate: Adding this plant improves pollinator/pest balance?
    pub fn evaluate_interaction_score(
        &self,
        guild: &[PlantId],
        candidate: PlantId,
    ) -> InteractionScore {
        let guild_nodes: Vec<NodeIndex> = guild.iter()
            .map(|p| self.plant_nodes[p])
            .collect();

        let candidate_node = self.plant_nodes[&candidate];

        // Current guild's organisms
        let current_pollinators = self.connected_organisms(
            &guild_nodes,
            InteractionType::Pollination,
        );
        let current_pests = self.connected_organisms(
            &guild_nodes,
            InteractionType::Herbivory,
        );

        // Candidate's organisms
        let new_pollinators = self.neighbors(
            candidate_node,
            InteractionType::Pollination,
        );
        let new_pests = self.neighbors(
            candidate_node,
            InteractionType::Herbivory,
        );

        // Check for biocontrol closure (predators of new pests)
        let biocontrol = self.predators_of(&new_pests);
        let biocontrol_available = biocontrol.iter()
            .any(|pred| current_pollinators.contains(pred) || guild_nodes.iter().any(|n| self.has_edge(*n, *pred)));

        // Score calculation
        let unique_new_pollinators = new_pollinators.difference(&current_pollinators).count();
        let unique_new_pests = new_pests.difference(&current_pests).count();
        let biocontrol_bonus = if biocontrol_available { 5.0 } else { 0.0 };

        InteractionScore {
            new_pollinators: unique_new_pollinators,
            new_pests: unique_new_pests,
            biocontrol_available: biocontrol_available,
            score: unique_new_pollinators as f64
                   - unique_new_pests as f64 * 0.5
                   + biocontrol_bonus,
        }
    }

    /// Helper: All organisms connected to these plants via given interaction
    fn connected_organisms(
        &self,
        plant_nodes: &[NodeIndex],
        interaction: InteractionType,
    ) -> HashSet<NodeIndex> {
        plant_nodes.iter()
            .flat_map(|n| {
                self.graph.neighbors_directed(*n, Direction::Outgoing)
                    .filter(|neighbor| {
                        self.graph.edges_connecting(*n, *neighbor)
                            .any(|e| matches!(e.weight(), t if *t == interaction))
                    })
            })
            .collect()
    }
}
```

**Input**: Phase 7 organisms_searchable.parquet (276,601 interactions)

**Output**: Fast interaction scoring (2ms per candidate)

**Performance**:
- Construction: ~500ms at startup
- Memory: ~30MB (bipartite graph)
- Query: O(E) where E = edges per plant (~20-50) = ~2ms

### Phase 10.3: Nutrient Cycling Network (Petgraph)

**Purpose**: Model nutrient flows between plants to evaluate M7 (nutrient cycling).

**Data Structure**:
```rust
pub struct NutrientGraph {
    // Directed graph: Plants with nutrient flow edges
    graph: Graph<PlantId, NutrientFlow>,
    plant_nodes: HashMap<PlantId, NodeIndex>,
}

#[derive(Debug, Clone)]
pub struct NutrientFlow {
    nutrient_type: NutrientType,
    flow_rate: f64,  // Modeled from decomposition rate + N-fixation
}

#[derive(Debug, Clone, Copy)]
pub enum NutrientType {
    Nitrogen,
    Phosphorus,
    Organic,
}

impl NutrientGraph {
    /// Build from plant traits: N-fixation, decomposition rate, root depth
    pub fn from_traits(plants: &DataFrame) -> Result<Self> {
        let mut graph = Graph::new();

        // Add all plants as nodes
        // Add directed edges based on:
        //   - N-fixers → other plants (N flow)
        //   - Fast decomposers → shallow-rooted plants (organic matter)
        //   - Deep-rooted → shallow-rooted (nutrient mining)
    }

    /// Evaluate: Does adding this plant close nutrient cycles?
    pub fn evaluate_cycling_score(
        &self,
        guild: &[PlantId],
        candidate: PlantId,
    ) -> CyclingScore {
        let guild_nodes: Vec<NodeIndex> = guild.iter()
            .map(|p| self.plant_nodes[p])
            .collect();
        let candidate_node = self.plant_nodes[&candidate];

        // Current cycles (strongly connected components)
        let subgraph_before = self.guild_subgraph(&guild_nodes);
        let cycles_before = petgraph::algo::tarjan_scc(&subgraph_before);

        // Cycles after adding candidate
        let mut guild_with_candidate = guild_nodes.clone();
        guild_with_candidate.push(candidate_node);
        let subgraph_after = self.guild_subgraph(&guild_with_candidate);
        let cycles_after = petgraph::algo::tarjan_scc(&subgraph_after);

        // Score based on:
        // 1. New cycles formed (good)
        // 2. Existing cycles strengthened (good)
        // 3. Nutrient sinks eliminated (good)

        let new_cycles = cycles_after.len() - cycles_before.len();
        let n_fixing = self.is_n_fixer(candidate);

        CyclingScore {
            new_cycles: new_cycles,
            closes_n_gap: n_fixing && self.has_n_deficiency(&guild_nodes),
            score: new_cycles as f64 * 10.0 + if n_fixing { 20.0 } else { 0.0 },
        }
    }

    /// Helper: Extract subgraph containing only these nodes
    fn guild_subgraph(&self, nodes: &[NodeIndex]) -> Graph<PlantId, NutrientFlow> {
        // Use Petgraph's filter_map to extract subgraph
    }
}
```

**Input**: Plant traits (N-fixation, decomposition, root depth)

**Output**: Nutrient cycling scores (5ms per candidate)

**Performance**:
- Construction: ~200ms
- Memory: ~20MB
- Query: O(V + E) for SCC = ~5ms

### Phase 10.4: Spatial Index (KDTree for EIVE)

**Purpose**: Fast spatial queries in 6D EIVE space for compatibility filtering.

**Data Structure**:
```rust
use kiddo::KdTree;

pub struct EIVEIndex {
    // 6D KD-tree: [L, M, T, K, N, R]
    tree: KdTree<f64, PlantId, 6>,

    // Plant ID → EIVE vector mapping
    plant_eive: HashMap<PlantId, [f64; 6]>,
}

impl EIVEIndex {
    /// Build from Phase 7 plants_searchable.parquet
    pub fn from_parquet(path: &str) -> Result<Self> {
        let df = read_parquet(path)?;

        let mut tree = KdTree::new();
        let mut plant_eive = HashMap::new();

        for row in df.iter() {
            let plant_id = row["wfo_taxon_id"];
            let eive = [
                row["EIVE_L"], row["EIVE_M"], row["EIVE_T"],
                row["EIVE_K"], row["EIVE_N"], row["EIVE_R"],
            ];

            tree.add(&eive, plant_id);
            plant_eive.insert(plant_id, eive);
        }

        Ok(Self { tree, plant_eive })
    }

    /// Fast: Find all plants within EIVE radius of guild centroid
    pub fn within_radius(
        &self,
        centroid: &[f64; 6],
        max_distance: f64,
    ) -> Vec<PlantId> {
        // KD-tree radius query (O(log N + k) where k = results)
        self.tree.within_radius(centroid, max_distance)
    }

    /// Fast: K-nearest neighbors to guild centroid
    pub fn knn(&self, centroid: &[f64; 6], k: usize) -> Vec<(PlantId, f64)> {
        // KD-tree KNN query (O(log N))
        self.tree.nearest(centroid, k)
            .into_iter()
            .map(|(dist, plant_id)| (*plant_id, dist))
            .collect()
    }

    /// Helper: Compute guild EIVE centroid
    pub fn guild_centroid(&self, guild: &[PlantId]) -> [f64; 6] {
        let mut sum = [0.0; 6];
        for plant_id in guild {
            let eive = self.plant_eive[plant_id];
            for i in 0..6 {
                sum[i] += eive[i];
            }
        }
        let n = guild.len() as f64;
        sum.iter_mut().for_each(|v| *v /= n);
        sum
    }
}
```

**Input**: Phase 7 plants_searchable.parquet (11,711 plants × 6 EIVE dimensions)

**Output**: Fast radius queries (5ms for ~2000 results)

**Performance**:
- Construction: ~50ms
- Memory: ~5MB
- Radius query: O(log N + k) = ~5ms for k=2000

**Advantage**: 100× faster than linear scan (500ms → 5ms)

### Phase 10.5: Climate Index (HashMap)

**Purpose**: Instant filtering by Köppen climate tier.

**Data Structure**:
```rust
pub struct ClimateIndex {
    // Climate tier → list of plant IDs in that tier
    tier_to_plants: HashMap<String, Vec<PlantId>>,

    // Plant ID → list of compatible tiers
    plant_to_tiers: HashMap<PlantId, Vec<String>>,
}

impl ClimateIndex {
    /// Build from Phase 7 plants_searchable.parquet
    pub fn from_parquet(path: &str) -> Result<Self> {
        let df = read_parquet(path)?;

        let tiers = [
            "tier_1_tropical",
            "tier_2_mediterranean",
            "tier_3_humid_temperate",
            "tier_4_continental",
            "tier_5_boreal_polar",
            "tier_6_arid",
        ];

        let mut tier_to_plants: HashMap<String, Vec<PlantId>> =
            tiers.iter().map(|t| (t.to_string(), Vec::new())).collect();
        let mut plant_to_tiers: HashMap<PlantId, Vec<String>> = HashMap::new();

        for row in df.iter() {
            let plant_id = row["wfo_taxon_id"];
            let mut compatible_tiers = Vec::new();

            for tier in &tiers {
                if row[tier] == true {  // Boolean column
                    tier_to_plants.get_mut(*tier).unwrap().push(plant_id);
                    compatible_tiers.push(tier.to_string());
                }
            }

            plant_to_tiers.insert(plant_id, compatible_tiers);
        }

        Ok(Self { tier_to_plants, plant_to_tiers })
    }

    /// Fast: Get all plants compatible with these tiers (intersection)
    pub fn compatible_plants(&self, tiers: &[String]) -> Vec<PlantId> {
        if tiers.is_empty() {
            return Vec::new();
        }

        // Start with first tier's plants
        let mut result: HashSet<PlantId> = self.tier_to_plants[&tiers[0]]
            .iter()
            .copied()
            .collect();

        // Intersect with other tiers
        for tier in &tiers[1..] {
            let tier_plants: HashSet<PlantId> = self.tier_to_plants[tier]
                .iter()
                .copied()
                .collect();
            result = result.intersection(&tier_plants).copied().collect();
        }

        result.into_iter().collect()
    }

    /// Fast: Get guild's compatible tiers (intersection of all member tiers)
    pub fn guild_tiers(&self, guild: &[PlantId]) -> Vec<String> {
        if guild.is_empty() {
            return Vec::new();
        }

        // Start with first plant's tiers
        let mut result: HashSet<String> = self.plant_to_tiers[&guild[0]]
            .iter()
            .cloned()
            .collect();

        // Intersect with other plants' tiers
        for plant_id in &guild[1..] {
            let plant_tiers: HashSet<String> = self.plant_to_tiers[plant_id]
                .iter()
                .cloned()
                .collect();
            result = result.intersection(&plant_tiers).cloned().collect();
        }

        result.into_iter().collect()
    }
}
```

**Performance**:
- Construction: ~10ms
- Memory: ~2MB
- Query: O(1) lookup + O(T × P) intersection where T=tiers, P=plants per tier = ~1ms

### Phase 10.6: Smart Plant Suggester (Main Algorithm)

**Purpose**: Orchestrate all components into a unified suggestion engine.

**Main Algorithm**:
```rust
pub struct SmartPlantSuggester {
    phylo_graph: PhyloGraph,
    interaction_graph: InteractionGraph,
    nutrient_graph: NutrientGraph,
    eive_index: EIVEIndex,
    climate_index: ClimateIndex,

    // Full plant data for final details
    plants_df: LazyFrame,
}

impl SmartPlantSuggester {
    /// Initialize all indexes and graphs (startup cost ~3 seconds)
    pub fn new(data_dir: &str) -> Result<Self> {
        println!("Loading phylogenetic graph...");
        let phylo_graph = PhyloGraph::from_newick(&format!("{}/phylogeny.nwk", data_dir))?;

        println!("Loading interaction network...");
        let interaction_graph = InteractionGraph::from_parquet(&format!("{}/organisms_searchable.parquet", data_dir))?;

        println!("Loading nutrient network...");
        let nutrient_graph = NutrientGraph::from_traits(&plants_df)?;

        println!("Building EIVE spatial index...");
        let eive_index = EIVEIndex::from_parquet(&format!("{}/plants_searchable_11711.parquet", data_dir))?;

        println!("Building climate index...");
        let climate_index = ClimateIndex::from_parquet(&format!("{}/plants_searchable_11711.parquet", data_dir))?;

        println!("Loading plant data...");
        let plants_df = LazyFrame::scan_parquet(&format!("{}/plants_searchable_11711.parquet", data_dir), Default::default())?;

        Ok(Self {
            phylo_graph,
            interaction_graph,
            nutrient_graph,
            eive_index,
            climate_index,
            plants_df,
        })
    }

    /// Main API: Suggest next plant for guild
    pub fn suggest_next_plant(
        &self,
        request: SuggestionRequest,
    ) -> Result<Vec<PlantSuggestion>> {
        let start = Instant::now();

        // STAGE 1: Climate filtering (1ms)
        let compatible_tiers = self.climate_index.guild_tiers(&request.current_guild);
        let climate_candidates = if let Some(user_tier) = request.user_climate_tier {
            // User specified tier: use that
            self.climate_index.tier_to_plants[&user_tier].clone()
        } else {
            // Use guild's compatible tiers
            self.climate_index.compatible_plants(&compatible_tiers)
        };

        println!("Stage 1 (Climate): {} candidates in {:?}", climate_candidates.len(), start.elapsed());
        let stage1_time = start.elapsed();

        // STAGE 2: Constraint pruning (10ms, parallel)
        let guild_state = self.compute_guild_state(&request.current_guild)?;

        let viable_candidates: Vec<PlantId> = climate_candidates.par_iter()
            .filter(|candidate| {
                self.meets_constraints(**candidate, &guild_state, &request.constraints)
            })
            .copied()
            .collect();

        println!("Stage 2 (Pruning): {} candidates in {:?}", viable_candidates.len(), start.elapsed() - stage1_time);
        let stage2_time = start.elapsed();

        // STAGE 3: Coarse scoring (50ms, parallel)
        // Use fast approximate metrics to get top 100
        let mut coarse_scored: Vec<(PlantId, f64)> = viable_candidates.par_iter()
            .map(|candidate| {
                let score = self.coarse_score(
                    &request.current_guild,
                    *candidate,
                    request.target_metric,
                    &guild_state,
                );
                (*candidate, score)
            })
            .collect();

        coarse_scored.par_sort_unstable_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        coarse_scored.truncate(100);  // Top 100 for fine scoring

        println!("Stage 3 (Coarse): Top 100 in {:?}", start.elapsed() - stage2_time);
        let stage3_time = start.elapsed();

        // STAGE 4: Fine scoring (100ms, parallel)
        // Full metric computation + explanations
        let suggestions: Vec<PlantSuggestion> = coarse_scored.par_iter()
            .map(|(candidate, _coarse_score)| {
                self.fine_score(
                    &request.current_guild,
                    *candidate,
                    request.target_metric,
                    &guild_state,
                )
            })
            .collect();

        println!("Stage 4 (Fine): Top {} in {:?}", request.top_k, start.elapsed() - stage3_time);

        let mut final_suggestions = suggestions;
        final_suggestions.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
        final_suggestions.truncate(request.top_k);

        println!("Total time: {:?}", start.elapsed());

        Ok(final_suggestions)
    }

    /// Helper: Compute guild state (cached statistics)
    fn compute_guild_state(&self, guild: &[PlantId]) -> Result<GuildState> {
        Ok(GuildState {
            eive_centroid: self.eive_index.guild_centroid(guild),
            csr_balance: self.compute_csr_balance(guild)?,
            current_faiths_pd: self.phylo_graph.faiths_pd(guild),
            current_pollinators: self.interaction_graph.guild_pollinators(guild),
            current_pests: self.interaction_graph.guild_pests(guild),
            // ... other cached stats
        })
    }

    /// Helper: Check if candidate meets constraints
    fn meets_constraints(
        &self,
        candidate: PlantId,
        guild_state: &GuildState,
        constraints: &Constraints,
    ) -> bool {
        // EIVE range check
        let candidate_eive = self.eive_index.plant_eive[&candidate];
        for i in 0..6 {
            if let Some((min, max)) = constraints.eive_ranges[i] {
                if candidate_eive[i] < min || candidate_eive[i] > max {
                    return false;
                }
            }
        }

        // EIVE distance from guild centroid
        let distance = euclidean_distance(&guild_state.eive_centroid, &candidate_eive);
        if distance > constraints.max_eive_distance {
            return false;
        }

        // CSR balance check
        // ... more constraint checks

        true
    }

    /// Helper: Coarse scoring (fast approximations)
    fn coarse_score(
        &self,
        guild: &[PlantId],
        candidate: PlantId,
        target_metric: Metric,
        guild_state: &GuildState,
    ) -> f64 {
        match target_metric {
            Metric::M1 => {
                // Approximate phylogenetic diversity gain
                self.phylo_graph.incremental_faiths_pd(guild, candidate)
            },
            Metric::M4 => {
                // Interaction network score
                self.interaction_graph.evaluate_interaction_score(guild, candidate).score
            },
            Metric::M7 => {
                // Nutrient cycling score
                self.nutrient_graph.evaluate_cycling_score(guild, candidate).score
            },
            // ... other metrics
        }
    }

    /// Helper: Fine scoring (exact metrics + explanation)
    fn fine_score(
        &self,
        guild: &[PlantId],
        candidate: PlantId,
        target_metric: Metric,
        guild_state: &GuildState,
    ) -> PlantSuggestion {
        // Compute full metrics (use existing GuildScorer)
        let test_guild = [guild, &[candidate]].concat();
        let full_metrics = self.compute_full_metrics(&test_guild);

        // Get plant details
        let plant_details = self.get_plant_details(candidate);

        // Generate explanation
        let explanation = self.generate_explanation(
            candidate,
            target_metric,
            guild_state,
            &full_metrics,
        );

        PlantSuggestion {
            plant_id: candidate,
            common_name: plant_details.common_name,
            latin_name: plant_details.latin_name,
            score: full_metrics[target_metric],
            improvement: full_metrics[target_metric] - guild_state.current_metrics[target_metric],
            explanation,
            metrics_breakdown: full_metrics,
        }
    }
}
```

**Performance Breakdown**:

| Stage | Operation | Time | Candidates |
|-------|-----------|------|------------|
| 1 | Climate filtering | 1ms | 11,711 → 2,000 |
| 2 | Constraint pruning | 10ms | 2,000 → 800 |
| 3 | Coarse scoring | 50ms | 800 → 100 |
| 4 | Fine scoring | 100ms | 100 → 10 |
| **Total** | | **~160ms** | **10 results** |

**Target met**: <200ms ✅

### Phase 10.7: API Integration

**New endpoint**:
```rust
// POST /api/guilds/suggest
async fn suggest_next_plant(
    State(state): State<AppState>,
    Json(request): Json<SuggestionRequest>,
) -> Result<Json<Vec<PlantSuggestion>>, (StatusCode, String)> {
    // CPU-bound work in blocking pool
    let suggester = state.smart_suggester.clone();

    let suggestions = tokio::task::spawn_blocking(move || {
        suggester.suggest_next_plant(request)
    })
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(suggestions))
}

#[derive(Deserialize)]
pub struct SuggestionRequest {
    pub current_guild: Vec<PlantId>,
    pub target_metric: Metric,  // M1-M7
    pub user_climate_tier: Option<String>,
    pub constraints: Constraints,
    pub top_k: usize,  // How many suggestions (default 10)
}

#[derive(Deserialize)]
pub struct Constraints {
    pub eive_ranges: [(Option<f64>, Option<f64>); 6],  // Min/max for each EIVE
    pub max_eive_distance: f64,  // Max distance from guild centroid
    pub csr_balance: Option<CSRBalance>,
    pub required_traits: Vec<String>,  // e.g., "nitrogen_fixing", "drought_tolerant"
}

#[derive(Serialize)]
pub struct PlantSuggestion {
    pub plant_id: PlantId,
    pub common_name: String,
    pub latin_name: String,
    pub score: f64,
    pub improvement: f64,  // How much this improves target metric
    pub explanation: String,
    pub metrics_breakdown: HashMap<Metric, f64>,
}
```

### Phase 10.8: Testing and Calibration

**Test scenarios**:

1. **Small guild (5 plants), target M1 (phylogenetic diversity)**:
   - Expected: Suggests phylogenetically distant plants
   - Verify: Incremental PD correctly computed

2. **Pollinator-poor guild (2 pollinators), target M4**:
   - Expected: Suggests high-pollinator plants
   - Verify: Interaction graph correctly identifies new pollinators

3. **N-deficient guild (no fixers), target M7**:
   - Expected: Suggests N-fixing plants
   - Verify: Nutrient graph detects deficiency

4. **EIVE-constrained search (narrow range)**:
   - Expected: Only suggests compatible plants
   - Verify: KD-tree correctly filters

5. **Climate-specific search (tier 5 boreal)**:
   - Expected: Only ~600 candidates
   - Verify: Climate index correctly filters

**Performance benchmarks**:
- Measure Stage 1-4 timings across all test cases
- Verify <200ms p95 latency
- Profile memory usage (<100MB increase over baseline)

## Implementation Roadmap

### Phase 10.1-10.5: Data Structures (Week 1)

**Day 1-2**: PhyloGraph (Petgraph)
- Load Newick tree
- Implement LCA table
- Test distance queries

**Day 3**: InteractionGraph (Petgraph)
- Load organism parquet
- Build bipartite graph
- Test interaction scoring

**Day 4**: NutrientGraph (Petgraph)
- Model from traits
- Implement SCC detection
- Test cycling scores

**Day 5**: Spatial + Climate indexes
- KDTree for EIVE
- HashMap for climate
- Test query performance

### Phase 10.6-10.7: Suggester + API (Week 2)

**Day 6-7**: SmartPlantSuggester
- Implement 4-stage pipeline
- Integrate all components
- Unit tests

**Day 8**: API integration
- Add endpoint to Axum
- Wire to suggester
- Integration tests

**Day 9**: Performance optimization
- Profile bottlenecks
- Optimize hot paths
- Verify <200ms target

**Day 10**: Documentation + examples
- API documentation
- Usage examples
- Client integration guide

## Dependencies

**Add to Cargo.toml**:
```toml
[dependencies]
# Existing
polars = "0.35"
rayon = "1.8"

# NEW for Phase 10
petgraph = "0.6"         # Graph algorithms
kiddo = "2.0"            # KD-tree spatial indexing
```

## Risk Assessment and Mitigation

### Risk 1: Performance Target Not Met

**Risk**: 4-stage pipeline still exceeds 200ms in practice.

**Likelihood**: Medium (untested on real data)

**Mitigation**:
- Add Stage 2.5: Use machine learning model to predict scores (train offline)
- Reduce fine scoring to top 50 instead of top 100
- Add aggressive caching of guild states
- Fallback: Increase latency target to 500ms (still acceptable UX)

### Risk 2: Graph Construction Too Slow

**Risk**: Loading petgraphs at startup takes >10 seconds.

**Likelihood**: Low (graphs are small)

**Mitigation**:
- Serialize graphs to binary format (bincode)
- Load pre-built graphs instead of rebuilding
- Lazy load: Build graphs on first use

### Risk 3: Memory Usage Too High

**Risk**: All indexes + graphs exceed 500MB RAM.

**Likelihood**: Low (estimated ~150MB total)

**Mitigation**:
- Use Arc to share graphs across workers
- Lazy load infrequently-used components
- Compress graphs with dictionary encoding

### Risk 4: Metric Accuracy Degraded

**Risk**: Fast approximate metrics don't correlate with exact metrics.

**Likelihood**: Medium (approximations are heuristics)

**Mitigation**:
- Calibrate coarse scoring against full metrics (correlation analysis)
- If correlation <0.8, skip Stage 3 and do full scoring on all viable candidates
- Tune Stage 2 filters to reduce candidates to <200 (allows full scoring)

## Success Criteria

1. ✅ **Performance**: <200ms p95 latency for top-10 suggestions
2. ✅ **Accuracy**: Coarse scores correlate >0.8 with fine scores
3. ✅ **Coverage**: Finds optimal plant in top-10 at least 80% of the time
4. ✅ **Scalability**: Memory usage <200MB increase over baseline
5. ✅ **Reliability**: No panics or errors on edge cases (empty guild, no candidates)

## Future Enhancements (Post-Phase 10)

1. **Multi-plant suggestions**: "Add these 3 plants together for synergy"
2. **Machine learning ranker**: Train model on historical guild scores
3. **Real-time updates**: WebSocket streaming as scores computed
4. **Explanation improvements**: Visual guild diagrams with new plant highlighted
5. **User feedback loop**: Learn from accepted/rejected suggestions

## Conclusion

Phase 10 builds a sophisticated optimization engine using Rust's strengths:
- **Petgraph**: Native graph algorithms for phylogeny, interactions, nutrients
- **Rayon**: Parallel evaluation across 2,000 candidates
- **KDTree**: 100× faster spatial filtering
- **Climate tiering**: 5× search space reduction

**Combined**: Transforms a 10-minute exhaustive search into a <200ms intelligent suggestion.

This enables the core user experience: "I have these plants, what should I add?" - answered instantly with explanations.

The architecture is tentative and results-dependent, but the foundation (Phases 7-8) provides the data infrastructure, and Phase 10 builds the intelligence layer on top.
