with claim_segments as (
    select
        'inpatient' as claim_type,
        claim_id,
        claim_segment as source_claim_segment,
        admitting_icd9_diagnosis_code,
        array[
            claim_icd9_diagnosis_code_1, claim_icd9_diagnosis_code_2, claim_icd9_diagnosis_code_3,
            claim_icd9_diagnosis_code_4, claim_icd9_diagnosis_code_5, claim_icd9_diagnosis_code_6,
            claim_icd9_diagnosis_code_7, claim_icd9_diagnosis_code_8, claim_icd9_diagnosis_code_9,
            claim_icd9_diagnosis_code_10
        ] as diagnosis_codes,
        array[
            claim_icd9_procedure_code_1, claim_icd9_procedure_code_2, claim_icd9_procedure_code_3,
            claim_icd9_procedure_code_4, claim_icd9_procedure_code_5, claim_icd9_procedure_code_6
        ] as procedure_codes,
        array[
            hcpcs_code_1, hcpcs_code_2, hcpcs_code_3, hcpcs_code_4, hcpcs_code_5,
            hcpcs_code_6, hcpcs_code_7, hcpcs_code_8, hcpcs_code_9, hcpcs_code_10,
            hcpcs_code_11, hcpcs_code_12, hcpcs_code_13, hcpcs_code_14, hcpcs_code_15,
            hcpcs_code_16, hcpcs_code_17, hcpcs_code_18, hcpcs_code_19, hcpcs_code_20,
            hcpcs_code_21, hcpcs_code_22, hcpcs_code_23, hcpcs_code_24, hcpcs_code_25,
            hcpcs_code_26, hcpcs_code_27, hcpcs_code_28, hcpcs_code_29, hcpcs_code_30,
            hcpcs_code_31, hcpcs_code_32, hcpcs_code_33, hcpcs_code_34, hcpcs_code_35,
            hcpcs_code_36, hcpcs_code_37, hcpcs_code_38, hcpcs_code_39, hcpcs_code_40,
            hcpcs_code_41, hcpcs_code_42, hcpcs_code_43, hcpcs_code_44, hcpcs_code_45
        ] as hcpcs_codes,
        null::text[] as line_diagnosis_codes
    from {{ ref('stg_inpatient_claims') }}

    union all

    select
        'outpatient' as claim_type,
        claim_id,
        claim_segment as source_claim_segment,
        admitting_icd9_diagnosis_code,
        array[
            claim_icd9_diagnosis_code_1, claim_icd9_diagnosis_code_2, claim_icd9_diagnosis_code_3,
            claim_icd9_diagnosis_code_4, claim_icd9_diagnosis_code_5, claim_icd9_diagnosis_code_6,
            claim_icd9_diagnosis_code_7, claim_icd9_diagnosis_code_8, claim_icd9_diagnosis_code_9,
            claim_icd9_diagnosis_code_10
        ] as diagnosis_codes,
        array[
            claim_icd9_procedure_code_1, claim_icd9_procedure_code_2, claim_icd9_procedure_code_3,
            claim_icd9_procedure_code_4, claim_icd9_procedure_code_5, claim_icd9_procedure_code_6
        ] as procedure_codes,
        array[
            hcpcs_code_1, hcpcs_code_2, hcpcs_code_3, hcpcs_code_4, hcpcs_code_5,
            hcpcs_code_6, hcpcs_code_7, hcpcs_code_8, hcpcs_code_9, hcpcs_code_10,
            hcpcs_code_11, hcpcs_code_12, hcpcs_code_13, hcpcs_code_14, hcpcs_code_15,
            hcpcs_code_16, hcpcs_code_17, hcpcs_code_18, hcpcs_code_19, hcpcs_code_20,
            hcpcs_code_21, hcpcs_code_22, hcpcs_code_23, hcpcs_code_24, hcpcs_code_25,
            hcpcs_code_26, hcpcs_code_27, hcpcs_code_28, hcpcs_code_29, hcpcs_code_30,
            hcpcs_code_31, hcpcs_code_32, hcpcs_code_33, hcpcs_code_34, hcpcs_code_35,
            hcpcs_code_36, hcpcs_code_37, hcpcs_code_38, hcpcs_code_39, hcpcs_code_40,
            hcpcs_code_41, hcpcs_code_42, hcpcs_code_43, hcpcs_code_44, hcpcs_code_45
        ] as hcpcs_codes,
        null::text[] as line_diagnosis_codes
    from {{ ref('stg_outpatient_claims') }}

    union all

    select
        'carrier' as claim_type,
        claim_id,
        null::integer as source_claim_segment,
        null::text as admitting_icd9_diagnosis_code,
        array[
            claim_icd9_diagnosis_code_1, claim_icd9_diagnosis_code_2, claim_icd9_diagnosis_code_3,
            claim_icd9_diagnosis_code_4, claim_icd9_diagnosis_code_5, claim_icd9_diagnosis_code_6,
            claim_icd9_diagnosis_code_7, claim_icd9_diagnosis_code_8
        ] as diagnosis_codes,
        null::text[] as procedure_codes,
        array[
            hcpcs_code_1, hcpcs_code_2, hcpcs_code_3, hcpcs_code_4, hcpcs_code_5,
            hcpcs_code_6, hcpcs_code_7, hcpcs_code_8, hcpcs_code_9, hcpcs_code_10,
            hcpcs_code_11, hcpcs_code_12, hcpcs_code_13
        ] as hcpcs_codes,
        array[
            line_icd9_diagnosis_code_1, line_icd9_diagnosis_code_2, line_icd9_diagnosis_code_3,
            line_icd9_diagnosis_code_4, line_icd9_diagnosis_code_5, line_icd9_diagnosis_code_6,
            line_icd9_diagnosis_code_7, line_icd9_diagnosis_code_8, line_icd9_diagnosis_code_9,
            line_icd9_diagnosis_code_10, line_icd9_diagnosis_code_11, line_icd9_diagnosis_code_12,
            line_icd9_diagnosis_code_13
        ] as line_diagnosis_codes
    from {{ ref('stg_carrier_claims') }}
),

claim_codes as (
    select
        claim_type || ':' || claim_id as claim_key,
        source_claim_segment,
        code_group.code_type,
        occurrence.code_position::integer as code_position,
        occurrence.code
    from claim_segments
    cross join lateral (
        values
            ('admitting_icd9_diagnosis', array[admitting_icd9_diagnosis_code]),
            ('icd9_diagnosis', diagnosis_codes),
            ('icd9_procedure', procedure_codes),
            ('hcpcs', hcpcs_codes),
            ('line_icd9_diagnosis', line_diagnosis_codes)
    ) as code_group(code_type, code_values)
    cross join lateral unnest(code_group.code_values) with ordinality as occurrence(code, code_position)
    where occurrence.code is not null
)

select
    claim_key || ':' || coalesce(source_claim_segment::text, '0') || ':' || code_type || ':' || code_position::text
        as code_occurrence_key,
    claim_key,
    source_claim_segment,
    code_type,
    code_position,
    code
from claim_codes
