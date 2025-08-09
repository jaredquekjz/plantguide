#!/usr/bin/env python3
"""
Batch convert all PDFs in Papers folder to Mathpix Markdown
"""

import os
import json
import time
import requests
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

APP_KEY = os.getenv('MATHPIX_APP_KEY')
BASE_URL = "https://api.mathpix.com/v3"

def process_pdf(file_path, output_dir):
    """Upload PDF and get MMD output"""
    
    pdf_name = Path(file_path).name
    output_file = output_dir / (Path(file_path).stem + ".mmd")
    
    # Skip if already processed
    if output_file.exists():
        print(f"  ✓ Already exists: {output_file.name}")
        return "skipped"
    
    # Upload PDF
    print(f"  📤 Uploading...")
    try:
        with open(file_path, 'rb') as f:
            response = requests.post(
                f"{BASE_URL}/pdf",
                headers={"app_key": APP_KEY},
                data={"options_json": json.dumps({
                    # MMD is the default output, no need to specify
                    "math_inline_delimiters": ["$", "$"],
                    "rm_spaces": True
                })},
                files={"file": f}
            )
        
        if response.status_code != 200:
            print(f"  ❌ Upload failed: Status {response.status_code}")
            print(f"      Response: {response.text}")
            return "failed"
        
        result_json = response.json()
        if 'pdf_id' not in result_json:
            print(f"  ❌ No pdf_id in response: {result_json}")
            return "failed"
        
        pdf_id = result_json['pdf_id']
        print(f"  🔄 Processing (ID: {pdf_id})...")
        
        # Wait for processing with timeout
        start_time = time.time()
        max_wait = 600  # 10 minutes max
        
        while time.time() - start_time < max_wait:
            status_response = requests.get(
                f"{BASE_URL}/pdf/{pdf_id}",
                headers={"app_key": APP_KEY}
            )
            
            if status_response.status_code != 200:
                print(f"  ⚠️  Status check failed")
                time.sleep(5)
                continue
            
            status = status_response.json()
            if status['status'] == 'completed':
                print(f"  ✅ Processing complete!")
                break
            elif status['status'] == 'error':
                print(f"  ❌ Processing error")
                return "error"
            
            percent = status.get('percent_done', 0)
            pages_done = status.get('num_pages_completed', 0)
            total_pages = status.get('num_pages', '?')
            print(f"    {percent:.1f}% - Pages: {pages_done}/{total_pages}")
            time.sleep(5)
        else:
            print(f"  ⏱️  Timeout after {max_wait} seconds")
            return "timeout"
        
        # Get MMD result
        print(f"  💾 Downloading MMD...")
        mmd_response = requests.get(
            f"{BASE_URL}/pdf/{pdf_id}.mmd",
            headers={"app_key": APP_KEY}
        )
        
        if mmd_response.status_code == 200:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(mmd_response.text)
            print(f"  ✨ Saved: {output_file.name}")
            return "success"
        else:
            print(f"  ❌ Failed to download MMD")
            return "download_failed"
            
    except Exception as e:
        print(f"  ❌ Error: {str(e)}")
        return "exception"


def main():
    papers_dir = Path("Papers")
    output_dir = papers_dir / "mmd"
    output_dir.mkdir(exist_ok=True)
    
    # Get all PDFs
    pdf_files = sorted(papers_dir.glob("*.pdf"))
    
    print(f"🔮 Found {len(pdf_files)} PDFs to convert")
    print(f"📁 Output directory: {output_dir}\n")
    
    results = {
        "success": [],
        "failed": [],
        "skipped": [],
        "error": [],
        "timeout": [],
        "exception": [],
        "download_failed": []
    }
    
    for i, pdf_file in enumerate(pdf_files, 1):
        print(f"[{i}/{len(pdf_files)}] {pdf_file.name}")
        result = process_pdf(pdf_file, output_dir)
        results[result].append(pdf_file.name)
        
        # Small delay between requests to be nice to the API
        if result not in ["skipped", "failed"]:
            time.sleep(2)
        print()
    
    # Summary
    print("\n" + "="*60)
    print("📊 CONVERSION SUMMARY")
    print("="*60)
    print(f"✅ Success: {len(results['success'])}")
    print(f"⏭️  Skipped (already exists): {len(results['skipped'])}")
    print(f"❌ Failed: {len(results['failed'])}")
    print(f"⚠️  Errors: {len(results['error'])}")
    print(f"⏱️  Timeouts: {len(results['timeout'])}")
    print(f"🐛 Exceptions: {len(results['exception'])}")
    print(f"📥 Download failures: {len(results['download_failed'])}")
    
    if results['failed'] or results['error'] or results['timeout']:
        print("\n❌ Failed conversions:")
        for category in ['failed', 'error', 'timeout', 'exception', 'download_failed']:
            if results[category]:
                print(f"\n{category.upper()}:")
                for file in results[category]:
                    print(f"  - {file}")
    
    print(f"\n✨ All done! Check {output_dir} for your MMD files")


if __name__ == "__main__":
    main()