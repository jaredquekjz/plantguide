#!/usr/bin/env python3
"""Check if test profile slugs conflict with existing encyclopedia collection."""

import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path
import sys

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

def check_conflicts():
    """Check for slug conflicts in encyclopedia collection."""
    db = firestore.client()
    collection_ref = db.collection('encyclopedia')

    print(f"\nChecking {len(TEST_PROFILES)} test profile slugs against 'encyclopedia' collection...\n")

    conflicts = []
    for slug in TEST_PROFILES:
        doc_ref = collection_ref.document(slug)
        doc = doc_ref.get()

        if doc.exists:
            data = doc.to_dict()
            common_name = data.get('common_name_primary', 'Unknown')
            species = data.get('species', slug)
            conflicts.append({
                'slug': slug,
                'species': species,
                'common_name': common_name
            })
            print(f"  ⚠️  CONFLICT: {slug}")
            print(f"      Existing: {species} ({common_name})")
        else:
            print(f"  ✓ {slug} - No conflict")

    print(f"\n{'='*60}")
    if conflicts:
        print(f"❌ Found {len(conflicts)} conflicts!")
        print(f"\nConflicting slugs:")
        for c in conflicts:
            print(f"  - {c['slug']}: {c['species']}")
        print(f"\n⚠️  WARNING: Uploading will overwrite these existing profiles!")
    else:
        print(f"✓ No conflicts found - safe to upload to 'encyclopedia' collection")
    print(f"{'='*60}\n")

def main():
    print("="*60)
    print("Check Slug Conflicts in Encyclopedia Collection")
    print("="*60)

    initialize_firebase()
    check_conflicts()

if __name__ == "__main__":
    main()
