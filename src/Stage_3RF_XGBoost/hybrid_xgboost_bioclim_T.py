#!/usr/bin/env python3

"""
Hybrid Trait-Bioclim XGBoost Model for Temperature (EIVE-T)

Adapted from run_xgboost_regression.py to integrate bioclim data
with trait-based modeling following the structured regression approach.

This implements:
1. Bioclim niche metric calculation from occurrence data
2. XGBoost for feature discovery and prediction
3. Model comparison (traits-only vs hybrid)
4. Feature importance analysis
"""

import argparse
import json
import os
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import StratifiedKFold, KFold
import xgboost as xgb


# Configuration
TARGET_COL = "EIVEres-T"

FEATURE_COLS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "LMA (g/m2)",
    "Plant height (m)",
    "Diaspore mass (mg)",
    "SSD used (mg/mm3)",
]

LOG_VARS = {
    "Leaf area (mm2)",
    "Diaspore mass (mg)",
    "Plant height (m)",
    "SSD used (mg/mm3)",
}


def compute_offset(series: pd.Series) -> float:
    """Compute offset for log transformation."""
    x = pd.to_numeric(series, errors="coerce")
    x = x[(x > 0) & np.isfinite(x)]
    if x.empty:
        return 1e-6
    return float(max(1e-6, 1e-3 * float(np.median(x))))


def calculate_bioclim_metrics(bioclim_dir: str, min_occurrences: int = 30) -> pd.DataFrame:
    """Calculate species-level climate niche metrics from bioclim CSV files."""
    
    print("Calculating bioclim niche metrics...")
    
    bioclim_path = Path(bioclim_dir)
    bioclim_files = list(bioclim_path.glob("*_bioclim.csv"))
    
    metrics_list = []
    
    for file in bioclim_files:
        species_name = file.stem.replace("_bioclim", "").replace("_", " ")
        
        try:
            bio_data = pd.read_csv(file)
            bio_data = bio_data[bio_data['bio1'].notna()]
            
            if len(bio_data) < min_occurrences:
                continue
                
            metrics = {
                'species': species_name,
                'n_occurrences': len(bio_data),
                
                # Temperature metrics (key for T axis)
                'mat_mean': bio_data['bio1'].mean(),
                'mat_sd': bio_data['bio1'].std(),
                'mat_q05': bio_data['bio1'].quantile(0.05),
                'mat_q95': bio_data['bio1'].quantile(0.95),
                'temp_seasonality': bio_data['bio4'].mean(),
                'temp_range': bio_data['bio7'].mean(),
                'tmax_mean': bio_data['bio5'].mean(),
                'tmin_mean': bio_data['bio6'].mean(),
                'tmin_q05': bio_data['bio6'].quantile(0.05),
                
                # Some moisture metrics for interactions
                'precip_mean': bio_data['bio12'].mean(),
                'precip_cv': bio_data['bio12'].std() / bio_data['bio12'].mean() if bio_data['bio12'].mean() > 0 else 0,
            }
            
            metrics_list.append(metrics)
            
        except Exception as e:
            print(f"Error processing {species_name}: {e}")
            continue
    
    climate_df = pd.DataFrame(metrics_list)
    print(f"Calculated metrics for {len(climate_df)} species")
    
    return climate_df


def prepare_features(trait_data: pd.DataFrame, climate_data: pd.DataFrame) -> Tuple[pd.DataFrame, pd.Series]:
    """Prepare hybrid feature set combining traits and climate."""
    
    # Normalize species names for matching
    trait_data['species_clean'] = trait_data['wfo_accepted_name'].str.lower().str.replace(' ', '_')
    climate_data['species_clean'] = climate_data['species'].str.lower().str.replace(' ', '_')
    
    # Merge data
    merged = trait_data.merge(climate_data, on='species_clean', how='inner')
    print(f"Merged data: {len(merged)} species with both traits and climate")
    
    # Calculate offsets for log transformation
    offsets = {col: compute_offset(merged[col]) for col in LOG_VARS}
    
    # Create trait features
    features = pd.DataFrame()
    
    # Log-transformed traits
    features['logLA'] = np.log10(merged['Leaf area (mm2)'] + offsets['Leaf area (mm2)'])
    features['logH'] = np.log10(merged['Plant height (m)'] + offsets['Plant height (m)'])
    features['logSM'] = np.log10(merged['Diaspore mass (mg)'] + offsets['Diaspore mass (mg)'])
    features['logSSD'] = np.log10(merged['SSD used (mg/mm3)'] + offsets['SSD used (mg/mm3)'])
    
    # Direct traits
    features['Nmass'] = merged['Nmass (mg/g)']
    features['LMA'] = merged['LMA (g/m2)']
    
    # Composite traits
    features['LES_core'] = -features['LMA'] + (features['Nmass'] - features['Nmass'].mean()) / features['Nmass'].std()
    features['SIZE'] = ((features['logH'] - features['logH'].mean()) / features['logH'].std() + 
                       (features['logSM'] - features['logSM'].mean()) / features['logSM'].std())
    
    # Climate features
    climate_cols = ['mat_mean', 'mat_sd', 'temp_seasonality', 'temp_range', 
                   'tmin_q05', 'precip_mean', 'precip_cv']
    for col in climate_cols:
        if col in merged.columns:
            features[col] = merged[col]
    
    # Interactions
    features['size_temp'] = features['SIZE'] * features['mat_mean']
    features['height_temp'] = features['logH'] * features['mat_mean']
    features['les_seasonality'] = features['LES_core'] * features['temp_seasonality']
    features['wood_cold'] = features['logSSD'] * features['tmin_q05']
    
    # Target
    y = merged[TARGET_COL]
    
    # Remove rows with missing values
    complete_idx = features.notna().all(axis=1) & y.notna()
    features = features[complete_idx]
    y = y[complete_idx]
    
    print(f"Final dataset: {len(y)} observations, {len(features.columns)} features")
    
    return features, y


