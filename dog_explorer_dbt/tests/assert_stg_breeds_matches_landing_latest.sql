-- tests/assert_stg_breeds_matches_landing_latest.sql
-- Validates curation completeness: every breed in the latest run_date
-- partition of landing survives into stg_breeds, and stg_breeds introduces
-- no breed that isn't in that partition.
with landing_latest as (
    select id::integer as breed_id
    from {{ ref('breeds') }}
    where regexp_extract(source_file, 'run_date=([0-9-]+)', 1) = (
        select max(regexp_extract(source_file, 'run_date=([0-9-]+)', 1))
        from {{ ref('breeds') }}
    )
),

staging as (
    select breed_id from {{ ref('stg_breeds') }}
)

-- in latest landing but missing from staging  (rows lost during curation)
select breed_id, 'dropped_from_staging' as issue
from landing_latest
where breed_id not in (select breed_id from staging)

union all

-- in staging but not in latest landing  (rows that shouldn't exist)
select breed_id, 'extra_in_staging' as issue
from staging
where breed_id not in (select breed_id from landing_latest)