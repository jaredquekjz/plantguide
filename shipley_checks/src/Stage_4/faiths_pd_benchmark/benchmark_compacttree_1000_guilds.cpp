/**
 * Benchmark OPTIMIZED CompactTree C++ on 1000 random guilds
 * Uses vector<uint8_t> for visited tracking (42% faster for 40-species guilds)
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_set>
#include <chrono>
#include "compact_tree.h"

using namespace std;
using namespace std::chrono;

// OPTIMIZED: Calculate Faith's PD using vector<uint8_t>
double calculate_faiths_pd_optimized(const compact_tree& tree,
                                     const vector<CT_NODE_T>& leaf_nodes) {
    if (leaf_nodes.size() < 2) return 0.0;

    // Find MRCA
    unordered_set<CT_NODE_T> leaf_set(leaf_nodes.begin(), leaf_nodes.end());
    CT_NODE_T mrca = tree.find_mrca(leaf_set);

    // Use vector<uint8_t> for visited tracking (fastest for 10-40 species)
    const size_t num_nodes = tree.get_num_nodes();
    vector<uint8_t> visited(num_nodes, 0);

    double total_pd = 0.0;
    for (CT_NODE_T leaf : leaf_nodes) {
        CT_NODE_T current = leaf;
        while (current != mrca) {
            if (!visited[current]) {
                total_pd += tree.get_edge_length(current);
                visited[current] = 1;
            }
            current = tree.get_parent(current);
        }
    }

    return total_pd;
}

// Parse guild CSV and calculate Faith's PD for all
int main() {
    // UPDATED: Nov 7, 2025 tree with 11,711 species
    string tree_path = "data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk";
    string guilds_path = "shipley_checks/stage4/test_guilds_1000.csv";
    string output_path = "shipley_checks/stage4/compacttree_results_1000.csv";

    // Load tree ONCE
    cout << "Loading tree..." << endl;
    auto tree_load_start = high_resolution_clock::now();
    compact_tree tree(tree_path, true, true, true, 25000);
    auto tree_load_end = high_resolution_clock::now();
    double tree_load_ms = duration_cast<microseconds>(tree_load_end - tree_load_start).count() / 1000.0;
    
    cout << "Tree loaded: " << tree.get_num_leaves() << " tips in " 
         << tree_load_ms << " ms" << endl;

    // Build tip label lookup
    unordered_map<string, CT_NODE_T> label_to_node;
    for (CT_NODE_T i = 0; i < tree.get_num_nodes(); i++) {
        if (tree.is_leaf(i)) {
            label_to_node[tree.get_label(i)] = i;
        }
    }

    // Load guilds CSV
    cout << "Loading guilds..." << endl;
    ifstream guilds_file(guilds_path);
    string line;
    
    // Skip header
    getline(guilds_file, line);
    
    vector<int> guild_ids;
    vector<int> guild_sizes;
    vector<string> guild_species_strings;
    
    while (getline(guilds_file, line)) {
        stringstream ss(line);
        string guild_id_str, guild_size_str, species_str;
        
        getline(ss, guild_id_str, ',');
        getline(ss, guild_size_str, ',');
        getline(ss, species_str);  // Rest of line (may contain commas in species list)
        
        guild_ids.push_back(stoi(guild_id_str));
        guild_sizes.push_back(stoi(guild_size_str));
        guild_species_strings.push_back(species_str);
    }
    guilds_file.close();
    
    cout << "Loaded " << guild_ids.size() << " guilds" << endl;

    // Warm-up (3 iterations)
    cout << "\nWarm-up..." << endl;
    for (int i = 0; i < 3; i++) {
        // Parse first guild (delimiter: ;;)
        vector<CT_NODE_T> leaf_nodes;
        size_t pos = 0;
        string remaining = guild_species_strings[0];
        while ((pos = remaining.find(";;")) != string::npos) {
            string species = remaining.substr(0, pos);
            if (label_to_node.find(species) != label_to_node.end()) {
                leaf_nodes.push_back(label_to_node[species]);
            }
            remaining = remaining.substr(pos + 2);
        }
        if (!remaining.empty() && label_to_node.find(remaining) != label_to_node.end()) {
            leaf_nodes.push_back(label_to_node[remaining]);
        }
        calculate_faiths_pd_optimized(tree, leaf_nodes);
    }

    // Benchmark all guilds
    cout << "\nBenchmarking " << guild_ids.size() << " guilds..." << endl;
    vector<double> results;
    results.reserve(guild_ids.size());
    
    auto start = high_resolution_clock::now();
    
    for (const auto& species_str : guild_species_strings) {
        // Parse species list (delimiter: ;;)
        vector<CT_NODE_T> leaf_nodes;
        size_t pos = 0;
        string remaining = species_str;
        while ((pos = remaining.find(";;")) != string::npos) {
            string species = remaining.substr(0, pos);
            if (label_to_node.find(species) != label_to_node.end()) {
                leaf_nodes.push_back(label_to_node[species]);
            }
            remaining = remaining.substr(pos + 2);
        }
        // Don't forget the last species
        if (!remaining.empty() && label_to_node.find(remaining) != label_to_node.end()) {
            leaf_nodes.push_back(label_to_node[remaining]);
        }

        // Calculate Faith's PD
        double pd = calculate_faiths_pd_optimized(tree, leaf_nodes);
        results.push_back(pd);
    }
    
    auto end = high_resolution_clock::now();
    double total_time_sec = duration_cast<microseconds>(end - start).count() / 1e6;
    double mean_time_ms = (total_time_sec / results.size()) * 1000.0;

    // Save results
    ofstream output_file(output_path);
    output_file << "guild_id,guild_size,faiths_pd\n";
    for (size_t i = 0; i < results.size(); i++) {
        output_file << guild_ids[i] << "," << guild_sizes[i] << "," 
                   << results[i] << "\n";
    }
    output_file.close();

    // Print summary
    cout << "\n=== COMPACTTREE C++ BENCHMARK (OPTIMIZED) ===" << endl;
    cout << "Guilds processed: " << results.size() << endl;
    cout << "Total time: " << total_time_sec << " seconds" << endl;
    cout << "Mean time per guild: " << mean_time_ms << " ms" << endl;
    cout << "Throughput: " << (results.size() / total_time_sec) << " guilds/second" << endl;
    cout << "\nResults saved to: " << output_path << endl;

    return 0;
}
