-- Customer counts by cohort, month and segment: the single input to the dashboard.
-- Every measure is a count of distinct customers, and each customer sits in exactly
-- one cohort, country and taxonomy, so rows can be summed across any of those.
-- Rates (retention, churn) are derived when reading; they are not additive.

with customer_months as (
    select
        fct.*,
        customers.cohort_month,
        customers.country,
        customers.acquisition_taxonomy
    from {{ ref('fct_customer_month') }} as fct
    inner join {{ ref('dim_customer') }} as customers
        on fct.customer_id = customers.customer_id
)

select
    customer_months.cohort_month,
    customer_months.activity_month,
    customer_months.months_since_cohort,
    customer_months.country,
    customer_months.acquisition_taxonomy,
    dates.is_churn_complete,
    count(*)                                        as active_customers,
    count(*) filter (where movement = 'new')        as new_customers,
    count(*) filter (where movement = 'continuing') as continuing_customers,
    count(*) filter (where movement = 'returning')  as returning_customers,
    count(*) filter (where is_churned)              as churned_customers
from customer_months
inner join {{ ref('dim_date') }} as dates
    on customer_months.activity_month = dates.date_day
group by all
