-- Customers churn in the last month they have cover, so each month's actives are
-- last month's actives, minus those who churned last month, plus this month's
-- new and returning customers:
--   active(M) = active(M-1) - churned(M-1) + new(M) + returning(M)
-- Returns the months where that doesn't hold; passes when it returns no rows.
-- (Columns are prefixed n_ because NEW and RETURNING are SQL keywords.)

with monthly as (
    select
        activity_month,
        count(*)                                       as n_active,
        count(*) filter (where movement = 'new')       as n_new,
        count(*) filter (where movement = 'returning') as n_returning,
        count(*) filter (where is_churned)             as n_churned
    from {{ ref('fct_customer_month') }}
    group by activity_month
),

with_previous as (
    select
        *,
        lag(n_active)  over (order by activity_month) as n_previous_active,
        lag(n_churned) over (order by activity_month) as n_previous_churned
    from monthly
)

select *
from with_previous
where n_previous_active is not null
  and n_active <> n_previous_active - n_previous_churned + n_new + n_returning
