with outpatient_claims as (
    select distinct on (claim_id)
        claim_id,
        beneficiary_id,
        claim_segment,
        claim_start_date,
        claim_end_date,
        claim_payment_amount,
        claim_icd9_diagnosis_code_1,
        claim_icd9_procedure_code_1,
        hcpcs_code_1,
        source_file,
        loaded_at
    from {{ ref('stg_outpatient_claims') }}
    where claim_segment in (1, 2)
    order by claim_id, claim_segment
),

claims as (
    select
        'inpatient' as claim_type,
        claim_id,
        beneficiary_id,
        claim_start_date,
        claim_end_date,
        claim_payment_amount,
        claim_payment_amount + claim_utilization_day_count * claim_pass_through_per_diem_amount
            as medicare_reimbursement_amount,
        claim_icd9_diagnosis_code_1 as primary_icd9_diagnosis_code,
        claim_icd9_procedure_code_1 as primary_icd9_procedure_code,
        hcpcs_code_1 as first_hcpcs_code,
        claim_segment as source_claim_segment,
        false as is_incomplete_claim,
        source_file,
        loaded_at
    from {{ ref('stg_inpatient_claims') }}
    where claim_segment = 1

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
        null::numeric as claim_payment_amount,
        null::numeric as medicare_reimbursement_amount,
        claim_icd9_diagnosis_code_1 as primary_icd9_diagnosis_code,
        null::text as primary_icd9_procedure_code,
        hcpcs_code_1 as first_hcpcs_code,
        null::integer as source_claim_segment,
        false as is_incomplete_claim,
        source_file,
        loaded_at
    from {{ ref('stg_carrier_claims') }}
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
    loaded_at
from claims
