-- One row per customer per month with any active day.
-- movement:   how the customer started the month
--   new        : their first contract starts this month
--   returning  : a later contract starts this month, after an earlier one ended
--   continuing : any other active month
-- is_churned: their contract ends this month (cover stops and doesn't restart within
-- grace_period_days). Only final where dim_date.is_churn_complete is true.

with periods as (
    select
        customer_id,
        period_number,
        period_start_date,
        period_end_date,
        days_since_previous_period,
        is_open_at_extract_end,
        cast(date_trunc('month', lag(period_end_date) over (
            partition by customer_id order by period_number
        )) as date) as previous_period_end_month
    from {{ ref('int_customer_active_periods') }}
),

period_months as (
    -- Expand each period into every calendar month it touches.
    select
        periods.*,
        cast(date_trunc('month', period_start_date) + to_months(cast(n as integer)) as date) as activity_month,
        n = 0                                                        as starts_this_month,
        n = date_diff('month', period_start_date, period_end_date)  as ends_this_month
    from periods,
        unnest(generate_series(0, date_diff('month', period_start_date, period_end_date))) as months(n)
),

customer_months as (
    -- Two periods can touch the same month (one ends early, the next starts late).
    select
        customer_id,
        activity_month,
        bool_or(starts_this_month and period_number = 1) as is_first_month,
        -- A later contract starting here is a return only if the previous one ended in an
        -- earlier month; an end and restart within one calendar month is neither.
        bool_or(starts_this_month and period_number > 1
                and previous_period_end_month < activity_month) as is_return_month,
        max(case
            when starts_this_month and period_number > 1
                 and previous_period_end_month < activity_month
                then days_since_previous_period
        end)                                                   as days_inactive_before,
        -- Churned if the latest period touching the month ends in it and is known to have ended.
        arg_max(ends_this_month and not is_open_at_extract_end, period_number) as is_churned
    from period_months
    group by customer_id, activity_month
)

select
    customer_id,
    activity_month,
    case
        when is_first_month  then 'new'
        when is_return_month then 'returning'
        else 'continuing'
    end                                                                    as movement,
    true                                                                   as is_active,
    is_churned,
    date_diff('month', min(activity_month) over (partition by customer_id), activity_month) as months_since_cohort,
    days_inactive_before
from customer_months
