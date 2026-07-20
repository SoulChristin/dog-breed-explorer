Scope:  In a paragraph per layer, which tool you chose and why, what you traded off, and what you would do differently with
more time.

1. Extraction & Ingestion

    --Extraction:
    Which tool and why:     
        I used Python with the request library to fetch the dataset from TheDogAPI. I chose requests because is a common libarby among engineers and easy to maintain from others & the script is small — one call, one job every day — a single-endpoint fetch doesn't need beacuse no need for concurrently calls.
    
    What it does shortly (dog-breed-explorer\src\ingest_breeds.py):  
        It fetches the data with idempotent runs, refuses anything that looks partial, and write only complete, validated payloads to disk preserving the data untouched. Failures are handled selectively.

    Traded off:
         There's no logging framework — just print to stdout/stderr — so the failure signal today is a non-zero exit code, with no structured detail (timestamps, run IDs, retry counts) beyond what's printed.

    With more time:
         One of the things I'd change the hardcoded 500 floor — it was an assumption based on the data count I observed, not a principled threshold, so it's fragile.

    --Storage: 
     Which tool and why: 
        Git stores the raw data in json format. A format that the DuckDB can read. I chose git over an object storage because git already gives version history, and diffs for free — putting the same raw JSON into a DuckDB blob column would just duplicate what git already does, for no benefit. Also no need for an object storage since the dataset is small and considering it's just a proof of concept and no need to run for a long time.

    What it does shortly:  
        Each run is saved under data/raw/run_date=<date>/, so the raw, immutable layer is partitioned by day and committed straight into the repo

    Traded off (on the tool): The repo grows by some KBs a day. That's fine now, but it wouldn't hold up if the payloads got much bigger or longer period.

    With more time: Nothing I would change at this scale. 

2. Database & Data Warehouse

    Which tool and why: 
        I chose DuckDB over a client-server database (Postgres/MySQL) or a cloud warehouse (BigQuery/Snowflake/Databricks) because that's infrastructure to run and maintain for no benefit at this scale. DuckDB also reads JSON natively (read_json) and lets me query it directly with SQL, so the raw files can be queried as-is.
        
    What arhitecture I build here shortly:
    Three layers in one DuckDB file (warehouse/dog_explorer_dev.duckdb):
    1) Landing — one row per JSON record, every source field kept as-is (typed VARCHAR/STRUCT to avoid breaking on schema drift in the source), plus a source_file column for traceability. Rebuilt from scratch every run by re-reading every committed run_date= partition — not appended to, because git is already the durable, versioned copy of each day's raw payload. The landing table is a disposable projection of what git holds, not a second store of history that could drift from it or be lost if the warehouse file is deleted. Tht way I can see the data and proceed to the next layer after evaluating the data.
    2) Staging — parses and cleans the landing columns into real types (dates, unpacked structs, etc.); still one row per breed, no business logic yet.
    3) Marts — the final tables shaped around the dashboard's actual questions, populating it directly.

    Traded off: Rebuilding landing from every historical raw file, rather than appending incrementally, means every build re-reads and re-parses all of it, not just the new day — fine at 628 rows, but the cost grows linearly with how long the pipeline has been running, and there's no incremental loading.

    With more time:
    Move landing to an incremental model — only parse and load new run_date partitions, keyed so a rerun of the same day doesn't duplicate — once the full-rebuild cost stops being negligible. I'd also add dbt tests (not_null/unique on id, accepted_values on categorical fields) at each layer boundary.


3. Transformation & Modelling
    Which tool and why: 
    I use dbt Core to move data through landing → staging → marts. It's the right fit for the case's requirements — schema/custom tests, generated docs, dev/prod targets — all built in, not something to hand-roll. The dataset is also small (628 rows, one file), which rules out heavier tools like Spark or Airflow-orchestrated transforms meant for distributed compute and multi-source orchestration this project doesn't need.

    What it does shortly:  

    Trade-off: 
    There isn't really a trade-off on the tool choice itself.

    With more time: 


4. Version Control
    Which tool and why: 
        
    What it does shortly:  

    Traded off: 

    With more time: 

5. CI/CD
    Which tool and why: 
        
    What it does shortly:  

    Traded off: 

    With more time: 

6. Orchestration & Schedulling

    Which tool and why: 
        
    What it does shortly:  

    Traded off: 

    With more time: 

7. Dashboard & Visualization
    Which tool and why: 
        
    What it does shortly:  

    Traded off: 

    With more time: 
