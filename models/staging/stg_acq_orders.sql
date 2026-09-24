with source as (
    select * from {{ source('raw', 'acq_orders') }}
)

select
    cast(customer_id as bigint) as customer_id,
    -- mental health single customer, too small to report
    case
        when taxonomy_business_category_group = 'Mental Health Group' then 'Other Group'
        else taxonomy_business_category_group
    end                                          as acquisition_taxonomy
from source
