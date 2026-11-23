select
    {{ clean_text('pde_id') }} as prescription_drug_event_id,
    {{ clean_text('desynpuf_id') }} as beneficiary_id,
    {{ clean_text('srvc_dt') }}::date as service_date,
    {{ clean_text('prod_srvc_id') }} as product_service_id,
    {{ clean_numeric('qty_dspnsd_num') }} as quantity_dispensed,
    {{ clean_text('days_suply_num') }}::integer as days_supply,
    {{ clean_numeric('ptnt_pay_amt') }} as patient_pay_amount,
    {{ clean_numeric('tot_rx_cst_amt') }} as gross_drug_cost_amount,
    source_file,
    loaded_at,
    created_on,
    updated_at
from {{ source('cms_raw', 'prescription_drug_events') }}
