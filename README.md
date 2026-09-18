# Flight Time Truth

**Can we trust the reported flight duration in US flight data?**

A SQL data quality analysis of 1.67 million US domestic flights. I rebuilt each flight's duration from its departure and arrival times and checked whether it matches the reported `actual_elapsed_time`.

📊 **[View the full report](https://shadishirinbeik.github.io/flight-time-truth-sql/report/index.html)**: open `report.html` in your browser after cloning the repo.

---

## Key findings

| Step | What changed | Match rate |
|---|---|---|
| 1 | Raw subtraction of HHMM numbers | 1.75% |
| 2 | Converted times to `TIME` and minutes to `INTERVAL` | 46.11% |
| 3 | Converted local times to UTC using airport time zones | 80.31% |
| 4 | Added 24 hours to flights that land after midnight UTC | **93.66%** |

- **The column is reliable.** Among completed flights, 97.1% match exactly. Every large gap had a technical cause (data type, time zone, midnight), not a wrong value.
- **Time zones** were the biggest single cause: fixing them moved the match rate from 46% to 80%.
- **233,665 flights (14%)** land after midnight UTC, which made their duration negative until the 24-hour fix.
- **Cancelled and diverted flights** (59,268, or 3.55%) have no departure or arrival time, so they can never match.

## Data

| File | Description |
|---|---|
| `data/flights.rar` | 1,671,142 flights, Jan 1 – Mar 31, 2026, 17 columns (compressed; the CSV is 147 MB, over GitHub's 100 MB limit) |
| `data/airports.csv` | Airport reference data: code (`faa`), name, location, UTC offset (`tz`) |

**Source:** US Department of Transportation, Bureau of Transportation Statistics: [Reporting Carrier On-Time Performance (1987–present)](https://transtats.bts.gov/DatabaseInfo.asp?QO_VQ=EFD). Column definitions: [BTS field reference](https://www.transtats.bts.gov/Fields.asp?gnoyr_VQ=FGJ).

Main columns used:

| Column | Meaning |
|---|---|
| `dep_time`, `arr_time` | Actual departure and arrival time, **local time**, HHMM format (`1235` = 12:35) |
| `actual_elapsed_time` | Actual flight duration in minutes, gate to gate |
| `origin`, `dest` | Airport codes, joined to `airports.faa` |
| `cancelled`, `diverted` | Flags; these flights have no times |

## Project structure

```
flight-time-truth/
├── README.md
├── index.html               ← redirection to the report file
├── report/
│   └── index.html           ← visual report of the results
├── data/
│   ├── flights.rar          ← compressed flight data
│   └── airports.csv
└── sql/
    ├── 01_create_table.sql  ← creates the flights and airports tables
    ├── 02_load_data.sql     ← loads the CSV files and checks the row counts
    └── 03_analysis.sql         ← all analysis steps with results and insights
```

## How to run

1. Install [PostgreSQL](https://www.postgresql.org/download/) and a SQL client (I used DBeaver).
2. Extract `data/flights.rar` to get `flights.csv`.
3. Copy `flights.csv` and `airports.csv` to a folder the PostgreSQL server can read (on Windows, `C:\Users\Public\` usually works) and update the paths in `02_load_data.sql` if needed.
4. Run the scripts in order:
   1. `sql/01_create_table.sql`
   2. `sql/02_load_data.sql` (expected: 1,671,142 flights, no flights without a matching airport)
   3. `sql/analysis.sql`, one section at a time

## SQL techniques used

- Type conversion with `MAKE_TIME` and `MAKE_INTERVAL`, plus integer division (`/`) and modulo (`%`) to split HHMM values
- Time and interval arithmetic (`TIME - TIME`, `TIME - INTERVAL`, `+ INTERVAL '24 hours'`)
- Joining the same table twice with aliases (origin and destination airport)
- Multi-step logic with chained CTEs (`WITH ... AS`)
- Conditional flags with `CASE WHEN`, and match rates with `SUM` / `AVG` of 0/1 flags
- Data quality checks: value ranges, `NULL` handling, row count validation

## Limitations

- The `tz` column holds one fixed UTC offset per airport, which does not change during the year.
- About 2.8% of flights still do not match; this group was not analyzed further.
- The dataset covers only one quarter (Q1 2026) of US domestic flights.

## Next steps

- Look into the remaining 2.8% of mismatches.
- Use the validated durations to compare scheduled and actual flight times per airline and route.

## A note on AI use

The HTML report (`report.html`) was created with the help of AI. The SQL queries, analysis and insights in this repository are my own work.
