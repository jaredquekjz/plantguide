#!/usr/bin/env python3
"""Test Mathpix API"""

import os
import json
import requests
from dotenv import load_dotenv

load_dotenv()

APP_KEY = os.getenv('MATHPIX_APP_KEY')
print(f"APP_KEY loaded: {APP_KEY[:10]}..." if APP_KEY else "No APP_KEY!")

# Test with the first PDF
pdf_file = "Papers/44177_2023_Article_48.pdf"

options = {
    # Don't specify conversion_formats - MMD is default
    "math_inline_delimiters": ["$", "$"],
    "rm_spaces": True
}

print(f"\nTesting with: {pdf_file}")
print("Sending request...")

with open(pdf_file, 'rb') as f:
    response = requests.post(
        "https://api.mathpix.com/v3/pdf",
        headers={"app_key": APP_KEY},
        data={"options_json": json.dumps(options)},
        files={"file": f}
    )

print(f"Status Code: {response.status_code}")
print(f"Response Headers: {dict(response.headers)}")
print(f"Response Text: {response.text}")

if response.status_code == 200:
    result = response.json()
    print(f"Success! PDF ID: {result.get('pdf_id')}")
else:
    print("Failed!")