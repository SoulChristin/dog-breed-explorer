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

    select
        id::integer as breed_id,
        trim(name) as breed_name,
        life_span,
        temperament,
        trim(origin) as origin,
        country_code,
        description,
        breed_group,
        history,
        reference_image_id as breed_image_id,
        image.url as image_url,
        image.width::integer as image_width,
        image.height::integer as image_height,
        weight.imperial as weight_imperial_raw,
        weight.metric as weight_metric_raw,
        height.imperial as height_imperial_raw,
        height.metric as height_metric_raw,
        venom_code as alt_breed_code,
        venom_name as alt_breed_name,
        source_file

    from latest

),

parsed as (

    select
        breed_id,
        breed_name,

        -- "12-15" -> 12 / 15. Null life_span stays null/null, not fabricated.
        split_part(life_span, '-', 1)::integer as life_span_min,
        split_part(life_span, '-', 2)::integer as life_span_max,

        -- comma-separated string -> trimmed list, so it's filterable with
        -- list_contains() instead of substring matching.
        list_transform(string_split(temperament, ','), x -> trim(x)) as temperament,

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
        list_min(list_transform(regexp_extract_all(weight_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_metric_min,
        list_max(list_transform(regexp_extract_all(weight_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as weight_metric_max,

        list_min(list_transform(regexp_extract_all(height_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_imperial_min,
        list_max(list_transform(regexp_extract_all(height_imperial_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_imperial_max,
        list_min(list_transform(regexp_extract_all(height_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_metric_min,
        list_max(list_transform(regexp_extract_all(height_metric_raw, '[0-9]+\.?[0-9]*'), x -> x::double)) as height_metric_max,

        alt_breed_code,
        alt_breed_name,
        source_file

    from renamed

)

select * from parsed
