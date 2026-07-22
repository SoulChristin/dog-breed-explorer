-- Answers: "Is dog size related to predicted life span?" - the plotting half.
--
-- One row per breed: the data a scatter plot of height vs life span needs, and
-- nothing else. Height is the average of the parsed range (cm), life span the
-- midpoint of the published range (years); both are computed once in staging
-- so this model and mart_height_lifespan_correlation read the same values.
--
-- Height is deliberately not bucketed. A scatter plots the raw measurements -
-- banding first would collapse the points the plot exists to show.
--
-- Breeds missing either measure are excluded: a point needs both coordinates.

select
    breed_id,
    breed_name,
    height_avg_cm,
    life_span_avg_years

from {{ ref('stg_breeds') }}
where height_avg_cm is not null
  and life_span_avg_years is not null
order by height_avg_cm, breed_name
