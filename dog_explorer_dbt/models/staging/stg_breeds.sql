{{ config(materialized='table', schema='staging') }}

-- One row per breed (same grain as landing). Types are fixed, names are
-- snake_case and self-explanatory. Dropped: `country_codes` (identical to
-- `country_code` in every row), `image.id` (identical to
-- `reference_image_id`), `species_id` (constant "2" across every row, no
-- information), `bred_for`/`perfect_for` (null in every row).

with source as (

    select * from {{ ref('breeds') }}

),

-- landing carries every committed run_date partition; staging only wants
-- the most recent one, so filter down to whichever partition's source_file
-- has the highest run_date.
latest as (

    select *
    from source
    where regexp_extract(source_file, 'run_date=([0-9-]+)', 1) = (
        select max(regexp_extract(source_file, 'run_date=([0-9-]+)', 1))
        from source
    )

),

renamed as (

    -- Every text field is trimmed and blank/whitespace-only strings are
    -- collapsed to NULL (nullif(trim(x), '')), so "" and "   " don't sneak
    -- through as non-null values. Integer casts and source_file are left as-is.
    select
        id::integer as breed_id,
        nullif(trim(name), '') as breed_name,
        nullif(trim(life_span), '') as life_span,
        nullif(trim(temperament), '') as temperament,
        nullif(trim(origin), '') as origin,
        nullif(trim(country_code), '') as country_code,
        nullif(trim(description), '') as description,
        nullif(trim(breed_group), '') as breed_group,
        nullif(trim(history), '') as history,
        nullif(trim(reference_image_id), '') as breed_image_id,
        nullif(trim(image.url), '') as image_url,
        image.width::integer as image_width,
        image.height::integer as image_height,
        nullif(trim(weight.imperial), '') as weight_imperial_raw,
        nullif(trim(weight.metric), '') as weight_metric_raw,
        nullif(trim(height.imperial), '') as height_imperial_raw,
        nullif(trim(height.metric), '') as height_metric_raw,
        nullif(trim(venom_code), '') as alt_breed_code,
        nullif(trim(venom_name), '') as alt_breed_name,
        source_file

    from latest

),

parsed as (

    select
        breed_id,
        breed_name,

        -- "12-15" -> 12 / 15. Null life_span stays null/null, not fabricated.
        split_part(life_span, '-', 1)::integer as life_span_min_years,
        split_part(life_span, '-', 2)::integer as life_span_max_years,

        -- Range midpoint: the single representative life expectancy used to
        -- rank breeds and correlate lifespan against size. Null propagates,
        -- so breeds with no life_span get null rather than a fabricated value.
        (life_span_min_years + life_span_max_years) / 2.0 as life_span_avg_years,

        -- Cleaned comma-separated temperament string. stg_breed_temperaments
        -- splits it into one row per breed x trait.
        temperament,

        origin,
        country_code,
        description,
        breed_group,
        history,
        breed_image_id,
        image_url,
        image_width,
        image_height,

        -- weight/height ranges sometimes embed "Male: a-b; Female: c-d"
        -- instead of a plain "a-b". Pulling every number out and taking the
        -- min/max collapses both shapes into one overall range per breed,
        -- keeping this table at one row per breed. A male/female information is not surfaced to the staging since its not required for the downstream analysis. 
        -- I think if I wanted to surface that, I would create a separate table for male/female ranges in order to keep the one row per breed grain of this table.
        list_min(list_transform(regexp_extract_all(weight_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_imperial_min,
        list_max(list_transform(regexp_extract_all(weight_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_imperial_max,
        list_min(list_transform(regexp_extract_all(weight_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_min_kg,
        list_max(list_transform(regexp_extract_all(weight_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_max_kg,

        list_min(list_transform(regexp_extract_all(height_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_imperial_min,
        list_max(list_transform(regexp_extract_all(height_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_imperial_max,
        list_min(list_transform(regexp_extract_all(height_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_metric_min,
        list_max(list_transform(regexp_extract_all(height_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_metric_max,

        alt_breed_code,
        alt_breed_name,

        -- run_date pulled off the partition path so downstream models can
        -- group/track by load date without re-parsing source_file.
        regexp_extract(source_file, 'run_date=([0-9-]+)', 1) as run_date,
        source_file

    from renamed

),

-- Derived business columns the mart aggregates on:
--   * size_class      -> "How are breeds distributed across weight classes?"
--                        (mart groups by size_class, counts -> breed_count)
--   * life_span_avg_years -> "Is there a relationship between size and life span?"
--                        (mart groups by size_class, avg(life_span_avg_years) -> avg_life_span)
classified as (

    select
        *,

        -- Representative weight (kg): midpoint of the combined min-max range.
        -- Exposed as its own column so the mart and size_class share one value.
        (weight_min_kg + weight_max_kg) / 2.0 as weight_avg_kg,

        -- Size bucket. Cutoffs are kilograms, so this reads the METRIC midpoint,
        -- not imperial. Null weight -> null class, guarded first so weightless
        -- breeds are not silently defaulted into 'Giant'.
        case
            when weight_min_kg is null then null
            when weight_avg_kg <  5 then 'Toy'
            when weight_avg_kg < 10 then 'Small'
            when weight_avg_kg < 25 then 'Medium'
            when weight_avg_kg < 45 then 'Large'
            else 'Giant'
        end as size_class

    from parsed

)

select * from classified
