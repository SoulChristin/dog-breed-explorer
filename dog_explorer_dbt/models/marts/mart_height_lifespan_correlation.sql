-- Answers: "Is dog size related to predicted life span?" - the coefficient.
--
-- One row. The Pearson correlation between average breed height (cm) and the
-- life-span midpoint (years), over the same breeds mart_height_lifespan_scatter
-- plots, so the number and the picture always agree.
--
-- Computed on the raw measurements, not on size bands: bucketing a continuous
-- variable before correlating it discards the resolution the coefficient is
-- measuring.

select
    count(*)                                            as n_breeds,
    round(corr(height_avg_cm, life_span_avg_years), 3)  as pearson_r

from {{ ref('mart_height_lifespan_scatter') }}
