{{ config(materialized='table', schema='landing') }}

-- Reads every committed run_date partition and rebuilds from scratch each
-- run - no insert/append, so there's no idempotency problem here. Every
-- field from the raw payload is carried through untouched, only adds the source file name is added to the output for traceability.
-- the dattypes are all set to NVARCHAR to avoid any issues with schema evolution in the source JSON.
with source as (

    select
        * exclude (filename),
        filename as source_file
    from read_json(
        '../data/raw/run_date=*/breeds.json',
        filename = true,
        hive_partitioning = false,
        columns = {
            id: 'VARCHAR',
            name: 'VARCHAR',
            species_id: 'VARCHAR',
            life_span: 'VARCHAR',
            temperament: 'VARCHAR',
            origin: 'VARCHAR',
            country_codes: 'VARCHAR',
            country_code: 'VARCHAR',
            description: 'VARCHAR',
            bred_for: 'VARCHAR',
            perfect_for: 'VARCHAR',
            breed_group: 'VARCHAR',
            history: 'VARCHAR',
            reference_image_id: 'VARCHAR',
            weight: 'STRUCT(imperial VARCHAR, metric VARCHAR)',
            height: 'STRUCT(imperial VARCHAR, metric VARCHAR)',
            venom_code: 'VARCHAR',
            venom_name: 'VARCHAR',
            image: 'STRUCT(id VARCHAR, url VARCHAR, width VARCHAR, height VARCHAR)'
        }
    )

)

select *
from source
