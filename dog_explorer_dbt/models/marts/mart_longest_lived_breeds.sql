-- Answers: "Which breeds have the longest predicted life span?"
--
-- Ranked on the midpoint of the published range, not the maximum. Ranking on
-- the maximum rewards a breed with a wide, uncertain range ("10-18") over one
-- with a tight, high one ("15-16"), which is an artefact of how the source
-- writes ranges rather than a fact about the dogs.
--
-- Only parsed, typed columns are exposed here; the original published range
-- string stays in landing.breeds if the ranking ever needs auditing.

select
    breed_name,
    breed_group,
    size_class,

    life_span_avg_years,
    life_span_min_years,
    life_span_max_years,

    weight_avg_kg,

    -- Ties are common: 147 breeds share "12-15". rank() rather than
    -- row_number() so tied breeds share a position instead of being ordered
    -- arbitrarily by whatever the engine returns first.
    rank() over (order by life_span_avg_years desc) as life_span_rank,

    run_date

from {{ ref('stg_breeds') }}
where life_span_avg_years is not null
order by life_span_avg_years desc, breed_name
