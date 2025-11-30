#!/usr/bin/env python3
"""
Extract environmental data for 3 test locations from the same rasters
used for plant occurrence sampling.

This ensures parity between LocalConditions and plant envelope data.

Data Sources:
- WorldClim 2.1: BIO5, BIO6, BIO12 (temperature and precipitation)
- Copernicus AgroClim: FD, TR, GSL, CDD, CWD (agroclimate indices)
- SoilGrids 250m: pH, CEC, clay, sand (soil properties)

Units and scaling match the plant parquet dataset exactly.
"""

import rasterio
from pathlib import Path
import json

# Test location coordinates (lat, lon)
LOCATIONS = {
    "singapore": {
        "name": "Singapore (Tropical)",
        "lat": 1.3521,
        "lon": 103.8198,
        "koppen_zone": "Af",
    },
    "london": {
        "name": "London, UK (Temperate)",
        "lat": 51.4700,  # Heathrow area
        "lon": -0.4543,
        "koppen_zone": "Cfb",
    },
    "helsinki": {
        "name": "Helsinki, Finland (Boreal)",
        "lat": 60.1699,
        "lon": 24.9384,
        "koppen_zone": "Dfb",
    },
}

# Raster file paths
DATA_DIR = Path("/home/olier/ellenberg/data")

RASTERS = {
    # WorldClim 2.1 (direct °C and mm values)
    "BIO5": DATA_DIR / "worldclim_uncompressed/bio/wc2.1_30s_bio_5.tif",
    "BIO6": DATA_DIR / "worldclim_uncompressed/bio/wc2.1_30s_bio_6.tif",
    "BIO12": DATA_DIR / "worldclim_uncompressed/bio/wc2.1_30s_bio_12.tif",

    # AgroClim means (1981-2010 period - more recent)
    # Note: These are TEMPORAL MEANS of seasonal/annual values, not extremes
    "FD": DATA_DIR / "agroclime_mean/FD_C3S-glob-agric_gfdl-esm2m_hist_dek_19810101-20101231_v1.1_FD_mean.tif",
    "TR": DATA_DIR / "agroclime_mean/TR_C3S-glob-agric_gfdl-esm2m_hist_dek_19810101-20101231_v1.1_TR_mean.tif",
    "GSL": DATA_DIR / "agroclime_mean/GSL_C3S-glob-agric_gfdl-esm2m_hist_yr_19810101-20101231_v1.1_GSL_mean.tif",
    "CDD": DATA_DIR / "agroclime_mean/CDD_C3S-glob-agric_gfdl-esm2m_hist_season_19810101-20101231_v1.1_CDD_mean.tif",
    "CWD": DATA_DIR / "agroclime_mean/CWD_C3S-glob-agric_gfdl-esm2m_hist_season_19810101-20101231_v1.1_CWD_mean.tif",

    # SoilGrids 250m (0-5cm + 5-15cm averaged for topsoil 0-15cm equivalent)
    # Note: Values are stored × 10 (pH, CEC, clay, sand) - need to divide by 10
    "phh2o_0_5cm": DATA_DIR / "soilgrids_250m_global/phh2o_0-5cm_global_250m.tif",
    "phh2o_5_15cm": DATA_DIR / "soilgrids_250m_global/phh2o_5-15cm_global_250m.tif",
    "cec_0_5cm": DATA_DIR / "soilgrids_250m_global/cec_0-5cm_global_250m.tif",
    "cec_5_15cm": DATA_DIR / "soilgrids_250m_global/cec_5-15cm_global_250m.tif",
    "clay_0_5cm": DATA_DIR / "soilgrids_250m_global/clay_0-5cm_global_250m.tif",
    "clay_5_15cm": DATA_DIR / "soilgrids_250m_global/clay_5-15cm_global_250m.tif",
    "sand_0_5cm": DATA_DIR / "soilgrids_250m_global/sand_0-5cm_global_250m.tif",
    "sand_5_15cm": DATA_DIR / "soilgrids_250m_global/sand_5-15cm_global_250m.tif",
}


def sample_raster(raster_path: Path, lat: float, lon: float) -> float:
    """Sample a raster value at a given lat/lon coordinate."""
    with rasterio.open(raster_path) as src:
        # Convert lat/lon to row/col indices
        row, col = src.index(lon, lat)
        # Read the value at that pixel
        data = src.read(1)
        value = data[row, col]
        # Handle nodata
        if value == src.nodata or value < -1e30:
            return float('nan')
        return float(value)


