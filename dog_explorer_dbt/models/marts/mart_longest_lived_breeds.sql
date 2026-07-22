-- Answers: "Which breeds have the longest predicted life span?"

select
    breed_name,
    breed_group,
    weight_class,
    life_span_avg_years,
    life_span_min_years,
    life_span_max_years,
    weight_avg_kg,
    -- Many breeds have the same life span (e.g. "12-15").
    -- Use RANK() so breeds with the same life span get the same rank,
    -- instead of ROW_NUMBER(), which would assign them different numbers.
    rank() over (order by life_span_avg_years desc) as life_span_rank,
    run_date

from {{ ref('stg_breeds') }}
where life_span_avg_years is not null
order by life_span_avg_years desc, breed_name
