/* ============================================================
   Purpose : Check if flight time data is reliable, then analyze
             scheduled vs. actual flight times
   Data    : US DOT / BTS On-Time Performance, Q1 2026 (1.67M flights)
   DB      : PostgreSQL (table: flights, see 01_create_table.sql)
   ============================================================ */


/* ------------------------------------------------------------
 * Question_1: Do we understand what our time columns really mean?
 * ------------------------------------------------------------
 * - dep_time, arr_time: clock time in local time, stored as an integer in HHMM format.
 *   Values should be between 0001 and 2400, and the last two digits never go above 59.
 * - actual_elapsed_time: a duration in minutes (integer), from gate departure to gate arrival.
 */


/* ------------------------------------------------------------
 * Question_2: Are the time values in a valid and expected range?
 * ------------------------------------------------------------
 */
		-- arr_time: clock time in HHMM
		SELECT DISTINCT arr_time
		FROM flights
		ORDER BY arr_time DESC;
		
		-- dep_time: clock time in HHMM
		SELECT DISTINCT dep_time
		FROM flights
		ORDER BY dep_time DESC;
		
		-- actual_elapsed_time: duration in minutes
		SELECT DISTINCT actual_elapsed_time
		FROM flights
		ORDER BY actual_elapsed_time DESC;

/* Insight:
 * - Our assumptions were correct.
 * - dep_time and arr_time go from 1 (00:01) to 2400 (midnight). There are 1,440 unique arr_time values,
 *   one for every minute of the day. No value has minutes above 59, so the HHMM format is clean.
 * - Midnight is stored as 2400, not 0.
 * - actual_elapsed_time goes from 14 to 763 minutes (about 12.7 hours). This looks realistic for US flights.
 * - All three columns have NULL values. These are cancelled and diverted flights.
 */
		

/* ------------------------------------------------------------
 * Question_3: Can we recalculate flight duration from departure and arrival times?
 * ------------------------------------------------------------
 */
		SELECT
		    dep_time,
		    arr_time,
		    arr_time - dep_time AS flight_duration,
		    actual_elapsed_time
		FROM flights;

/* Insight:
 * - A simple subtraction does not give the real duration. Only 1.8% of flights
 *   (29,257 of 1.61M) have flight_duration equal to actual_elapsed_time.
 * - Reasons: HHMM is not minutes (1300 - 1255 = 45, but real difference is 5 min),
 *   and dep_time and arr_time are in different time zones.
 * - Next step: convert HHMM to minutes before subtracting.
 */


/* ------------------------------------------------------------
 * Question_4: Can we turn raw numbers into real clock times and durations?
 * ------------------------------------------------------------
 */
		WITH converted AS (
			SELECT
				origin,
				dest,
			    dep_time,
			    MAKE_TIME(dep_time / 100, dep_time % 100, 0) AS dep_time_f,
			    arr_time,
			    MAKE_TIME(arr_time / 100, arr_time % 100, 0) AS arr_time_f,
			    actual_elapsed_time,
			    MAKE_INTERVAL(mins => actual_elapsed_time) AS actual_elapsed_time_f
			FROM flights
		)
		SELECT *,
			arr_time_f - dep_time_f AS flight_duration_f
		FROM converted;

/* Insight:
 * - HHMM numbers are now real TIME values (1235 -> 12:35:00), and minutes are now
 *   INTERVAL values (140 -> 02:20:00).
 * - Converting to TIME fixed the HHMM problem: exact matches went up from 1.8% to 47.8%
 *   (770,598 of 1.61M completed flights).
 * - 69,147 flights have a negative flight_duration because they land after midnight.
 * - The time zone problem is still there: both times are local, so the difference can
 *   still be wrong for flights between time zones or past midnight.
 */


/* ------------------------------------------------------------
 * Question_5: Does the recalculated flight duration match the reported one?
 * ------------------------------------------------------------
 */

