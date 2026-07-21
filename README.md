# Dog Breed Explorer

An analytics pipeline over [TheDogAPI](https://api.thedogapi.com/v1/breeds).

See **(DECISIONS.md)** for the reasoning and trade-offs behind the choices.

## Pipeline

**1. Extraction & Ingestion** — `src/ingest_breeds.py` fetches the breed catalogue from TheDogAPI and writes the raw response to disk, unmodified, partitioned by run date (`data/raw/run_date=<date>/breeds.json`).

**2. Daily refresh** — `.github/workflows/daily-refresh.yml` runs the ingestion script on a schedule (and can be triggered manually), committing a new raw partition back to the repo when the data changes.

**3. Transformation** — `dog_explorer_dbt/` (dbt Core + DuckDB):
- **Landing** (`models/landing/breeds.sql`) — every raw JSON field, untouched, plus a `source_file` column for traceability.
- **Staging** (`models/staging/stg_breeds.sql`) — filters to the latest `run_date`, renames to snake_case with real types, drops unused/duplicate columns, and parses `life_span`, `temperament`, `weight`, `height` into usable shapes.
- **Marts** — analytics-ready tables for the dashboard. *(not yet built)*

## Running it

```bash
pip install -r requirements.txt
export DOG_API_KEY='.........'  ##The key was locally stored
python src/ingest_breeds.py
```

## Transforming it

```bash
cd dog_explorer_dbt
dbt build --profiles-dir . --target dev
```