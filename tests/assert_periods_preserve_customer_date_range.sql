-- The merge may reshape a customer's timeline but must never shorten, extend or lose it:
-- each customer's first and last active day must match the raw activity exactly.
-- Returns the customers where they don't; the test passes when this returns no rows.

{% set end_date = "date '" ~ var('analysis_end_date') ~ "'" %}

with raw_range as (
    select
        customer_id,
        min(active_from_date)                         as first_day,
        max(least(active_to_date, {{ end_date }}))    as last_day
    from {{ ref('stg_activity') }}
    where active_from_date <= {{ end_date }}
    group by customer_id
),

merged_range as (
    select
        customer_id,
        min(period_start_date) as first_day,
        max(period_end_date)   as last_day
    from {{ ref('int_customer_active_periods') }}
    group by customer_id
)

select
    coalesce(raw_range.customer_id, merged_range.customer_id) as customer_id,
    raw_range.first_day    as raw_first_day,
    merged_range.first_day as merged_first_day,
    raw_range.last_day     as raw_last_day,
    merged_range.last_day  as merged_last_day
from raw_range
full outer join merged_range
    on raw_range.customer_id = merged_range.customer_id
where raw_range.first_day is distinct from merged_range.first_day
   or raw_range.last_day  is distinct from merged_range.last_day
