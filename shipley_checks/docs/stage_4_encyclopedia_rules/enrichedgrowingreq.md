
# Part I: Environmental Envelope from Occurrence Data

## 3. Climate Envelope from Natural Occurrence Data

### 3.1 Data Provenance and Interpretation

**Critical Understanding**: The WorldClim and climate extremes data in Phase 0 are **derived from aggregated plant occurrence coordinates**. Each plant species has occurrence records from herbarium specimens, field surveys, and biodiversity databases (GBIF, etc.). For each occurrence point, we extract the corresponding WorldClim and climate extreme values, then aggregate across all occurrences to produce:

- **q05**: 5th percentile (lower extreme of the distribution)
- **q50**: Median (typical conditions where the plant occurs)
- **q95**: 95th percentile (upper extreme of the distribution)

**Interpretation**: These values describe **where the plant naturally occurs and thrives**, not prescriptive "requirements." The q05 and q95 represent the extremes of tolerance, while q50 represents typical conditions. For example:
- BIO_6 (min winter temp): q05 = coldest locations → evidence of **cold hardiness**
- BIO_5 (max summer temp): q95 = hottest locations → evidence of **heat tolerance**
- BIO_12 (annual precip): q05 = driest locations → evidence of **drought tolerance**

### 3.2 Winter Cold Tolerance from Natural Range

**Scientific Basis**: BIO_6 (Minimum Temperature of Coldest Month) represents the **average** daily minimum temperature during the coldest month. This measures **chronic cold exposure** - what the plant routinely experiences throughout winter.

**Relationship to TNn (Section 1.10)**: TNn measures the single coldest night of the year - the **acute cold extreme**. Both are useful:

| Metric | Measures | Use |
|--------|----------|-----|
| **BIO_6** | Monthly average of daily minimums | Adaptation to prolonged cold; dormancy requirements |
| **TNn** | Absolute coldest night | Survival threshold; "will it survive my coldest night?" |

A plant might have BIO_6_q05 = -10°C but TNn_q05 = -25°C, meaning it routinely experiences -10°C nights but has survived -25°C cold snaps.

**Data Source**: `wc2.1_30s_bio_6_q05`, `wc2.1_30s_bio_6_q50`, `wc2.1_30s_bio_6_q95`

**Algorithm**:

```rust
/// Describe chronic winter cold exposure from natural occurrence range
/// BIO_6 = average daily minimum during coldest month (chronic exposure)
/// For acute cold survival, see TNn in Section 1.10
fn describe_chronic_cold_exposure(bio_6_q05: f64, bio_6_q50: f64, bio_6_q95: f64) -> ChronicColdInfo {
    let range_description = format!(
        "{}°C to {}°C (median {}°C)",
        bio_6_q05.round(), bio_6_q95.round(), bio_6_q50.round()
    );

    // q50: Typical winter regime where plant occurs
    let typical_winter_regime = match bio_6_q50 {
        t if t < -20.0 => "Typically occurs in severe winter climates (avg min < -20°C)",
        t if t < -10.0 => "Typically occurs in cold winter climates (avg min -20 to -10°C)",
        t if t < 0.0 => "Typically occurs in mild winter climates (avg min -10 to 0°C)",
        t if t < 5.0 => "Typically occurs in cool winter climates (avg min 0 to 5°C)",
        _ => "Typically occurs in frost-free climates",
    };

    // q05: Coldest edge of range - evidence of chronic cold tolerance
    let chronic_cold_tolerance = match bio_6_q05 {
        t if t < -25.0 => "Tolerates prolonged severe cold (populations exist where avg winter min < -25°C)",
        t if t < -15.0 => "Tolerates prolonged hard frost (populations exist where avg winter min < -15°C)",
        t if t < -5.0 => "Tolerates prolonged moderate frost",
        t if t < 0.0 => "Tolerates prolonged light frost",
        _ => "Limited tolerance for prolonged frost",
    };

    ChronicColdInfo {
        natural_range: range_description,
        typical_winter_regime: typical_winter_regime.into(),
        chronic_cold_tolerance: chronic_cold_tolerance.into(),
        note: "For acute cold survival (single coldest night), see TNn (Section 1.10)".into(),
    }
}
```

**Output Format**:
```
**Chronic Winter Cold** (average coldest month minimums)
   Natural range: -18°C to -2°C (median -8°C)
   Typical regime: Typically occurs in mild winter climates (avg min -10 to 0°C)
   Tolerance: Tolerates prolonged hard frost (populations exist where avg winter min < -15°C)
   Note: For acute cold survival, see TNn
```

### 3.3 Summer Heat Tolerance from Natural Range

**Scientific Basis**: BIO_5 (Maximum Temperature of Warmest Month) represents the **average** daily maximum temperature during the warmest month. This measures **chronic heat exposure** - the sustained summer heat the plant routinely experiences.

**Relationship to TXx (Section 1.10)**: TXx measures the single hottest day of the year - the **acute heat extreme**. Both are useful:

| Metric | Measures | Use |
|--------|----------|-----|
| **BIO_5** | Monthly average of daily maximums | Adaptation to sustained summer heat |
| **TXx** | Absolute hottest day | Survival threshold; "will it survive my hottest day?" |

A plant might have BIO_5_q95 = 30°C but TXx_q95 = 42°C, meaning it routinely experiences 30°C summer days but has survived 42°C heatwaves.

**Data Source**: `wc2.1_30s_bio_5_q05`, `wc2.1_30s_bio_5_q50`, `wc2.1_30s_bio_5_q95`

**Algorithm**:

```rust
/// Describe chronic summer heat exposure from natural occurrence range
/// BIO_5 = average daily maximum during warmest month (chronic exposure)
/// For acute heat survival, see TXx in Section 1.10
fn describe_chronic_heat_exposure(bio_5_q05: f64, bio_5_q50: f64, bio_5_q95: f64) -> ChronicHeatInfo {
    let range_description = format!(
        "{}°C to {}°C (median {}°C)",
        bio_5_q05.round(), bio_5_q95.round(), bio_5_q50.round()
    );

    // q50: Typical summer regime where plant occurs
    let typical_summer_regime = match bio_5_q50 {
        t if t > 35.0 => "Typically occurs in hot summer climates (avg max > 35°C)",
        t if t > 28.0 => "Typically occurs in warm summer climates (avg max 28-35°C)",
        t if t > 22.0 => "Typically occurs in mild summer climates (avg max 22-28°C)",
        t if t > 15.0 => "Typically occurs in cool summer climates (avg max 15-22°C)",
        _ => "Typically occurs in cold summer climates (alpine/arctic)",
    };

    // q95: Hottest edge of range - evidence of chronic heat tolerance
    let chronic_heat_tolerance = match bio_5_q95 {
        t if t > 38.0 => "Tolerates sustained high heat (populations exist where avg summer max > 38°C)",
        t if t > 32.0 => "Tolerates sustained warm conditions (populations exist where avg summer max > 32°C)",
        t if t > 26.0 => "Tolerates sustained mild heat",
        t if t > 20.0 => "Limited tolerance for sustained heat",
        _ => "Cool-climate specialist; avoids sustained heat",
    };

    ChronicHeatInfo {
        natural_range: range_description,
        typical_summer_regime: typical_summer_regime.into(),
        chronic_heat_tolerance: chronic_heat_tolerance.into(),
        note: "For acute heat survival (single hottest day), see TXx (Section 1.10)".into(),
    }
}
```

### 3.4 Annual Temperature Range and Continentality

**Scientific Basis**: BIO_7 (Temperature Annual Range) indicates whether the plant naturally occurs in continental (large range) or oceanic (small range) climates.

**Data Source**: `wc2.1_30s_bio_7_q05`, `wc2.1_30s_bio_7_q50`, `wc2.1_30s_bio_7_q95`

**Algorithm**:

```rust
fn describe_continentality(bio_7_q50: f64) -> &'static str {
    match bio_7_q50 {
        r if r < 15.0 => "Oceanic climate preference (mild, equable temperatures year-round)",
        r if r < 25.0 => "Transitional climate (moderate seasonal variation)",
        r if r < 35.0 => "Continental climate adapted (tolerates hot summers, cold winters)",
        _ => "Extreme continental adapted (wide temperature swings tolerated)",
    }
}
```

### 3.5 Precipitation Patterns from Natural Range

**Scientific Basis**: BIO_12 (Annual Precipitation) and BIO_15 (Precipitation Seasonality) describe the moisture regime where the plant naturally occurs.

**Data Source**: `wc2.1_30s_bio_12_q05/q50/q95`, `wc2.1_30s_bio_15_q05/q50/q95`

