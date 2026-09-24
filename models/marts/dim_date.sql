-- One row per day, from the first month with activity to analysis_end_date.
-- Month facts join on month_start_date = activity_month (the first of the month).

{% set end_date = "date '" ~ var('analysis_end_date') ~ "'" %}

with bounds as (
    select cast(date_trunc('month', min(period_start_date)) as date) as first_day
    from {{ ref('int_customer_active_periods') }}
),

days as (
    select cast(unnest(generate_series(first_day, {{ end_date }}, interval 1 day)) as date) as date_day
    from bounds
)

select
    date_day,
    cast(date_trunc('month', date_day) as date)        as month_start_date,
    strftime(date_day, '%Y-%m')                        as month_label,
    year(date_day) || '-Q' || quarter(date_day)        as quarter_label,
    year(date_day)                                     as year,
    date_day = cast(date_trunc('month', date_day) as date) as is_month_start,
    -- Churn in a month is only final once grace_period_days have passed after its last day.
    last_day(date_day) + {{ var('grace_period_days') }} <= {{ end_date }} as is_churn_complete
from days
