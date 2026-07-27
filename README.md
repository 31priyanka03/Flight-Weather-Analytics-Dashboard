# Flight-Weather-Analytics-Dashboard

**Does weather actually change how planes fly — or is it just assumption?**

An end-to-end data project that combines live flight telemetry with real-time weather data to test common assumptions about how weather affects aircraft performance. Built from raw API data collection through to an interactive Power BI dashboard.


## Overview

Every day, thousands of aircraft transmit real-time data on their location, speed, and altitude, while weather services independently track conditions like wind and visibility across the same skies. These two data sources rarely get analyzed together at scale.

This project builds a pipeline that:
1. Collects live flight and weather data from independent public APIs
2. Merges them by matching each flight to its nearest weather observation in space and time
3. Cleans and validates the merged dataset
4. Analyzes and visualizes the relationship between weather conditions and flight behavior

The result is a dataset — and dashboard — that lets you actually test whether weather changes flight speed, instead of assuming it does.

## Objectives

- **Wind Impact** — Measure how headwinds, tailwinds, and crosswinds shift aircraft ground speed
- **Visibility Conditions** — Compare flight speed against visibility levels (good, average, poor)
- **Match Validation** — Confirm every flight is paired with its genuinely nearest weather observation, both spatially and in time
- **Aviation Insights** — Turn the combined dataset into decision-ready visuals

## Data Pipeline

```
Collect  →  Merge  →  Clean & Validate  →  Visualize
(APIs)      (Python)   (MySQL + Power Query)  (Power BI)
```

### 1. Collect
Live flight positions were pulled from the **OpenSky Network API**, which broadcasts real-time aircraft telemetry (position, altitude, velocity, heading) for thousands of aircraft worldwide. Since a single API call only returns a live snapshot, the API was called repeatedly (15 calls, 12-second intervals) to build a richer dataset spanning multiple moments rather than a single frozen picture.

Weather data was pulled from the **Open-Meteo API**, which maintains a continuously updated global weather model built from real station and satellite data.

### 2. Merge (Python)
Fetching weather individually for every flight would be redundant — nearby flights experience essentially the same weather. To avoid excessive API calls:
- Flight coordinates were rounded to the nearest 1.0° to create `grid_lat` / `grid_lon` cells, grouping nearby flights into shared weather-lookup zones
- Weather was fetched once per unique grid cell, then joined back onto every flight in that cell
- Original (unrounded) coordinates were preserved alongside the grid columns, so no positional precision was lost

Output: `flight_weather_merged.csv` — one row per flight observation, containing both flight attributes and the weather conditions at its location and time.

### 3. Clean & Validate (MySQL + Power Query)
- Removed duplicate records using `ROW_NUMBER()` partitioned by aircraft ID and timestamp
- Filtered out invalid placeholder timestamps
- Corrected boolean fields (`on_ground`, `spi`, `has_weather`) that were mis-typed on import, via a secondary lookup table and `UPDATE ... JOIN`
- Indexed on `(icao24, time_position_utc)` for join performance
- Additional calculated columns (wind relative direction, visibility category, angle-of-incidence between heading and wind) built in Power Query for the dashboard layer

### 4. Visualize (Power BI)
Interactive dashboard with DAX measures, calculated columns, slicers, and cross-filtered visuals across four analysis pages plus a project overview and conclusion page.


## Key Findings

### 1. Wind has a real, measurable effect on ground speed
Ground speed was classified by the angle between aircraft heading and wind direction:

| Wind Category | Avg Velocity (km/h) |
|---|---|
| Crosswind | 162 |
| Tailwind | 161 |
| Headwind | 153 |

Headwind flights showed measurably lower ground speed than tailwind flights, confirming that real aerodynamics are visible in live flight telemetry — flying against the wind reduces ground speed.

### 2. Visibility does not slow flights down at cruise altitude
Counter-intuitively, flights recorded under **poor visibility averaged the highest speed (184 km/h)**, higher than both average and good visibility conditions.

This is not a data error. Most records in this dataset represent aircraft in cruise phase, where pilots rely on onboard instruments (Primary Flight Display, Flight Management System, GPS, autopilot) rather than outside visual conditions. Ground-level assumptions about weather slowing planes down apply mainly during takeoff, approach, and landing — not en-route cruise flight.

### 3. Country-level flight counts reflect tracking infrastructure, not just traffic
Flight volume by country correlates strongly with ADS-B ground receiver density. Europe and North America show disproportionately higher counts partly because of denser tracking infrastructure, not solely because of higher real-world air traffic. This is an important caveat when interpreting raw geographic counts in any open-source flight dataset.

## Data Validation

Before trusting the analysis above, the flight–weather match itself was validated:

- **98.4%** of flight records were successfully matched to a nearby weather observation
- Average spatial deviation between an aircraft's actual position and its matched weather grid point stayed under **0.1°** (roughly 11 km)
- Timestamp gaps between a flight's position report and its matched weather reading stayed within an acceptable window; repeated gap values across records reflect the weather API's refresh interval, where multiple flights share the same nearest weather snapshot — expected behavior, not an error

## Dashboard

The Power BI dashboard is organized into five pages:
# Dashboard Preview

## Project Overview


## Wind Analysis


## Visibility Analysis


1. **Project Overview** — problem statement, objectives, and pipeline summary  ![Project Overview](Images/project-overview.png)
2. **Global Flight Traffic** — world map of flight positions, ground status, top countries by volume  ![Global_Flight](Images/global_flight.png)
3. **Wind Analysis** — ground speed by wind direction and intensity, plus data-quality validation table  ![Wind Analysis](Images/wind-analysis.png)
4. **Visibility Analysis** — speed and flight volume by visibility category, including a low-altitude subset comparison  ![Visibility Analysis](Images/visibility-analysis.png)
5. **Key Findings & Conclusion** — summary of results and closing insights  ![Key Findings](Images/key_findings.png)