**Threshold Derivation**: The moisture classification thresholds are based on the Köppen-Geiger climate classification system:
- **Arid (BWh/BWk)**: < 250mm annual precipitation
- **Semi-arid (BSh/BSk)**: 250-500mm
- **Humid temperate**: 500-1500mm typical range
- **Wet tropical/oceanic**: > 1500mm

BIO_15 (Precipitation Seasonality) is measured as the coefficient of variation (CV) of monthly precipitation. Higher values indicate stronger wet/dry seasonal contrast.

**Algorithm**:

```rust
fn describe_precipitation_preference(
    bio_12_q05: f64, bio_12_q50: f64, bio_12_q95: f64,
    bio_15_q50: f64
) -> PrecipitationPreference {
    let annual_range = format!(
        "{}mm to {}mm annually (median {}mm)",
        bio_12_q05.round(), bio_12_q95.round(), bio_12_q50.round()
    );

    // q50: Typical rainfall regime (Köppen-aligned)
    let typical_rainfall_regime = match bio_12_q50 {
        p if p < 250.0 => "Typically occurs in arid climates (Köppen arid: <250mm)",
        p if p < 500.0 => "Typically occurs in semi-arid climates (Köppen semi-arid: 250-500mm)",
        p if p < 1000.0 => "Typically occurs in temperate rainfall climates (500-1000mm)",
        p if p < 1500.0 => "Typically occurs in moist climates (1000-1500mm)",
        _ => "Typically occurs in high-rainfall climates (>1500mm)",
    };

    // q05: Driest edge of range - evidence of drought tolerance
    let drought_tolerance = match bio_12_q05 {
        p if p < 200.0 => "Drought-tolerant (populations exist in arid conditions <200mm/year)",
        p if p < 400.0 => "Moderate drought tolerance (populations exist in semi-arid conditions)",
        p if p < 600.0 => "Limited drought tolerance",
        _ => "Requires consistent moisture (no populations in dry climates)",
    };

    // Seasonality interpretation based on CV thresholds
    let seasonality = if bio_15_q50 > 100.0 {
        "Highly seasonal rainfall (strong wet/dry seasons; CV>100)"
    } else if bio_15_q50 > 60.0 {
        "Moderately seasonal rainfall (CV 60-100)"
    } else if bio_15_q50 > 30.0 {
        "Weakly seasonal rainfall (CV 30-60)"
    } else {
        "Even rainfall distribution year-round (CV<30)"
    };

    PrecipitationPreference {
        natural_range: annual_range,
        typical_rainfall_regime: typical_rainfall_regime.into(),
        drought_tolerance: drought_tolerance.into(),
        seasonality: seasonality.into(),
        note: "Use EIVE-M (moisture indicator) for specific watering guidance".into(),
    }
}
```

**Note**: Annual precipitation alone does not determine watering needs - distribution throughout the year, evapotranspiration rates, and soil water-holding capacity all matter. Use EIVE-M (Section 3.3) for watering guidance, which integrates ecological moisture preference directly.

### 3.6 Frost Exposure in Natural Range

**Data Source**: Climate extremes FD (Frost Days) - count of days per year with Tmin < 0°C

**Interpretation**: FD is a count variable. The values describe the frost regime **where the plant naturally occurs**.

**Algorithm**:

```rust
fn describe_frost_exposure(fd_q05: f64, fd_q50: f64, fd_q95: f64) -> FrostExposure {
    // FD = count of frost days per year (Tmin < 0°C)
    let range_description = format!(
        "{} to {} frost days/year (median {})",
        fd_q05.round(), fd_q95.round(), fd_q50.round()
    );

    // q50: Typical frost regime where plant occurs
    let typical_frost_regime = match fd_q50 {
        f if f < 5.0 => "Typically occurs in frost-free or near frost-free climates",
        f if f < 30.0 => "Typically occurs where frost is occasional (<30 days/year)",
        f if f < 90.0 => "Typically occurs in climates with regular frost (30-90 days/year)",
        f if f < 150.0 => "Typically occurs in climates with extended frost (90-150 days/year)",
        _ => "Typically occurs in climates with prolonged frost (>150 days/year)",
    };

    // q95: Most frost-prone edge of range - evidence of frost tolerance
    let frost_tolerance = match fd_q95 {
        f if f < 10.0 => "Limited frost tolerance (no populations in frosty climates)",
        f if f < 60.0 => "Moderate frost tolerance (populations exist where frost occurs up to 60 days)",
        f if f < 120.0 => "Good frost tolerance (populations exist in climates with 60-120 frost days)",
        _ => "High frost tolerance (populations exist in climates with >120 frost days/year)",
    };

    FrostExposure {
        natural_range: range_description,
        typical_frost_regime: typical_frost_regime.into(),
        frost_tolerance: frost_tolerance.into(),
    }
}
```

### 3.7 Growing Season in Natural Range

**Data Source**: Climate extremes GSL (Growing Season Length) - count of days in the growing season

**Interpretation**: GSL is a count variable representing the number of consecutive days with temperatures suitable for growth.

**Algorithm**:

```rust
fn describe_growing_season(gsl_q05: f64, gsl_q50: f64, gsl_q95: f64) -> GrowingSeasonInfo {
    // GSL = count of growing season days
    let range_description = format!(
        "{} to {} days (median {})",
        gsl_q05.round(), gsl_q95.round(), gsl_q50.round()
    );

    // q50: Typical growing season where plant occurs
    let typical_growing_season = match gsl_q50 {
        g if g < 120.0 => "Typically occurs in short-season climates (<4 months growing)",
        g if g < 180.0 => "Typically occurs in standard temperate climates (5-6 months growing)",
        g if g < 270.0 => "Typically occurs in long-season climates (7-9 months growing)",
        _ => "Typically occurs in year-round growing climates (>9 months)",
    };

    // q05: Shortest growing season in range - evidence of short-season adaptation
    let short_season_tolerance = match gsl_q05 {
        g if g < 90.0 => "Adapted to very short seasons (populations exist where growing season <3 months)",
        g if g < 150.0 => "Adapted to short seasons (populations exist where growing season <5 months)",
        g if g < 210.0 => "Moderate season-length flexibility",
        _ => "Requires long growing season (no populations in short-season climates)",
    };

    GrowingSeasonInfo {
        natural_range: range_description,
        typical_growing_season: typical_growing_season.into(),
        short_season_tolerance: short_season_tolerance.into(),
    }
}
```

### 3.8 Annual Mean Temperature (Overall Climate)

**Data Source**: `wc2.1_30s_bio_1_q05/q50/q95` (°C × 10)

**Scientific Basis**: BIO_1 provides the overall thermal regime where the plant occurs.

**Note**: Climate zone classification should use the pre-computed Köppen zones already present in the dataset (from Stage 4 calibration), not be derived from BIO_1. BIO_1 is presented as supplementary quantitative data.

**Algorithm**:

```rust
fn describe_annual_temperature(bio_1_q05: f64, bio_1_q50: f64, bio_1_q95: f64) -> AnnualTempInfo {
    // BIO_1 is stored as °C × 10
    let t_q05 = bio_1_q05 / 10.0;
    let t_q50 = bio_1_q50 / 10.0;
    let t_q95 = bio_1_q95 / 10.0;

    let range_description = format!(
        "{:.1}°C to {:.1}°C annual mean (median {:.1}°C)",
        t_q05, t_q95, t_q50
    );

    // Present the data only; climate zone comes from Köppen field in dataset
    AnnualTempInfo {
        natural_range: range_description,
    }
}
```

### 3.9 Temperature Seasonality (Continental vs Oceanic)

**Data Source**: `wc2.1_30s_bio_4_q05/q50/q95` (standard deviation × 100)

**Scientific Basis**: BIO_4 measures how much temperature varies throughout the year. High values indicate continental climates with hot summers and cold winters; low values indicate oceanic climates with mild, stable temperatures.

**Algorithm**:

