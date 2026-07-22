-- Answers: "How are breeds distributed across weight classes?"
--
-- One row per weight class. Kept deliberately small: a mart that answers a
-- question should be readable in full on one screen, and this one is five rows.


with breeds as (

    select *
    from {{ ref('stg_breeds') }}
    where weight_class is not null

)

select
    weight_class,

    -- Ordering column. Alphabetical would render Giant, Large, Medium, Small,
    -- Toy - which reads as meaningless on a chart axis. Every consumer of this
    -- model should order by this, not by the label.
    case weight_class
        when 'Toy'    then 1
        when 'Small'  then 2
        when 'Medium' then 3
        when 'Large'  then 4
        when 'Giant'  then 5
    end                                             as weight_rank,

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
group by weight_class
order by weight_rank
