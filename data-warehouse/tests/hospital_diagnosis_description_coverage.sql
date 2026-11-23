{{ config(severity='warn', store_failures=true) }}

select
    {{ normalize_icd9_code('code') }} as diagnosis_code,
    count(*) as unmatched_occurrences
from {{ ref('tableau_hospital_claim_codes') }}
where code_type in ('admitting_icd9_diagnosis', 'icd9_diagnosis')
    and diagnosis_description is null
group by 1
