# Dog Breed Explorer

**A daily-refreshed analytics layer over TheDogAPI's breed catalogue.**

[![CI](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/ci.yml/badge.svg)](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/ci.yml)
[![Deploy](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/deploy.yml/badge.svg)](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/deploy.yml)
[![Daily refresh](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/daily-refresh.yml/badge.svg)](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/daily-refresh.yml)

> Tool choices and their trade-offs are argued in [DECISIONS.md](DECISIONS.md) — this file is only how to run it.

---

## 📝 Project Overview

### Description

[TheDogAPI](https://api.thedogapi.com/v1/breeds) publishes a breed catalogue that is easy to read but hard to analyse. Measurements arrive as free text rather than numbers, several attributes are packed many-to-one into a single field, and some records are incomplete — so nothing in the raw payload can be grouped, averaged or joined without being cleaned first. This project fetches that catalogue every day, keeps each day's response raw and immutable, and rebuilds a typed, tested warehouse on top of it through three layers: landing, staging and marts. Each of the four business questions gets its own mart table, shaped so the dashboard reads it directly with no logic in the presentation layer.

### Key Features

- Idempotent daily ingestion — re-running the same day overwrites in place rather than duplicating, and a crash mid-write leaves the previous good file intact.
- The raw layer is never modified. Each response is validated before it is stored, and what reaches disk is the original payload, byte for byte.
- Incomplete or malformed responses are rejected instead of stored, and transient network and server failures are retried automatically.
- Every day's response is kept as its own partition, so the history is versioned and any past state can be rebuilt.
- Free-text measurements are parsed into real numeric ranges, including the records that split a range by sex.
- Multi-value attributes are split into a bridge table at one row per breed and trait, so they can be grouped, counted and joined.
- Breeds are bucketed into five size bands derived from weight; breeds with no usable weight are left unclassified rather than defaulted into a band.
- 22 automated tests run alongside the models — 20 schema tests covering keys, required fields, permitted values and referential integrity, plus 2 custom tests checking that no breed is lost or invented during curation and that no parsed range is inverted.
- Tests run interleaved with the models, so bad data stops the models downstream of it from being built on top of it.
- Continuous integration on every pull request, building and testing against a throwaway warehouse. It never calls the API — the committed raw data is the fixture, so checks are reproducible and cost no rate limit.
- The same models run against a second target on merge to main, which is what proves the transformations are environment-agnostic.
- A scheduled daily refresh fetches, stores and rebuilds on its own, committing only when the upstream data actually changed.
- A local dashboard reads the finished tables directly, with the size bands, rankings and trait counts presented as the marts already computed them.


### Tech Stack

| Layer | Tool (confirmed in repo) |
| --- | --- |
| Ingestion | Python 3.12 + `requests==2.34.2` |
| Raw storage | JSON files committed to git, partitioned `data/raw/run_date=<date>/` |
| Warehouse | DuckDB (`duckdb==1.5.4`), one file per target under `warehouse/` |
| Transformation | dbt Core `1.8.8` with `dbt-duckdb==1.8.3` |
| Testing | dbt schema tests (`models/**/*.yml`) + singular tests (`tests/*.sql`) |
| Orchestration & scheduling | GitHub Actions (`schedule:` cron) |
| CI/CD | GitHub Actions (`ci.yml`, `deploy.yml`) |
| Dashboard | Streamlit `1.59.2` + Altair, reading DuckDB read-only |
| Version control | Git / GitHub |

## ⚙️ Getting Started

### Prerequisites

- **Python 3.12** — the version all three workflows pin via `actions/setup-python`.
- **Git** — the raw data layer *is* the repo, so a clone gives you every historical partition.
- **A GitHub account** only if you want the workflows to run on your fork.
- **A free [TheDogAPI](https://thedogapi.com/) key** — needed **only** to fetch fresh data. Building the warehouse, running the tests and opening the dashboard all work offline from the committed partitions, which is exactly why CI needs no key.

### Installation

```bash
git clone https://github.com/SoulChristin/dog-breed-explorer.git
cd dog-breed-explorer

python -m venv .venv
source .venv/bin/activate        # Windows PowerShell: .venv\Scripts\Activate.ps1

pip install -r requirements.txt

# warehouse/ holds only gitignored .duckdb files, so these directories do not
# exist in a fresh clone and DuckDB cannot create the database without them.
# This is the same step all three workflows run.
mkdir -p warehouse/dev warehouse/prod
```

`pip` is the package manager used everywhere (`pip install -r requirements.txt` in all three workflows). dbt reads its profile from the repo itself — `dog_explorer_dbt/profiles.yml`, passed with `--profiles-dir .` — so there is nothing to set up in `~/.dbt/`.

### Environment Variables

| Variable | Where it is set | Needed for |
| --- | --- | --- |
| `DOG_API_KEY` | **Local:** your shell environment. **CI:** GitHub repository secret, referenced as `${{ secrets.DOG_API_KEY }}` in `daily-refresh.yml` only. | `python src/ingest_breeds.py` — the only code that calls TheDogAPI |

That is the complete list. `ci.yml` and `deploy.yml` reference no secrets at all.

```bash
export DOG_API_KEY='your-key'            # macOS / Linux
```
```powershell
$env:DOG_API_KEY = 'your-key'            # Windows PowerShell
```

**How credentials stay out of git:** the key is read once from `os.environ` in `ingest_breeds.py` and never written to disk, logged, or included in the persisted payload; the script exits non-zero if it is unset. `profiles.yml` is safe to commit because DuckDB is a local file with no credentials — the only things it names are the two `.duckdb` paths, and `.gitignore` excludes `warehouse/**/*.duckdb` along with `dog_explorer_dbt/target/`, `logs/` and `.user.yml`. Setting the key in your shell (not in a file) is the local mechanism; GitHub Secrets is the CI one.

---

## 🚀 Usage Guide

### Quick Start

Build the whole warehouse locally from the data already in the repo — no API key, no network:

```bash
cd dog_explorer_dbt
dbt build --profiles-dir . --target dev     # or --target prod
```

Every model is a table rebuilt from scratch each run, so re-running is safe and never duplicates rows.

Fetch a fresh partition first (needs `DOG_API_KEY`), exactly as `daily-refresh.yml` does:

```bash
python src/ingest_breeds.py                 # writes data/raw/run_date=<today>/breeds.json
cd dog_explorer_dbt && dbt build --profiles-dir . --target dev
```

Then open the dashboard:

```bash
streamlit run src/dashboard.py
```

It defaults to the **dev** warehouse — the one a plain `dbt build` produces — so the quick start above is all you need before opening it. Switch to `prod` with the sidebar radio if you built that target too. A missing warehouse produces an in-app error naming the exact `dbt build` command to run.

To browse the tables directly, the DuckDB UI can attach both warehouses read-only (read-only matters — DuckDB allows one writing process per file, so a UI holding the file will block dbt):

```powershell
& "C:\Users\User\duckdb\duckdb.exe" -ui -cmd "ATTACH 'warehouse/dev/dog_explorer.duckdb' AS dev (READ_ONLY); ATTACH 'warehouse/prod/dog_explorer.duckdb' AS prod (READ_ONLY);"
```

### Running Tests

The exact command CI runs — models and their tests, together:

```bash
cd dog_explorer_dbt
dbt build --profiles-dir . --target dev
```

To run only the tests against an already-built warehouse:

```bash
dbt test --profiles-dir . --target dev
```

**Seeing results:** locally, dbt prints a `PASS/FAIL` line per test and a summary, with full detail in `target/run_results.json`. On GitHub, the **CI** badge at the top of this file links to the [Actions tab](https://github.com/SoulChristin/dog-breed-explorer/actions/workflows/ci.yml); every run — green or red — uploads `target/` and `logs/` as the `dbt-run-results` artifact (14-day retention), so a failure is diagnosable without re-running it.

---

## 📊 What the dashboard shows

Figures below are from the `prod` warehouse built off the `run_date=2026-07-21` partition (628 breeds); the daily refresh moves them slightly.

**Bigger breeds live shorter lives, and the trend is monotonic.** Average life span falls from **13.34 years** for Toy breeds to **10.62** for Giant — a **2.7-year** drop — decreasing at every step in between (Toy 13.34 → Small 13.27 → Medium 12.98 → Large 12.18 → Giant 10.62). The mart carries `breeds_with_life_span` per band precisely so the average can be read against how many breeds it rests on; 40 of 628 breeds publish no life span at all.

**The catalogue is concentrated in the middle.** Medium (5–25 kg midpoint) holds **249 breeds, 39.8%** of those with a parsed weight, and Large another **203 (32.4%)**. The tails are thin: **40 Toy (6.4%)** and **59 Giant (9.4%)**. Two breeds have no parsable weight and are excluded from this mart rather than bucketed into an "Unknown" band.

**Longest-lived is a five-way tie at 15.0 years** — Denmark Feist, Koolie, Miniature Fox Terrier, Rat Terrier and Silken Windhound — followed by Pointer at 14.5. Ranking uses `RANK()` on the *midpoint* of the published range, not its maximum: ranking on the maximum would reward a breed with a wide, uncertain range over one with a tight, high one, and ties genuinely share a rank here.

**Among family-friendly breeds, the top traits aren't the friendliness ones.** Of the 341 breeds carrying at least one defining trait, the most common temperaments are **Intelligent (293, 85.9%)**, **Loyal (195, 57.2%)** and **Alert (181, 53.1%)** — none of which were used to select the population. The defining traits themselves (Affectionate 47.8%, Friendly 47.2%, Playful 41.1%, Gentle 37.8%) rank high by construction, which is why the mart flags them with `is_defining_trait` and the dashboard offers a checkbox to hide them. "Family-friendly" has no flag in the source; it is a stated convention — an eight-trait list declared inline in `mart_temperament_summary.sql` — not an unauditable score.
