# User guide

How to query the retention models: which table to use, what every term means, and what every
column contains. For rules and example queries aimed at AI assistants, see the
[AI guide](ai_guide.md). For how the model was built and why, see the [README](../README.md).

## Which table to use

| Your question is about… | Use | Grain |
|---|---|---|
| Active customers, new / continuing / returning, churn, cohorts, by month | `fct_customer_month` | customer × month |
| A customer's country, treatment or cohort | `dim_customer` (join on `customer_id`) | customer |
| Activity between any two dates, contract lengths, time away | `int_customer_active_periods` | customer × continuous active period |
| Calendar labels, and whether a month's churn is final | `dim_date` | day |
| The dashboard's pre-aggregated counts | `rpt_monthly_retention_summary` | cohort × month × country × treatment |

## Definitions

| Term | Definition |
|---|---|
| **Active** | The customer is covered by at least one subscription on any day of the month. Two subscriptions don't make them "more active". |
| **Active period** (contract) | An unbroken stretch of cover, after merging all of a customer's subscriptions and bridging gaps of up to 28 days. |
| **New** (`movement = 'new'`) | The month the customer's first contract starts. |
| **Continuing** (`movement = 'continuing'`) | An active month carried on from the previous month. |
| **Returning** (`movement = 'returning'`) | The month a later contract starts, after an earlier one ended. |
| **Churn** (`is_churned = true`) | The customer's contract ends this month: cover stops and doesn't restart within 28 days. **A separate flag, not a fourth movement:** the customer is still active that month, so a churned month is also new, continuing or returning. See [Churn is not a movement](#churn-is-not-a-movement). |
| **Cohort** | The month of the customer's first active day. |
| **Acquisition treatment** | The treatment category of the order that acquired the customer (`acquisition_taxonomy`). Fixed for life. |
| **Churn rate** | Contract ends in the month ÷ active customers that month. Only for complete months. |
| **Monthly retention** | Customers continuing this month ÷ active customers last month. |
| **Cohort retention at month n** | Customers active *n* months after their cohort month ÷ cohort size. Customers who left and came back count as active. |

**The latest month's churn is never final.** A contract end is only confirmed once 28 days
have passed without cover. With data ending on 31 July 2024, only July contract ends on 1–2
July are known. `dim_date.is_churn_complete` marks the months that are final (up to June 2024).

### Churn is not a movement

Each row of `fct_customer_month` answers two separate questions about a customer's month:

| Question | Column | Values |
|---|---|---|
| How did the customer **start** the month? | `movement` | exactly one of `new`, `continuing`, `returning` |
| Did their contract **end** during the month? | `is_churned` | true or false, independently of `movement` |

A customer churns in the **last month they have cover**, so they are still active in that
month. Churn therefore sits *on top of* one of the three movements rather than replacing it.
All six combinations occur:

| `movement` | not churned | churned | A churned month means… |
|---|---|---|---|
| `continuing` | 2,896,212 | 417,351 | an existing customer's contract ended this month (the usual case) |
| `new` | 478,865 | 27,398 | the customer's first contract started and ended in the same calendar month |
| `returning` | 128,821 | 14,001 | a customer came back and their new contract ended again the same month |

For example, customer 38757 in 2024:

| `activity_month` | `movement` | `is_churned` | What happened |
|---|---|---|---|
| 2024-01 | continuing | **true** | cover stopped on 31 January |
| 2024-02 | | | no row: no cover at all in February |
| 2024-03 | returning | false | a new contract started on 1 March |
| 2024-04 | continuing | false | still covered |
| 2024-05 | continuing | **true** | cover stopped on 30 May |
| 2024-06 | | | no row |
| 2024-07 | returning | false | came back on 27 July |

**How to count correctly:**

- **Active customers = new + continuing + returning.** Never add churned customers to that
  total. They're already in it.
- **Churned customers are a subset of that month's active customers.** So the churn rate is
  churned ÷ active *in the same month*, and it can never exceed 100%.
- **Churn affects the following month.** Customers who churn in June aren't active in July:
  active(July) = active(June) − churned(June) + new(July) + returning(July).
- **Don't treat churn as the opposite of new.** "New minus churned" within one month isn't net
  growth, because the churned customers were counted as active that month.

This differs from some retention frameworks where "churned" is a fourth category recorded in the
month *after* the customer's last active month. Here churn is dated to when the contract ended,
which is standard for subscription businesses. That's why it's a flag rather than a category.

## Table reference

Every column is also described in the dbt YAML files (`models/*/_*.yml`), which feed
`dbt docs` and the dbt metadata an AI tool can read.

### `fct_customer_month`: customer × month

One row per customer per month in which they had any active day.

| Column | Type | Description |
|---|---|---|
| `customer_id` | bigint | The customer. Joins to `dim_customer`. |
| `activity_month` | date | First day of the month, e.g. `2024-07-01`. Joins to `dim_date.date_day`. |
| `movement` | varchar | How the customer started the month: `new`, `continuing` or `returning`. |
| `is_active` | boolean | Always true. Every row is an active month. |
| `is_churned` | boolean | The customer's contract ends this month. Final only where `dim_date.is_churn_complete`. |
| `months_since_cohort` | bigint | Whole months since the customer's first active month (0 in that month). |
| `days_inactive_before` | bigint | On `returning` rows: days without cover since the previous contract ended. Null otherwise. |

### `dim_customer`: one row per customer

| Column | Type | Description |
|---|---|---|
| `customer_id` | bigint | Primary key. |
| `country` | varchar | `United Kingdom` or `Brazil`. |
| `acquisition_taxonomy` | varchar | Treatment category of the acquiring order: `Hair Loss Group`, `ED Group`, `Weight Loss Group`, `Other Group`, `Sleep Group`, `TRT Group`, or `Unknown`. |
| `cohort_month` | date | Month of the first active day. Null if no activity. |
| `first_active_date` / `last_active_date` | date | First and last active day in the analysis window. |
| `n_active_periods` | bigint | Number of contracts. More than 1 means they left and came back. |
| `total_active_days` | integer | Days across all contracts, including bridged gaps. |
| `is_active_at_extract_end` | boolean | Their latest contract may still be running on 31 July 2024. |
| `has_activity` | boolean | False for customers never active in the window (20,482 never subscribed; 6,103 active only in the excluded August 2024 extract). |

### `int_customer_active_periods`: customer × continuous active period

| Column | Type | Description |
|---|---|---|
| `customer_id` | bigint | The customer. |
| `period_number` | integer | 1, 2, 3… in date order per customer. |
| `period_start_date` / `period_end_date` | date | First and last active day, inclusive. |
| `period_length_days` | bigint | Days from start to end inclusive, including bridged gaps. |
| `days_since_previous_period` | bigint | Days without cover before this period. Null for the first. Always more than 28. |
| `subscriptions_in_period` | bigint | Distinct subscriptions that contributed. |
| `is_open_at_extract_end` | boolean | Ends within 28 days of 31 July 2024, so it may still be running. Not a confirmed contract end. |

### `dim_date`: one row per day

`date_day` (primary key), `month_start_date`, `month_label` (`YYYY-MM`), `quarter_label`
(`YYYY-Qn`), `year`, `is_month_start`, `is_churn_complete`.

### `rpt_monthly_retention_summary`: cohort × month × country × treatment

Grain columns `cohort_month`, `activity_month`, `months_since_cohort`, `country`,
`acquisition_taxonomy`, `is_churn_complete`, and the counts `active_customers`,
`new_customers`, `continuing_customers`, `returning_customers` and `churned_customers`. Every
count can be summed across cohorts, countries and treatments. Derive rates when reading. For
your own analysis, prefer `fct_customer_month`.

## Querying the data

From the repo root:

```bash
uv run python scripts/explore.py    # DuckDB's SQL editor at http://localhost:4213
```

Stop it (press Enter) before running `uv run dbt build`, because an open connection locks
`warehouse.duckdb`. For a quick look without the editor:

```bash
uv run dbt show --inline "select count(*) from {{ ref('fct_customer_month') }}"
```

The raw extracts can also be read directly, e.g. `select * from 'data/activity.csv.gz' limit 10`,
but for analysis always use the modelled tables above.

## Common pitfalls

- **Don't add monthly customer counts across months.** The same customer appears in every
  month they're active, so April + May + June counts customers up to three times. For a period
  total, use `count(distinct customer_id)` or `int_customer_active_periods`.
- **Filter churn on `dim_date.is_churn_complete`.** The latest month's churn isn't final.
- **Average retention curves only over cohorts old enough to reach each month.** Otherwise
  recent cohorts drag the curve down (5.2% instead of 18.8% at month 24).
- **Hold country fixed when comparing treatments, and the other way round.** Brazil is almost all Hair Loss, and Weight Loss is almost all UK.

Tested queries for all of these are in the [AI guide](ai_guide.md#example-queries).
