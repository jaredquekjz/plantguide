/**
 * Guild Builder Frontend Example (React)
 *
 * This demonstrates how to integrate the Guild Builder API
 * with a modern React frontend.
 *
 * Key Features:
 * - Plant search/autocomplete
 * - Guild composition (drag & drop)
 * - Real-time guild scoring
 * - User-friendly explanations
 * - Product recommendations (conversion driver!)
 *
 * Stack:
 * - React 18+
 * - Fetch API (or axios)
 * - Tailwind CSS (styling)
 */

import React, { useState, useEffect } from 'react';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080';

// ============================================
// MAIN COMPONENT
// ============================================

export default function GuildBuilder() {
  const [selectedPlants, setSelectedPlants] = useState([]);
  const [guildResult, setGuildResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // Auto-score when guild changes (with debounce)
  useEffect(() => {
    if (selectedPlants.length < 2) {
      setGuildResult(null);
      return;
    }

    const timer = setTimeout(() => {
      scoreGuild();
    }, 500);  // Debounce 500ms

    return () => clearTimeout(timer);
  }, [selectedPlants]);

  async function scoreGuild() {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`${API_BASE}/api/score-guild`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          plant_ids: selectedPlants.map(p => p.wfo_id)
        })
      });

      const data = await response.json();

      if (!data.success) {
        throw new Error(data.error);
      }

      setGuildResult(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  function addPlant(plant) {
    if (selectedPlants.length >= 10) {
      alert('Maximum 10 plants per guild');
      return;
    }

    if (selectedPlants.find(p => p.wfo_id === plant.wfo_id)) {
      return;  // Already added
    }

    setSelectedPlants([...selectedPlants, plant]);
  }

  function removePlant(wfoId) {
    setSelectedPlants(selectedPlants.filter(p => p.wfo_id !== wfoId));
  }

  return (
    <div className="guild-builder max-w-7xl mx-auto p-6">
      <h1 className="text-4xl font-bold mb-8">🌱 Guild Builder</h1>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* LEFT: Plant Selection */}
        <div>
          <PlantSearch onSelectPlant={addPlant} />

          <div className="mt-6">
            <h2 className="text-2xl font-semibold mb-4">
              Your Guild ({selectedPlants.length}/10)
            </h2>

            {selectedPlants.length === 0 && (
              <p className="text-gray-500 italic">
                Search and add plants to start building your guild
              </p>
            )}

            <div className="space-y-2">
              {selectedPlants.map(plant => (
                <PlantCard
                  key={plant.wfo_id}
                  plant={plant}
                  onRemove={() => removePlant(plant.wfo_id)}
                />
              ))}
            </div>
          </div>
        </div>

        {/* RIGHT: Guild Score & Explanation */}
        <div>
          {loading && (
            <div className="text-center py-12">
              <div className="spinner"></div>
              <p className="mt-4 text-gray-600">Analyzing guild...</p>
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <p className="text-red-800">Error: {error}</p>
            </div>
          )}

          {guildResult && !loading && (
            <GuildExplanation result={guildResult} />
          )}

          {!guildResult && !loading && !error && selectedPlants.length >= 2 && (
            <div className="text-center py-12 text-gray-500">
              <p>Add more plants to see guild analysis...</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ============================================
// PLANT SEARCH (Autocomplete)
// ============================================

function PlantSearch({ onSelectPlant }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    if (query.length < 3) {
      setResults([]);
      return;
    }

    const timer = setTimeout(() => {
      searchPlants();
    }, 300);  // Debounce 300ms

    return () => clearTimeout(timer);
  }, [query]);

  async function searchPlants() {
    setSearching(true);

    try {
      const response = await fetch(
        `${API_BASE}/api/plants/search?q=${encodeURIComponent(query)}&limit=10`
      );
      const data = await response.json();

      if (data.success) {
        setResults(data.results);
      }
    } catch (err) {
      console.error('Search error:', err);
    } finally {
      setSearching(false);
    }
  }

  return (
    <div className="relative">
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search plants (e.g., oak, tomato, basil)..."
        className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500"
      />

      {searching && (
        <div className="absolute right-3 top-3">
          <div className="spinner-sm"></div>
        </div>
      )}

      {results.length > 0 && (
        <div className="absolute z-10 w-full mt-2 bg-white border border-gray-200 rounded-lg shadow-lg max-h-96 overflow-y-auto">
          {results.map(plant => (
            <button
              key={plant.wfo_id}
              onClick={() => {
                onSelectPlant(plant);
                setQuery('');
                setResults([]);
              }}
              className="w-full px-4 py-3 text-left hover:bg-gray-50 border-b border-gray-100 last:border-0"
            >
              <div className="font-semibold text-gray-900">
                {plant.scientific_name}
              </div>
              <div className="text-sm text-gray-500">
                {plant.family} · {plant.genus}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ============================================
// PLANT CARD
// ============================================

function PlantCard({ plant, onRemove }) {
  return (
    <div className="flex items-center justify-between p-3 bg-white border border-gray-200 rounded-lg hover:shadow-md transition">
      <div>
        <div className="font-semibold text-gray-900">{plant.scientific_name}</div>
        <div className="text-sm text-gray-500">{plant.family}</div>
      </div>
      <button
        onClick={onRemove}
        className="text-red-600 hover:text-red-800 font-bold px-3 py-1"
      >
        ✕
      </button>
    </div>
  );
}

// ============================================
// GUILD EXPLANATION (Main Display)
// ============================================

function GuildExplanation({ result }) {
  const { explanation, score, veto } = result;
  const { overall } = explanation;

  // Handle vetoed guilds
  if (veto) {
    return (
      <div className="bg-red-50 border-2 border-red-200 rounded-lg p-6">
        <div className="text-3xl mb-2">{overall.title}</div>
        <p className="text-lg mb-4">{overall.message}</p>

        <div className="bg-white rounded p-4 mb-4">
          <ul className="space-y-2">
            {overall.details.map((detail, i) => (
              <li key={i} className="text-gray-700">• {detail}</li>
            ))}
          </ul>
        </div>

        <div className="bg-blue-50 border border-blue-200 rounded p-4">
          <div className="font-semibold text-blue-900 mb-1">💡 Recommendation:</div>
          <p className="text-blue-800">{overall.advice}</p>
        </div>
      </div>
    );
  }

  // Successful guild
  return (
    <div className="space-y-6">
      {/* Overall Score */}
      <div className={`border-2 rounded-lg p-6 ${getColorClass(overall.color)}`}>
        <div className="text-4xl mb-2">{overall.emoji} {overall.label}</div>
        <div className="text-2xl mb-2">{overall.stars}</div>
        <p className="text-lg">{overall.message}</p>
        <div className="mt-3 text-3xl font-bold">
          Score: {score.toFixed(2)}
        </div>
      </div>

      {/* Climate */}
      {explanation.climate && (
        <ClimateSection climate={explanation.climate} />
      )}

      {/* Risks */}
      {explanation.risks && explanation.risks.length > 0 && (
        <RisksSection risks={explanation.risks} />
      )}

      {/* Benefits */}
      {explanation.benefits && explanation.benefits.length > 0 && (
        <BenefitsSection benefits={explanation.benefits} />
      )}

      {/* Products (KEY FOR CONVERSION!) */}
      {explanation.products && explanation.products.length > 0 && (
        <ProductsSection products={explanation.products} />
      )}
    </div>
  );
}

// ============================================
// CLIMATE SECTION
// ============================================

function ClimateSection({ climate }) {
  return (
    <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-2">🌡 Climate Compatibility</h3>

      {climate.messages.map((msg, i) => (
        <p key={i} className="text-sm text-gray-700">{msg}</p>
      ))}

      {climate.warnings && climate.warnings.map((warning, i) => (
        <div key={i} className="mt-3 bg-yellow-50 border border-yellow-200 rounded p-3">
          <div className="font-semibold text-yellow-900">{warning.message}</div>
          <p className="text-sm text-yellow-800 mt-1">{warning.detail}</p>
          <p className="text-sm text-yellow-700 mt-2 italic">💡 {warning.advice}</p>
        </div>
      ))}
    </div>
  );
}

// ============================================
// RISKS SECTION
// ============================================

function RisksSection({ risks }) {
  return (
    <div className="bg-orange-50 border border-orange-200 rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-3">⚠ Risks & Vulnerabilities</h3>

      {risks.map((risk, i) => (
        <div key={i} className="mb-4 last:mb-0">
          <div className="font-semibold text-gray-900">
            {risk.icon} {risk.title}
          </div>
          <p className="text-sm text-gray-700 mt-1">{risk.message}</p>
          <p className="text-sm text-gray-600 mt-1">{risk.detail}</p>

          {risk.evidence && risk.evidence.length > 0 && (
            <div className="mt-2 text-sm text-gray-600">
              <strong>Examples:</strong> {risk.evidence.join(', ')}
            </div>
          )}

          {risk.advice && (
            <div className="mt-2 text-sm text-blue-700 italic">
              💡 {risk.advice}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

// ============================================
// BENEFITS SECTION
// ============================================

function BenefitsSection({ benefits }) {
  return (
    <div className="bg-green-50 border border-green-200 rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-3">✓ Beneficial Interactions</h3>

      {benefits.map((benefit, i) => (
        <div key={i} className="mb-3 last:mb-0">
          <div className="font-semibold text-gray-900">
            {benefit.icon} {benefit.title}
          </div>
          <p className="text-sm text-gray-700 mt-1">{benefit.message}</p>
          <p className="text-sm text-gray-600 mt-1">{benefit.detail}</p>
        </div>
      ))}
    </div>
  );
}

// ============================================
// PRODUCTS SECTION (CONVERSION DRIVER!)
// ============================================

function ProductsSection({ products }) {
  return (
    <div className="bg-purple-50 border-2 border-purple-300 rounded-lg p-6">
      <h3 className="text-xl font-bold mb-4">🛒 Recommended Products</h3>
      <p className="text-sm text-gray-600 mb-4">
        Based on your guild's vulnerabilities, these products can help prevent disease outbreaks:
      </p>

      {products.map((product, i) => (
        <div
          key={i}
          className="bg-white border border-gray-200 rounded-lg p-4 mb-4 last:mb-0 hover:shadow-lg transition"
        >
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-2xl">{product.icon}</span>
                <h4 className="text-lg font-semibold">{product.name}</h4>
                <span className={`px-2 py-1 rounded text-xs font-bold ${
                  product.priority === 'critical' ? 'bg-red-100 text-red-800' :
                  product.priority === 'high' ? 'bg-orange-100 text-orange-800' :
                  'bg-yellow-100 text-yellow-800'
                }`}>
                  {product.urgency}
                </span>
              </div>

              <p className="text-sm text-gray-700 mb-2">
                <strong>Why:</strong> {product.reason}
              </p>

              <p className="text-sm text-gray-700 mb-2">
                <strong>Benefit:</strong> {product.benefit}
              </p>

              <p className="text-sm text-gray-600 mb-3">
                <strong>Application:</strong> {product.application}
              </p>

              <div className="flex items-center gap-4">
                <span className="text-xl font-bold text-green-700">
                  {product.price}
                </span>

                <a
                  href={product.affiliate_link}
                  className={`px-6 py-2 rounded-lg font-semibold text-white transition ${
                    product.priority === 'critical' ? 'bg-red-600 hover:bg-red-700' :
                    product.priority === 'high' ? 'bg-orange-600 hover:bg-orange-700' :
                    'bg-blue-600 hover:bg-blue-700'
                  }`}
                >
                  Buy Now →
                </a>
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

// ============================================
// HELPERS
// ============================================

function getColorClass(color) {
  const colorMap = {
    green: 'bg-green-50 border-green-300',
    lightgreen: 'bg-green-50 border-green-200',
    yellow: 'bg-yellow-50 border-yellow-300',
    orange: 'bg-orange-50 border-orange-300',
    red: 'bg-red-50 border-red-300'
  };

  return colorMap[color] || 'bg-gray-50 border-gray-300';
}

// ============================================
// CSS (Add to your global styles)
// ============================================

/*
.spinner {
  border: 4px solid #f3f3f3;
  border-top: 4px solid #3498db;
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
  margin: 0 auto;
}

.spinner-sm {
  border: 2px solid #f3f3f3;
  border-top: 2px solid #3498db;
  border-radius: 50%;
  width: 16px;
  height: 16px;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
*/
