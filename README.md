# Dog Breed Explorer

An analytics pipeline over [TheDogAPI](https://api.thedogapi.com/v1/breeds).

See **(DECISIONS.md)** for the reasoning and trade-offs behind the choices.

## Pipeline

**1. Extraction & Ingestion** — `src/ingest_breeds.py` fetches the breed catalogue from TheDogAPI and writes the raw response to disk, unmodified, partitioned by run date (`data/raw/run_date=<date>/breeds.json`).

**2. Daily refresh** — `.github/workflows/daily-refresh.yml` runs the ingestion script on a schedule (and can be triggered manually), committing a new raw partition back to the repo when the data changes.

**3. Transformation** — `dog_explorer_dbt/` (dbt Core + DuckDB):

- **Landing** (`models/landing/breeds.sql`) — every raw JSON field, untouched, plus a `source_file` column for traceability. Rebuilt from every committed `run_date=` partition on each run.
- **Staging** (`models/staging/`) — reads landing, filters to the latest `run_date`, renames to snake_case with real types, trims text and collapses blanks to `NULL`, drops unused/duplicate columns, and parses `life_span`, `temperament`, `weight` and `height` into usable shapes. Also derives the business columns the marts aggregate on (`size_class`, the life-span midpoint, the weight midpoint).
  - `stg_breeds` — one row per breed.
  - `stg_breed_temperaments` — one row per breed x trait, so temperaments are joinable and countable.
- **Marts** (`models/marts/`) — analytics-ready tables.

## Warehouses

Two separate DuckDB files, selected by dbt target:

| Target | File |
| --- | --- |
| `dev` (default) | `warehouse/dev/dog_explorer.duckdb` |
| `prod` | `warehouse/prod/dog_explorer.duckdb` |

Both hold the same schemas — `landing`, `staging`, `marts` — so the two environments are isolated by file, not by schema name. The warehouse files are gitignored: they are disposable output, rebuildable from the raw partitions at any time.

## Testing

Schema tests live beside the models (`models/**/*.yml`) and cover primary keys, non-null columns, accepted values and referential integrity between the traits table and `stg_breeds`. Two custom tests in `tests/` go further:

- `assert_stg_breeds_matches_landing_latest` — reconciles staging against landing, failing if the latest `run_date` partition loses or gains a breed on the way through.
- `assert_stg_breeds_ranges_valid` — fails if any parsed min/max range comes out inverted.

## Running it

```bash
pip install -r requirements.txt
export DOG_API_KEY='.........'  ##The key was locally stored
python src/ingest_breeds.py
```

## Transforming it

```bash
cd dog_explorer_dbt
dbt build --profiles-dir . --target dev     # or --target prod
```

`dbt build` runs the models and their tests together, so a failing test stops anything downstream from being built on bad data. Every model is materialized as a table and rebuilt from scratch on each run, so re-running is safe and never duplicates rows.

## Exploring the warehouse

The DuckDB UI can open both warehouses side by side:

```powershell
& "C:\Users\User\duckdb\duckdb.exe" -ui -cmd "ATTACH 'warehouse/dev/dog_explorer.duckdb' AS dev (READ_ONLY); ATTACH 'warehouse/prod/dog_explorer.duckdb' AS prod (READ_ONLY);"
```

Then open <http://localhost:4213>. Attaching read-only keeps the UI from locking a file that dbt needs to write — DuckDB allows only one writing process per file, so close the UI before running dbt against a warehouse it holds.
