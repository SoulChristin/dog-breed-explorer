-- Fails if any parsed min/max range is inverted (min > max). The staging
-- model derives these bounds via regex extraction, so a malformed source
-- string could silently produce a lower bound above the upper bound.
select
    breed_id,
    breed_name
from {{ ref('stg_breeds') }}
where life_span_min      > life_span_max
   or weight_imperial_min > weight_imperial_max
   or weight_metric_min   > weight_metric_max
   or height_imperial_min > height_imperial_max
   or height_metric_min   > height_metric_max