def run_cv_comparison(X: pd.DataFrame, y: pd.Series, n_splits: int = 10, n_repeats: int = 5) -> pd.DataFrame:
    """Run cross-validation comparing different feature sets."""
    
    results = []
    
    # Define feature sets
    trait_features = ['logLA', 'logH', 'logSM', 'logSSD', 'Nmass', 'LMA', 'LES_core', 'SIZE']
    climate_features = ['mat_mean', 'mat_sd', 'temp_seasonality', 'temp_range', 
                       'tmin_q05', 'precip_mean', 'precip_cv']
    interaction_features = ['size_temp', 'height_temp', 'les_seasonality', 'wood_cold']
    
    feature_sets = {
        'traits_only': trait_features,
        'traits_climate': trait_features + climate_features,
        'full_hybrid': trait_features + climate_features + interaction_features
    }
    
    # XGBoost parameters
    xgb_params = {
        'objective': 'reg:squarederror',
        'max_depth': 6,
        'learning_rate': 0.1,
        'n_estimators': 500,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'random_state': 42,
        'n_jobs': -1
    }
    
    for repeat in range(n_repeats):
        print(f"Repeat {repeat + 1}/{n_repeats}")
        
        # Create stratified folds based on target quantiles
        y_bins = pd.qcut(y, q=10, labels=False)
        skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42 + repeat)
        
        for fold_idx, (train_idx, test_idx) in enumerate(skf.split(X, y_bins)):
            X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
            y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]
            
            # Standardize features
            train_means = X_train.mean()
            train_stds = X_train.std()
            train_stds[train_stds == 0] = 1
            
            X_train_scaled = (X_train - train_means) / train_stds
            X_test_scaled = (X_test - train_means) / train_stds
            
            # Test each feature set
            for model_name, feature_list in feature_sets.items():
                # Select features
                X_train_subset = X_train_scaled[feature_list]
                X_test_subset = X_test_scaled[feature_list]
                
                # Train XGBoost
                model = xgb.XGBRegressor(**xgb_params)
                model.fit(X_train_subset, y_train, 
                         eval_set=[(X_test_subset, y_test)],
                         early_stopping_rounds=50,
                         verbose=False)
                
                # Predict
                y_pred = model.predict(X_test_subset)
                
                # Calculate metrics
                results.append({
                    'repeat': repeat,
                    'fold': fold_idx,
                    'model': model_name,
                    'rmse': np.sqrt(mean_squared_error(y_test, y_pred)),
                    'mae': mean_absolute_error(y_test, y_pred),
                    'r2': r2_score(y_test, y_pred)
                })
    
    return pd.DataFrame(results)