```rust
fn describe_temperature_seasonality(bio_4_q05: f64, bio_4_q50: f64, bio_4_q95: f64) -> SeasonalityInfo {
    // BIO_4 = standard deviation of monthly temperatures × 100
    let range_description = format!(
        "{:.0} to {:.0} (median {:.0})",
        bio_4_q05, bio_4_q95, bio_4_q50
    );

    // q50: Typical seasonality regime where plant occurs
    let typical_seasonality = match bio_4_q50 {
        s if s < 200.0 => "Typically occurs in stable climates (oceanic/tropical; BIO_4 <200)",
        s if s < 400.0 => "Typically occurs in moderately stable climates (maritime temperate)",
        s if s < 600.0 => "Typically occurs in transitional climates (moderate seasonality)",
        s if s < 800.0 => "Typically occurs in seasonal climates (continental temperate)",
        _ => "Typically occurs in highly seasonal climates (extreme continental; BIO_4 >800)",
    };

    // q95: Most seasonal edge of range - evidence of continental tolerance
    let continental_tolerance = match bio_4_q95 {
        s if s < 300.0 => "Limited tolerance for seasonal extremes (no populations in continental climates)",
        s if s < 500.0 => "Moderate tolerance for seasonal variation",
        s if s < 700.0 => "Good tolerance for seasonal climates (populations exist where BIO_4 >500)",
        _ => "High tolerance for continental extremes (populations exist in highly seasonal climates)",
    };

    SeasonalityInfo {
        natural_range: range_description,
        typical_regime: typical_seasonality.into(),
        continental_tolerance: continental_tolerance.into(),
    }
}
```

**Output Format**:
```
**Temperature Seasonality** (from natural occurrence range)
   BIO_4 range: 245 to 612 (median 385)
   Typical regime: Typically occurs in moderately stable climates (maritime temperate)
   Continental tolerance: Good tolerance for seasonal climates (populations exist where BIO_4 >500)
```

### 3.10 Absolute Temperature Extremes (TNn and TXx)

**Data Source**:
- `TNn_q05/q50/q95`: Minimum of daily minimum temperature (coldest night of year)
- `TXx_q05/q50/q95`: Maximum of daily maximum temperature (hottest day of year)

**Scientific Basis**: These are the true absolute extremes - more relevant for plant survival than monthly means. TNn_q05 represents the coldest conditions the plant has experienced; TXx_q95 represents the hottest.

**Algorithm**:

```rust
fn describe_absolute_extremes(
    tnn_q05: f64, tnn_q50: f64, tnn_q95: f64,
    txx_q05: f64, txx_q50: f64, txx_q95: f64,
) -> AbsoluteExtremesInfo {
    // Coldest night range (TNn q05 = coldest edge of range)
    let cold_extreme = format!(
        "Coldest nights: {:.0}°C to {:.0}°C (median {:.0}°C)",
        tnn_q05, tnn_q95, tnn_q50
    );

    // Hottest day range (TXx q95 = hottest edge of range)
    let heat_extreme = format!(
        "Hottest days: {:.0}°C to {:.0}°C (median {:.0}°C)",
        txx_q05, txx_q95, txx_q50
    );

    // q50: Typical absolute cold the plant experiences
    let typical_winter_low = match tnn_q50 {
        t if t < -20.0 => "Typically experiences severe winter cold (median coldest night below -20°C)",
        t if t < -10.0 => "Typically experiences hard winter frost (median coldest night -10°C to -20°C)",
        t if t < 0.0 => "Typically experiences moderate frost (median coldest night 0°C to -10°C)",
        t if t < 5.0 => "Typically experiences near-freezing winters (median coldest night 0°C to 5°C)",
        _ => "Typically experiences frost-free winters (median coldest night above 5°C)",
    };

    // q05: Cold hardiness evidence - coldest edge of natural range
    let cold_hardiness = match tnn_q05 {
        t if t < -40.0 => "Extremely cold-hardy (populations survive -40°C and below)",
        t if t < -25.0 => "Very cold-hardy (populations survive severe frosts to -25°C)",
        t if t < -15.0 => "Cold-hardy (populations survive hard frosts to -15°C)",
        t if t < -5.0 => "Moderately hardy (populations survive moderate frosts)",
        t if t < 0.0 => "Half-hardy (populations exist where coldest nights reach light frost)",
        _ => "Frost-tender (no populations in frost-prone areas)",
    };

    // q50: Typical absolute heat the plant experiences
    let typical_summer_high = match txx_q50 {
        t if t > 40.0 => "Typically experiences extreme summer heat (median hottest day above 40°C)",
        t if t > 35.0 => "Typically experiences hot summers (median hottest day 35°C-40°C)",
        t if t > 30.0 => "Typically experiences warm summers (median hottest day 30°C-35°C)",
        t if t > 25.0 => "Typically experiences mild summers (median hottest day 25°C-30°C)",
        _ => "Typically experiences cool summers (median hottest day below 25°C)",
    };

    // q95: Heat tolerance evidence - hottest edge of natural range
    let heat_tolerance = match txx_q95 {
        t if t > 45.0 => "Extreme heat tolerant (populations survive 45°C+)",
        t if t > 40.0 => "Very heat tolerant (populations survive 40°C+)",
        t if t > 35.0 => "Heat tolerant (populations survive hot summers)",
        t if t > 30.0 => "Moderate heat tolerance (populations exist where peaks reach 30°C+)",
        _ => "Cool-climate preference (no populations in areas with extreme heat)",
    };

    AbsoluteExtremesInfo {
        cold_extreme,
        heat_extreme,
        typical_winter_low: typical_winter_low.into(),
        cold_hardiness: cold_hardiness.into(),
        typical_summer_high: typical_summer_high.into(),
        heat_tolerance: heat_tolerance.into(),
    }
}
```

**Output Format**:
```
**Absolute Temperature Extremes** (from natural occurrence range)
   Coldest nights: -22°C to -5°C (median -12°C)
   Typical winter: Typically experiences hard winter frost (median coldest night -10°C to -20°C)
   Cold hardiness: Cold-hardy (populations survive hard frosts to -15°C)
   Hottest days: 28°C to 38°C (median 33°C)
   Typical summer: Typically experiences warm summers (median hottest day 30°C-35°C)
   Heat tolerance: Heat tolerant (populations survive hot summers)
```

### 3.11 Summer Days and Tropical Nights (Heat Stress Indicators)

**Data Source**:
- `SU_q05/q50/q95`: Summer Days (days with Tmax > 25°C)
- `TR_q05/q50/q95`: Tropical Nights (nights with Tmin > 20°C)

**Scientific Basis**: Many plants require cool nights for optimal growth and flowering. Tropical nights indicate sustained heat stress. Summer days count indicates overall summer heat load.

**Algorithm**:

```rust
fn describe_heat_stress_indicators(
    su_q05: f64, su_q50: f64, su_q95: f64,
    tr_q05: f64, tr_q50: f64, tr_q95: f64,
) -> HeatStressInfo {
    let summer_days = format!(
        "{:.0} to {:.0} days >25°C (median {:.0})",
        su_q05, su_q95, su_q50
    );

    // TR = count of nights per year where Tmin > 20°C
    let tropical_nights = format!(
        "{:.0} to {:.0} nights >20°C per year (median {:.0})",
        tr_q05, tr_q95, tr_q50
    );

    // q50: Typical summer heat regime where plant naturally occurs
    let typical_summer_regime = match su_q50 {
        s if s < 7.0 => "Typically occurs in cool-summer climates (few days >25°C)",
        s if s < 30.0 => "Typically occurs in mild-summer climates",
        s if s < 60.0 => "Typically occurs in warm-summer climates",
        s if s < 120.0 => "Typically occurs in hot-summer climates",
        _ => "Typically occurs in very hot climates (>120 days >25°C)",
    };

    // q95: Hot summer tolerance - hottest edge of range
    let hot_summer_tolerance = match su_q95 {
        s if s < 30.0 => "Limited heat tolerance (no populations in hot-summer areas)",
        s if s < 60.0 => "Moderate heat tolerance (populations exist with up to 60 hot days)",
        s if s < 120.0 => "Good heat tolerance (populations exist with 60-120 hot days)",
        _ => "High heat tolerance (populations thrive with >120 days above 25°C)",
    };

    // q50: Typical night heat regime where plant naturally occurs
    let typical_night_regime = match tr_q50 {
        t if t < 5.0 => "Typically occurs where warm nights are rare (<5 tropical nights/year)",
        t if t < 30.0 => "Typically occurs with occasional warm nights",
        t if t < 90.0 => "Typically occurs with frequent warm nights",
        _ => "Typically occurs in persistently warm climates (>90 tropical nights/year)",
    };

    // q95: Tropical night tolerance - hottest edge of range
    let warm_night_tolerance = match tr_q95 {
        t if t < 10.0 => "Requires cool nights (no populations where tropical nights are common)",
        t if t < 30.0 => "Tolerates occasional warm nights (populations exist with up to 30 TR)",
        t if t < 90.0 => "Good tolerance for warm nights (populations exist with 30-90 TR)",
        _ => "High tolerance for persistent warm nights (populations exist with >90 TR)",
    };

    HeatStressInfo {
        summer_days,
        tropical_nights,
        typical_summer_regime: typical_summer_regime.into(),
        hot_summer_tolerance: hot_summer_tolerance.into(),
        typical_night_regime: typical_night_regime.into(),
        warm_night_tolerance: warm_night_tolerance.into(),
    }
}
```

