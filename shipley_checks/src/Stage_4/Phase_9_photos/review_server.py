#!/usr/bin/env python3
"""
Simple Flask server for photo review flag storage.
Stores flags in a JSON file on the server.

Usage: python3 review_server.py
Runs on port 5050
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import json
from pathlib import Path
from datetime import datetime

app = Flask(__name__)
CORS(app)

FLAGS_FILE = Path('/opt/photo-review/flags.json')

def load_flags():
    if FLAGS_FILE.exists():
        with open(FLAGS_FILE) as f:
            data = json.load(f)
            # Ensure fields exist for backwards compat
            if 'needsPhotos' not in data:
                data['needsPhotos'] = []
            if 'crowns' not in data:
                data['crowns'] = {}
            return data
    return {'flags': {}, 'reviewed': [], 'needsPhotos': [], 'crowns': {}, 'updated_at': None}

def save_flags(data):
    data['updated_at'] = datetime.now().isoformat()
    with open(FLAGS_FILE, 'w') as f:
        json.dump(data, f, indent=2)

@app.route('/api/flags', methods=['GET'])
def get_flags():
    """Get all flags."""
    return jsonify(load_flags())

@app.route('/api/flags', methods=['POST'])
def update_flags():
    """Update flags from client."""
    data = request.json
    current = load_flags()

    # Merge flags
    if 'flags' in data:
        current['flags'] = data['flags']
    if 'reviewed' in data:
        current['reviewed'] = data['reviewed']
    if 'needsPhotos' in data:
        current['needsPhotos'] = data['needsPhotos']
    if 'crowns' in data:
        current['crowns'] = data['crowns']

    save_flags(current)
    return jsonify({
        'status': 'ok',
        'total_flagged': sum(len(v) for v in current['flags'].values()),
        'needs_photos': len(current['needsPhotos']),
        'crowns': len(current['crowns'])
    })

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get review statistics."""
    data = load_flags()
    total_flagged = sum(len(v) for v in data['flags'].values())
    return jsonify({
        'total_reviewed': len(data['reviewed']),
        'total_flagged': total_flagged,
        'species_with_flags': len(data['flags']),
        'updated_at': data.get('updated_at')
    })

if __name__ == '__main__':
    FLAGS_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not FLAGS_FILE.exists():
        save_flags({'flags': {}, 'reviewed': []})
    app.run(host='127.0.0.1', port=5050, debug=False)
