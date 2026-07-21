# Decisions

**Scope:** In a paragraph per layer, which tool you chose and why, what you traded off, and what you would do differently with more time.

---

## 1. Extraction & Ingestion

### Extraction

**Which tool and why**
I used Python with the request library to fetch the dataset from TheDogAPI. I chose requests because is a common libarby among engineers and easy to maintain from others & the script is small — one call, one job every day — a single-endpoint fetch doesn't need beacuse no need for concurrently calls.

**What it does shortly** (`dog-breed-explorer\src\ingest_breeds.py`)
It fetches the data with idempotent runs, refuses anything that looks partial, and write only complete, validated payloads to disk preserving the data untouched. Failures are handled selectively.

**Traded off**
There's no logging framework — just print to stdout/stderr — so the failure signal today is a non-zero exit code, with no structured detail (timestamps, run IDs, retry counts) beyond what's printed.

**With more time**
One of the things I'd change the hardcoded 500 floor — it was an assumption based on the data count I observed, not a principled threshold, so it's fragile.

### Storage

**Which tool and why**
Git stores the raw data in json format. A format that the DuckDB can read. I chose git over an object storage because git already gives version history, and diffs for free — putting the same raw JSON into a DuckDB blob column would just duplicate what git already does, for no benefit. Also no need for an object storage since the dataset is small and considering it's just a proof of concept and no need to run for a long time.

**What it does shortly**
Each run is saved under `data/raw/run_date=<date>/`, so the raw, immutable layer is partitioned by day and committed straight into the repo.

**Traded off** (on the tool)
The repo grows by some KBs a day. That's fine now, but it wouldn't hold up if the payloads got much bigger or longer period.

**With more time**
Nothing I would change at this scale.

---

## 2. Database & Data Warehouse

**Which tool and why**
I chose DuckDB over a client-server database (Postgres/MySQL) or a cloud warehouse (BigQuery/Snowflake/Databricks) because that's infrastructure to run and maintain for no benefit at this scale. DuckDB also reads JSON natively (`read_json`) and lets me query it directly with SQL, so the raw files can be queried as-is.
**Traded off** 
No trade off on the tool I can think.








---

## 3. Transformation & Modelling

**Which tool and why**
I use dbt Core to move data through landing → staging → marts. It's the right fit for the case's requirements — schema/custom tests, generated docs, dev/prod targets — all built in, not something to hand-roll. The dataset is also small (628 rows, one file), which rules out heavier tools like Spark or Airflow-orchestrated transforms meant for distributed compute and multi-source orchestration this project doesn't need.


**What architecture I build here shortly**

1. **Landing** — one row per JSON record, every source field kept as-is (typed VARCHAR/STRUCT to avoid breaking on schema drift in the source), plus a `source_file` column for traceability. Rebuilt from scratch every run by re-reading every committed `run_date=` partition — not appended to, because git is already the durable, versioned copy of each day's raw payload. The landing table is a disposable projection of what git holds, not a second store of history that could drift from it or be lost if the warehouse file is deleted. That way I can see the data and proceed to the next layer after evaluating the data.

2. **Staging** — parses and cleans the landing columns into real types (dates, unpacked structs, etc.); also drop unesseccary columns, still one row per breed, no business logic yet. Also it reads from landing and filters down to only the latest `run_date` partition — the business questions don't care about the data's history, only its current state, so staging doesn't carry the timeline forward.

3. **Marts** — the final tables shaped around the dashboard's actual questions, populating it directly.

**Traded off**
Rebuilding landing from every historical raw file, rather than appending incrementally, means every build re-reads and re-parses all of it, not just the new day — fine at 628 rows, but the cost grows linearly with how long the pipeline has been running, and there's no incremental loading.


**With more time**
Move landing to an incremental model — only parse and load new `run_date` partitions, keyed so a rerun of the same day doesn't duplicate — once the full-rebuild cost stops being negligible. 

On the modelling: `weight`/`height` sometimes embed a male/female split (`"Male: 55-65; Female: 45-55"`) instead of a plain range — staging collapses both shapes to one overall min/max per breed, so the sex-specific split isn't surfaced past this layer. That's deliberate, not an oversight: none of the four target questions need it, and the raw distinction still exists untouched in `landing.breeds` if it's ever needed. Modelling it properly later would mean a separate table at `breed_id` + `sex` grain (one row per sex where the source splits it, one `unisex` row where it doesn't), built off landing rather than off `stg_breeds`, so the normalized shape only gets built once a question actually needs it.

Also, I'd move the "only latest" filter out of staging entirely. Right now stg_breeds cleans and immediately filters to the latest run_date. If reusability and time-series analysis became a requirement, I'd have staging clean and type all historical partitions with no filtering, and push the "latest only" logic down into a new intermediate layer instead. That keeps every cleaned row available for anything that needs history, while marts (or the dashboard) still get a simple, current-state view through the intermediate layer.


---

## 4. Version Control

**Which tool and why**
Git, hosted on GitHub. Every part of this project is text — the Python ingestion script, the SQL models, the workflow YAML, the docs — so there's nothing that needs a store other than git. GitHub specifically because it also gives me Actions and Secrets, so version control, scheduling and CI/CD all live in one system instead of three accounts wired together.


---

## 5. CI/CD

**Which tool and why**
GitHub Actions again, for the same reason as the scheduling: the repo is already on GitHub, so there's no separate CI service to stand up, authorise and maintain. 
**With more time**
Unit tests for `ingest_breeds.py` with the HTTP call mocked, covering the cases that matter: a truncated payload is rejected, a non-200 response raises, the partition path is correct, and re-running the same day is idempotent.


---

## 6. Orchestration & Scheduling

**Which tool and why**
I used GitHub workflows (`.github/workflows/daily-refresh.yml`) because the repo already lives on GitHub, so there's no extra system to stand up — a dedicated orchestrator (Airflow, Dagster, Prefect) would be solving for multi-step DAGs and retries across many jobs, which this single daily fetch doesn't have.
GitHub Actions handles when things run (the daily schedule, retries, secrets), while dbt handles what order the SQL models run in and whether they're correct (tests, docs). Splitting them keeps each tool doing only the job it's good at, instead of one heavy tool trying to do both.

**What it does shortly**
The Github workflow: The Runs on a cron schedule (02:00 UTC daily), plus `workflow_dispatch` so a failed night can be re-run manually without waiting a day. A `concurrency` group prevents two runs from writing the same day's partition at once. It checks out the repo, installs dependencies, runs `src/ingest_breeds.py` with `DOG_API_KEY` from GitHub Secrets, and commits the raw payload back to `main` under a bot identity — only committing when the data actually changed (an identical payload is a successful no-op, not a failure). It then rebuilds the `prod` warehouse and runs every test against the newly landed data.

The dbt build runs *after* the commit on purpose. The raw payload is the thing that can't be regenerated once the day has passed, so it gets stored first; a broken model then fails the run without costing me the day's data.



---

## 7. Dashboard & Visualization

**Which tool and why**
Streamlit, on the same reasoning I've applied everywhere else here: it adds no infrastructure. It's a Python file in the repo that opens the DuckDB file directly — no server to run, no BI connector, no export step, and it's reviewable by reading it like any other source file.

**Traded off**
It's local only. There's nothing deployed, so a reviewer has to clone the repo, install the dependencies and build the warehouse with dbt before they can see anything — which is a real cost for something whose whole purpose is to be looked at.


**With more time**
Deploy it.

