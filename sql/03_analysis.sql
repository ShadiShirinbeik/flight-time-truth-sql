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