**Output Format**:
```
**Heat Stress Indicators** (from natural occurrence range)
   Summer days: 25 to 85 days >25°C (median 52)
   Tropical nights: 5 to 40 nights >20°C per year (median 18)
   Typical summer: Typically occurs in warm-summer climates
   Hot summer tolerance: Good heat tolerance (populations exist with 60-120 hot days)
   Typical nights: Typically occurs with occasional warm nights
   Warm night tolerance: Good tolerance for warm nights (populations exist with 30-90 TR)
```

### 3.12 Icing Days and Cold Spell Duration (Severe Winter Indicators)

**Data Source**:
- `ID_q05/q50/q95`: Icing Days (count of days per year with Tmax < 0°C - entire day below freezing)
- `CSDI_q05/q50/q95`: Cold Spell Duration Index (consecutive days with Tmin below normal)

**Scientific Basis**: These values describe the severe winter conditions **where the plant naturally occurs**. ID counts days where even daytime temperatures stay below freezing; CSDI measures cold spell duration.

**Algorithm**:

```rust
fn describe_severe_cold_adaptation(
    id_q05: f64, id_q50: f64, id_q95: f64,
    csdi_q05: f64, csdi_q50: f64, csdi_q95: f64,
) -> SevereColdAdaptation {
    // ID = count of days per year where Tmax < 0°C
    let icing_days = format!(
        "{:.0} to {:.0} icing days/year (median {:.0})",
        id_q05, id_q95, id_q50
    );

    let cold_spells = format!(
        "{:.0} to {:.0} days (median {:.0})",
        csdi_q05, csdi_q95, csdi_q50
    );

    // q50: Typical winter severity where plant naturally occurs
    let typical_winter_severity = match id_q50 {
        i if i < 1.0 => "Typically occurs in frost-free or near frost-free climates",
        i if i < 10.0 => "Typically occurs where severe cold is occasional (<10 icing days)",
        i if i < 30.0 => "Typically occurs in climates with regular severe cold",
        i if i < 60.0 => "Typically occurs in climates with extended severe winters",
        _ => "Typically occurs in climates with prolonged severe winters (>60 icing days)",
    };

    // q95: Severe cold tolerance - most extreme conditions in the plant's range
    let severe_cold_tolerance = match id_q95 {
        i if i < 5.0 => "Limited tolerance for severe cold (no populations in harsh winter areas)",
        i if i < 30.0 => "Moderate tolerance for severe cold (populations exist with up to 30 icing days)",
        i if i < 60.0 => "Good tolerance for severe winters (populations exist with 30-60 icing days)",
        _ => "High tolerance for continental winters (populations exist with >60 icing days)",
    };

    // q95: Cold spell tolerance
    let cold_spell_tolerance = match csdi_q95 {
        c if c < 5.0 => "Limited tolerance for prolonged cold spells",
        c if c < 15.0 => "Tolerates brief cold spells (populations exist with CSDI up to 15)",
        c if c < 30.0 => "Good tolerance for cold spells (populations exist with CSDI up to 30)",
        _ => "High tolerance for extended cold spells (populations exist with CSDI >30)",
    };

    SevereColdAdaptation {
        icing_days,
        cold_spells,
        typical_winter_severity: typical_winter_severity.into(),
        severe_cold_tolerance: severe_cold_tolerance.into(),
        cold_spell_tolerance: cold_spell_tolerance.into(),
    }
}
```

**Output Format**:
```
**Severe Winter Indicators** (from natural occurrence range)
   Icing days: 5 to 35 icing days/year (median 18)
   Cold spells: 8 to 22 days (median 14)
   Typical winter: Typically occurs in climates with regular severe cold
   Severe cold tolerance: Moderate tolerance for severe cold (populations exist with up to 30 icing days)
   Cold spell tolerance: Good tolerance for cold spells (populations exist with CSDI up to 30)
```

### 3.13 Warm Spell Duration Index (Heatwave Tolerance)

**Data Source**: `WSDI_q05/q50/q95` (consecutive days with Tmax above normal)

**Scientific Basis**: WSDI measures heatwave duration - critical for understanding whether a plant tolerates prolonged heat stress or just brief hot spells.

**Algorithm**:

```rust
fn describe_heatwave_tolerance(wsdi_q05: f64, wsdi_q50: f64, wsdi_q95: f64) -> HeatwaveInfo {
    let range_description = format!(
        "{:.0} to {:.0} consecutive warm days (median {:.0})",
        wsdi_q05, wsdi_q95, wsdi_q50
    );

    // q50: Typical heatwave exposure where plant naturally occurs
    let typical_heatwave_exposure = match wsdi_q50 {
        w if w < 5.0 => "Typically occurs where heatwaves are rare (<5 days WSDI)",
        w if w < 15.0 => "Typically occurs where heatwaves are occasional (5-15 days WSDI)",
        w if w < 30.0 => "Typically occurs where heatwaves are regular (15-30 days WSDI)",
        _ => "Typically occurs in climates with prolonged heatwaves (>30 days WSDI)",
    };

    // q95: Heatwave tolerance - most extreme conditions in the plant's range
    let heatwave_tolerance = match wsdi_q95 {
        w if w < 10.0 => "Limited heatwave tolerance (no populations in heatwave-prone areas)",
        w if w < 20.0 => "Moderate heatwave tolerance (populations exist with WSDI up to 20)",
        w if w < 40.0 => "Good heatwave tolerance (populations exist with WSDI up to 40)",
        _ => "High heatwave tolerance (populations thrive with >40 days WSDI)",
    };

    let care_advice = match wsdi_q95 {
        w if w < 10.0 => "Provide shade and extra water during heatwaves",
        w if w < 25.0 => "Tolerates most summer heat; monitor during extreme events",
        _ => "Heat-adapted; thrives even during prolonged hot spells",
    };

    HeatwaveInfo {
        natural_range: range_description,
        typical_exposure: typical_heatwave_exposure.into(),
        heatwave_tolerance: heatwave_tolerance.into(),
        care_advice: care_advice.into(),
    }
}
```

**Output Format**:
```
**Heatwave Tolerance** (from natural occurrence range)
   WSDI range: 5 to 28 consecutive warm days (median 14)
   Typical exposure: Typically occurs where heatwaves are occasional (5-15 days WSDI)
   Heatwave tolerance: Good heatwave tolerance (populations exist with WSDI up to 40)
   → Tolerates most summer heat; monitor during extreme events
```

### 3.14 Drought Period Indicators (BIO_14, BIO_17, CDD)

**Data Source**:
- `wc2.1_30s_bio_14_q05/q50/q95`: Precipitation of Driest Month (mm)
- `wc2.1_30s_bio_17_q05/q50/q95`: Precipitation of Driest Quarter (mm)
- `CDD_q05/q50/q95`: Consecutive Dry Days (longest dry spell)

**Scientific Basis**: These variables characterize drought stress during the driest period. BIO_14 shows monthly minimum rainfall; BIO_17 shows quarterly drought; CDD shows the longest continuous dry spell the plant experiences.

**Algorithm**:

