#!/usr/bin/env python3
"""
Simple Mathpix PDF to MMD converter
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

def process_pdf(file_path):
    """Upload PDF and get MMD output"""
    
    # Upload PDF
    print(f"Uploading {file_path}...")
    with open(file_path, 'rb') as f:
        response = requests.post(
            f"{BASE_URL}/pdf",
            headers={"app_key": APP_KEY},
            data={"options_json": json.dumps({"conversion_formats": {"mmd": True}})},
            files={"file": f}
        )
    
    if response.status_code != 200:
        print(f"Upload failed: {response.text}")
        return None
    
    pdf_id = response.json()['pdf_id']
    print(f"PDF ID: {pdf_id}")
    
    # Wait for processing
    print("Processing...")
    while True:
        status_response = requests.get(
            f"{BASE_URL}/pdf/{pdf_id}",
            headers={"app_key": APP_KEY}
        )
        
        status = status_response.json()
        if status['status'] == 'completed':
            print("Done!")
            break
        elif status['status'] == 'error':
            print("Processing error")
            return None
        
        percent = status.get('percent_done', 0)
        print(f"  {percent:.1f}% complete")
        time.sleep(3)
    
    # Get MMD result
    mmd_response = requests.get(
        f"{BASE_URL}/pdf/{pdf_id}.mmd",
        headers={"app_key": APP_KEY}
    )
    
    if mmd_response.status_code == 200:
        output_file = Path(file_path).stem + ".mmd"
        with open(output_file, 'w') as f:
            f.write(mmd_response.text)
        print(f"Saved to: {output_file}")
        return output_file
    else:
        print("Failed to get MMD")
        return None


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python mathpix_to_mmd.py <pdf_file>")
        sys.exit(1)
    
    process_pdf(sys.argv[1])