def extract_location_data(location_id: str, location_info: dict) -> dict:
    """Extract all environmental variables for a location."""
    lat = location_info["lat"]
    lon = location_info["lon"]

    print(f"\n{'='*60}")
    print(f"Extracting data for: {location_info['name']}")
    print(f"Coordinates: {lat:.4f}°N, {lon:.4f}°E")
    print(f"Köppen zone: {location_info['koppen_zone']}")
    print(f"{'='*60}")

    results = {
        "name": location_info["name"],
        "koppen_zone": location_info["koppen_zone"],
        "lat": lat,
        "lon": lon,
    }

    # Sample WorldClim variables (direct values)
    print("\n--- WorldClim 2.1 (1970-2000) ---")

    bio5 = sample_raster(RASTERS["BIO5"], lat, lon)
    bio6 = sample_raster(RASTERS["BIO6"], lat, lon)
    bio12 = sample_raster(RASTERS["BIO12"], lat, lon)

    results["temp_warmest_month"] = round(bio5, 1)  # BIO5 in °C
    results["temp_coldest_month"] = round(bio6, 1)  # BIO6 in °C
    results["annual_rainfall_mm"] = round(bio12, 0)  # BIO12 in mm

    print(f"  BIO5 (temp warmest month): {bio5:.1f}°C")
    print(f"  BIO6 (temp coldest month): {bio6:.1f}°C")
    print(f"  BIO12 (annual rainfall): {bio12:.0f} mm")

    # Sample AgroClim variables (means over 1981-2010)
    print("\n--- Copernicus AgroClim (1981-2010 means) ---")

    fd = sample_raster(RASTERS["FD"], lat, lon)
    tr = sample_raster(RASTERS["TR"], lat, lon)
    gsl = sample_raster(RASTERS["GSL"], lat, lon)
    cdd = sample_raster(RASTERS["CDD"], lat, lon)
    cwd = sample_raster(RASTERS["CWD"], lat, lon)

    results["frost_days"] = round(fd, 0)  # FD: days/year with Tmin < 0°C
    results["tropical_nights"] = round(tr, 0)  # TR: nights/year with Tmin > 20°C
    results["growing_season_days"] = round(gsl, 0)  # GSL: days/year with Tmean > 5°C
    results["consecutive_dry_days"] = round(cdd, 0)  # CDD: max consecutive dry days
    results["consecutive_wet_days"] = round(cwd, 0)  # CWD: max consecutive wet days

    print(f"  FD (frost days/year): {fd:.0f}")
    print(f"  TR (tropical nights/year): {tr:.0f}")
    print(f"  GSL (growing season days): {gsl:.0f}")
    print(f"  CDD (max dry spell days): {cdd:.0f}")
    print(f"  CWD (max wet spell days): {cwd:.0f}")

    # Sample SoilGrids variables (need to average 0-5cm and 5-15cm, divide by 10)
    print("\n--- SoilGrids 2.0 (topsoil 0-15cm) ---")

    # pH (stored × 10)
    ph_0_5 = sample_raster(RASTERS["phh2o_0_5cm"], lat, lon) / 10.0
    ph_5_15 = sample_raster(RASTERS["phh2o_5_15cm"], lat, lon) / 10.0
    soil_ph = (ph_0_5 + ph_5_15) / 2.0  # Average for 0-15cm

    # CEC (stored × 10)
    cec_0_5 = sample_raster(RASTERS["cec_0_5cm"], lat, lon) / 10.0
    cec_5_15 = sample_raster(RASTERS["cec_5_15cm"], lat, lon) / 10.0
    soil_cec = (cec_0_5 + cec_5_15) / 2.0  # Average for 0-15cm

    # Clay % (stored × 10)
    clay_0_5 = sample_raster(RASTERS["clay_0_5cm"], lat, lon) / 10.0
    clay_5_15 = sample_raster(RASTERS["clay_5_15cm"], lat, lon) / 10.0
    soil_clay = (clay_0_5 + clay_5_15) / 2.0  # Average for 0-15cm

    # Sand % (stored × 10)
    sand_0_5 = sample_raster(RASTERS["sand_0_5cm"], lat, lon) / 10.0
    sand_5_15 = sample_raster(RASTERS["sand_5_15cm"], lat, lon) / 10.0
    soil_sand = (sand_0_5 + sand_5_15) / 2.0  # Average for 0-15cm

    results["soil_ph"] = round(soil_ph, 1)
    results["soil_cec"] = round(soil_cec, 1)
    results["soil_clay_pct"] = round(soil_clay, 1)
    results["soil_sand_pct"] = round(soil_sand, 1)

    print(f"  pH (0-15cm avg): {soil_ph:.1f}")
    print(f"  CEC (0-15cm avg): {soil_cec:.1f} cmol/kg")
    print(f"  Clay (0-15cm avg): {soil_clay:.1f}%")
    print(f"  Sand (0-15cm avg): {soil_sand:.1f}%")
    print(f"  Silt (calculated): {100 - soil_clay - soil_sand:.1f}%")

    return results


