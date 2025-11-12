// dump_tree_structure.cpp
// Utility to export CompactTree internal structure for Rust loading
//
// Usage: ./dump_tree_structure <tree.nwk> <output.bin>
//
// Output format (binary):
// - u32: num_nodes
// - u32: num_leaves
// For each node (0..num_nodes):
//   - u32: parent index (0xFFFFFFFF = NULL)
//   - u32: num_children
//   - u32[num_children]: child indices
//   - u32: label_len
//   - char[label_len]: label string
//   - f32: edge_length

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdint>
#include "../../CompactTree/CompactTree/compact_tree.h"

using namespace std;

void write_u32(ofstream& out, uint32_t value) {
    out.write(reinterpret_cast<const char*>(&value), sizeof(uint32_t));
}

void write_f32(ofstream& out, float value) {
    out.write(reinterpret_cast<const char*>(&value), sizeof(float));
}

void write_string(ofstream& out, const string& str) {
    uint32_t len = str.length();
    write_u32(out, len);
    out.write(str.c_str(), len);
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <tree.nwk> <output.bin>" << endl;
        return 1;
    }

    string tree_path = argv[1];
    string output_path = argv[2];

    // Load tree
    cout << "Loading tree from: " << tree_path << endl;
    compact_tree tree(tree_path);

    uint32_t num_nodes = tree.get_num_nodes();
    uint32_t num_leaves = tree.get_num_leaves();

    cout << "Tree loaded:" << endl;
    cout << "  Nodes: " << num_nodes << endl;
    cout << "  Leaves: " << num_leaves << endl;

    // Open output file
    ofstream out(output_path, ios::binary);
    if (!out) {
        cerr << "Failed to open output file: " << output_path << endl;
        return 1;
    }

    // Write header
    write_u32(out, num_nodes);
    write_u32(out, num_leaves);

    // Write each node
    for (uint32_t i = 0; i < num_nodes; i++) {
        // Parent
        CT_NODE_T parent = tree.get_parent(i);
        write_u32(out, parent);

        // Children
        vector<CT_NODE_T> children = tree.get_children(i);
        write_u32(out, children.size());
        for (CT_NODE_T child : children) {
            write_u32(out, child);
        }

        // Label
        string label = tree.get_label(i);
        write_string(out, label);

        // Edge length
        float edge_length = tree.get_edge_length(i);
        write_f32(out, edge_length);
    }

    out.close();
    cout << "Tree structure dumped to: " << output_path << endl;

    return 0;
}
