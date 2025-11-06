/**
 * Benchmark ONLY the PD calculation step (excluding tree loading and leaf finding)
 *
 * Compile:
 *   g++ -O3 -std=c++11 -march=native -o benchmark_pd_calculation_only \
 *       benchmark_pd_calculation_only.cpp -I../../CompactTree/CompactTree
 */

#include <iostream>
#include <vector>
#include <unordered_set>
#include <chrono>
#include <algorithm>
#include <cmath>
#include "compact_tree.h"

using namespace std;
using namespace std::chrono;

// ORIGINAL: unordered_set for visited
double calculate_faiths_pd_original(const compact_tree& tree,
                                     const vector<CT_NODE_T>& leaf_nodes) {
    if (leaf_nodes.size() < 2) return 0.0;

    unordered_set<CT_NODE_T> leaf_set(leaf_nodes.begin(), leaf_nodes.end());
    CT_NODE_T mrca = tree.find_mrca(leaf_set);

    unordered_set<CT_NODE_T> visited;  // Hash set
    double total_pd = 0.0;

    for (CT_NODE_T leaf : leaf_nodes) {
        CT_NODE_T current = leaf;
        while (current != mrca) {
            if (visited.find(current) == visited.end()) {
                total_pd += tree.get_edge_length(current);
                visited.insert(current);
            }
            current = tree.get_parent(current);
        }
    }

    return total_pd;
}

// OPTIMIZED: vector<bool> for visited
double calculate_faiths_pd_vectorbool(const compact_tree& tree,
                                      const vector<CT_NODE_T>& leaf_nodes) {
    if (leaf_nodes.size() < 2) return 0.0;

    unordered_set<CT_NODE_T> leaf_set(leaf_nodes.begin(), leaf_nodes.end());
    CT_NODE_T mrca = tree.find_mrca(leaf_set);

    const size_t num_nodes = tree.get_num_nodes();
    vector<bool> visited(num_nodes, false);  // Boolean array
    double total_pd = 0.0;

    for (CT_NODE_T leaf : leaf_nodes) {
        CT_NODE_T current = leaf;
        while (current != mrca) {
            if (!visited[current]) {
                total_pd += tree.get_edge_length(current);
                visited[current] = true;
            }
            current = tree.get_parent(current);
        }
    }

    return total_pd;
}

// ALTERNATIVE: vector<uint8_t> instead of vector<bool> (avoid bit-packing overhead)
double calculate_faiths_pd_vectoruint8(const compact_tree& tree,
                                       const vector<CT_NODE_T>& leaf_nodes) {
    if (leaf_nodes.size() < 2) return 0.0;

    unordered_set<CT_NODE_T> leaf_set(leaf_nodes.begin(), leaf_nodes.end());
    CT_NODE_T mrca = tree.find_mrca(leaf_set);

    const size_t num_nodes = tree.get_num_nodes();
    vector<uint8_t> visited(num_nodes, 0);  // Byte array (no bit-packing)
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

int main(int argc, char** argv) {
    if (argc < 3) {
        cerr << "Usage: " << argv[0] << " <tree.nwk> <species1> <species2> ..." << endl;
        return 1;
    }

    // Load tree ONCE
    cout << "Loading tree..." << endl;
    compact_tree tree(argv[1], true, true, true, 25000);

    // Find leaf nodes ONCE
    vector<string> species_labels;
    for (int i = 2; i < argc; i++) {
        species_labels.push_back(argv[i]);
    }

    vector<CT_NODE_T> leaf_nodes;
    for (CT_NODE_T i = 0; i < tree.get_num_nodes(); i++) {
        if (tree.is_leaf(i)) {
            string label = tree.get_label(i);
            for (const auto& sp : species_labels) {
                if (label == sp) {
                    leaf_nodes.push_back(i);
                    break;
                }
            }
        }
    }

    cout << "Found " << leaf_nodes.size() << " leaf nodes" << endl;
    cout << endl;

    // Warm-up (3 iterations)
    for (int i = 0; i < 3; i++) {
        calculate_faiths_pd_original(tree, leaf_nodes);
        calculate_faiths_pd_vectorbool(tree, leaf_nodes);
        calculate_faiths_pd_vectoruint8(tree, leaf_nodes);
    }

    const int N = 1000;

    // Benchmark ORIGINAL (unordered_set)
    auto start1 = high_resolution_clock::now();
    double result1 = 0.0;
    for (int i = 0; i < N; i++) {
        result1 = calculate_faiths_pd_original(tree, leaf_nodes);
    }
    auto end1 = high_resolution_clock::now();
    double time1 = duration_cast<nanoseconds>(end1 - start1).count() / 1e6 / N;

    // Benchmark VECTORBOOL (vector<bool>)
    auto start2 = high_resolution_clock::now();
    double result2 = 0.0;
    for (int i = 0; i < N; i++) {
        result2 = calculate_faiths_pd_vectorbool(tree, leaf_nodes);
    }
    auto end2 = high_resolution_clock::now();
    double time2 = duration_cast<nanoseconds>(end2 - start2).count() / 1e6 / N;

    // Benchmark VECTORUINT8 (vector<uint8_t>)
    auto start3 = high_resolution_clock::now();
    double result3 = 0.0;
    for (int i = 0; i < N; i++) {
        result3 = calculate_faiths_pd_vectoruint8(tree, leaf_nodes);
    }
    auto end3 = high_resolution_clock::now();
    double time3 = duration_cast<nanoseconds>(end3 - start3).count() / 1e6 / N;

    // Results
    cout << "=== BENCHMARK RESULTS (1000 iterations) ===" << endl;
    cout << endl;
    cout << "Faith's PD value: " << result1 << " (all versions)" << endl;
    cout << endl;
    cout << "1. ORIGINAL (unordered_set):  " << time1 << " ms" << endl;
    cout << "2. VECTORBOOL (vector<bool>): " << time2 << " ms  (" << (time1/time2) << "× vs original)" << endl;
    cout << "3. VECTORUINT8 (vector<u8>):  " << time3 << " ms  (" << (time1/time3) << "× vs original)" << endl;
    cout << endl;

    // Winner
    if (time1 < time2 && time1 < time3) {
        cout << "WINNER: ORIGINAL (unordered_set)" << endl;
    } else if (time2 < time1 && time2 < time3) {
        cout << "WINNER: VECTORBOOL (vector<bool>)" << endl;
        cout << "Speedup: " << (time1/time2) << "×" << endl;
    } else {
        cout << "WINNER: VECTORUINT8 (vector<uint8_t>)" << endl;
        cout << "Speedup: " << (time1/time3) << "×" << endl;
    }

    return 0;
}
