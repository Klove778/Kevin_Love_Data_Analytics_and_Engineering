{% set line_fields = [
    ('prf_physn_npi', 'performing_physician_npi', 'text'),
    ('tax_num', 'provider_tax_number', 'text'),
    ('hcpcs_cd', 'hcpcs_code', 'text'),
    ('line_nch_pmt_amt', 'line_payment_amount', 'numeric'),
    ('line_bene_ptb_ddctbl_amt', 'line_part_b_deductible_amount', 'numeric'),
    ('line_bene_prmry_pyr_pd_amt', 'line_beneficiary_primary_payer_paid_amount', 'numeric'),
    ('line_coinsrnc_amt', 'line_coinsurance_amount', 'numeric'),
    ('line_alowd_chrg_amt', 'line_allowed_charge_amount', 'numeric'),
    ('line_prcsg_ind_cd', 'line_processing_indicator_code', 'text'),
    ('line_icd9_dgns_cd', 'line_icd9_diagnosis_code', 'text')
] %}

select
    nullif(btrim(clm_id), '') as claim_id,
    nullif(btrim(desynpuf_id), '') as beneficiary_id,
    nullif(btrim(clm_from_dt), '')::date as claim_start_date,
    nullif(btrim(clm_thru_dt), '')::date as claim_end_date,

    {% for position in range(1, 9) %}
    nullif(btrim(icd9_dgns_cd_{{ position }}), '') as claim_icd9_diagnosis_code_{{ position }},
    {% endfor %}

    -- Keep each carrier line's fields aligned by their original position.
    {% for source_prefix, output_prefix, data_type in line_fields %}
    {% for position in range(1, 14) %}
    nullif(btrim({{ source_prefix }}_{{ position }}), '')::{{ data_type }} as {{ output_prefix }}_{{ position }},
    {% endfor %}
    {% endfor %}

    source_file,
    loaded_at
from {{ source('cms_raw', 'carrier_claims') }}
