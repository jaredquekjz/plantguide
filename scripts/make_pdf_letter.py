#!/usr/bin/env python3
import textwrap
import datetime

A4_WIDTH = 595  # points
A4_HEIGHT = 842
MARGIN_L = 56   # ~0.78 inch
MARGIN_R = 56
MARGIN_T = 56
MARGIN_B = 56
FONT_SIZE = 11
LEADING = 14

def pdf_escape(s: str) -> str:
    return s.replace('\\', r'\\').replace('(', r'\(').replace(')', r'\)')

def build_page_stream(lines):
    # Build a content stream with simple absolute-positioned text lines.
    y = A4_HEIGHT - MARGIN_T
    x = MARGIN_L
    chunks = []
    for line in lines:
        if y < MARGIN_B + LEADING:
            # signal page break by None marker
            chunks.append(None)
            y = A4_HEIGHT - MARGIN_T
        esc = pdf_escape(line)
        cmd = f"BT /F1 {FONT_SIZE} Tf {x} {y} Td ({esc}) Tj ET\n"
        chunks.append(cmd)
        y -= LEADING
    return chunks

def paginate(lines):
    # Split into page-wise content command lists
    cmds = build_page_stream(lines)
    pages = []
    cur = []
    for c in cmds:
        if c is None:
            pages.append(''.join(cur).encode('utf-8'))
            cur = []
        else:
            cur.append(c)
    if cur:
        pages.append(''.join(cur).encode('utf-8'))
    return pages

def build_pdf(pages):
    objects = []
    xref = []

    def add_object(obj_bytes):
        xref.append(len(pdf))
        objects.append(obj_bytes)

    # Prepare catalog, pages, fonts, per-page content
    # We'll build pages first to know their object numbers
    pdf = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    xref.append(len(pdf))
    # We'll add objects later; for now, reserve index 0
    objects.append(b"")

    font_obj_num = len(objects)
    font_obj = f"{font_obj_num} 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>\nendobj\n".encode()
    add_object(font_obj)

    content_obj_nums = []
    page_obj_nums = []
    for content in pages:
        cnum = len(objects) + 1
        stream = b"stream\n" + content + b"endstream\n"
        cobj = f"{cnum} 0 obj\n<< /Length {len(content)} >>\n".encode() + stream + b"endobj\n"
        add_object(cobj)
        content_obj_nums.append(len(objects))
        page_obj_nums.append(None)

    pages_obj_num = len(objects) + 1
    # Create page objects referencing content and font; parent set later
    for idx, cnum in enumerate(content_obj_nums):
        pnum = len(objects) + 1
        pobj = (
            f"{pnum} 0 obj\n"
            f"<< /Type /Page /Parent {pages_obj_num} 0 R /Resources << /Font << /F1 {font_obj_num} 0 R >> >> "
            f"/MediaBox [0 0 {A4_WIDTH} {A4_HEIGHT}] /Contents {cnum} 0 R >>\n"
            f"endobj\n"
        ).encode()
        add_object(pobj)
        page_obj_nums[idx] = len(objects)

    kids = ' '.join(f"{n} 0 R" for n in page_obj_nums)
    pages_obj = (
        f"{pages_obj_num} 0 obj\n<< /Type /Pages /Count {len(page_obj_nums)} /Kids [ {kids} ] >>\nendobj\n"
    ).encode()
    add_object(pages_obj)

    catalog_obj_num = len(objects) + 1
    catalog_obj = f"{catalog_obj_num} 0 obj\n<< /Type /Catalog /Pages {pages_obj_num} 0 R >>\nendobj\n".encode()
    add_object(catalog_obj)

    # Assemble
    pdf = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    xref = [len(pdf)]
    for obj in objects[1:]:
        xref.append(len(pdf))
        pdf += obj
    # xref table
    xref_pos = len(pdf)
    pdf += f"xref\n0 {len(xref)}\n".encode()
    pdf += b"0000000000 65535 f \n"
    for off in xref[1:]:
        pdf += f"{off:010d} 00000 n \n".encode()
    pdf += (
        b"trailer\n<< /Size " + str(len(xref)).encode() + b" /Root " + str(catalog_obj_num).encode() + b" 0 R >>\nstartxref\n" + str(xref_pos).encode() + b"\n%%EOF\n"
    )
    return pdf

