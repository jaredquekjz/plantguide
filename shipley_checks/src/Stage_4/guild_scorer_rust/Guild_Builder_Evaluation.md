# Guild Builder Architecture Evaluation

## Executive Summary

For **extremely low cost, high efficient serving** of a Guild Builder (which implies combinatorial optimization or search), **Polars is NOT the optimal architecture**.

While Polars is excellent for *scoring* a fixed batch of guilds (vectorized operations), it is ill-suited for the *iterative search* required to *build* a guild (e.g., Genetic Algorithms, Simulated Annealing, or Greedy Search). The overhead of DataFrame creation and dispatch for thousands of small permutations will be a bottleneck.

**Recommendation**: Use a **Hybrid Architecture**.
1.  **Filter (Polars/DataFusion)**: Narrow down the 11,000+ plants to a "Candidate Set" (e.g., 50-100 plants) based on user constraints (climate, size, light).
2.  **Materialize (Graph/Matrix)**: Convert the Candidate Set into pure Rust primitives (Adjacency Matrices or `petgraph` structures) representing the ecological relationships.
3.  **Search (Pure Rust)**: Run the optimization algorithm using these zero-overhead primitives.

## Detailed Comparison

### 1. Polars Approach (Current Trajectory)
*   **Workflow**: Generate a candidate guild (DataFrame) -> Join with Organisms -> Join with Fungi -> GroupBy -> Agg -> Score. Repeat 10,000x.
*   **Pros**: Reuses existing `GuildScorer` logic. Easy to implement.
*   **Cons**:
    *   **High Overhead**: DataFrame operations have startup costs (allocations, schema checks) that dominate when N is small (e.g., 7 plants).
    *   **Memory Churn**: Constant allocation/deallocation of temporary DataFrames during search.
    *   **Latency**: Unlikely to achieve sub-500ms for a complex search.

### 2. Why Polars Fails for Search (The "Micro-Batch" Problem)
Polars is optimized for **Throughput** (processing 1M rows at once), not **Latency** (processing 7 rows 1M times).

| Operation | Polars (LazyFrame) | Rust Primitive (Graph/Matrix) |
|-----------|--------------------|-------------------------------|
| **Overhead** | Query Planning + Schema Check (~1-2ms) | Array Indexing (~1-2ns) |
| **Data Access** | Columnar Scan + Filter | Direct Memory Access (L1 Cache) |
| **1 Million Guilds** | ~15-20 minutes | ~1-2 seconds |

**Conclusion**: For a Genetic Algorithm that needs to score 100,000 permutations to find the best guild, Polars is **1000x too slow**.

### 3. Graph Approach (`petgraph` / Adjacency Matrices)
*   **Workflow**:
    *   Pre-compute interaction weights between all pairs in the Candidate Set.
    *   **M3/M4/M5/M7 (Ecological)**: Become `O(1)` lookups in a `weights[i][j]` matrix.
    *   **M1 (Phylogenetic)**: Becomes `tree.calculate_faiths_pd(indices)` (On-demand tree walk, microseconds).
    *   **M2 (CSR)**: Becomes Euclidean distance between `vec[i]` and `vec[j]`.
*   **Pros**:
    *   **Extremely Fast**: Nanosecond-scale lookups for pairwise metrics, Microsecond-scale for M1.
    *   **Cache Friendly**: Small matrices fit in L1/L2 CPU cache.
    *   **Parallelizable**: Genetic algorithms can run on thousands of threads with no memory contention.
*   **Cons**: Requires writing a "Lightweight Scorer" that works on Matrices instead of DataFrames.

## Proposed "Graph Pet" (Petgraph) Implementation

**Where is the PetGraph?**
`petgraph` is used to model the **Candidate Set** (e.g., 100 filtered plants) as a graph.
- **Nodes**: The 100 candidate plants.
- **Edges**: Ecological relationships (e.g., Plant A --repels--> Pest of Plant B).
- **Weights**: The score benefit of that relationship.

This graph is built *once* at the start of the request. Then, the optimization loop just "walks" this graph (or looks up the adjacency matrix) to score permutations instantly.

Using `petgraph` (or simple adjacency matrices) is superior for the **connectivity** metrics (M3, M4, M5, M7). M1 is handled separately by the `CompactTree`.

