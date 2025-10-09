#!/usr/bin/env python3
"""Upload the 10 Stage 7 trial profiles (with reliability) to Firestore."""

from pathlib import Path
import json

import firebase_admin
from firebase_admin import credentials, firestore

from upload_encyclopedia_to_firestore import flatten_profile


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
    'achillea-millefolium',
]


def initialize_firebase() -> None:
    """Initialise Firebase Admin SDK."""
    service_account_path = Path("/home/olier/olier-farm/backend/serviceAccountKey.json")

    if not service_account_path.exists():
        raise SystemExit(f"❌ Service account key not found at {service_account_path}")

    cred = credentials.Certificate(str(service_account_path))
    try:
        firebase_admin.initialize_app(cred)
        print("✓ Firebase Admin initialised")
    except Exception as exc:
        raise SystemExit(f"❌ Firebase initialization error: {exc}")


def upload_test_profiles() -> None:
    """Upload the predefined trial profiles."""
    db = firestore.client()
    collection_ref = db.collection('encyclopedia_ellenberg')
    profiles_dir = Path("/home/olier/ellenberg/data/encyclopedia_profiles")

    print(f"\nUploading {len(TEST_PROFILES)} test profiles...")

    for index, slug in enumerate(TEST_PROFILES, start=1):
        profile_path = profiles_dir / f"{slug}.json"
        try:
            with open(profile_path, "r", encoding="utf-8") as handle:
                profile = json.load(handle)
            flattened = flatten_profile(profile)
            collection_ref.document(slug).set(flattened)
            print(f"  {index}. ✓ {slug}")
        except Exception as exc:
            print(f"  {index}. ✗ {slug}: {exc}")

    print("\n✓ Test upload complete!")
    print("  Collection: encyclopedia_ellenberg")
    print(f"  Profiles: {len(TEST_PROFILES)}")


def main() -> None:
    print("=" * 60)
    print("Upload Test Profiles (10 with reliability data)")
    print("=" * 60)
    initialize_firebase()
    upload_test_profiles()


if __name__ == "__main__":
    main()
