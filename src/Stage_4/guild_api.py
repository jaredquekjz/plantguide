#!/usr/bin/env python3
"""
Guild Builder API - Frontend Endpoint

Simple Flask API for guild scoring and explanations.
Ready to deploy to Google Cloud Run.

Endpoints:
- POST /api/score-guild  - Score a guild and return explanation
- GET /api/plants        - Search/autocomplete plants
- GET /api/plant/{id}    - Get plant details

Usage (local testing):
    python src/Stage_4/guild_api.py

    # Test endpoint
    curl -X POST http://localhost:8080/api/score-guild \
      -H "Content-Type: application/json" \
      -d '{"plant_ids": ["wfo-001", "wfo-002", ...]}'

Deployment to Cloud Run:
    gcloud run deploy guild-builder-api \
      --source . \
      --region us-central1 \
      --allow-unauthenticated
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
from guild_scorer_v2 import GuildScorer
from explanation_engine import generate_explanation
import duckdb
from pathlib import Path

app = Flask(__name__)
CORS(app)  # Enable CORS for frontend

# Initialize scorer (shared instance)
scorer = GuildScorer()

# Database connection for plant search
con = duckdb.connect()
PLANTS_PATH = Path('model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet')


# ============================================
# MAIN ENDPOINT: Score Guild
# ============================================

@app.route('/api/score-guild', methods=['POST'])
def score_guild():
    """
    Score a guild of plants and return user-friendly explanation.

    Request body:
    {
        "plant_ids": ["wfo-001", "wfo-002", ..., "wfo-010"]
    }

    Response:
    {
        "success": true,
        "score": 0.75,
        "explanation": {
            "overall": {...},
            "climate": {...},
            "risks": [...],
            "benefits": [...],
            "products": [...]
        },
        "plant_names": ["Quercus robur", ...]
    }
    """
    try:
        data = request.get_json()

        if not data or 'plant_ids' not in data:
            return jsonify({
                'success': False,
                'error': 'Missing plant_ids in request body'
            }), 400

        plant_ids = data['plant_ids']

        if not isinstance(plant_ids, list):
            return jsonify({
                'success': False,
                'error': 'plant_ids must be an array'
            }), 400

        if len(plant_ids) < 2:
            return jsonify({
                'success': False,
                'error': 'Need at least 2 plants'
            }), 400

        if len(plant_ids) > 20:
            return jsonify({
                'success': False,
                'error': 'Maximum 20 plants per guild'
            }), 400

        # Score guild
        guild_result = scorer.score_guild(plant_ids)

        # Generate explanation
        explanation = generate_explanation(guild_result)

        # Return response
        return jsonify({
            'success': True,
            'score': guild_result.get('guild_score', -1.0),
            'veto': guild_result.get('veto', False),
            'explanation': explanation,
            'plant_names': guild_result.get('plant_names', []),
            'n_plants': len(plant_ids)
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# PLANT SEARCH/AUTOCOMPLETE
# ============================================

@app.route('/api/plants/search', methods=['GET'])
def search_plants():
    """
    Search plants by name (autocomplete).

    Query params:
    - q: search query (min 3 chars)
    - limit: max results (default 20)

    Response:
    {
        "success": true,
        "results": [
            {
                "wfo_id": "wfo-001",
                "scientific_name": "Quercus robur",
                "common_name": "English Oak",
                "family": "Fagaceae"
            },
            ...
        ]
    }
    """
    try:
        query = request.args.get('q', '').strip()
        limit = int(request.args.get('limit', 20))

        if len(query) < 3:
            return jsonify({
                'success': False,
                'error': 'Search query must be at least 3 characters'
            }), 400

        # Search by scientific name or common name
        results = con.execute(f"""
            SELECT
                wfo_taxon_id as wfo_id,
                wfo_scientific_name as scientific_name,
                wfo_family as family,
                genus
            FROM read_parquet('{PLANTS_PATH}')
            WHERE LOWER(wfo_scientific_name) LIKE LOWER('%{query}%')
               OR LOWER(genus) LIKE LOWER('%{query}%')
            ORDER BY wfo_scientific_name
            LIMIT {limit}
        """).fetchdf()

        plants = results.to_dict('records')

        return jsonify({
            'success': True,
            'results': plants,
            'count': len(plants)
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# GET PLANT DETAILS
# ============================================

@app.route('/api/plants/<wfo_id>', methods=['GET'])
def get_plant_details(wfo_id):
    """
    Get detailed information about a specific plant.

    Response:
    {
        "success": true,
        "plant": {
            "wfo_id": "wfo-001",
            "scientific_name": "Quercus robur",
            "family": "Fagaceae",
            "genus": "Quercus",
            "climate": {...},
            "csr": {...},
            ...
        }
    }
    """
    try:
        result = con.execute(f"""
            SELECT
                wfo_taxon_id as wfo_id,
                wfo_scientific_name as scientific_name,
                wfo_family as family,
                genus,
                "wc2.1_30s_bio_1_q05" as temp_min,
                "wc2.1_30s_bio_1_q95" as temp_max,
                "wc2.1_30s_bio_6_q05" as winter_min,
                "wc2.1_30s_bio_6_q95" as winter_max,
                drought_sensitivity,
                frost_sensitivity,
                heat_sensitivity,
                CSR_C,
                CSR_S,
                CSR_R,
                EIVEres_L as eive_light,
                height_max,
                life_form
            FROM read_parquet('{PLANTS_PATH}')
            WHERE wfo_taxon_id = '{wfo_id}'
        """).fetchdf()

        if len(result) == 0:
            return jsonify({
                'success': False,
                'error': f'Plant not found: {wfo_id}'
            }), 404

        plant = result.iloc[0].to_dict()

        return jsonify({
            'success': True,
            'plant': plant
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================
# HEALTH CHECK
# ============================================

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Cloud Run."""
    return jsonify({
        'status': 'healthy',
        'service': 'guild-builder-api',
        'version': '2.0'
    })


@app.route('/', methods=['GET'])
def index():
    """API documentation."""
    return jsonify({
        'service': 'Guild Builder API',
        'version': '2.0',
        'endpoints': {
            'POST /api/score-guild': 'Score a guild and get explanation',
            'GET /api/plants/search?q=...': 'Search plants (autocomplete)',
            'GET /api/plants/{wfo_id}': 'Get plant details',
            'GET /health': 'Health check'
        },
        'documentation': 'https://docs.example.com/guild-builder-api'
    })


# ============================================
# RUN SERVER
# ============================================

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    debug = os.environ.get('DEBUG', 'false').lower() == 'true'

    print(f"Starting Guild Builder API on port {port}")
    print(f"Debug mode: {debug}")
    print()
    print("Endpoints:")
    print("  POST http://localhost:{}/api/score-guild".format(port))
    print("  GET  http://localhost:{}/api/plants/search?q=oak".format(port))
    print("  GET  http://localhost:{}/api/plants/wfo-0000292049".format(port))
    print()

    app.run(host='0.0.0.0', port=port, debug=debug)