```rust
// The "Search Space" for a specific user request
struct SearchSpace {
    // Map local index (0..N) to global WFO ID
    candidates: Vec<String>,
    
    // Pre-computed benefit matrix (M3 + M4 + M5 + M7 combined)
    // benefit[i][j] = score boost if plant i and plant j are in the same guild
    synergy_matrix: Vec<Vec<f32>>,
    
    // Pre-computed compatibility matrix (M2 + M6)
    // cost[i][j] = penalty if plant i and plant j are incompatible
    conflict_matrix: Vec<Vec<f32>>,

    // Reference to the phylogenetic tree (shared across threads)
    tree: Arc<CompactTree>,
}

impl SearchSpace {
    fn score_permutation(&self, indices: &[usize]) -> f32 {
        let mut score = 0.0;
        
    // 1. Pairwise Metrics (M2, M3, M4, M6-Strat) - O(N^2) lookups
        for i in 0..indices.len() {
            for j in (i+1)..indices.len() {
                let u = indices[i];
                let v = indices[j];
                score += self.synergy_matrix[u][v];
                score -= self.conflict_matrix[u][v];
            }
        }

        // 2. High-Order Metrics (M5, M7, M6-Form) - Set Operations
        // These depend on the COUNT of shared organisms (Quadratic scaling in M7)
        // We use pre-computed BitSets or Feature Vectors for fast counting
        score += self.calculate_m5_m7_set_ops(indices);

        // 3. Phylogenetic Diversity (M1) - O(N) tree walk
        // We map local indices back to tree node IDs for the calculator
        let tree_nodes: Vec<u32> = indices.iter()
            .map(|&i| self.get_tree_node(i))
            .collect();
        let pd = self.tree.calculate_faiths_pd(&tree_nodes);
        score += transform_pd_to_score(pd);

        score
    }
}

## How Petgraph Works (Conceptual)

`petgraph` is a Rust crate for graph data structures. For the Guild Builder, we would use `petgraph::Graph` or `petgraph::MatrixGraph`.

### 1. The Graph Structure
*   **Nodes**: Represent plants in the candidate set.
    *   `NodeWeight`: Struct containing plant metadata (ID, size, root depth).
*   **Edges**: Represent *interactions* between plants.
    *   `EdgeWeight`: Float representing the strength of the interaction (positive for synergy, negative for conflict).

### 2. Building the Graph (Once)
At the start of the request, we iterate through our candidate plants and add edges for every known interaction (e.g., "Plant A repels Pest X which attacks Plant B").

```rust
// Add edge from Marigold to Tomato with weight +5.0 (Pest Repellent)
graph.add_edge(marigold_idx, tomato_idx, 5.0);
```

### 3. Searching the Graph (Millions of times)
When the Genetic Algorithm proposes a guild (e.g., [Tomato, Basil, Marigold]), we calculate the score by summing the edges *within* that subgraph.

```rust
// Score a guild of 3 plants
let mut score = 0.0;
for plant_a in guild {
    for plant_b in guild {
        // O(1) lookup in MatrixGraph
        if let Some(weight) = graph.edge_weight(plant_a, plant_b) {
            score += weight;
        }
    }
}
```

This is why it's so fast: **Scoring a guild becomes just summing a few numbers from memory.** No database lookups, no DataFrame joins.
```

## Concurrency Model: CPU-Bound & Sync

You are correct: The optimization loop itself is **100% CPU-bound and Synchronous**.
*   It performs millions of math operations in a tight loop.
*   There is **NO I/O** (no database, no network) inside the loop.
*   Therefore, it cannot be "async" in the Rust sense (there is nothing to `await`).

**How to serve this safely:**
We must use `tokio::task::spawn_blocking` to offload this work from the Async API thread to a dedicated CPU thread pool (Rayon).

```rust
// API Handler (Async)
async fn build_guild_endpoint(req: GuildRequest) -> Result<Json<Guild>> {
    // 1. Offload CPU-intensive work to a thread pool
    let result = tokio::task::spawn_blocking(move || {
        // 2. Run the Synchronous Optimization Loop (Rayon)
        let builder = GuildBuilder::new(req);
        builder.run_genetic_algorithm() // Blocks for ~500ms
    }).await?;
    
    Ok(Json(result))
}
```

This ensures the API remains responsive (handling 100k req/s) while the heavy lifting happens on background threads.
