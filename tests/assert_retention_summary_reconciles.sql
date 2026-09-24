-- The summary must lose and duplicate nothing: for every month, each count summed
-- across the summary equals the same count taken straight from fct_customer_month.
-- Returns the months that differ; passes when it returns no rows.

with from_fact as (
    select
        activity_month,
        count(*)                                        as active_customers,
        count(*) filter (where movement = 'new')        as new_customers,
        count(*) filter (where movement = 'continuing') as continuing_customers,
        count(*) filter (where movement = 'returning')  as returning_customers,
        count(*) filter (where is_churned)              as churned_customers
    from {{ ref('fct_customer_month') }}
    group by activity_month
),

from_summary as (
    select
        activity_month,
        sum(active_customers)     as active_customers,
        sum(new_customers)        as new_customers,
        sum(continuing_customers) as continuing_customers,
        sum(returning_customers)  as returning_customers,
        sum(churned_customers)    as churned_customers
    from {{ ref('rpt_monthly_retention_summary') }}
    group by activity_month
)

select
    coalesce(from_fact.activity_month, from_summary.activity_month) as activity_month,
    from_fact.active_customers    as fact_active,
    from_summary.active_customers as summary_active
from from_fact
full outer join from_summary
    on from_fact.activity_month = from_summary.activity_month
where from_fact.active_customers     is distinct from from_summary.active_customers
   or from_fact.new_customers        is distinct from from_summary.new_customers
   or from_fact.continuing_customers is distinct from from_summary.continuing_customers
   or from_fact.returning_customers  is distinct from from_summary.returning_customers
   or from_fact.churned_customers    is distinct from from_summary.churned_customers
