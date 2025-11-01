#!/usr/bin/env python3
"""
Convert all PDF files under the current directory to text files using PyMuPDF (fitz).

For each PDF found, a sibling subfolder named "txt" is created in the same directory
and a .txt file with the same base name is written there.

Example:
  Papers/Shipley_et_al-2017-Journal_of_Vegetation_Science.pdf ->
  Papers/txt/Shipley_et_al-2017-Journal_of_Vegetation_Science.txt

Usage:
  python scripts/convert_pdfs_to_txt.py [--root PATH]

Dependencies:
  pip install pymupdf
"""

import argparse
import os
import sys
from typing import List, Tuple

try:
    import fitz  # PyMuPDF
except Exception as e:  # pragma: no cover
    print("Error: PyMuPDF (fitz) is not installed. Install with: pip install pymupdf", file=sys.stderr)
    raise


def find_pdfs(root: str) -> List[str]:
    pdfs: List[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Skip any existing 'txt' subfolders to avoid scanning outputs
        dirnames[:] = [d for d in dirnames if d.lower() != "txt"]
        for name in filenames:
            if name.lower().endswith(".pdf"):
                pdfs.append(os.path.join(dirpath, name))
    return sorted(pdfs)


def pdf_to_txt_path(pdf_path: str) -> str:
    directory, filename = os.path.split(pdf_path)
    base, _ = os.path.splitext(filename)
    out_dir = os.path.join(directory, "txt")
    os.makedirs(out_dir, exist_ok=True)
    return os.path.join(out_dir, base + ".txt")


def extract_text_with_fitz(pdf_path: str) -> str:
    text_parts: List[str] = []
    with fitz.open(pdf_path) as doc:
        for page in doc:
            # "text" gives a layout-preserving text representation in reading order
            page_text = page.get_text("text")
            if not page_text:
                # Fallback to a simpler text extraction if needed
                page_text = page.get_text()
            text_parts.append(page_text)
    return "\n".join(text_parts)


def convert_pdf(pdf_path: str) -> Tuple[str, bool, str]:
    out_path = pdf_to_txt_path(pdf_path)
    try:
        text = extract_text_with_fitz(pdf_path)
        with open(out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        return out_path, True, ""
    except Exception as e:  # pragma: no cover
        return out_path, False, str(e)


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert PDFs to TXT using PyMuPDF (fitz)")
    parser.add_argument("--root", default=".", help="Root directory to scan (default: current directory)")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    pdfs = find_pdfs(root)

    if not pdfs:
        print(f"No PDFs found under: {root}")
        return 0

    print(f"Found {len(pdfs)} PDF(s). Converting to txt subfolders...\n")

    ok = 0
    failed = 0
    for i, pdf in enumerate(pdfs, 1):
        rel_pdf = os.path.relpath(pdf, root)
        out_path, success, err = convert_pdf(pdf)
        rel_out = os.path.relpath(out_path, root)
        if success:
            ok += 1
            print(f"[{i}/{len(pdfs)}] ✓ {rel_pdf} -> {rel_out}")
        else:
            failed += 1
            print(f"[{i}/{len(pdfs)}] ✗ {rel_pdf} FAILED: {err}", file=sys.stderr)

    print("\nSummary:")
    print(f"  Succeeded: {ok}")
    print(f"  Failed:    {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

