#!/usr/bin/env python3
"""Convert PDF to MMD using Mathpix API"""

import os
import json
import time
import requests
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

APP_KEY = os.getenv('MATHPIX_APP_KEY')
BASE_URL = "https://api.mathpix.com/v3"

def convert_pdf_to_mmd(pdf_path, output_path=None):
    """Convert PDF to MMD format using Mathpix API"""
    
    if not APP_KEY:
        print("Error: MATHPIX_APP_KEY not found in environment")
        return None
    
    # Upload PDF
    print(f"Uploading {pdf_path}...")
    options = {
        "math_inline_delimiters": ["$", "$"],
        "rm_spaces": True
    }
    
    with open(pdf_path, 'rb') as f:
        response = requests.post(
            f"{BASE_URL}/pdf",
            headers={"app_key": APP_KEY},
            data={"options_json": json.dumps(options)},
            files={"file": f}
        )
    
    if response.status_code != 200:
        print(f"Upload failed: {response.text}")
        return None
    
    pdf_id = response.json().get('pdf_id')
    if not pdf_id:
        print(f"No PDF ID in response: {response.text}")
        return None
    
    print(f"PDF ID: {pdf_id}")
    
    # Wait for processing
    print("Processing", end="")
    max_wait = 300  # 5 minutes max
    waited = 0
    
    while waited < max_wait:
        status_response = requests.get(
            f"{BASE_URL}/pdf/{pdf_id}",
            headers={"app_key": APP_KEY}
        )
        
        if status_response.status_code != 200:
            print(f"\nStatus check failed: {status_response.text}")
            return None
        
        status_data = status_response.json()
        status = status_data.get('status')
        percent = status_data.get('percent_done', 0)
        
        if status == 'completed':
            print(" Done!")
            break
        elif status == 'error':
            print(f"\nProcessing error: {status_data}")
            return None
        else:
            print(f"\rProcessing... {percent:.1f}%", end="")
            time.sleep(3)
            waited += 3
    
    if waited >= max_wait:
        print("\nTimeout waiting for processing")
        return None
    
    # Get MMD result
    print("Downloading MMD...")
    mmd_response = requests.get(
        f"{BASE_URL}/pdf/{pdf_id}.mmd",
        headers={"app_key": APP_KEY}
    )
    
    if mmd_response.status_code != 200:
        print(f"Failed to get MMD: {mmd_response.text}")
        return None
    
    # Save to file
    if output_path is None:
        # Default: same directory, .mmd extension
        output_path = Path(pdf_path).with_suffix('.mmd')
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(mmd_response.text)
    
    print(f"Saved to: {output_path}")
    return output_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python convert_to_mmd.py <pdf_file> [output_file]")
        sys.exit(1)
    
    pdf_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    convert_pdf_to_mmd(pdf_file, output_file)