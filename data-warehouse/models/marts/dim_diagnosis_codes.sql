select
    {{ normalize_icd9_code('diagnosis_code') }} as diagnosis_code,
    {{ clean_text('diagnosis_description') }} as diagnosis_description,
    cms_version
from {{ ref('icd9_cm_diagnosis_titles') }}
