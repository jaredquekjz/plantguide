#!/usr/bin/env python3
import sys, argparse, pathlib

def main():
    ap = argparse.ArgumentParser(description="Extract text from PDF using PyMuPDF (fitz)")
    ap.add_argument('--in', dest='in_pdf', required=True, help='Input PDF path')
    ap.add_argument('--out', dest='out_txt', required=True, help='Output text path')
    args = ap.parse_args()

    in_path = pathlib.Path(args.in_pdf)
    out_path = pathlib.Path(args.out_txt)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        import fitz  # PyMuPDF
    except Exception as e:
        print('ERROR: PyMuPDF (fitz) is not available:', e, file=sys.stderr)
        sys.exit(2)

    if not in_path.exists():
        print(f'ERROR: input PDF not found: {in_path}', file=sys.stderr)
        sys.exit(1)

    doc = fitz.open(in_path)
    with out_path.open('w', encoding='utf-8') as f:
        for page in doc:
            text = page.get_text("text")
            f.write(text)
            f.write("\n")
    print(f'Wrote: {out_path}')

if __name__ == '__main__':
    main()

