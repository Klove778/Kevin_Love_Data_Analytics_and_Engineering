{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='claim_key',
    on_schema_change='append_new_columns'
) }}

with
{% if is_incremental() %}
watermark as (
    select coalesce(max(updated_at), '-infinity'::timestamptz) as updated_at
    from {{ this }}
),

source_updates as (
    {% for claim_type in ('inpatient', 'outpatient', 'carrier') %}
    select '{{ claim_type }}' as claim_type, claim_id, updated_at
    from {{ ref('stg_' ~ claim_type ~ '_claims') }}
    where updated_at >= (select updated_at from watermark)
    {% if claim_type != 'carrier' %}
        and claim_segment in (1, 2)
    {% endif %}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

changed_claims as (
    select claim_type, claim_id
    from source_updates
    where updated_at > (select updated_at from watermark)

    union

    -- Include new claims at the watermark without reprocessing existing ties.
    select source.claim_type, source.claim_id
    from source_updates as source
    where source.updated_at = (select updated_at from watermark)
        and not exists (
            select 1
            from {{ this }} as target
            where target.claim_key = source.claim_type || ':' || source.claim_id
                and target.updated_at = (select updated_at from watermark)
        )
),
{% endif %}

inpatient_claims as (
    -- Select the authoritative segment after reading every segment for a changed claim.
    select distinct on (claim_id)
        *,
        min(created_on) over (partition by claim_id) as claim_created_on,
        max(updated_at) over (partition by claim_id) as claim_updated_at
    from {{ ref('stg_inpatient_claims') }}
    where claim_segment in (1, 2)
    {% if is_incremental() %}
        and claim_id in (select claim_id from changed_claims where claim_type = 'inpatient')
    {% endif %}
    order by claim_id, claim_segment
),

outpatient_claims as (
    select distinct on (claim_id)
        *,
        min(created_on) over (partition by claim_id) as claim_created_on,
        max(updated_at) over (partition by claim_id) as claim_updated_at
    from {{ ref('stg_outpatient_claims') }}
    where claim_segment in (1, 2)
    {% if is_incremental() %}
        and claim_id in (select claim_id from changed_claims where claim_type = 'outpatient')
    {% endif %}
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
        loaded_at,
        claim_created_on as created_on,
        claim_updated_at as updated_at
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
        loaded_at,
        claim_created_on as created_on,
        claim_updated_at as updated_at
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
        carrier.source_file,
        carrier.loaded_at,
        carrier.created_on,
        carrier.updated_at
    from (
        select *
        from {{ ref('stg_carrier_claims') }}
        {% if is_incremental() %}
        where claim_id in (select claim_id from changed_claims where claim_type = 'carrier')
        {% endif %}
    ) as carrier
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
    provider_npi,
    created_on,
    updated_at
from claims
