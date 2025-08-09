#!/usr/bin/env python3
"""
Simple Visual Diagram: Shipley 2017 → Extended 2024 Model
Creates a clear visualization of how we extend the original work
"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np

# Set up the figure
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 10))
fig.suptitle('Extending Shipley 2017: From Correlation to Causation to Application', 
             fontsize=16, fontweight='bold')

# ========== LEFT PANEL: Shipley 2017 Original ==========
ax1.set_title('Shipley 2017 Original Model', fontsize=14, fontweight='bold')
ax1.set_xlim(0, 10)
ax1.set_ylim(0, 10)
ax1.axis('off')

# Input box
input_box = FancyBboxPatch((1, 7), 3, 2,
                           boxstyle="round,pad=0.1",
                           facecolor='lightblue',
                           edgecolor='darkblue', linewidth=2)
ax1.add_patch(input_box)
ax1.text(2.5, 8.3, '4 Traits', ha='center', fontweight='bold')
ax1.text(2.5, 7.8, '• Leaf Area', ha='center', fontsize=9)
ax1.text(2.5, 7.5, '• LDMC', ha='center', fontsize=9)
ax1.text(2.5, 7.2, '• SLA', ha='center', fontsize=9)

# Method box
method_box = FancyBboxPatch((1, 4), 3, 1.5,
                            boxstyle="round,pad=0.1",
                            facecolor='lightyellow',
                            edgecolor='darkorange', linewidth=2)
ax1.add_patch(method_box)
ax1.text(2.5, 4.7, 'Ordinal\nRegression', ha='center', fontweight='bold')

# Output box
output_box = FancyBboxPatch((1, 1), 3, 1.5,
                            boxstyle="round,pad=0.1",
                            facecolor='lightgreen',
                            edgecolor='darkgreen', linewidth=2)
ax1.add_patch(output_box)
ax1.text(2.5, 1.7, 'Ellenberg\nScores (1-9)', ha='center', fontweight='bold')

# Arrows
arrow1 = FancyArrowPatch((2.5, 7), (2.5, 5.5),
                        connectionstyle="arc3", 
                        arrowstyle='->', mutation_scale=20, linewidth=2)
ax1.add_patch(arrow1)

arrow2 = FancyArrowPatch((2.5, 4), (2.5, 2.5),
                        connectionstyle="arc3",
                        arrowstyle='->', mutation_scale=20, linewidth=2)
ax1.add_patch(arrow2)

# Stats box
stats_box = FancyBboxPatch((5, 3), 3, 4,
                           boxstyle="round,pad=0.1",
                           facecolor='#f0f0f0',
                           edgecolor='black', linewidth=1)
ax1.add_patch(stats_box)
ax1.text(6.5, 6, 'Results:', fontweight='bold', ha='center')
ax1.text(6.5, 5.3, '~1,000 species', ha='center')
ax1.text(6.5, 4.8, '70-90% accurate', ha='center')
ax1.text(6.5, 4.3, 'Point estimates', ha='center')
ax1.text(6.5, 3.8, 'Correlation-based', ha='center')

# ========== RIGHT PANEL: Extended 2024 Model ==========
ax2.set_title('Extended 2024 Model', fontsize=14, fontweight='bold')
ax2.set_xlim(0, 10)
ax2.set_ylim(0, 10)
ax2.axis('off')

# Enhanced Input
input2_box = FancyBboxPatch((0.5, 7.5), 3.5, 2,
                           boxstyle="round,pad=0.1",
                           facecolor='lightblue',
                           edgecolor='darkblue', linewidth=2)
ax2.add_patch(input2_box)
ax2.text(2.25, 8.8, 'Expanded Traits', ha='center', fontweight='bold')
ax2.text(2.25, 8.3, 'Original 4 + Root depth', ha='center', fontsize=9)
ax2.text(2.25, 8.0, 'Stomatal density, etc.', ha='center', fontsize=9)

# Advanced Methods
method2_box = FancyBboxPatch((0.5, 5), 3.5, 2,
                            boxstyle="round,pad=0.1",
                            facecolor='#ffffcc',
                            edgecolor='darkorange', linewidth=2)
ax2.add_patch(method2_box)
ax2.text(2.25, 6.3, 'Multi-Method', ha='center', fontweight='bold')
ax2.text(2.25, 5.9, '• Causal SEM', ha='center', fontsize=9)
ax2.text(2.25, 5.6, '• Machine Learning', ha='center', fontsize=9)
ax2.text(2.25, 5.3, '• D-separation tests', ha='center', fontsize=9)

# Causal Discovery
causal_box = FancyBboxPatch((4.5, 5), 3, 2,
                           boxstyle="round,pad=0.1",
                           facecolor='#ffeeee',
                           edgecolor='darkred', linewidth=2)
ax2.add_patch(causal_box)
ax2.text(6, 6.3, 'Causal Discovery', ha='center', fontweight='bold')
ax2.text(6, 5.9, 'WHY not just WHAT', ha='center', fontsize=9)
ax2.text(6, 5.6, 'Validated pathways', ha='center', fontsize=9)
ax2.text(6, 5.3, 'DAG validation', ha='center', fontsize=9)

# Enhanced Output
output2_box = FancyBboxPatch((0.5, 2.5), 3.5, 2,
                            boxstyle="round,pad=0.1",
                            facecolor='lightgreen',
                            edgecolor='darkgreen', linewidth=2)
ax2.add_patch(output2_box)
ax2.text(2.25, 3.8, 'Ellenberg + Confidence', ha='center', fontweight='bold')
ax2.text(2.25, 3.4, '14,835 species', ha='center', fontsize=9)
ax2.text(2.25, 3.0, 'Uncertainty quantified', ha='center', fontsize=9)

# Practical Application
app_box = FancyBboxPatch((4.5, 0.5), 4, 3,
                         boxstyle="round,pad=0.1",
                         facecolor='#ffe6f2',
                         edgecolor='purple', linewidth=2)
ax2.add_patch(app_box)
ax2.text(6.5, 3, '🌱 Garden Guides', ha='center', fontweight='bold', fontsize=11)
ax2.text(6.5, 2.4, '💧 Water 2-3x weekly', ha='center', fontsize=9)
ax2.text(6.5, 2.0, '☀️ 6+ hours sun', ha='center', fontsize=9)
ax2.text(6.5, 1.6, '📊 85% confidence', ha='center', fontsize=9)
ax2.text(6.5, 1.0, '50,000+ plants!', ha='center', fontweight='bold', fontsize=9)

# Complex arrows showing flow
arrow3 = FancyArrowPatch((2.25, 7.5), (2.25, 7),
                        arrowstyle='->', mutation_scale=20, linewidth=2)
ax2.add_patch(arrow3)

arrow4 = FancyArrowPatch((2.25, 5), (2.25, 4.5),
                        arrowstyle='->', mutation_scale=20, linewidth=2)
ax2.add_patch(arrow4)

arrow5 = FancyArrowPatch((4, 6), (4.5, 6),
                        arrowstyle='->', mutation_scale=20, linewidth=2, color='red')
ax2.add_patch(arrow5)

arrow6 = FancyArrowPatch((4, 3.5), (4.5, 2),
                        arrowstyle='->', mutation_scale=20, linewidth=2, color='purple')
ax2.add_patch(arrow6)

# Add comparison callout
comparison_text = fig.text(0.5, 0.05, 
                          '🔄 KEY IMPROVEMENTS: 14x more species | Causal understanding | ' +
                          'Confidence intervals | Practical applications',
                          ha='center', fontsize=12, fontweight='bold',
                          bbox=dict(boxstyle="round,pad=0.3", facecolor='yellow', alpha=0.7))

plt.tight_layout()
plt.savefig('shipley_model_extension.png', dpi=300, bbox_inches='tight')
plt.show()

print("✨ Diagram created as 'shipley_model_extension.png'!")
print("\nKey talking points for Prof. Shipley:")
print("1. Your model is the foundation - we're building on it, not replacing it")
print("2. With 14x more data, we can validate your causal theories")
print("3. We add practical value while maintaining scientific rigor")
print("4. Your d-separation tests ensure we're finding real causation")
print("5. This could help millions of gardeners make better decisions")