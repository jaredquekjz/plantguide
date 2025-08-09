#!/usr/bin/env python3
"""
Convert Douma-Shipley 2022 paper preserving mathematical equations
Using pymupdf4llm which handles LaTeX math well
"""

import pymupdf4llm
import os

# Input PDF
pdf_path = "Papers/DoumaShipley2022SEMTestingModelFitinPathModelswithDependentErrorsGivenNonNormalityNonLinearityandHierarchicalData.pdf"

print(f"Converting: {os.path.basename(pdf_path)}")
print("This may take a minute for a complex paper...")

# Convert to markdown with math preservation
md_result = pymupdf4llm.to_markdown(
    pdf_path,
    page_chunks=True,  # Preserve page structure
    write_images=True,  # Extract equation images
    image_path="Papers/equation_images/",
    dpi=150  # Good quality for equations
)

# Join pages if it's a list
if isinstance(md_result, list):
    md_text = "\n\n---\n\n".join([page["text"] for page in md_result])
else:
    md_text = md_result

# Save the markdown
output_path = "Papers/DoumaShipley2022_converted.md"
with open(output_path, "w", encoding="utf-8") as f:
    f.write(md_text)

print(f"\n✅ Conversion complete!")
print(f"📄 Markdown saved to: {output_path}")
print(f"🖼️  Equation images saved to: Papers/equation_images/")

# Extract first few pages to check quality
print("\n📊 First 500 characters of conversion:")
print("=" * 50)
print(md_text[:500])
print("=" * 50)

# Count equations and key terms
equation_count = md_text.count("$$") // 2  # LaTeX math blocks
dsep_mentions = md_text.lower().count("d-sep")
hierarchical_mentions = md_text.lower().count("hierarchical")
copula_mentions = md_text.lower().count("copula")

print(f"\n📈 Content Statistics:")
print(f"- Math equation blocks found: {equation_count}")
print(f"- D-separation mentions: {dsep_mentions}")
print(f"- Hierarchical mentions: {hierarchical_mentions}")
print(f"- Copula mentions: {copula_mentions}")

print("\n💡 Next steps:")
print("1. Check Papers/DoumaShipley2022_converted.md for the full text")
print("2. Review Papers/equation_images/ for complex equations")
print("3. Key sections to focus on:")
print("   - Section on hierarchical data decomposition")
print("   - Copula formulation for dependent errors")
print("   - Algorithm for model testing")
print("   - Examples with ecological data")