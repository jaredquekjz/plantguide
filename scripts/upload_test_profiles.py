#!/usr/bin/env python3
"""Upload only the 10 test profiles with reliability data to Firestore."""

import json
import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path
import sys

# Import flatten_profile from main upload script
sys.path.insert(0, str(Path(__file__).parent))
from upload_encyclopedia_to_firestore import flatten_profile

# Profiles with reliability data
TEST_PROFILES = [
    'abies-alba',
    'abies-grandis',
    'abies-lasiocarpa',
    'abutilon-theophrasti',
    'acacia-mearnsii',
    'acer-campestre',
    'acer-rubrum',
    'acer-saccharinum',
    'acer-saccharum',
    'achillea-millefolium'
]

def initialize_firebase():
    """Initialize Firebase Admin SDK."""
    service_account_path = Path("/home/olier/olier-farm/backend/serviceAccountKey.json")

    if not service_account_path.exists():
        print(f"❌ Service account key not found at {service_account_path}")
        sys.exit(1)

    try:
        cred = credentials.Certificate(str(service_account_path))
        firebase_admin.initialize_app(cred)
        print(f"✓ Firebase Admin initialized")
    except Exception as e:
        print(f"❌ Firebase initialization error: {e}")
        sys.exit(1)

def upload_test_profiles():
    """Upload 10 test profiles to Firestore."""
    db = firestore.client()
    collection_ref = db.collection('encyclopedia_ellenberg')

    profiles_dir = Path("/home/olier/ellenberg/data/encyclopedia_profiles")

    print(f"\nUploading {len(TEST_PROFILES)} test profiles...")

    for i, slug in enumerate(TEST_PROFILES, 1):
        profile_path = profiles_dir / f"{slug}.json"

        try:
            with open(profile_path) as f:
                profile = json.load(f)

            # Flatten profile for frontend compatibility
            flattened = flatten_profile(profile)

            # Upload flattened profile
            doc_ref = collection_ref.document(slug)
            doc_ref.set(flattened)

            print(f"  {i}. ✓ {slug}")

        except Exception as e:
            print(f"  {i}. ❌ {slug}: {e}")

    print(f"\n✓ Test upload complete!")
    print(f"  Collection: 'encyclopedia_ellenberg'")
    print(f"  Profiles: {len(TEST_PROFILES)} with reliability data")

def main():
    print("="*60)
    print("Upload Test Profiles (10 with reliability data)")
    print("="*60)

    initialize_firebase()
    upload_test_profiles()

if __name__ == "__main__":
    main()
