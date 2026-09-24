with source as (
    select * from {{ source('raw', 'activity') }}
)

select
    cast(customer_id as bigint)     as customer_id,
    cast(subscription_id as bigint) as subscription_id,
    cast(from_date as date)         as active_from_date,
    cast(to_date as date)           as active_to_date
from source
