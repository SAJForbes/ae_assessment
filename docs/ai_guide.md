# AI guide

For AI assistants querying the retention models, and the people setting them up. It covers the rules to follow and tested example queries to adapt. For what each metric means and what every column contains, see the [user guide](user_guide.md).

## Why use the modelled tables

**Query the modelled tables and use their definitions. Never query the raw files.**

## What makes these tables safe to query

1. **One clear grain per table**, stated in its description. In `fct_customer_month`,
   `count(*)` counts customers, and no de-duplication is needed.
2. **Every column is described** in the dbt YAML. Those descriptions are published in dbt's
   docs and metadata (`target/manifest.json`), which is where an AI tool picks up context.
3. **Categorical values are listed and tested** (`accepted_values`), so an AI knows `movement`
   can only be `new`, `continuing` or `returning`.
4. **The traps are written down** where an AI will read them: in the table descriptions and in
   the rules below.
5. **The example queries below are tested patterns** an AI can adapt rather than invent.

## Rules for querying

Give these to an AI assistant (or a new analyst) before it writes SQL against these tables:

1. Use `fct_customer_month` for monthly questions and `int_customer_active_periods` for
   date-range or duration questions. Don't use staging tables or the raw CSVs.
2. Get country, treatment and cohort by joining `dim_customer` on `customer_id`.
3. Never add monthly customer counts across months. For a period total, use
   `count(distinct customer_id)` or the periods table.