def train_final_model(X: pd.DataFrame, y: pd.Series) -> Tuple[xgb.XGBRegressor, pd.DataFrame]:
    """Train final model on all data and get feature importance."""
    
    # Standardize
    X_scaled = (X - X.mean()) / X.std()
    
    # Train final model
    xgb_params = {
        'objective': 'reg:squarederror',
        'max_depth': 6,
        'learning_rate': 0.1,
        'n_estimators': 1000,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'random_state': 42,
        'n_jobs': -1
    }
    
    model = xgb.XGBRegressor(**xgb_params)
    model.fit(X_scaled, y)
    
    # Get feature importance
    importance = pd.DataFrame({
        'feature': X.columns,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)
    
    return model, importance


def main():
    parser = argparse.ArgumentParser(description='Hybrid Trait-Bioclim XGBoost Model for Temperature')
    parser.add_argument('--trait_data', default='artifacts/model_data_complete_case_with_myco.csv',
                       help='Path to trait data CSV')
    parser.add_argument('--bioclim_dir', default='data/bioclim_extractions_cleaned/species_bioclim/',
                       help='Directory containing bioclim CSV files')
    parser.add_argument('--out_dir', default='artifacts/stage3rf_xgboost_hybrid_T/',
                       help='Output directory')
    parser.add_argument('--min_occurrences', type=int, default=30,
                       help='Minimum occurrences for climate statistics')
    parser.add_argument('--cv_folds', type=int, default=10,
                       help='Number of CV folds')
    parser.add_argument('--cv_repeats', type=int, default=5,
                       help='Number of CV repeats')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.out_dir, exist_ok=True)
    
    print("==========================================")
    print("Hybrid Trait-Bioclim XGBoost for Temperature")
    print("==========================================\n")
    
    # Load trait data
    print("Loading trait data...")
    trait_data = pd.read_csv(args.trait_data)
    print(f"Loaded {len(trait_data)} species with trait data")
    
    # Calculate bioclim metrics
    climate_data = calculate_bioclim_metrics(args.bioclim_dir, args.min_occurrences)
    climate_data.to_csv(os.path.join(args.out_dir, 'climate_metrics.csv'), index=False)
    
    # Prepare features
    X, y = prepare_features(trait_data, climate_data)
    
    # Run cross-validation
    print(f"\nRunning {args.cv_folds}-fold × {args.cv_repeats} repeats cross-validation...")
    cv_results = run_cv_comparison(X, y, args.cv_folds, args.cv_repeats)
    cv_results.to_csv(os.path.join(args.out_dir, 'cv_results_detailed.csv'), index=False)
    
    # Calculate summary statistics
    cv_summary = cv_results.groupby('model').agg({
        'r2': ['mean', 'std'],
        'rmse': ['mean', 'std'],
        'mae': ['mean', 'std']
    }).round(4)
    
    print("\n==========================================")
    print("Cross-Validation Results:")
    print("==========================================")
    print(cv_summary)
    
    cv_summary.to_csv(os.path.join(args.out_dir, 'cv_results_summary.csv'))
    
    # Train final model
    print("\n==========================================")
    print("Training Final Model on Full Data")
    print("==========================================")
    
    final_model, importance = train_final_model(X, y)
    
    # Save model
    final_model.save_model(os.path.join(args.out_dir, 'final_model.json'))
    
    # Save feature importance
    importance.to_csv(os.path.join(args.out_dir, 'feature_importance.csv'), index=False)
    
    print("\nTop 15 Important Features:")
    print(importance.head(15))
    
    # Calculate final metrics
    y_pred = final_model.predict((X - X.mean()) / X.std())
    final_r2 = r2_score(y, y_pred)
    
    # Compare with baseline (traits only)
    trait_features = ['logLA', 'logH', 'logSM', 'logSSD', 'Nmass', 'LMA', 'LES_core', 'SIZE']
    X_traits = X[trait_features]
    X_traits_scaled = (X_traits - X_traits.mean()) / X_traits.std()
    
    baseline_model = xgb.XGBRegressor(
        objective='reg:squarederror',
        max_depth=6,
        learning_rate=0.1,
        n_estimators=1000,
        random_state=42
    )
    baseline_model.fit(X_traits_scaled, y)
    y_pred_baseline = baseline_model.predict(X_traits_scaled)
    baseline_r2 = r2_score(y, y_pred_baseline)
    
    # Save summary
    summary = {
        'timestamp': pd.Timestamp.now().isoformat(),
        'n_species_merged': len(X),
        'n_features': len(X.columns),
        'baseline_r2': float(baseline_r2),
        'final_r2': float(final_r2),
        'improvement_pct': float(100 * (final_r2 - baseline_r2) / baseline_r2),
        'cv_summary': cv_summary.to_dict(),
        'top_features': importance.head(15).to_dict('records')
    }
    
    with open(os.path.join(args.out_dir, 'summary.json'), 'w') as f:
        json.dump(summary, f, indent=2)
    
    print("\n==========================================")
    print("SUMMARY")
    print("==========================================")
    print(f"Baseline R² (traits only): {baseline_r2:.3f}")
    print(f"Final Model R² (hybrid): {final_r2:.3f}")
    print(f"Improvement: +{summary['improvement_pct']:.1f}%")
    print(f"\nResults saved to: {args.out_dir}")


if __name__ == '__main__':
    main()