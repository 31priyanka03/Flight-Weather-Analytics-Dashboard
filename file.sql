create database project;
use project;

-- Create the main table to hold combined flight + weather data
-- Includes flight telemetry (position, altitude, velocity, etc.)
-- and matched weather conditions (temperature, wind, visibility, etc.)
CREATE TABLE flights_weather (
    icao24 VARCHAR(10),              -- unique aircraft transponder ID
    callsign VARCHAR(20),            -- flight callsign
    origin_country VARCHAR(100),     -- country the aircraft is registered to
    latitude DOUBLE,                 -- aircraft's actual latitude
    longitude DOUBLE,                -- aircraft's actual longitude
    grid_lat DOUBLE,                 -- latitude of the weather grid cell used
    grid_lon DOUBLE,                 -- longitude of the weather grid cell used
    baro_altitude DOUBLE,            -- barometric altitude
    geo_altitude DOUBLE,             -- geometric (GPS) altitude
    velocity DOUBLE,                 -- ground speed
    true_track DOUBLE,               -- heading in degrees
    vertical_rate DOUBLE,            -- climb/descent rate
    on_ground BOOLEAN,               -- whether aircraft is on the ground
    squawk VARCHAR(10),              -- transponder code
    spi BOOLEAN,                     -- special position indicator flag
    position_source INT,             -- source of position data
    batch_no INT,                    -- batch identifier for data ingestion
    time_position_utc DATETIME,      -- timestamp of position report
    last_contact_utc DATETIME,       -- last contact timestamp
    snapshot_time_utc DATETIME,      -- when this snapshot was taken
    collection_time_utc DATETIME,    -- when the data was collected/pulled
    temperature_C DOUBLE,            -- weather: temperature in Celsius
    humidity_pct DOUBLE,             -- weather: humidity percentage
    wind_speed_kmh DOUBLE,           -- weather: wind speed
    wind_direction_deg DOUBLE,       -- weather: wind direction in degrees
    pressure_hpa DOUBLE,             -- weather: atmospheric pressure
    cloud_cover_pct DOUBLE,          -- weather: cloud cover percentage
    precipitation_mm DOUBLE,         -- weather: precipitation amount
    visibility_m DOUBLE,             -- weather: visibility in meters
    weather_code INT,                -- weather: coded weather condition
    weather_time_utc DATETIME,       -- timestamp of the weather reading
    has_weather BOOLEAN              -- flag: whether weather data was matched
);

SET GLOBAL local_infile = 1;

-- Skips the header row, treats comma as delimiter, handles quoted fields
LOAD DATA LOCAL INFILE 'D:/Data/transfer/Projects/API/flight_weather_cleaned.csv'
INTO TABLE flights_weather
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Summary stats: total row count, number of unique aircraft, number of unique countries
select count(*) as Total_Records,
	   count(distinct icao24) as Unique_Aircrafts,
       count(distinct origin_country) as Countries
       from flights_weather;

-- Top 10 countries by flight count, with average velocity and altitude per country
select origin_country,
       count(*) as Flight_Count,
       round(avg(velocity),2) as Average_Velocity,
       round(avg(baro_altitude),2) as Average_Altitude
       from flights_weather
       group by origin_country
       order by Flight_Count desc
       LIMIT 10;
       