```rust
fn describe_drought_tolerance(
    bio_14_q05: f64, bio_14_q50: f64, bio_14_q95: f64,
    bio_17_q05: f64, bio_17_q50: f64, bio_17_q95: f64,
    cdd_q05: f64, cdd_q50: f64, cdd_q95: f64,
) -> DroughtInfo {
    let driest_month = format!(
        "{:.0}mm to {:.0}mm (median {:.0}mm)",
        bio_14_q05, bio_14_q95, bio_14_q50
    );

    let driest_quarter = format!(
        "{:.0}mm to {:.0}mm (median {:.0}mm)",
        bio_17_q05, bio_17_q95, bio_17_q50
    );

    let consecutive_dry = format!(
        "{:.0} to {:.0} days (median {:.0})",
        cdd_q05, cdd_q95, cdd_q50
    );

    // q50: Typical dry season conditions where plant naturally occurs
    let typical_drought_regime = match bio_14_q50 {
        p if p < 10.0 => "Typically occurs in seasonally arid climates (driest month <10mm)",
        p if p < 30.0 => "Typically occurs in climates with pronounced dry season",
        p if p < 50.0 => "Typically occurs in climates with moderate dry season",
        _ => "Typically occurs in year-round moist climates (driest month >50mm)",
    };

    // q05: Drought tolerance evidence - driest conditions where populations exist
    let drought_tolerance = match bio_14_q05 {
        p if p < 5.0 => "Extreme drought tolerant (populations survive near-zero rainfall months)",
        p if p < 15.0 => "Strong drought tolerance (populations survive very dry periods)",
        p if p < 30.0 => "Moderate drought tolerance (populations exist where driest month <30mm)",
        p if p < 50.0 => "Limited drought tolerance (populations need >30mm in driest month)",
        _ => "No significant drought tolerance (populations require consistent moisture)",
    };

    // q50: Typical dry spell duration
    let typical_dry_spells = match cdd_q50 {
        d if d > 30.0 => "Typically experiences extended dry spells (median CDD >30 days)",
        d if d > 14.0 => "Typically experiences moderate dry spells (median CDD 14-30 days)",
        _ => "Typically experiences brief dry spells (median CDD <14 days)",
    };

    // q95: Dry spell tolerance from CDD - longest spells at edge of range
    let dry_spell_tolerance = match cdd_q95 {
        d if d > 60.0 => "High tolerance for extended drought (populations exist with 60+ consecutive dry days)",
        d if d > 30.0 => "Tolerates month-long dry spells (populations exist with CDD >30)",
        d if d > 14.0 => "Tolerates 2-week dry periods (populations exist with CDD up to 30)",
        _ => "Limited dry spell tolerance (no populations in prolonged-drought areas)",
    };

    let watering_advice = match (bio_14_q05, cdd_q95) {
        (p, _) if p < 10.0 => "Highly drought-adapted; water sparingly; overwatering harmful",
        (p, d) if p < 30.0 || d > 30.0 => "Drought-tolerant once established; deep infrequent watering",
        (p, _) if p < 50.0 => "Moderate water needs; water during dry spells",
        _ => "Regular watering required; don't allow to dry out",
    };

    DroughtInfo {
        driest_month,
        driest_quarter,
        consecutive_dry_days: consecutive_dry,
        typical_drought_regime: typical_drought_regime.into(),
        drought_tolerance: drought_tolerance.into(),
        typical_dry_spells: typical_dry_spells.into(),
        dry_spell_tolerance: dry_spell_tolerance.into(),
        watering_advice: watering_advice.into(),
    }
}
```

**Output Format**:
```
**Drought Tolerance** (from natural occurrence range)
   Driest month: 8mm to 45mm (median 22mm)
   Driest quarter: 35mm to 150mm (median 85mm)
   Consecutive dry days: 15 to 45 days (median 28)
   Typical regime: Typically occurs in climates with pronounced dry season
   Drought tolerance: Moderate drought tolerance (populations exist where driest month <30mm)
   Typical dry spells: Typically experiences moderate dry spells (median CDD 14-30 days)
   Dry spell tolerance: Tolerates month-long dry spells (populations exist with CDD >30)
   → Drought-tolerant once established; deep infrequent watering
```

### 3.15 Summer Precipitation (Irrigation Planning)

**Data Source**: `wc2.1_30s_bio_18_q05/q50/q95` (Precipitation of Warmest Quarter, mm)

**Scientific Basis**: BIO_18 indicates rainfall during the growing season's warmest months - critical for irrigation planning. Plants from summer-dry climates (Mediterranean) differ from those from summer-wet climates (monsoon).

**Algorithm**:

```rust
fn describe_summer_precipitation(
    bio_18_q05: f64, bio_18_q50: f64, bio_18_q95: f64,
) -> SummerPrecipInfo {
    let range_description = format!(
        "{:.0}mm to {:.0}mm in warmest quarter (median {:.0}mm)",
        bio_18_q05, bio_18_q95, bio_18_q50
    );

    // q50: Typical summer rainfall regime where plant naturally occurs
    let typical_summer_regime = match bio_18_q50 {
        p if p < 50.0 => "Typically occurs in summer-dry climates (Mediterranean pattern; BIO_18 <50mm)",
        p if p < 150.0 => "Typically occurs in climates with moderate summer rainfall",
        p if p < 300.0 => "Typically occurs in summer-wet climates",
        _ => "Typically occurs in monsoon/high summer rainfall climates (BIO_18 >300mm)",
    };

    // q05: Summer drought tolerance - driest summer conditions where populations exist
    let summer_drought_tolerance = match bio_18_q05 {
        p if p < 30.0 => "High summer drought tolerance (populations survive with <30mm in warmest quarter)",
        p if p < 100.0 => "Moderate summer drought tolerance (populations exist with 30-100mm summer rainfall)",
        p if p < 200.0 => "Limited summer drought tolerance (populations need >100mm in summer)",
        _ => "No summer drought tolerance (populations require >200mm in warmest quarter)",
    };

    // q95: Wet summer tolerance - wettest summer conditions where populations exist
    let wet_summer_tolerance = match bio_18_q95 {
        p if p > 400.0 => "Tolerates high summer rainfall (populations exist with >400mm summer)",
        p if p > 250.0 => "Tolerates wet summers (populations exist with 250-400mm summer)",
        _ => "Prefers drier summers (no populations in wet-summer areas)",
    };

    let irrigation_advice = match bio_18_q05 {
        p if p < 30.0 => "Adapted to dry summers; minimal irrigation once established; avoid overwatering",
        p if p < 100.0 => "Tolerates summer drought; occasional deep watering beneficial",
        p if p < 200.0 => "Moderate summer water needs; regular irrigation in dry spells",
        _ => "High summer water needs; maintain consistent moisture",
    };

    SummerPrecipInfo {
        natural_range: range_description,
        typical_summer_regime: typical_summer_regime.into(),
        summer_drought_tolerance: summer_drought_tolerance.into(),
        wet_summer_tolerance: wet_summer_tolerance.into(),
        irrigation_advice: irrigation_advice.into(),
    }
}
```

**Output Format**:
```
**Summer Precipitation** (from natural occurrence range)
   Warmest quarter: 45mm to 220mm (median 110mm)
   Typical regime: Typically occurs in climates with moderate summer rainfall
   Summer drought tolerance: Moderate summer drought tolerance (populations exist with 30-100mm summer rainfall)
   Wet summer tolerance: Tolerates wet summers (populations exist with 250-400mm summer)
   → Tolerates summer drought; occasional deep watering beneficial
```

---

## 4. Soil Envelope from Natural Occurrence Data

### 4.1 Data Provenance and Interpretation

**Critical Understanding**: Like the climate data, SoilGrids data in Phase 0 are **derived from aggregated plant occurrence coordinates**. For each occurrence point, we extract the underlying soil properties from SoilGrids 2.0, then aggregate across all occurrences to produce:

- **q05**: 5th percentile (lower extreme of the distribution)
- **q50**: Median (typical soil conditions where the plant is found)
- **q95**: 95th percentile (upper extreme of the distribution)

**Interpretation**: These values describe the **edaphic envelope** where the plant naturally occurs and thrives. The q05 and q95 represent the extremes of tolerance, while q50 represents typical conditions. For example:
- pH: q05 = most acidic locations, q95 = most alkaline locations
- Clay %: q05 = sandiest locations, q95 = heaviest clay locations
- A plant with pH_q50 = 6.5 is typically found in slightly acidic to neutral soils

**Data available at 6 depth layers**: 0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm. For horticultural purposes, the 0-5cm (topsoil) layer is primary; deeper layers relevant for trees and deep-rooted perennials.

### 4.2 Soil Texture from Natural Range

**Scientific Basis**: SoilGrids provides clay and sand percentages at occurrence locations. The texture range indicates what soil types the plant naturally tolerates.

**Data Source**: `clay_0_5cm_q05/q50/q95`, `sand_0_5cm_q05/q50/q95` (topsoil layer most relevant for gardening)

**Algorithm**:

