/* ============================================================
   Purpose : Load flights.csv into flights and check the load
   DB      : PostgreSQL
   ============================================================ */

-- Change the path to where flights.csv is on your computer.
COPY flights
FROM 'C:/Users/Public/flights.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- Check: expected 1,671,142 rows, from 2026-01-01 to 2026-03-31
SELECT
    COUNT(*) AS total_rows,
    MIN(flight_date) AS first_day,
    MAX(flight_date) AS last_day
FROM flights;