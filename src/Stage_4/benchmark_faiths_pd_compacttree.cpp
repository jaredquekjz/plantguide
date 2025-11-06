/**
 * Benchmark Faith's PD calculation using CompactTree (pure C++)
 *
 * Compile:
 *   g++ -O3 -std=c++11 -o benchmark_faiths_pd_compacttree \
 *       benchmark_faiths_pd_compacttree.cpp \
 *       -I../../CompactTree/CompactTree
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <chrono>
#include <algorithm>
#include <cmath>
#include "compact_tree.h"

using namespace std;
using namespace std::chrono;

// Calculate Faith's Phylogenetic Diversity
double calculate_faiths_pd(const compact_tree& tree, const vector<CT_NODE_T>& leaf_nodes) {
    if (leaf_nodes.size() == 0) return 0.0;
    if (leaf_nodes.size() == 1) return 0.0;  // Single species: no diversity

    // Find MRCA using CompactTree's optimized find_mrca
    unordered_set<CT_NODE_T> leaf_set(leaf_nodes.begin(), leaf_nodes.end());
    CT_NODE_T mrca = tree.find_mrca(leaf_set);

    // Sum unique branch lengths from each leaf to MRCA
    unordered_set<CT_NODE_T> visited_nodes;
    double total_pd = 0.0;

    for (CT_NODE_T leaf : leaf_nodes) {
        CT_NODE_T current = leaf;
        while (current != mrca) {
            if (visited_nodes.find(current) == visited_nodes.end()) {
                total_pd += tree.get_edge_length(current);
                visited_nodes.insert(current);
            }
            current = tree.get_parent(current);
        }
    }

    return total_pd;
}

// Load WFO ID to tree tip mapping
unordered_map<string, string> load_mapping(const string& mapping_path) {
    unordered_map<string, string> wfo_to_tip;
    ifstream file(mapping_path);
    string line;

    // Skip header
    getline(file, line);

    while (getline(file, line)) {
        stringstream ss(line);
        string wfo_id, wfo_scientific_name, is_infraspecific, parent_binomial, parent_label, tree_tip;

        // Parse CSV: wfo_taxon_id,wfo_scientific_name,is_infraspecific,parent_binomial,parent_label,tree_tip
        getline(ss, wfo_id, ',');
        getline(ss, wfo_scientific_name, ',');
        getline(ss, is_infraspecific, ',');
        getline(ss, parent_binomial, ',');
        getline(ss, parent_label, ',');
        getline(ss, tree_tip, ',');

        if (!tree_tip.empty()) {
            wfo_to_tip[wfo_id] = tree_tip;
        }
    }

    return wfo_to_tip;
}

// Find node IDs for given species labels
vector<CT_NODE_T> find_leaf_nodes(const compact_tree& tree, const vector<string>& species_labels) {
    vector<CT_NODE_T> leaf_nodes;

    for (CT_NODE_T i = 0; i < tree.get_num_nodes(); i++) {
        if (tree.is_leaf(i)) {
            string label = tree.get_label(i);
            if (find(species_labels.begin(), species_labels.end(), label) != species_labels.end()) {
                leaf_nodes.push_back(i);
            }
        }
    }

    return leaf_nodes;
}

int main(int argc, char** argv) {
    // Configuration
    string tree_path = "data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk";
    string mapping_path = "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv";
    int n_iterations = 50;

    // Test species (7 plants for guild)
    vector<string> test_species_wfo = {
        "wfo-0000510888",
        "wfo-0000510976",
        "wfo-0000511089",
        "wfo-0000511376",
        "wfo-0000511572",
        "wfo-0000511610",
        "wfo-0000511783"
    };

    cout << "======================================================================" << endl;
    cout << "COMPACTTREE PURE C++ BENCHMARK" << endl;
    cout << "======================================================================" << endl;

    // Load tree
    cout << "Loading tree from: " << tree_path << endl;
    auto start = high_resolution_clock::now();
    compact_tree tree(tree_path);
    auto end = high_resolution_clock::now();
    double load_time = duration_cast<microseconds>(end - start).count() / 1000.0;

    cout << "  Tree loaded: " << tree.get_num_leaves() << " tips in "
         << load_time << " ms" << endl;

    // Load mapping
    cout << "Loading mapping from: " << mapping_path << endl;
    auto wfo_to_tip = load_mapping(mapping_path);
    cout << "  Loaded " << wfo_to_tip.size() << " mappings" << endl;

    // Convert WFO IDs to tree tips
    vector<string> test_species;
    for (const auto& wfo : test_species_wfo) {
        if (wfo_to_tip.find(wfo) != wfo_to_tip.end()) {
            test_species.push_back(wfo_to_tip[wfo]);
        }
    }
    cout << "  Test species: " << test_species.size() << endl;

    // Debug: Print first few tree labels
    cout << "\n  Debug: First 5 tree tip labels:" << endl;
    int count = 0;
    for (CT_NODE_T i = 0; i < tree.get_num_nodes() && count < 5; i++) {
        if (tree.is_leaf(i)) {
            cout << "    " << tree.get_label(i) << endl;
            count++;
        }
    }

    cout << "\n  Debug: Looking for species:" << endl;
    for (const auto& sp : test_species) {
        cout << "    " << sp << endl;
    }

    // Find leaf nodes
    auto leaf_nodes = find_leaf_nodes(tree, test_species);
    cout << "\n  Found " << leaf_nodes.size() << " leaf nodes in tree" << endl;

    // Warm-up
    for (int i = 0; i < 3; i++) {
        calculate_faiths_pd(tree, leaf_nodes);
    }

    // Benchmark
    cout << "\nRunning " << n_iterations << " iterations..." << endl;
    vector<double> times;
    double faiths_pd_value = 0.0;

    for (int i = 0; i < n_iterations; i++) {
        start = high_resolution_clock::now();
        faiths_pd_value = calculate_faiths_pd(tree, leaf_nodes);
        end = high_resolution_clock::now();

        double elapsed_ms = duration_cast<nanoseconds>(end - start).count() / 1e6;
        times.push_back(elapsed_ms);
    }

    // Calculate statistics
    sort(times.begin(), times.end());
    double mean = 0.0;
    for (double t : times) mean += t;
    mean /= times.size();

    double median = times[times.size() / 2];
    double min_time = times[0];
    double max_time = times[times.size() - 1];

    double variance = 0.0;
    for (double t : times) {
        variance += (t - mean) * (t - mean);
    }
    double stdev = sqrt(variance / times.size());

    // Print results
    cout << "\nResults (" << n_iterations << " iterations):" << endl;
    cout << "  Mean: " << mean << " ms" << endl;
    cout << "  Median: " << median << " ms" << endl;
    cout << "  Min: " << min_time << " ms" << endl;
    cout << "  Max: " << max_time << " ms" << endl;
    cout << "  Std Dev: " << stdev << " ms" << endl;
    cout << "  Faith's PD: " << faiths_pd_value << endl;
    cout << "\n  Throughput: " << (1000.0 / median) << " guilds/second/core" << endl;

    cout << "\n======================================================================" << endl;

    return 0;
}