WITH converted AS (
    SELECT
        MAKE_TIME(dep_time / 100, dep_time % 100, 0) AS dep_time_f,
        MAKE_TIME(arr_time / 100, arr_time % 100, 0) AS arr_time_f,
        MAKE_INTERVAL(mins => actual_elapsed_time)   AS actual_elapsed_time_f
    FROM flights
),
calculate_duration AS (
    SELECT
        actual_elapsed_time_f,
        arr_time_f - dep_time_f AS flight_duration_f
    FROM converted
),
calculate_match_flag AS (
    SELECT
        actual_elapsed_time_f,
        flight_duration_f,
        CASE
            WHEN flight_duration_f = actual_elapsed_time_f THEN 1
            ELSE 0
        END AS match_flag
    FROM calculate_duration
)
SELECT
    SUM(match_flag) AS number_of_same_values,
    COUNT(*) AS total_count,
    ROUND(AVG(match_flag) * 100.0, 2) AS same_value_pct
FROM calculate_match_flag;

/* Result:
 * number_of_same_values | total_count | same_value_pct
 *               770,598 |   1,671,142 |          46.11
 *
 * Insight:
 * - Only 46% of all flights have a matching duration. At first sight this looks like
 *   actual_elapsed_time is not reliable.
 * - But the total includes 59,268 cancelled and diverted flights, which have no times at all.
 *   Among completed flights, the match rate is 47.8%.
 * - Most of the other flights differ by exactly 1-3 hours (time zones) or land after midnight.
 *   So a low match rate here does not mean the data is wrong. It means our calculation
 *   is still missing time zone and date information.
 */


/* ------------------------------------------------------------
 * Question_5: In which time zone is each flight's departure and arrival?
 * ------------------------------------------------------------
 * Task:
 * - Add the time zone of the origin and destination airport (origin_tz, dest_tz) as INTERVAL.
 * - Convert dep_time_f and arr_time_f to UTC (dep_time_f_utc, arr_time_f_utc).
 * - Calculate flight_duration_f_utc and the percentage of flights where it
 *   matches actual_elapsed_time_f (rounded to two decimals).
 * 
 * Approach:
 * 1. converted            -> HHMM to TIME, minutes to INTERVAL, tz (hours) to INTERVAL
 * 2. calculate_utc        -> UTC time = local time - tz, then arrival - departure
 * 3. calculate_match_flag -> 1 if both durations are equal, otherwise 0
 * 4. Final SELECT         -> match count, total count, match rate
 */

WITH converted AS (
    SELECT
	    f.flight_date,
	    f.origin,
	    f.dest,
	    f.dep_time,
        MAKE_TIME(f.dep_time / 100, f.dep_time % 100, 0) AS dep_time_f,
        MAKE_TIME(f.arr_time / 100, f.arr_time % 100, 0) AS arr_time_f,
        MAKE_INTERVAL(mins => f.actual_elapsed_time)     AS actual_elapsed_time_f,
        a_origin.tz * INTERVAL '1 hour'                  AS origin_tz,
        a_dest.tz   * INTERVAL '1 hour'                  AS dest_tz
    FROM flights AS f
    JOIN airports AS a_origin
        ON f.origin = a_origin.faa
    JOIN airports AS a_dest
        ON f.dest = a_dest.faa
),
calculate_utc AS (
    SELECT
        actual_elapsed_time_f,
        dep_time_f - origin_tz                          AS dep_time_f_utc,
        arr_time_f - dest_tz                            AS arr_time_f_utc,
        (arr_time_f - dest_tz) - (dep_time_f - origin_tz) AS flight_duration_f_utc
    FROM converted
),
calculate_match_flag AS (
    SELECT
        actual_elapsed_time_f,
        flight_duration_f_utc,
        CASE
            WHEN flight_duration_f_utc = actual_elapsed_time_f THEN 1
            ELSE 0
        END AS match_flag
    FROM calculate_utc
)
SELECT
    SUM(match_flag)                    AS number_of_same_values,
    COUNT(*)                           AS total_count,
    ROUND(AVG(match_flag) * 100.0, 2)  AS same_value_pct
FROM calculate_match_flag;

