# Decisions

**Scope:** In a paragraph per layer, which tool you chose and why, what you traded off, and what you would do differently with more time.

---
## 1. Extraction & Ingestion

**Which tool and why**
I used Python with the request library to fetch the dataset from TheDogAPI. I chose requests because is a common libarby among engineers and easy to maintain from others & the script is small — one call, one job every day — a single-endpoint fetch doesn't need beacuse no need for concurrently calls.
Regarding storage, Git stores the raw data in json format. A format that the DuckDB can read. I chose git over an object storage because there is no need since the dataset is small and considering it's just a proof of concept and no need to run for a long time. Also git already gives version history, and diffs for free — putting the same raw JSON into a DuckDB blob column would just duplicate what git already does, for no benefit.

**Traded off**
There's no logging framework — just print to stdout/stderr — so the failure signal today is a non-zero exit code, with no structured detail (timestamps, run IDs, retry counts) beyond what's printed.
The repo grows by some KBs a day. That's fine now, but it wouldn't hold up if the payloads got much bigger or longer period.

**With more time**
One of the things I'd change the hardcoded 500 floor — it was an assumption based on the data count I observed, not a principled threshold, so it's fragile.

---
## 2. Database & Data Warehouse

**Which tool and why**
I chose DuckDB over a client-server database (Postgres/MySQL) or a cloud warehouse (BigQuery/Snowflake/Databricks) because that's infrastructure to run and maintain for no benefit at this scale. DuckDB also reads JSON natively and lets me query it directly with SQL, so the raw files can be queried as-is.

**Traded off** 
No trade off on the tool I can think.

**With more time**
Nothing to change over the toll selection. 

---
## 3. Transformation & Modelling

**Which tool and why**
I use dbt Core to move data through landing → staging → marts. It's the right fit for the case's requirements — schema/custom tests, generated docs, dev/prod targets — all built in, not something to hand-roll. The dataset is also small, which rules out heavier tools like Spark or Airflow-orchestrated transforms meant for distributed compute and multi-source orchestration this project doesn't need.

**---------------------What architecture I build here shortly---------------------**

    1. **Landing** — one row per JSON record, every source field kept as-is, plus a `source_file` column for traceability. Rebuilt from scratch every run by re-reading every committed `run_date=` partition — not appended to, because git is already the durable. The landing table is a disposable projection of what git holds, not a second store of history that could drift from it or be lost if the warehouse file is deleted.

    2. **Staging** — parses and cleans the landing columns into real types (dates, unpacked structs, etc.); also drop unesseccary columns, still one row per breed, no business logic yet.Also, creating the stg_breeds_temperaments in order the temperament column to be queryable (the gran is per breed and temperamen). Also it reads from landing and filters down to only the latest `run_date` partition — the business questions don't care about the data's history, only its current state, so staging doesn't carry the timeline forward.

    3. **Marts** — the final tables shaped around the dashboard's actual questions, populating it directly.

**Traded off**
 Regarding the archtecture: The current architecture does not retain history in the cleaned layer, so time-series analysis is not possible on curated data.

**With more time**
Rebuilding landing from every historical raw file, rather than appending incrementally, means every build re-reads and re-parses all of it, not just the new day — fine at 628 rows, but the cost grows linearly with how long the pipeline has been running, and there's no incremental loading.

On the modelling: `weight`/`height` sometimes embed a male/female split (`"Male: 55-65; Female: 45-55"`) instead of a plain range — staging collapses both shapes to one overall min/max per breed, so the sex-specific split isn't surfaced past this layer. That's deliberate, not an oversight: none of the four target questions need it, and the raw distinction still exists untouched in `landing.breeds` if it's ever needed. Modelling it properly later would mean a separate table at `breed_id` + `sex` grain (one row per sex where the source splits it, one `unisex` row where it doesn't), built off landing rather than off `stg_breeds`, so the normalized shape only gets built once a question actually needs it.

Also, I'd move the "only latest" filter out of staging entirely. Right now stg_breeds cleans and immediately filters to the latest run_date. If reusability and time-series analysis became a requirement, I'd have staging clean and type all historical partitions with no filtering, and push the "latest only" logic down into a new intermediate layer instead. That keeps every cleaned row available for anything that needs history, while marts (or the dashboard) still get a simple, current-state view through the intermediate layer.
I would also add more tests.


---

## 4. Version Control

**Which tool and why**
Git, hosted on GitHub. Every part of this project is text — the Python ingestion script, the SQL models, the workflow YAML, the docs — so there's nothing that needs a store other than git. GitHub specifically because it also gives me Actions and Secrets, so version control, scheduling and CI/CD all live in one system instead of three accounts wired together.

**Traded off** 
No trade off on the tool I can think.

**With more time**
Nothing to change. 

---

## 5. CI/CD

**Which tool and why**
GitHub Actions again, for the same reason as the scheduling: the repo is already on GitHub, so there's no separate CI service to stand up, authorise and maintain. 

**Traded off** 
No trade off on the tool I can think.

**With more time**
If I had more time, I would improve the CI/CD by adding stronger validation, better failure diagnostics, and a clearer “build proved by dev and prod” pipeline.

---

## 6. Orchestration & Scheduling

**Which tool and why**
I used GitHub workflows because the repo already lives on GitHub, so there's no extra system to stand up — a dedicated orchestrator (Airflow, Dagster, Prefect) would be solving for multi-step DAGs and retries across many jobs, which this single daily fetch doesn't have.
GitHub handles when things run (the daily schedule, retries, secrets), while dbt handles what order the SQL models run in and whether they're correct (tests, docs). Splitting them keeps each tool doing only the job it's good at, instead of one heavy tool trying to do both.

**Traded off** 
Simple and cheap now but less powerful (lose the observability on data) for future growth.

**With more time**
At this scale, I would not replace the orchestrator. I would only strengthen the failure reporting and keep the scheduled job simple.
---

## 7. Dashboard & Visualization

**Which tool and why**
Streamlit, on the same reasoning I've applied everywhere else here: it adds no infrastructure. It's a Python file in the repo that opens the DuckDB file directly — no server to run, no BI connector, no export step, and it's reviewable by reading it like any other source file.

**Traded off**
It's local only. There's nothing deployed, so a reviewer has to clone the repo, install the dependencies and build the warehouse with dbt before they can see anything.

**With more time**
Deploy it.

