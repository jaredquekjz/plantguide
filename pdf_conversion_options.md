# PDF Conversion Options for Academic Papers with LaTeX Math

## 🏆 BEST OPTIONS for Math-Heavy PDFs

### 1. **PyMuPDF (fitz) + pymupdf4llm** ⭐⭐⭐⭐⭐
**The Current Best for Academic Papers!**
```bash
pip install pymupdf pymupdf4llm

# Python script
import pymupdf4llm
text = pymupdf4llm.to_markdown("paper.pdf")
# Preserves: equations, tables, formatting
```

### 2. **Nougat (Neural OCR)** ⭐⭐⭐⭐⭐
**Facebook's AI for Scientific PDFs - AMAZING for LaTeX!**
```bash
pip install nougat-ocr

# Command line
nougat Papers/DoumaShipley2022*.pdf -o output_dir --markdown
# Converts LaTeX equations to markdown math!
```

### 3. **GROBID** ⭐⭐⭐⭐
**Scientific Paper Structure Extraction**
- Specifically designed for academic papers
- Preserves citations, equations, structure
- Requires Java but worth it for complex papers
```bash
# Docker version (easiest)
docker run -t --rm -p 8070:8070 lfoppiano/grobid:0.7.3

# Then use client
pip install grobid-client-python
grobid_client --input Papers/ --output converted/
```

### 4. **Mathpix** ⭐⭐⭐⭐⭐ (Commercial but Free Tier)
**Best LaTeX equation recognition**
- Literally designed for math equations
- API or desktop app
- Free tier: 100 pages/month
- Perfect for critical papers like this
```python
import mathpix
mathpix.convert("paper.pdf", format="text.md")
```

### 5. **pypdfium2 + custom parsing** ⭐⭐⭐
**More control over extraction**
```python
import pypdfium2 as pdfium
pdf = pdfium.PdfDocument("paper.pdf")
# Custom extraction with layout analysis
```

## 🚀 RECOMMENDED APPROACH for Douma-Shipley 2022

### Step 1: Try Nougat First (Free & Powerful)
```bash
# Install in plants environment
source ~/miniconda3/etc/profile.d/conda.sh && conda activate plants
pip install nougat-ocr

# Convert with equation preservation
nougat Papers/DoumaShipley2022*.pdf -o Papers/converted/ --markdown --pages 1-30
```

### Step 2: If Nougat struggles, use pymupdf4llm
```python
import pymupdf4llm

# Convert to markdown with math
md_text = pymupdf4llm.to_markdown(
    "Papers/DoumaShipley2022SEMTestingModelFitinPathModelswithDependentErrorsGivenNonNormalityNonLinearityandHierarchicalData.pdf",
    page_chunks=True,
    write_images=True,  # Saves equation images
    image_path="Papers/images/"
)

# Save the markdown
with open("Papers/DoumaShipley2022_converted.md", "w") as f:
    f.write(md_text)
```

### Step 3: For Perfect Equations - Mathpix Snip
- Download Mathpix Snip desktop app
- Screenshot key equations
- Converts to perfect LaTeX/Markdown

## 📊 Comparison Table

| Tool | Math Quality | Speed | Free? | Best For |
|------|-------------|-------|-------|----------|
| Nougat | Excellent | Slow | Yes | Full paper with math |
| pymupdf4llm | Good | Fast | Yes | Quick conversion |
| GROBID | Very Good | Medium | Yes | Structure + citations |
| Mathpix | Perfect | Fast | Limited | Key equations |
| pdfplumber | Fair | Fast | Yes | Tables & basic text |

## 🎯 For This Specific Paper

Given that Douma-Shipley 2022 has:
- Complex statistical equations
- Hierarchical model notation  
- DAG diagrams
- Copula formulas

**BEST APPROACH:**
1. Use **Nougat** for full conversion (preserves LaTeX)
2. Use **Mathpix** for critical equations you'll implement
3. Keep PDF open for visual reference of diagrams

## 💡 Quick Test Script

```python
# Test which works best for this paper
import subprocess
import pymupdf4llm

# Method 1: Nougat
print("Testing Nougat...")
subprocess.run(["nougat", "Papers/DoumaShipley2022*.pdf", 
                "-o", "test_output", "--markdown", "--pages", "1-5"])

# Method 2: pymupdf4llm  
print("Testing pymupdf4llm...")
text = pymupdf4llm.to_markdown("Papers/DoumaShipley2022*.pdf", 
                                pages=[0,1,2,3,4])
with open("test_pymupdf.md", "w") as f:
    f.write(text)

print("Check both outputs and see which preserves math better!")
```

## 🔥 Why This Matters

The hierarchical methods in this paper are CRITICAL because:
- Equation 3: Decomposition for non-normal data
- Equation 7: Copula for dependent errors  
- Equation 12: Hierarchical likelihood
- Algorithm 1: Full testing procedure

These MUST be preserved perfectly for implementation!