```rust
/// Describe soil texture preferences from natural occurrence range
fn describe_texture_preference(
    clay_q05: f64, clay_q50: f64, clay_q95: f64,
    sand_q05: f64, sand_q50: f64, sand_q95: f64,
) -> TexturePreference {
    // Classify typical texture from median values
    let typical_texture = classify_texture(clay_q50, sand_q50);

    // Range description
    let clay_range = format!("{}% to {}% clay (median {}%)",
        clay_q05.round(), clay_q95.round(), clay_q50.round());
    let sand_range = format!("{}% to {}% sand (median {}%)",
        sand_q05.round(), sand_q95.round(), sand_q50.round());

    // q50: Typical texture regime where plant occurs
    let typical_regime = match (clay_q50, sand_q50) {
        (c, _) if c > 35.0 => "Typically occurs in heavy clay soils",
        (c, s) if c > 25.0 && s < 40.0 => "Typically occurs in clay loam soils",
        (_, s) if s > 70.0 => "Typically occurs in sandy soils",
        (_, s) if s > 50.0 => "Typically occurs in sandy loam soils",
        _ => "Typically occurs in loamy soils (balanced texture)",
    };

    // q95 clay: Heavy soil tolerance - clay-rich edge of range
    let heavy_soil_tolerance = match clay_q95 {
        c if c > 45.0 => "Tolerates heavy clay (populations exist in soils with >45% clay)",
        c if c > 35.0 => "Tolerates clay soils (populations exist in soils with >35% clay)",
        c if c > 25.0 => "Moderate clay tolerance (populations exist in soils up to 25-35% clay)",
        _ => "Limited clay tolerance (no populations in heavy soils)",
    };

    // q95 sand: Light soil tolerance - sandy edge of range
    let light_soil_tolerance = match sand_q95 {
        s if s > 80.0 => "Tolerates very sandy soils (populations exist in soils with >80% sand)",
        s if s > 65.0 => "Tolerates sandy soils (populations exist in soils with >65% sand)",
        s if s > 50.0 => "Moderate sand tolerance (populations exist in soils up to 50-65% sand)",
        _ => "Limited sand tolerance (no populations in very light soils)",
    };

    // Texture breadth assessment
    let texture_flexibility = if (clay_q95 - clay_q05) > 25.0 || (sand_q95 - sand_q05) > 40.0 {
        "Broad texture tolerance; adaptable to various soil types"
    } else if (clay_q95 - clay_q05) > 15.0 || (sand_q95 - sand_q05) > 25.0 {
        "Moderate texture flexibility"
    } else {
        "Narrow texture preference; match soil conditions carefully"
    };

    TexturePreference {
        typical_texture,
        clay_range,
        sand_range,
        typical_regime: typical_regime.into(),
        heavy_soil_tolerance: heavy_soil_tolerance.into(),
        light_soil_tolerance: light_soil_tolerance.into(),
        texture_flexibility: texture_flexibility.into(),
    }
}

/// Classify soil texture from clay and sand percentages (USDA Triangle)
fn classify_texture(clay_pct: f64, sand_pct: f64) -> &'static str {
    if sand_pct >= 85.0 && clay_pct < 10.0 { "Sand" }
    else if sand_pct >= 70.0 && clay_pct < 15.0 { "Loamy sand" }
    else if clay_pct >= 40.0 { "Clay" }
    else if clay_pct >= 35.0 && sand_pct < 45.0 { "Silty clay" }
    else if clay_pct >= 27.0 && sand_pct < 20.0 { "Silty clay loam" }
    else if clay_pct >= 27.0 { "Clay loam" }
    else if sand_pct >= 50.0 && clay_pct < 20.0 { "Sandy loam" }
    else { "Loam" }
}
```

**Output Format**:
```
**Soil Texture** (from natural occurrence range)
   Clay: 12% to 35% (median 22%)
   Sand: 25% to 55% (median 38%)
   Typical texture: Loam
   Typical regime: Typically occurs in loamy soils (balanced texture)
   Heavy soil tolerance: Moderate clay tolerance (populations exist in soils up to 25-35% clay)
   Light soil tolerance: Moderate sand tolerance (populations exist in soils up to 50-65% sand)
   Flexibility: Moderate texture flexibility
```

### 4.3 Soil pH from Natural Range

**Data Source**: `phh2o_0_5cm_q05/q50/q95` (pH in water, 0-14 scale × 10)

**Scientific Basis**: pH is a bidirectional variable - both acid (low pH) and alkaline (high pH) extremes are horticulturally significant. Calcifuge plants (acid-loving) will fail in alkaline soils; calcicole plants (lime-loving) struggle in acid conditions.

**Algorithm**:

```rust
/// Describe soil pH preferences from natural occurrence range
/// Note: SoilGrids pH values are stored as pH × 10 (so 65 = pH 6.5)
fn describe_ph_preference(ph_q05: f64, ph_q50: f64, ph_q95: f64) -> PhPreference {
    // Convert from SoilGrids format (×10) to actual pH
    let ph_q05 = ph_q05 / 10.0;
    let ph_q50 = ph_q50 / 10.0;
    let ph_q95 = ph_q95 / 10.0;

    // q50: Typical pH regime where plant occurs
    let typical_ph_regime = match ph_q50 {
        p if p < 5.0 => "Typically occurs in strongly acid soils (calcifuge; pH <5.0)",
        p if p < 5.5 => "Typically occurs in moderately acid soils (pH 5.0-5.5)",
        p if p < 6.5 => "Typically occurs in slightly acid soils (pH 5.5-6.5)",
        p if p < 7.5 => "Typically occurs in neutral soils (pH 6.5-7.5)",
        p if p < 8.0 => "Typically occurs in slightly alkaline soils (pH 7.5-8.0)",
        _ => "Typically occurs in alkaline/calcareous soils (calcicole; pH >8.0)",
    };

    // q05: Acid tolerance - most acidic edge of range
    let acid_tolerance = match ph_q05 {
        p if p < 4.5 => "Tolerates very acid soils (populations exist at pH <4.5)",
        p if p < 5.0 => "Tolerates strongly acid soils (populations exist at pH <5.0)",
        p if p < 5.5 => "Tolerates moderately acid soils (populations exist at pH 5.0-5.5)",
        p if p < 6.0 => "Tolerates slightly acid soils (populations exist at pH 5.5-6.0)",
        _ => "Limited acid tolerance (no populations in acid soils below pH 6.0)",
    };

    // q95: Alkaline tolerance - most alkaline edge of range
    let alkaline_tolerance = match ph_q95 {
        p if p > 8.5 => "Tolerates strongly alkaline soils (populations exist at pH >8.5)",
        p if p > 8.0 => "Tolerates alkaline/calcareous soils (populations exist at pH >8.0)",
        p if p > 7.5 => "Tolerates slightly alkaline soils (populations exist at pH 7.5-8.0)",
        p if p > 7.0 => "Tolerates neutral to slightly alkaline (populations exist at pH 7.0-7.5)",
        _ => "Limited alkaline tolerance (no populations in soils above pH 7.0)",
    };

    // pH range breadth
    let ph_flexibility = if (ph_q95 - ph_q05) > 2.0 {
        "Wide pH tolerance; adaptable to most garden soils"
    } else if (ph_q95 - ph_q05) > 1.0 {
        "Moderate pH flexibility"
    } else {
        "Narrow pH preference; match soil pH carefully"
    };

    // Practical gardening advice
    let soil_management = match (ph_q05, ph_q95) {
        (low, _) if low < 5.0 && ph_q50 < 5.5 =>
            "Ericaceous compost required; avoid lime; use rainwater if tap water is alkaline",
        (_, high) if high > 8.0 && ph_q50 > 7.0 =>
            "Thrives on chalk/limestone; can add lime to acid soils",
        (low, high) if (high - low) > 2.0 =>
            "Adaptable; standard multi-purpose compost suitable for most conditions",
        _ => "Standard to slightly acid compost; most garden soils suitable",
    };

    PhPreference { /* fields */ }
}
```

**Output Format**:
```
**Soil pH** (from natural occurrence range)
   pH range: 5.2 to 7.8 (median 6.4)
   Typical regime: Typically occurs in slightly acid soils (pH 5.5-6.5)
   Acid tolerance: Tolerates moderately acid soils (populations exist at pH 5.0-5.5)
   Alkaline tolerance: Tolerates slightly alkaline soils (populations exist at pH 7.5-8.0)
   Flexibility: Wide pH tolerance; adaptable to most garden soils
   → Standard to slightly acid compost; most garden soils suitable
```

### 4.4 Soil Organic Carbon from Natural Range

**Data Source**: `soc_0_5cm_q05/q50/q95` (g/kg)

**Scientific Basis**: Soil organic carbon (SOC) indicates the organic matter content of soils where the plant naturally occurs. Plants adapted to high-SOC soils often have higher nutrient demands; plants from mineral soils may be harmed by excessive organic matter.

**Algorithm**: Uses q50 for typical regime, q05 for lean soil tolerance, q95 for organic-rich tolerance.

**Output Format**:
```
**Soil Organic Carbon** (from natural occurrence range)
   SOC range: 12g/kg to 45g/kg (median 24g/kg)
   Typical regime: Typically occurs in humus-rich soils (20-40 g/kg SOC)
   Lean soil tolerance: Tolerates lean soils (populations exist where SOC <15 g/kg)
   Organic-rich tolerance: Tolerates humus-rich conditions (populations exist where SOC >30 g/kg)
   → Standard garden soil with annual compost mulch suitable
```

