-- One row per customer, including those with no activity in the analysis window.

with customers as (
    select * from {{ ref('stg_customers') }}
),

acquisition as (
    select * from {{ ref('stg_acq_orders') }}
),

activity_summary as (
    select
        customer_id,
        min(period_start_date)                   as first_active_date,
        max(period_end_date)                     as last_active_date,
        count(*)                                 as n_active_periods,
        cast(sum(period_length_days) as integer) as total_active_days,
        bool_or(is_open_at_extract_end)          as is_active_at_extract_end
    from {{ ref('int_customer_active_periods') }}
    group by customer_id
)

select
    customers.customer_id,
    customers.country,
    coalesce(acquisition.acquisition_taxonomy, 'Unknown')  as acquisition_taxonomy,
    cast(date_trunc('month', activity_summary.first_active_date) as date) as cohort_month,
    activity_summary.first_active_date,
    activity_summary.last_active_date,
    coalesce(activity_summary.n_active_periods, 0) as n_active_periods,
    coalesce(activity_summary.total_active_days, 0) as total_active_days,
    coalesce(activity_summary.is_active_at_extract_end, false) as is_active_at_extract_end,
    activity_summary.customer_id is not null as has_activity
from customers
left join acquisition
    on customers.customer_id = acquisition.customer_id
left join activity_summary
    on customers.customer_id = activity_summary.customer_id
