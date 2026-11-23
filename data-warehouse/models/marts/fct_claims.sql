{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='claim_key',
    on_schema_change='append_new_columns'
) }}

with inpatient_claims as (
    select distinct on (claim_id)
        *
    from {{ ref('stg_inpatient_claims') }}
    where claim_segment in (1, 2)
    order by claim_id, claim_segment
),

outpatient_claims as (
    select distinct on (claim_id)
        *
    from {{ ref('stg_outpatient_claims') }}
    where claim_segment in (1, 2)
    order by claim_id, claim_segment
),

claims as (
    select
        'inpatient' as claim_type,
        claim_id,
        beneficiary_id,
        case when claim_segment = 1 then claim_start_date end as claim_start_date,
        case when claim_segment = 1 then claim_end_date end as claim_end_date,
        case when claim_segment = 1 then claim_payment_amount end as claim_payment_amount,
        case
            when claim_segment = 1 then
                claim_payment_amount
                + claim_utilization_day_count * claim_pass_through_per_diem_amount
        end as medicare_reimbursement_amount,
        case when claim_segment = 1 then claim_icd9_diagnosis_code_1 end as primary_icd9_diagnosis_code,
        case when claim_segment = 1 then claim_icd9_procedure_code_1 end as primary_icd9_procedure_code,
        case when claim_segment = 1 then hcpcs_code_1 end as first_hcpcs_code,
        case when claim_segment = 1 then
            coalesce(operating_physician_npi, attending_physician_npi, other_physician_npi)
        end as provider_npi,
        claim_segment as source_claim_segment,
        claim_segment = 2 as is_incomplete_claim,
        source_file,
        loaded_at
    from inpatient_claims

    union all

    select
        'outpatient' as claim_type,
        claim_id,
        beneficiary_id,
        case when claim_segment = 1 then claim_start_date end as claim_start_date,
        case when claim_segment = 1 then claim_end_date end as claim_end_date,
        case when claim_segment = 1 then claim_payment_amount end as claim_payment_amount,
        case when claim_segment = 1 then claim_payment_amount end as medicare_reimbursement_amount,
        case when claim_segment = 1 then claim_icd9_diagnosis_code_1 end as primary_icd9_diagnosis_code,
        case when claim_segment = 1 then claim_icd9_procedure_code_1 end as primary_icd9_procedure_code,
        case when claim_segment = 1 then hcpcs_code_1 end as first_hcpcs_code,
        case when claim_segment = 1 then
            coalesce(operating_physician_npi, attending_physician_npi, other_physician_npi)
        end as provider_npi,
        claim_segment as source_claim_segment,
        claim_segment = 2 as is_incomplete_claim,
        source_file,
        loaded_at
    from outpatient_claims

    union all

    select
        'carrier' as claim_type,
        claim_id,
        beneficiary_id,
        claim_start_date,
        claim_end_date,
        carrier_payment.paid_amount as claim_payment_amount,
        carrier_payment.paid_amount as medicare_reimbursement_amount,
        claim_icd9_diagnosis_code_1 as primary_icd9_diagnosis_code,
        null::text as primary_icd9_procedure_code,
        hcpcs_code_1 as first_hcpcs_code,
        performing_physician_npi_1 as provider_npi,
        null::integer as source_claim_segment,
        false as is_incomplete_claim,
        source_file,
        loaded_at
    from {{ ref('stg_carrier_claims') }} as carrier
    cross join lateral (
        select coalesce(sum(payment_amount), 0) as paid_amount
        from (
            values
                {% for line in range(1, 14) -%}
                (carrier.line_payment_amount_{{ line }},
                 carrier.line_processing_indicator_code_{{ line }},
                 carrier.line_allowed_charge_amount_{{ line }}){{ ',' if not loop.last }}
                {% endfor %}
        ) as claim_line(payment_amount, processing_indicator, allowed_charge_amount)
        where processing_indicator = 'A'
            or (processing_indicator in ('R', 'S') and allowed_charge_amount > 0)
    ) as carrier_payment
)

select
    claim_type || ':' || claim_id as claim_key,
    claim_type,
    claim_id,
    beneficiary_id,
    claim_start_date,
    claim_end_date,
    claim_payment_amount,
    medicare_reimbursement_amount,
    primary_icd9_diagnosis_code,
    primary_icd9_procedure_code,
    first_hcpcs_code,
    source_claim_segment,
    is_incomplete_claim,
    source_file,
    loaded_at,
    provider_npi
from claims
{% if is_incremental() %}
where loaded_at >= (
    select coalesce(max(loaded_at), '-infinity'::timestamptz)
    from {{ this }}
)
{% endif %}