### 4.5 Cation Exchange Capacity (CEC) from Natural Range

**Data Source**: `cec_0_5cm_q05/q50/q95` (cmol(+)/kg)

**Scientific Basis**: CEC indicates the soil's nutrient-holding capacity. High CEC soils retain nutrients well (clay, organic-rich); low CEC soils (sandy) leach nutrients quickly.

**Output Format**:
```
**Soil Fertility (CEC)** (from natural occurrence range)
   CEC range: 8 to 28 cmol/kg (median 16)
   Typical regime: Typically occurs in moderate fertility soils (CEC 10-20 cmol/kg)
   Low fertility tolerance: Tolerates low fertility soils (populations exist where CEC <10 cmol/kg)
   High fertility tolerance: Tolerates fertile soils (populations exist where CEC >25 cmol/kg)
   → Regular feeding schedule; standard garden practices appropriate
```

### 4.6 Bulk Density from Natural Range

**Data Source**: `bdod_0_5cm_q05/q50/q95` (cg/cm³, divide by 100 for g/cm³)

**Scientific Basis**: Bulk density indicates soil compaction and porosity. Low bulk density soils are well-aerated (organic-rich, loose); high bulk density indicates compacted or heavy mineral soils. Root growth is impaired above ~1.6 g/cm³ for most plants.

**Output Format**:
```
**Soil Structure (Bulk Density)** (from natural occurrence range)
   Bulk density: 1.05 to 1.48 g/cm³ (median 1.28)
   Typical regime: Typically occurs in moderately structured soils (BD 1.2-1.4)
   Loose soil tolerance: Tolerates loose soils (populations exist where BD <1.0)
   Compaction tolerance: Moderate compaction tolerance (populations exist where BD >1.4)
   → Standard garden soil suitable; maintain structure with organic matter
```

### 4.7 Soil Nitrogen from Natural Range

**Data Source**: `nitrogen_0_5cm_q05/q50/q95` (g/kg total nitrogen)

**Scientific Basis**: Total soil nitrogen indicates nitrogen availability. Plants from high-N soils typically have higher growth rates and nutrient demands; plants from low-N soils may be nitrogen-sensitive and prone to lush, weak growth when over-fertilized.

**Output Format**:
```
**Soil Nitrogen** (from natural occurrence range)
   Total N: 1.2g/kg to 4.8g/kg (median 2.6g/kg)
   Typical regime: Typically occurs in moderate nitrogen soils (2-4 g/kg N)
   Low N tolerance: Tolerates low nitrogen soils (populations exist where N <1 g/kg)
   High N tolerance: Tolerates nitrogen-rich soils (populations exist where N >6 g/kg)
   → Standard nitrogen needs; balanced NPK fertilizer appropriate
```

### 4.8 Integration: Soil Summary for Gardeners

Combine soil metrics into a practical summary highlighting the most horticulturally relevant tolerance information:

**Output Format**:
```
**Soil Summary** (from natural occurrence range)
   Texture: Loam (moderate flexibility)
   pH: 5.2 to 7.8 (median 6.4) - wide tolerance
   Key tolerances: acid-tolerant, clay-tolerant
   → Standard to slightly acid compost; most garden soils suitable
```

### 4.9 Relationship with EIVE Indicators

The occurrence-derived soil data (SoilGrids) and EIVE indicators provide complementary information:

| Source | Measures | Best For |
|--------|----------|----------|
| **SoilGrids occurrence data** | Actual soil properties where plant grows | Objective tolerance ranges; "what soils does it survive in?" |
| **EIVE-R (Reaction)** | Ecological pH niche from vegetation science | Relative pH preference; competitive advantage |
| **EIVE-N (Nitrogen)** | Ecological fertility niche | Feeding requirements; growth rate expectations |

**Integration guidance**:
- Use SoilGrids pH range (q05-q95) for "will it survive in my soil?"
- Use EIVE-R for "will it thrive and compete well?"
- Use SoilGrids nitrogen + EIVE-N together for feeding schedules
- When SoilGrids shows wide tolerance but EIVE shows strong preference, the plant survives broadly but performs best in preferred conditions

---

# Part II: Ecological Indicator Values (EIVE)


### 5.6 Why EIVE Complements Raw Environmental Data

| Aspect | Raw Environmental Envelope | EIVE |
|--------|---------------------------|------|
| **Measures** | Actual conditions at occurrence points | Competitive optimum in communities |
| **Scale** | Absolute values (°C, mm, pH) | Relative 0-10 scale |
| **Biotic context** | None (abiotic only) | Includes competition/facilitation |
| **Best for** | Survival limits, matching to garden conditions | Optimal growing conditions, plant behaviour |
| **Precision** | Quantitative, directly measurable | Ordinal, expert-calibrated |

**Practical example**:
- Environmental envelope says: "Survives -15°C to +35°C, 400-1200mm rainfall"
- EIVE says: "EIVE-T=6 (warmth-loving), EIVE-M=4 (moderately dry)"
- Together: "Mediterranean plant that survives temperate winters but thrives in warm, somewhat dry conditions"

---

### 4.1 EIVE-L (Light) - Pre-computed Semantic Bins

The lookup table maps continuous EIVE-L values (0-10) to 9 ecological classes:

| Class | EIVE-L Range | Ecological Label |
|-------|--------------|------------------|
| 1 | 0.00 - 1.61 | deep shade plant (<1% relative illumination) |
| 2 | 1.61 - 2.44 | between deep shade and shade |
| 3 | 2.44 - 3.20 | shade plant (mostly <5% relative illumination) |
| 4 | 3.20 - 4.23 | between shade and semi-shade |
| 5 | 4.23 - 5.45 | semi-shade plant (>10% illumination, seldom full light) |
| 6 | 5.45 - 6.50 | between semi-shade and semi-sun |
| 7 | 6.50 - 7.47 | half-light plant (mostly well lit but tolerates shade) |
| 8 | 7.47 - 8.37 | light-loving plant (rarely <40% illumination) |
| 9 | 8.37 - 10.0 | full-light plant (requires full sun) |

**Algorithm** (uses lookup table directly):

```rust
fn get_light_advice(eive_l: f64) -> LightAdvice {
    // Get semantic label from pre-computed bins
    let label = get_eive_label(eive_l, EiveAxis::Light)
        .unwrap_or("Unknown light preference");
    let class = get_eive_class(eive_l, EiveAxis::Light).unwrap_or(5);

    // Translate to garden placement advice
    let garden_placement = match class {
        1..=2 => "Plant under dense evergreen canopy or north-facing walls; avoid any direct sun",
        3..=4 => "Woodland floor, shaded border, or east-facing position; dappled light ideal",
        5..=6 => "Open woodland edge, filtered light, or morning sun with afternoon shade",
        7 => "Well-lit positions; tolerates light shade but performs better with good light",
        8 => "Sunny border or south-facing position; open exposure preferred",
        9 => "Full sun essential; hot, exposed positions; maximum light required",
        _ => "Adaptable to various light conditions",
    };

    LightAdvice {
        eive_value: eive_l,
        class,
        ecological_label: label.into(),
        garden_placement: garden_placement.into(),
    }
}
```

### 4.2 EIVE-M (Moisture) - Pre-computed Semantic Bins

The lookup table maps continuous EIVE-M values (0-10) to 11 ecological classes:

| Class | EIVE-M Range | Ecological Label |
|-------|--------------|------------------|
| 1 | 0.00 - 1.51 | indicator of extreme dryness; soils often dry out |
| 2 | 1.51 - 2.47 | very dry sites; shallow soils or sand |
| 3 | 2.47 - 3.22 | dry-site indicator; more often on dry ground |
| 4 | 3.22 - 3.95 | moderately dry; also in dry sites with humidity |
| 5 | 3.95 - 4.69 | fresh/mesic soils of average dampness |
| 6 | 4.69 - 5.39 | moist; upper range of fresh soils |
| 7 | 5.39 - 6.07 | constantly moist or damp but not wet |
| 8 | 6.07 - 6.78 | moist to wet; tolerates short inundation |
| 9 | 6.78 - 7.54 | wet, water-saturated poorly aerated soils |
| 10 | 7.54 - 8.40 | shallow water sites; often temporarily flooded |
| 11 | 8.40 - 10.0 | rooted in water, emergent or floating |

**Algorithm** (uses lookup table directly):