def wrap_paragraphs(text):
    wrapped = []
    for para in text.split('\n\n'):
        lines = textwrap.wrap(para, width=90, replace_whitespace=False, drop_whitespace=False)
        if not lines:
            wrapped.append("")
        else:
            wrapped.extend(lines)
        wrapped.append("")
    return wrapped

def to_ascii_safe(s: str) -> str:
    # Replace common Unicode symbols with ASCII-safe equivalents
    replacements = {
        "–": "-", "—": "-", "−": "-", "•": "-", "·": "-",
        "×": "x", "→": "->", "↔": "<->", "≥": ">=", "≤": "<=", "≈": "~",
        "ß": "ss", "’": "'", "‘": "'", "“": '"', "”": '"', "€": "EUR",
        " ": " ", " ": " ", " ": " ", " ": " ", "﻿": "",
        "τ": "tau", "ρ": "rho", "σ": "sigma", "µ": "u",
    }
    out = []
    for ch in s:
        if ord(ch) < 128 and ch not in ["\u000b", "\u000c"]:
            out.append(ch)
        else:
            out.append(replacements.get(ch, '?'))
    return ''.join(out)

def main(out_path):
    today = datetime.date.today().isoformat()
    letter = f"""
Project Brief: From Plant Traits to Gardening Requirements\n
{today}\n
Dear Prof. Shipley,\n
Thank you for taking the time to discuss this project. Below is a concise overview of what has been built so far, the key evidence behind modeling choices, and the places where your guidance would most strengthen the work.\n
Scope & Goal\n- Purpose: Predict continuous EIVE (L, T, M, R, N) from six curated TRY traits (LA, Nmass, LMA, H, SM, SSD), then translate predictions into simple gardening requirements with uncertainty.\n- Philosophy: Diagnostic-first. Quantify exactly what six widely available traits can and cannot explain; add missing predictors with evidence.\n- Outputs: Per-species axis predictions (0–10), bin labels (low/med/high) with confidence, and optional joint suitability via residual copulas.\n
Data & Pipeline\n- Data: 5,799 species matched to EIVE; 1,069 complete-case (SSD observed+imputed); 389 observed-SSD-only sensitivity set.\n- Preprocessing: log10 transforms (LA, H, SM, SSD), standardized predictors per fold, repeated stratified CV (5×5 to 10×5).\n- Reproducibility: All scripts and artifacts are saved end-to-end (data assembly → multiple regression → SEM → copulas → gardening).\n
Modeling Decisions (Evidence-Driven)\n- Mean structure (SEM, piecewise): LES_core (−LMA, +Nmass) and SIZE (+logH, +logSM). Deconstructing SIZE to logH+logSM for M/N improved CV. Final linear forms: L/T/R ~ LES + SIZE + logLA; M/N ~ LES + logH + logSM + logSSD + logLA; retain LES×logSSD for N only.\n- SSD effects: Adopt direct SSD→M and SSD→N; leave R weak in piecewise. Woodiness/mycorrhiza used diagnostically; not in default means.\n- Nonlinearity: Splines and extra interactions rejected after consistent CV degradation; linear models retained for parsimony and clarity.\n- lavaan vs piecewise: lavaan with co-adaptation (LES↔SIZE, LES↔logSSD) shows large IC gains but subpar absolute fit with only six predictors; piecewise consistently wins on CV and is used for predictions (lavaan retained for transparent structure/fit reporting).\n- Residual dependence (MAG + copulas): Targeted spouse set via mixed, rank-based m-sep: T–R (+), T–M (−), M–R (−), L–M (−), M–N (+). Gaussian copulas chosen by AIC and adequacy checks (Kendall τ, tails). Optional per-group copulas with shrinkage n/(n+K) to stabilize small groups.\n
Performance & Diagnostics\n- Baseline (multiple regression, CV R²±SD): L 0.15±0.05, T 0.10±0.04, M 0.13±0.05, R 0.04±0.03, N 0.36±0.04; RMSE ≈ 1.26–1.52. Strongest: N; weakest: R.\n- SEM improvements: Clear gains on M/N via structure and SIZE deconstruction; L/T modest; R remains weakest; linear forms preferred by CV/IC.\n- Residuals: Copulas capture modest, meaningful co-movement (e.g., T–R ≈ +0.33; T–M ≈ −0.39) to calibrate joint probabilities without changing means.\n- Reliability bands: Per-axis confidence from SEM CV R²: M/N strongest, L/T moderate, R weakest; borderline handling reduces overconfident edge calls.\n
Gardening Plan\n- Axis bins: [0,3.5), [3.5,6.5), [6.5,10]; labels aligned to expert terms (e.g., Full Sun, Drought-Tolerant).\n- Joint suitability: Monte Carlo with MAG residual copulas; thresholded gates (e.g., require M=high & N=high at p ≥ 0.6); preset scenarios with/without R.\n- Group-aware uncertainty: Optional per-group σ (from CV residuals) and ρ (from per-group copulas) improve joint calibration; fall back to global if missing.\n- Label usage: Stage 6 joint scoring never uses observed EIVE labels for test species; it treats EIVE as unknown and scores around trait-predicted means.\n
Key Decision Points (Why)\n- Keep it linear: Nonlinear terms and extra interactions showed no robust predictive gains; parsimony and interpretability prioritized.\n- SSD direct effects: Retained for M/N based on wood economics theory and CV; R remains weak — handled via cautious confidence and R-excluded presets.\n- Co-adaptation: Documented in lavaan; predictions anchored in piecewise for better CV; signals readiness for later latent refinements.\n- Residual copulas: Small, tested spouse set included to focus on practical dependencies; shrinkage prevents overfitting small groups.\n
Bottom Line\nWith six traits, predictive skill ranges from useful to strong depending on axis: best for N, useful for L/T/M, weak for R. SEM provides a coherent causal mean structure tied to global spectra (LES, SIZE, SSD) and yields robust, linear final equations. Copulas add realistic joint behavior for multi-constraint gardening decisions; group-aware options strengthen calibration without altering means. The system outputs transparent, confidence-coded guidance suitable for end users and for benchmarking future improvements.\n
Limitations & Open Needs\n- R (soil pH) weak: Six traits miss edaphic signals; needs root traits, base cations, mycorrhiza, and/or soil covariates.\n- Temperature specificity: Add exogenous climate envelopes (CHELSA/WorldClim) and categorical syndromes (phenology, growth form).\n- Light specificity: Add leaf thickness, N per area, growth form, woodiness, phenology; mycorrhiza as context.\n- Global fit (m-sep/LRT): Defer full global fit until richer predictors/groups are integrated; then use to adjudicate competing MAGs and finalize structure.\n- Missing data: Plan phylogenetic/multiple imputation for new predictors; validate imputation via CV without leakage.\n
Where Your Expertise Helps Most\n- Integrating predictors: Principled inclusion of new continuous/categorical traits and exogenous covariates; encode groupings without overfitting; advise on phylogenetic/multivariate imputation.\n- Structural expansion: Evolve SEM/MAG while preserving causal interpretability; set criteria for interactions/nonlinearities; define when/how to re-run global m-sep/LRT and interpret diagnostics.\n- Residual modeling: Validate spouse set selection; assess non-Gaussian copulas or vines if tails/asymmetries emerge; calibrate per-group shrinkage and diagnostics.\n- Strategy/services: Map traits to CSR positions and to ecosystem-service indicators with quantified uncertainty and validation plans.\n- Global extension: Justify extension beyond Europe via occurrences (GBIF), climate/soil layers, and biotic context (GloBI); plan transferability tests and bias controls.\n
Immediate Next Steps (Proposed)\n- Add high-coverage light and temperature predictors (leaf thickness, Narea; phenology, growth form; climate envelopes) and root/edaphic traits for R.\n- Implement occurrence-weighted climate/soil summaries and integrate as exogenous covariates; evaluate gains via CV and updated m-sep.\n- Tune per-group copula shrinkage (sensitivity to K); explore additional groupings only where diagnostics support distinct σ/ρ.\n- Schedule a global fit checkpoint after predictor integration to lock in final structure and document fit.\n
Sincerely,\n
Jared Quek\nHead of AI, Singapore Sports School\nFounder, Olier AI\n"""
    letter = to_ascii_safe(letter)
    lines = wrap_paragraphs(letter)
    pages = paginate(lines)
    pdf = build_pdf(pages)
    with open(out_path, 'wb') as f:
        f.write(pdf)

if __name__ == '__main__':
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else 'results/Shipley_Brief.pdf'
    main(out)