-- Airborne vs grounded split
-- NOTE: this references on_ground_text, which doesn't exist yet at this point 
-- in the script (it's added later via ALTER TABLE) — this query would fail if run here
select on_ground_text,
       count(*) AS Total,
       round(avg(velocity),2) AS Avg_Velocity
       from flights_weather
       group by on_ground_text;
       
-- Dump entire table for manual inspection
select * from flights_weather;

CREATE TABLE flights_boolean_fix (
    icao24 VARCHAR(10),
    time_position_utc DATETIME,
    on_ground VARCHAR(10),
    spi VARCHAR(10),
    has_weather VARCHAR(10)
);

-- Add new text-based columns to the main table to hold the corrected boolean values
-- (keeping the original on_ground/spi/has_weather columns untouched)
ALTER TABLE flights_weather
ADD COLUMN on_ground_text VARCHAR(10),
ADD COLUMN spi_text VARCHAR(10),
ADD COLUMN has_weather_text VARCHAR(10);

-- Index both tables on the join keys (icao24 + time_position_utc) to speed up the UPDATE JOIN below
CREATE INDEX idx_fw ON flights_weather (icao24, time_position_utc);
CREATE INDEX idx_fbf ON flights_boolean_fix (icao24, time_position_utc);

-- Populate the new text columns in flights_weather by matching rows against
-- the corrected values in flights_boolean_fix
UPDATE flights_weather fw
JOIN flights_boolean_fix fb
  ON fw.icao24 = fb.icao24
 AND fw.time_position_utc = fb.time_position_utc
SET
    fw.on_ground_text   = fb.on_ground,
    fw.spi_text         = fb.spi,
    fw.has_weather_text = fb.has_weather;

-- ============================================
-- WIND ANALYSIS
-- ============================================

-- Bucket records into wind speed categories and compare average velocity per bucket
-- NOTE: references flights_weather_cleann, which is only created later in the script
select
	case
		when wind_speed_kmh < 10 then 'Low Wind'
        when wind_speed_kmh between 10 and 25 then 'Average Wind'
        else 'High Wind'
	end as Wind_Category,
    count(*) as Record_Count,
    round(avg(velocity),2) as Avg_Velocity
from flights_weather_cleann
where wind_speed_kmh is not null
group by Wind_Category
order by Avg_Velocity DESC;

-- Classify each flight's relative wind direction (tailwind/headwind/crosswind)
-- by comparing aircraft heading (true_track) to wind direction, then compare
-- average velocity and wind speed across the three groups
SELECT 
    CASE 
        WHEN LEAST(
                ABS(true_track - MOD(wind_direction_deg + 180, 360)),
                360 - ABS(true_track - MOD(wind_direction_deg + 180, 360))
             ) <= 45 THEN 'Tailwind'
        WHEN LEAST(
                ABS(true_track - MOD(wind_direction_deg + 180, 360)),
                360 - ABS(true_track - MOD(wind_direction_deg + 180, 360))
             ) >= 135 THEN 'Headwind'
        ELSE 'Crosswind'
    END AS wind_relative_direction,
    COUNT(*) AS record_count,
    ROUND(AVG(velocity), 2) AS avg_velocity,
    ROUND(AVG(wind_speed_kmh), 2) AS avg_wind_speed
FROM flights_weather_cleann
WHERE wind_direction_deg IS NOT NULL 
  AND true_track IS NOT NULL
GROUP BY wind_relative_direction
ORDER BY avg_velocity DESC;

-- ============================================
-- VISIBILITY ANALYSIS
-- ============================================

-- Using a CTE, bucket flights into visibility categories (only where weather data exists),
-- then compare record count, average velocity, and average wind speed per bucket
WITH weather_buckets AS (
    SELECT 
        icao24, velocity, wind_speed_kmh, visibility_m,
        CASE 
            WHEN visibility_m < 5000 THEN 'Poor Visibility'
            WHEN visibility_m BETWEEN 5000 AND 20000 THEN 'Moderate Visibility'
            ELSE 'Good Visibility'
        END AS visibility_category
    FROM flights_weather_cleann
    WHERE has_weather_text = 'TRUE'
)
SELECT 
    visibility_category,
    COUNT(*) AS record_count,
    ROUND(AVG(velocity), 2) AS avg_velocity,
    ROUND(AVG(wind_speed_kmh), 2) AS avg_wind
FROM weather_buckets
GROUP BY visibility_category
ORDER BY avg_velocity DESC;

-- ============================================
-- COUNTRY RANKING
-- ============================================

-- Rank countries by number of flights using a window function, top 15 rows
SELECT 
    origin_country,
    COUNT(*) AS flight_count,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS country_rank
FROM flights_weather_cleann
GROUP BY origin_country
LIMIT 15;

-- ============================================
-- DATA CLEANING: DEDUPLICATION
-- ============================================

-- Create a cleaned version of the table:
-- - Removes duplicate rows per (icao24, time_position_utc) pair, keeping only the first (rn = 1)
-- - Filters out rows with invalid/zero datetime placeholders in either timestamp field
-- This is the table referenced by all the analysis queries above (flights_weather_cleann)
CREATE TABLE flights_weather_cleann AS
SELECT * FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY icao24, time_position_utc ORDER BY icao24) AS rn
    FROM flights_weather
    WHERE time_position_utc != '0000-00-00 00:00:00'
      AND weather_time_utc != '0000-00-00 00:00:00'
) t
WHERE rn = 1;

-- ============================================
-- DATA QUALITY CHECKS
-- ============================================

-- Check how far apart (in minutes) the flight position timestamp is from the
-- matched weather reading timestamp — identifies the 20 worst-matched pairs
-- (largest time gap), useful for validating the weather-matching logic
SELECT 
    icao24,
    time_position_utc,
    weather_time_utc,
    TIMESTAMPDIFF(MINUTE, weather_time_utc, time_position_utc) AS time_gap_minutes
FROM flights_weather_cleann
WHERE has_weather_text = 'TRUE'
ORDER BY ABS(TIMESTAMPDIFF(MINUTE, weather_time_utc, time_position_utc)) DESC
LIMIT 20;

-- Check how far the aircraft's actual lat/lon is from the weather grid cell's lat/lon
-- (the 20 largest mismatches) — validates how well the nearest weather grid point
-- represents the aircraft's actual location
SELECT 
    icao24,
    latitude,
    grid_lat,
    ROUND(latitude - grid_lat, 4) AS lat_diff,
    longitude,
    grid_lon,
    ROUND(longitude - grid_lon, 4) AS lon_diff
FROM flights_weather_cleann
ORDER BY ABS(latitude - grid_lat) DESC
LIMIT 20;

-- Overall average absolute distance (in degrees) between actual aircraft position
-- and the weather grid point used — a single summary metric for grid-matching accuracy
SELECT 
    ROUND(AVG(ABS(latitude - grid_lat)), 4) AS avg_lat_diff,
    ROUND(AVG(ABS(longitude - grid_lon)), 4) AS avg_lon_diff
FROM flights_weather_cleann;

-- ============================================
-- VISIBILITY vs ALTITUDE ANALYSIS
-- ============================================

-- Same visibility bucketing as before, but this time comparing average
-- velocity AND average altitude across visibility categories
WITH weather_buckets AS (
    SELECT 
        velocity, baro_altitude,
        CASE 
            WHEN visibility_m < 5000 THEN 'Poor Visibility'
            WHEN visibility_m BETWEEN 5000 AND 20000 THEN 'Moderate Visibility'
            ELSE 'Good Visibility'
        END AS visibility_category
    FROM flights_weather_cleann
    WHERE has_weather_text = 'TRUE'
)
SELECT 
    visibility_category,
    COUNT(*) AS record_count,
    ROUND(AVG(velocity), 2) AS avg_velocity,
    ROUND(AVG(baro_altitude), 2) AS avg_altitude
FROM weather_buckets
GROUP BY visibility_category
ORDER BY avg_velocity DESC;