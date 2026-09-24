with source as (
    select * from {{ source('raw', 'customers') }}
)

select
    cast(customer_id as bigint)       as customer_id,
    cast(customer_country as varchar) as country
from source
