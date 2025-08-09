#!/usr/bin/env python3
"""
Convert medfatebook.pdf to Mathpix Markdown
"""

import os
import json
import time
import requests
from pathlib import Path

# Load API key from .env file
def load_api_key():
    env_file = Path("/home/olier/ellenberg/.env")
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                if line.startswith('MATHPIX_APP_KEY='):
                    return line.split('=', 1)[1].strip()
    return os.getenv('MATHPIX_APP_KEY')

APP_KEY = load_api_key()
BASE_URL = "https://api.mathpix.com/v3"

def convert_medfatebook():
    """Convert medfatebook.pdf to MMD"""
    
    pdf_path = Path("/home/olier/ellenberg/papers/medfatebook.pdf")
    output_dir = Path("/home/olier/ellenberg/papers/mmd")
    output_dir.mkdir(exist_ok=True)
    output_file = output_dir / "medfatebook.mmd"
    
    # Check if already exists
    if output_file.exists():
        print(f"✓ Already exists: {output_file}")
        print("Delete it first if you want to reconvert.")
        return
    
    if not APP_KEY:
        print("❌ MATHPIX_APP_KEY not found in environment")
        print("Please set it in .env file or export it")
        return
    
    print(f"📚 Converting medfatebook.pdf")
    print(f"   Size: {pdf_path.stat().st_size / 1024 / 1024:.1f} MB")
    
    # Upload PDF
    print("📤 Uploading to Mathpix...")
    try:
        with open(pdf_path, 'rb') as f:
            response = requests.post(
                f"{BASE_URL}/pdf",
                headers={"app_key": APP_KEY},
                data={"options_json": json.dumps({
                    "math_inline_delimiters": ["$", "$"],
                    "rm_spaces": True,
                    "enable_tables_fallback": True  # Better table extraction
                })},
                files={"file": f}
            )
        
        if response.status_code != 200:
            print(f"❌ Upload failed: Status {response.status_code}")
            print(f"   Response: {response.text}")
            return
        
        result_json = response.json()
        if 'pdf_id' not in result_json:
            print(f"❌ No pdf_id in response: {result_json}")
            return
        
        pdf_id = result_json['pdf_id']
        print(f"🔄 Processing (ID: {pdf_id})...")
        
        # Wait for processing
        start_time = time.time()
        max_wait = 900  # 15 minutes for large book
        
        while time.time() - start_time < max_wait:
            status_response = requests.get(
                f"{BASE_URL}/pdf/{pdf_id}",
                headers={"app_key": APP_KEY}
            )
            
            if status_response.status_code != 200:
                print("⚠️  Status check failed, retrying...")
                time.sleep(10)
                continue
            
            status = status_response.json()
            if status['status'] == 'completed':
                print("✅ Processing complete!")
                break
            elif status['status'] == 'error':
                print(f"❌ Processing error: {status.get('error', 'Unknown')}")
                return
            
            percent = status.get('percent_done', 0)
            pages_done = status.get('num_pages_completed', 0)
            total_pages = status.get('num_pages', '?')
            elapsed = time.time() - start_time
            print(f"   {percent:.1f}% - Pages: {pages_done}/{total_pages} - Time: {elapsed:.0f}s")
            time.sleep(10)  # Check every 10 seconds
        else:
            print(f"⏱️  Timeout after {max_wait} seconds")
            print(f"   PDF ID: {pdf_id} - Check manually later")
            return
        
        # Download MMD result
        print("💾 Downloading MMD...")
        mmd_response = requests.get(
            f"{BASE_URL}/pdf/{pdf_id}.mmd",
            headers={"app_key": APP_KEY}
        )
        
        if mmd_response.status_code == 200:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(mmd_response.text)
            print(f"✨ Saved: {output_file}")
            print(f"   Size: {len(mmd_response.text) / 1024:.1f} KB")
            
            # Quick stats
            content = mmd_response.text
            equations = content.count('$$')
            tables = content.count('\\begin{tabular}')
            print(f"📊 Content: ~{equations} equations, ~{tables} tables")
        else:
            print(f"❌ Download failed: {mmd_response.status_code}")
            
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    convert_medfatebook()