-- Builds a long-format staging table of breed traits from the cleaned
-- stg_breeds model.
--
-- What it does:
--   * starts from stg_breeds
--   * keeps only rows where temperament is not null
--   * splits the comma-separated temperament string into separate values
--   * trims whitespace and normalises them to lower case
--   * filters out empty values
--   * emits one row per breed-trait pair
--   * adds a capitalised display label for each trait
--
-- Output: one row per breed x trait, so traits can be joined, grouped, and
-- counted across breeds.


with source as (

    select
        breed_id,
        temperament,
        run_date
    from {{ ref('stg_breeds') }}
    where temperament is not null

),

exploded as (

    select
        breed_id,
        run_date,
        trim(unnest(str_split(temperament, ','))) as trait_raw
    from source

),

normalised as (

    select
        breed_id,
        run_date,
        trait_raw,
        lower(trait_raw) as trait_key
    from exploded
    where trait_raw <> ''

)

-- DISTINCT because normalising case can collapse two source entries into one:
-- a breed listing both "Friendly" and "friendly" would otherwise produce two
-- identical rows and break the uniqueness test on (breed_id, trait_key).
select distinct
    breed_id,
    -- Canonical lower-case form: the key to group and join on.
    trait_key,
    -- Display form, capitalised from the canonical value so that
    -- "affectionate" and "Affectionate" collapse to one label.
    upper(substr(trait_key, 1, 1)) || substr(trait_key, 2) as trait,
    run_date
from normalised
where length(trait_key) <= 30
