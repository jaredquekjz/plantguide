# WorldClim Bioclimatic Variables Reference

Source: https://www.worldclim.org/data/bioclim.html
Date Accessed: 2025-11-27
WorldClim Version: 2.x

## Units

- Temperature variables: degrees Celsius (°C)
- Precipitation variables: millimeters (mm)

Note: WorldClim 2.x stores temperature values directly in °C (not °C × 10 as in version 1.4)

## Variable Definitions

| Code | Variable Name | Description | Unit |
|------|---------------|-------------|------|
| BIO1 | Annual Mean Temperature | Mean of monthly temperature values | °C |
| BIO2 | Mean Diurnal Range | Mean of monthly (max temp - min temp) | °C |
| BIO3 | Isothermality | BIO2/BIO7 × 100 | dimensionless |
| BIO4 | Temperature Seasonality | Standard deviation × 100 | dimensionless |
| BIO5 | Max Temperature of Warmest Month | Maximum temperature in warmest month | °C |
| BIO6 | Min Temperature of Coldest Month | Minimum temperature in coldest month | °C |
| BIO7 | Temperature Annual Range | BIO5 - BIO6 | °C |
| BIO8 | Mean Temperature of Wettest Quarter | Mean temperature in wettest quarter | °C |
| BIO9 | Mean Temperature of Driest Quarter | Mean temperature in driest quarter | °C |
| BIO10 | Mean Temperature of Warmest Quarter | Mean temperature in warmest quarter | °C |
| BIO11 | Mean Temperature of Coldest Quarter | Mean temperature in coldest quarter | °C |
| BIO12 | Annual Precipitation | Sum of monthly precipitation values | mm |
| BIO13 | Precipitation of Wettest Month | Precipitation in wettest month | mm |
| BIO14 | Precipitation of Driest Month | Precipitation in driest month | mm |
| BIO15 | Precipitation Seasonality | Coefficient of variation | dimensionless |
| BIO16 | Precipitation of Wettest Quarter | Sum of precipitation in wettest quarter | mm |
| BIO17 | Precipitation of Driest Quarter | Sum of precipitation in driest quarter | mm |
| BIO18 | Precipitation of Warmest Quarter | Sum of precipitation in warmest quarter | mm |
| BIO19 | Precipitation of Coldest Quarter | Sum of precipitation in coldest quarter | mm |

## Notes

### Temperature Seasonality (BIO4)
Temperature seasonality is calculated using standard deviation rather than coefficient of variation, because coefficient of variation is not meaningful for temperatures between -1 and 1.

### Quarter Definitions
A "quarter" refers to a period of three consecutive months. For quarterly variables (BIO8-BIO11, BIO16-BIO19), the wettest/driest/warmest/coldest quarter is determined by examining all possible 3-month periods in a year.

### Dimensionless Variables
Variables BIO3, BIO4, and BIO15 are dimensionless ratios or scaled statistics that provide relative measures of temperature or precipitation variability.