def generate_rust_code(all_results: dict) -> str:
    """Generate Rust code for local_conditions.rs."""

    code_blocks = []

    for loc_id, data in all_results.items():
        code = f'''/// {data["name"]} - Köppen {data["koppen_zone"]}
/// Data extracted from WorldClim 2.1, Copernicus AgroClim, SoilGrids 2.0
/// Coordinates: {data["lat"]:.4f}°N, {data["lon"]:.4f}°E
pub fn {loc_id}() -> LocalConditions {{
    LocalConditions {{
        name: "{data["name"]}".to_string(),
        koppen_zone: "{data["koppen_zone"]}".to_string(),

        // Temperature (WorldClim 2.1, 1970-2000)
        temp_warmest_month: {data["temp_warmest_month"]},   // BIO5
        temp_coldest_month: {data["temp_coldest_month"]},   // BIO6

        // Frost/Heat (AgroClim 1981-2010 means)
        frost_days: {data["frost_days"]:.1f},              // FD: days/year with Tmin < 0°C
        tropical_nights: {data["tropical_nights"]:.1f},    // TR: nights/year with Tmin > 20°C
        growing_season_days: {data["growing_season_days"]:.1f},  // GSL: days with Tmean > 5°C

        // Moisture (WorldClim + AgroClim)
        annual_rainfall_mm: {data["annual_rainfall_mm"]:.1f},  // BIO12
        consecutive_dry_days: {data["consecutive_dry_days"]:.1f},  // CDD
        consecutive_wet_days: {data["consecutive_wet_days"]:.1f},  // CWD

        // Soil (SoilGrids 2.0, 0-15cm average)
        soil_ph: {data["soil_ph"]},
        soil_cec: {data["soil_cec"]},
        soil_clay_pct: {data["soil_clay_pct"]},
        soil_sand_pct: {data["soil_sand_pct"]},
    }}
}}'''
        code_blocks.append(code)

    return "\n\n".join(code_blocks)


def main():
    print("=" * 60)
    print("Test Location Data Extraction")
    print("Extracting from same rasters used for plant occurrence sampling")
    print("=" * 60)

    # Check all rasters exist
    print("\nChecking raster files...")
    missing = []
    for name, path in RASTERS.items():
        if not path.exists():
            missing.append(f"  {name}: {path}")

    if missing:
        print("ERROR: Missing raster files:")
        for m in missing:
            print(m)
        return

    print("All raster files found.")

    # Extract data for each location
    all_results = {}
    for loc_id, loc_info in LOCATIONS.items():
        all_results[loc_id] = extract_location_data(loc_id, loc_info)

    # Output summary
    print("\n" + "=" * 60)
    print("SUMMARY - LocalConditions Values")
    print("=" * 60)

    for loc_id, data in all_results.items():
        print(f"\n{data['name']}:")
        print(f"  koppen_zone: \"{data['koppen_zone']}\"")
        print(f"  temp_warmest_month: {data['temp_warmest_month']}")
        print(f"  temp_coldest_month: {data['temp_coldest_month']}")
        print(f"  frost_days: {data['frost_days']}")
        print(f"  tropical_nights: {data['tropical_nights']}")
        print(f"  growing_season_days: {data['growing_season_days']}")
        print(f"  annual_rainfall_mm: {data['annual_rainfall_mm']}")
        print(f"  consecutive_dry_days: {data['consecutive_dry_days']}")
        print(f"  consecutive_wet_days: {data['consecutive_wet_days']}")
        print(f"  soil_ph: {data['soil_ph']}")
        print(f"  soil_cec: {data['soil_cec']}")
        print(f"  soil_clay_pct: {data['soil_clay_pct']}")
        print(f"  soil_sand_pct: {data['soil_sand_pct']}")

    # Generate Rust code
    print("\n" + "=" * 60)
    print("RUST CODE FOR local_conditions.rs")
    print("=" * 60)
    rust_code = generate_rust_code(all_results)
    print(rust_code)

    # Save to JSON for reference
    output_path = Path("/home/olier/ellenberg/shipley_checks/stage4/test_location_data.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\nData saved to: {output_path}")


if __name__ == "__main__":
    main()