4. Churn is the `is_churned` flag, not a value of `movement`. A churned customer is still active
   that month, so the flag sits on top of `new`, `continuing` or `returning`. Count churn with
   `count(*) filter (where is_churned)`, and never add it to the active total.
   See [Churn is not a movement](user_guide.md#churn-is-not-a-movement).
5. When reporting churn, filter on `dim_date.is_churn_complete`. July 2024's churn isn't final.
6. For retention curves across cohorts, use only cohorts that have reached the month in
   question (query g).
7. `new` and `returning` are SQL keywords. Use them as quoted values (`movement = 'new'`), but
   don't use them as bare column aliases (use `n_new`).
8. Treat segments with fewer than ~100 customers as noise (Unknown, Sleep in Brazil, and TRT
   in early cohorts).

## Example queries

DuckDB SQL; paste them into the DuckDB UI (`scripts/explore.py`). They answer the questions
the model was designed around. Every one has been run against the built database, and the
results shown are real.

### a. How many active customers did we have last month, by treatment and country?

```sql
select d.acquisition_taxonomy, d.country, count(*) as active_customers
from fct_customer_month f
join dim_customer d on d.customer_id = f.customer_id
where f.activity_month = date '2024-07-01'
group by 1, 2
order by active_customers desc;
```

`count(*)` is correct: `fct_customer_month` has one row per customer per month, so each row
is one customer. Hair Loss in Brazil is 118,239 of the 191,784 total.

### b. Of the customers acquired in January 2023, what share were active 12 months later?

```sql
select
    count(*) filter (where f.months_since_cohort = 0)  as cohort_size,
    count(*) filter (where f.months_since_cohort = 12) as active_at_month_12,
    round(100.0 * active_at_month_12 / cohort_size, 1) as retention_12m_pct
from fct_customer_month f
join dim_customer d on d.customer_id = f.customer_id
where d.cohort_month = date '2023-01-01';
```

11,991 customers, 3,884 active at month 12: **32.4%**.

### c. What's our monthly churn rate, and how many customers came back?

```sql
select
    f.activity_month,
    count(*)                                         as n_active,
    count(*) filter (where f.is_churned)             as n_contracts_ended,
    round(100.0 * n_contracts_ended / n_active, 1)   as churn_rate_pct,
    count(*) filter (where f.movement = 'returning') as n_returning
from fct_customer_month f
join dim_date dd on dd.date_day = f.activity_month
where dd.is_churn_complete                -- the latest month's churn isn't final
  and f.activity_month >= date '2024-01-01'
group by 1
order by 1;
```

Churn runs at 10–11% a month in 2024. To follow one group of churned customers forward, for
example *of the contracts that ended in January 2024, how many came back?*, use the periods
table:

```sql
with ended_jan as (
    select customer_id, period_number
    from int_customer_active_periods
    where period_end_date between date '2024-01-01' and date '2024-01-31'
      and not is_open_at_extract_end
)
select
    count(*)                                                  as contracts_ended,
    count(*) filter (where later.customer_id is not null)    as came_back_by_jul_2024,
    round(100.0 * came_back_by_jul_2024 / contracts_ended, 1) as came_back_pct
from ended_jan e
left join int_customer_active_periods later
    on later.customer_id = e.customer_id
   and later.period_number = e.period_number + 1;
```

17,368 contracts ended; 4,365 (**25.1%**) had come back by July.

### d. How long do customers stay, and how long are they away before coming back?

Time away, by treatment:

```sql
select
    d.acquisition_taxonomy,
    count(*)                        as n_returns,
    median(f.days_inactive_before)  as median_days_away
from fct_customer_month f
join dim_customer d on d.customer_id = f.customer_id
where f.movement = 'returning'
group by 1
order by n_returns desc;
```

Returning Hair Loss customers were away for a median of 113 days, ED 138, Weight Loss 72.

For **how long customers stay**, use the cohort retention curve (query g), not the average
contract length. Contracts still running on 31 July haven't ended yet. Including them
understates lifetimes, and excluding them keeps only the customers who left early. The
retention curve handles both correctly: median lifetime is the month where the curve falls
below 50% (month 7 across all treatments: 50.4% at month 6, 41.0% at month 7).

### e. Which customers were active between two specific dates?

```sql
select count(distinct customer_id) as customers_active_in_range
from int_customer_active_periods
where period_start_date <= date '2024-06-30'   -- range end
  and period_end_date   >= date '2024-04-01';  -- range start
```

A period overlaps the range if it starts before the range ends and ends after it starts.
Result: **219,453** customers in Q2 2024. Remove `count(distinct …)` to list them.

> **Don't add monthly figures together to get a period total.** Summing April + May + June
> active customers gives 531,407, which is 2.4× too many, because the same customers are
> counted in every month.

### f. Cohort retention triangle

```sql
with cohort_size as (
    select d.cohort_month, count(*) as n
    from fct_customer_month f
    join dim_customer d on d.customer_id = f.customer_id
    where f.months_since_cohort = 0
    group by 1
)
select
    d.cohort_month,
    f.months_since_cohort,
    round(100.0 * count(*) / any_value(s.n), 1) as retention_pct
from fct_customer_month f
join dim_customer d on d.customer_id = f.customer_id
join cohort_size s  on s.cohort_month = d.cohort_month
where d.cohort_month >= date '2023-01-01'
  and f.months_since_cohort in (0, 1, 3, 6, 12)
group by 1, 2
order by 1, 2;
```

### g. Average retention curve across cohorts

```sql
with cohorts as (
    select customer_id, cohort_month
    from dim_customer
    where cohort_month >= date '2021-01-01'
),
months as (select unnest(range(0, 25)) as m),
eligible as (
    -- at month m, only cohorts old enough to have reached month m
    select m.m, c.customer_id
    from months m
    join cohorts c on date_diff('month', c.cohort_month, date '2024-07-01') >= m.m
)
select
    e.m                                               as months_since_cohort,
    count(*)                                          as eligible_customers,
    round(100.0 * count(f.customer_id) / count(*), 1) as retention_pct
from eligible e
left join fct_customer_month f
    on f.customer_id = e.customer_id and f.months_since_cohort = e.m
group by 1
order by 1;
```

The `eligible` step matters. If every cohort's size goes into the denominator at every
month, recent cohorts that haven't reached month 24 yet count as lost, and month-24
retention comes out at 5.2% instead of the correct 18.8%.

### h. One customer's history

```sql
select activity_month, movement, is_churned, months_since_cohort, days_inactive_before
from fct_customer_month
where customer_id = 38757
order by activity_month;
```