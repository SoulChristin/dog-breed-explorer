-- Answers: "What are the top temperaments among family-friendly breeds?"
--
-- DEFINING "FAMILY-FRIENDLY" TRANSPARENTLY
--
-- A breed counts as family-friendly here if it carries at least one of a short
-- list of traits associated with tolerance of children and household life.
-- This is a stated convention, not a fact about dogs.


with family_traits as (

    select unnest([
        'affectionate',
        'friendly',
        'gentle',
        'good-natured',
        'patient',
        'playful',
        'sweet-tempered',
        'tolerant'
    ]) as trait_key

),

family_friendly_breeds as (

    select distinct t.breed_id
    from {{ ref('stg_breed_temperaments') }} t
    inner join family_traits f on lower(t.trait_key) = lower(f.trait_key)

),

trait_counts as (

    select
        t.trait,
        t.trait_key,
        count(distinct t.breed_id) as breed_count
    from {{ ref('stg_breed_temperaments') }} t
    inner join family_friendly_breeds ff on t.breed_id = ff.breed_id
    group by t.trait, t.trait_key

)

select
    trait,
    trait_key,
    breed_count,
    round(
        100.0 * breed_count / (select count(*) from family_friendly_breeds),
        1
    ) as pct_of_family_friendly_breeds,
    -- Flags whether this trait is one of the defining ones, so a reader can
    -- tell at a glance which rows are circular by construction.
    trait_key in (select lower(trait_key) from family_traits) as is_defining_trait
from trait_counts
order by breed_count desc
