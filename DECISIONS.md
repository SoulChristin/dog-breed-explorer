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
3. Transformation & Modelling
4. Version Control
5. CI/CD
6. Orchestration & Schedulling
7. Dashboard & Visualization