```rust
fn get_moisture_advice(eive_m: f64, s_score: Option<f64>) -> MoistureAdvice {
    let label = get_eive_label(eive_m, EiveAxis::Moisture)
        .unwrap_or("Unknown moisture preference");
    let class = get_eive_class(eive_m, EiveAxis::Moisture).unwrap_or(5);

    let watering_schedule = match class {
        1..=2 => "Minimal watering; once every 2-3 weeks in drought; allow soil to dry completely",
        3..=4 => "Sparse watering; weekly in summer drought; none needed in winter",
        5..=6 => "Regular watering; 1-2 times weekly during growing season; reduce in cool weather",
        7..=8 => "Frequent watering; keep consistently moist; mulch to retain moisture",
        9..=11 => "Constant moisture; bog garden, pond margin, or water feature required",
        _ => "Moderate watering based on soil conditions",
    };

    let mut advice = MoistureAdvice {
        eive_value: eive_m,
        class,
        ecological_label: label.into(),
        watering_schedule: watering_schedule.into(),
        stress_tolerator_note: None,
    };

    // Add stress-tolerator modifier if applicable
    if let Some(s) = s_score {
        if s > 0.5 && class <= 6 {
            advice.stress_tolerator_note = Some(
                "Stress-tolerator: exceptionally drought-hardy once established".into()
            );
        }
    }

    advice
}
```

### 4.3 EIVE-T (Temperature) - Pre-computed Semantic Bins

The lookup table maps continuous EIVE-T values (0-10) to 12 ecological classes:

| Class | EIVE-T Range | Ecological Label |
|-------|--------------|------------------|
| 1 | 0.00 - 0.91 | very cold climates (high alpine / arctic-boreal) |
| 2 | 0.91 - 1.81 | cold alpine to subalpine zones |
| 3 | 1.81 - 2.74 | cool; mainly subalpine and high montane |
| 4 | 2.74 - 3.68 | rather cool montane climates |
| 5 | 3.68 - 4.43 | moderately cool to moderately warm (montane-submontane) |
| 6 | 4.43 - 5.09 | submontane / colline; mild montane |
| 7 | 5.09 - 5.94 | warm; colline, extending to mild northern areas |
| 8 | 5.94 - 6.84 | warm-submediterranean to mediterranean core |
| 9 | 6.84 - 7.74 | very warm; southern-central European lowlands |
| 10 | 7.74 - 8.50 | hot-submediterranean; warm Mediterranean foothills |
| 11 | 8.50 - 9.21 | hot Mediterranean lowlands |
| 12 | 9.21 - 10.0 | very hot / subtropical Mediterranean extremes |

**Algorithm**:

```rust
fn get_temperature_advice(eive_t: f64) -> TemperatureAdvice {
    let label = get_eive_label(eive_t, EiveAxis::Temperature)
        .unwrap_or("Unknown temperature preference");
    let class = get_eive_class(eive_t, EiveAxis::Temperature).unwrap_or(6);

    let climate_suitability = match class {
        1..=3 => "Cool-climate specialist; best in northern gardens or high altitude; struggles in warm summers",
        4..=6 => "Temperate climate adapted; thrives in most UK/northern European gardens",
        7..=8 => "Warm climate preference; ideal for southern UK, sheltered positions in north",
        9..=10 => "Mediterranean climate adapted; requires warm, sunny position; protect from frost",
        11..=12 => "Hot climate specialist; greenhouse or conservatory in temperate regions",
        _ => "Adaptable to various temperature regimes",
    };

    TemperatureAdvice {
        eive_value: eive_t,
        class,
        ecological_label: label.into(),
        climate_suitability: climate_suitability.into(),
    }
}
```

### 4.4 EIVE-N (Nitrogen/Fertility) - Pre-computed Semantic Bins

The lookup table maps continuous EIVE-N values (0-10) to 9 ecological classes:

| Class | EIVE-N Range | Ecological Label |
|-------|--------------|------------------|
| 1 | 0.00 - 1.98 | extremely infertile, oligotrophic sites |
| 2 | 1.98 - 2.77 | very low fertility |
| 3 | 2.77 - 3.71 | infertile to moderately poor soils |
| 4 | 3.71 - 4.79 | moderately poor; low fertility |
| 5 | 4.79 - 5.71 | intermediate fertility |
| 6 | 5.71 - 6.60 | moderately rich soils |
| 7 | 6.60 - 7.47 | rich, eutrophic sites |
| 8 | 7.47 - 8.35 | very rich, high nutrient supply |
| 9 | 8.35 - 10.0 | extremely rich; manure or waste sites |

**Algorithm**:

```rust
fn get_fertility_advice(eive_n: f64, c_score: Option<f64>) -> FertilityAdvice {
    let label = get_eive_label(eive_n, EiveAxis::Nitrogen)
        .unwrap_or("Unknown fertility preference");
    let class = get_eive_class(eive_n, EiveAxis::Nitrogen).unwrap_or(5);

    let feeding_schedule = match class {
        1..=2 => "No feeding required; avoid fertilizer which causes weak, leggy growth",
        3..=4 => "Light annual feed in spring; avoid excess nitrogen; lean compost preferred",
        5..=6 => "Standard feeding; balanced NPK in spring with optional summer top-up",
        7..=8 => "Heavy feeder; monthly balanced feed during growing season; rich compost beneficial",
        9 => "Very heavy feeder; weekly liquid feed; annual compost mulch (50mm); intensive care",
        _ => "Moderate feeding based on soil conditions",
    };

    let mut advice = FertilityAdvice {
        eive_value: eive_n,
        class,
        ecological_label: label.into(),
        feeding_schedule: feeding_schedule.into(),
        competitor_note: None,
    };

    // Add competitor modifier if applicable
    if let Some(c) = c_score {
        if c > 0.5 && class >= 5 {
            advice.competitor_note = Some(
                "Competitive strategy: responds vigorously to feeding; benefits from rich conditions".into()
            );
        }
    }

    advice
}
```

### 4.5 EIVE-R (Reaction/pH) - Pre-computed Semantic Bins

The lookup table maps continuous EIVE-R values (0-10) to 9 ecological classes:

| Class | EIVE-R Range | Ecological Label |
|-------|--------------|------------------|
| 1 | 0.00 - 1.82 | strongly acidic substrates only |
| 2 | 1.82 - 2.73 | very acidic, seldom on less acidic soils |
| 3 | 2.73 - 3.50 | acid indicator; mainly acid soils |
| 4 | 3.50 - 4.42 | slightly acidic; between acid and moderately acid |
| 5 | 4.42 - 5.41 | moderately acidic soils; occasional neutral/basic |
| 6 | 5.41 - 6.38 | slightly acidic to neutral |
| 7 | 6.38 - 7.24 | weakly acidic to weakly basic; absent from very acid |
| 8 | 7.24 - 8.05 | between weakly basic and basic |
| 9 | 8.05 - 10.0 | basic/alkaline; calcareous substrates |

**Algorithm**:

```rust
fn get_ph_advice(eive_r: f64) -> PhAdvice {
    let label = get_eive_label(eive_r, EiveAxis::Reaction)
        .unwrap_or("Unknown pH preference");
    let class = get_eive_class(eive_r, EiveAxis::Reaction).unwrap_or(5);

    let (target_ph, soil_management) = match class {
        1..=2 => ("pH 4.0-5.0", "Use ericaceous (lime-free) compost only; rainwater preferred; never add lime"),
        3..=4 => ("pH 5.0-6.0", "Ericaceous compost recommended; avoid chalky or alkaline soils"),
        5..=6 => ("pH 5.5-7.0", "Standard multi-purpose compost suitable; adaptable to most garden soils"),
        7 => ("pH 6.5-7.5", "Neutral soil ideal; tolerates slight acidity or alkalinity"),
        8..=9 => ("pH 7.5-8.5", "Thrives on chalk/limestone; add lime to acid soils if needed"),
        _ => ("pH 6.0-7.0", "Adaptable to various pH conditions"),
    };

    PhAdvice {
        eive_value: eive_r,
        class,
        ecological_label: label.into(),
        target_ph: target_ph.into(),
        soil_management: soil_management.into(),
    }
}
```

### 4.6 Complementary Use with Environmental Envelope Data

EIVE indicators and occurrence-derived climate data provide complementary information:

- **EIVE indicators**: Ecological niche preferences derived from vegetation science (where the plant is found relative to other plants)
- **Climate occurrence data**: Actual climatic envelope from georeferenced occurrences (absolute temperature, precipitation values)

Both should be presented to give gardeners a complete picture:
- EIVE-M tells us the plant prefers "moist but not wet" conditions
- Climate precipitation data tells us the plant occurs where annual rainfall is 600-1200mm
