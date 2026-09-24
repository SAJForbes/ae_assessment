-- Merges every subscription interval into continuous, customer-level active periods.
-- A customer is active if ANY of their subscriptions is running (the brief: subscription
-- count does not change how "active" a customer is). Gaps of up to grace_period_days
-- uncovered days are bridged, so routine renewal and payment-retry gaps don't split a period.

{% set grace_days = var('grace_period_days') %}
{% set end_date = "date '" ~ var('analysis_end_date') ~ "'" %}

with activity as (
    -- Drop the August 2024 fragments; cap anything running past the analysis end.
    select
        customer_id,
        subscription_id,
        active_from_date,
        least(active_to_date, {{ end_date }}) as active_to_date
    from {{ ref('stg_activity') }}
    where active_from_date <= {{ end_date }}
),

with_previous_coverage as (
    -- Latest end date among ALL earlier rows for the customer. A running max, not lag():
    -- a long row can still be covering the customer after shorter rows have ended.
    select
        *,
        max(active_to_date) over (
            partition by customer_id
            order by active_from_date, active_to_date, subscription_id
            rows between unbounded preceding and 1 preceding
        ) as covered_until
    from activity
),

flagged as (
    -- A row starts a new period if it's the customer's first, or if more than
    -- grace_days uncovered days separate it from everything before it.
    select
        *,
        case
            when covered_until is null then 1
            when date_diff('day', covered_until, active_from_date) - 1 > {{ grace_days }} then 1
            else 0
        end as starts_new_period
    from with_previous_coverage
),

numbered as (
    -- Running count of period starts = the period each row belongs to.
    -- ROWS (not the default RANGE) so tied dates don't get summed together.
    select
        *,
        cast(sum(starts_new_period) over (
            partition by customer_id
            order by active_from_date, active_to_date, subscription_id
            rows between unbounded preceding and current row
        ) as integer) as period_number
    from flagged
),

periods as (
    select
        customer_id,
        period_number,
        min(active_from_date)           as period_start_date,
        max(active_to_date)             as period_end_date,
        count(distinct subscription_id) as subscriptions_in_period
    from numbered
    group by customer_id, period_number
)

select
    customer_id,
    period_number,
    period_start_date,
    period_end_date,
    date_diff('day', period_start_date, period_end_date) + 1 as period_length_days,
    date_diff(
        'day',
        lag(period_end_date) over (partition by customer_id order by period_number),
        period_start_date
    ) - 1                                                    as days_since_previous_period,
    subscriptions_in_period,
    -- Within grace of the analysis end, a period may just be mid-renewal: not known to have ended.
    period_end_date >= {{ end_date }} - {{ grace_days }}     as is_open_at_extract_end
from periods
