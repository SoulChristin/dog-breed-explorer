-- Answers two of the case's four questions at once:
--   "How are breeds distributed across weight classes?"  -> breed_count
--   "Is there a relationship between size and life span?" -> avg_life_span
--
-- One row per size class. Kept deliberately small: a mart that answers a
-- question should be readable in full on one screen, and this one is five rows.
--
-- Breeds with no parsed weight are excluded rather than bucketed into an
-- "Unknown" band - a size/lifespan comparison over breeds whose size is
-- unknown is not a comparison.

with breeds as (

    select *
    from {{ ref('stg_breeds') }}
    where size_class is not null

)

select
    size_class,

    -- Ordering column. Alphabetical would render Giant, Large, Medium, Small,
    -- Toy - which reads as meaningless on a chart axis. Every consumer of this
    -- model should order by this, not by the label.
    case size_class
        when 'Toy'    then 1
        when 'Small'  then 2
        when 'Medium' then 3
        when 'Large'  then 4
        when 'Giant'  then 5
    end                                             as size_rank,

    count(*)                                        as breed_count,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_breeds,

    round(avg(weight_avg_kg), 1)                    as avg_weight_kg,
    round(min(weight_min_kg), 1)                    as min_weight_kg,
    round(max(weight_max_kg), 1)                    as max_weight_kg,

    -- Life span averages skip breeds with no published range, so this count
    -- says how many breeds each average actually rests on.
    count(life_span_avg_years)                      as breeds_with_life_span,
    round(avg(life_span_avg_years), 2)              as avg_life_span_years,
    round(min(life_span_min_years), 1)              as min_life_span_years,
    round(max(life_span_max_years), 1)              as max_life_span_years

from breeds
group by size_class
order by size_rank
