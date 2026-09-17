/* ============================================================
   Purpose : Create the raw table for the flight data
   Data    : US DOT / BTS On-Time Performance, Q1 2026
   DB      : PostgreSQL
   ============================================================ */

DROP TABLE IF EXISTS flights;
CREATE TABLE flights (
    flight_date          DATE        NOT NULL,  -- day of the flight
    dep_time             SMALLINT,              -- actual departure, local time (HHMM)
    sched_dep_time       SMALLINT    NOT NULL,  -- scheduled departure, local time (HHMM)
    dep_delay            SMALLINT,              -- departure delay in minutes (negative = early)
    arr_time             SMALLINT,              -- actual arrival, local time (HHMM)
    sched_arr_time       SMALLINT    NOT NULL,  -- scheduled arrival, local time (HHMM)
    arr_delay            SMALLINT,              -- arrival delay in minutes (negative = early)
    airline              VARCHAR(3)  NOT NULL,  -- airline code, e.g. WN, DL, AA
    tail_number          VARCHAR(10),           -- aircraft ID
    flight_number        INTEGER     NOT NULL,
    origin               CHAR(3)     NOT NULL,  -- origin airport code
    dest                 CHAR(3)     NOT NULL,  -- destination airport code
    air_time             SMALLINT,              -- minutes in the air
    actual_elapsed_time  SMALLINT,              -- actual gate-to-gate minutes
    distance             SMALLINT    NOT NULL,  -- miles
    cancelled            BOOLEAN     NOT NULL,
    diverted             BOOLEAN     NOT NULL
);