/* Insight:
 * - Converting to UTC raised the match rate from 46.11% to 80.31%.
 *   Among completed flights, it is 83.3%. Time zones were the biggest reason for the mismatches.
 * - About 224,000 flights (13.9%) are still off by exactly 24 hours.
 *   These flights cross midnight in UTC, and the TIME type has no date, so the result "wraps around".
 */


/* ------------------------------------------------------------
 * Question_6: Are overnight flights causing the remaining mismatches?
 * ------------------------------------------------------------
 * Task:
 * - Find what is special about flight_duration_f_utc for overnight flights.
 * - Count the flights that arrive after midnight UTC.
 * - Fix them and calculate the match rate again.
 *
 * Approach:
 * 1. converted            -> HHMM to TIME, minutes to INTERVAL, tz to INTERVAL
 * 2. calculate_utc        -> local time - tz = UTC time
 * 3. calculate_duration   -> arrival - departure; flag flights that arrive after midnight UTC
 * 4. fix_overnight        -> add 24 hours to overnight flights
 * 5. calculate_match_flag -> compare durations before and after the fix
 * 6. Final SELECT         -> overnight count and match rate before vs. after
 *
 * Tip: to see the negative durations (7.1), replace the final SELECT with:
 *      SELECT * FROM calculate_duration ORDER BY flight_duration_f_utc;
 */


CREATE OR REPLACE VIEW flights_utc AS
WITH converted AS (
    SELECT
        f.flight_date,
        f.airline,
        f.flight_number,
        f.origin,
        f.dest,
        MAKE_TIME(f.dep_time / 100, f.dep_time % 100, 0) AS dep_time_f,
        MAKE_TIME(f.arr_time / 100, f.arr_time % 100, 0) AS arr_time_f,
        MAKE_INTERVAL(mins => f.actual_elapsed_time)     AS actual_elapsed_time_f,
        a_origin.tz * INTERVAL '1 hour'                  AS origin_tz,
        a_dest.tz   * INTERVAL '1 hour'                  AS dest_tz
    FROM flights AS f
    JOIN airports AS a_origin
        ON f.origin = a_origin.faa
    JOIN airports AS a_dest
        ON f.dest = a_dest.faa
)
SELECT
    *,
    dep_time_f - origin_tz                            AS dep_time_f_utc,
    arr_time_f - dest_tz                              AS arr_time_f_utc,
    (arr_time_f - dest_tz) - (dep_time_f - origin_tz) AS flight_duration_f_utc
FROM converted;


SELECT
    origin,
    dest,
    dep_time_f_utc,
    arr_time_f_utc,
    flight_duration_f_utc,
    actual_elapsed_time_f
FROM flights_utc
ORDER BY flight_duration_f_utc;


SELECT COUNT(*) AS flights_arriving_after_midnight_utc
FROM flights_utc
WHERE arr_time_f_utc < dep_time_f_utc;


WITH fixed_duration AS (
    SELECT
        actual_elapsed_time_f,
        CASE
            WHEN flight_duration_f_utc < INTERVAL '0'
                THEN flight_duration_f_utc + INTERVAL '24 hours'
            ELSE flight_duration_f_utc
        END AS flight_duration_f_utc_fixed
    FROM flights_utc
),
calculate_match_flag AS (
    SELECT
        *,
        CASE
            WHEN flight_duration_f_utc_fixed = actual_elapsed_time_f THEN 1
            ELSE 0
        END AS match_flag
    FROM fixed_duration
)
SELECT
    SUM(match_flag)                    AS number_of_same_values,
    COUNT(*)                           AS total_count,
    ROUND(AVG(match_flag) * 100.0, 2)  AS same_value_pct
FROM calculate_match_flag;

/* Result:
 * total_count | overnight_flights | matches_before_fix | match_pct_before_fix | matches_after_fix | match_pct_after_fix
 *   1,671,142 |           233,665 |          1,342,016 |                80.31 |         1,565,626 |               93.66
 *
 * Insight:
 * - 233,665 flights (14%) arrive after midnight UTC.
 * - Fixing them raised the match rate from 80.31% to 93.66% (97.13% of completed flights).
 * - Almost all remaining mismatches are cancelled/diverted flights (no times).
 * - Conclusion: actual_elapsed_time is reliable.
 */