{{ config(materialized='view') }}

select
    codes.code_occurrence_key,
    codes.claim_key,
    codes.source_claim_segment,
    codes.code_type,
    codes.code_position,
    codes.code,
    diagnoses.diagnosis_description
from {{ ref('fct_claim_codes') }} as codes
left join {{ ref('dim_diagnosis_codes') }} as diagnoses
    on codes.code_type in ('admitting_icd9_diagnosis', 'icd9_diagnosis')
    and {{ normalize_icd9_code('codes.code') }} = diagnoses.diagnosis_code
where codes.claim_key like 'inpatient:%'
    or codes.claim_key like 'outpatient:%'
