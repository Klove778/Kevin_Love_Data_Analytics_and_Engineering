with condition_groups as (
    select
        flags.condition_name,
        flags.condition_code,
        count(*) as beneficiary_years,
        avg(mart.total_medicare_reimbursement) as avg_annual_reimbursement,
        100.0 * count(*) filter (where mart.is_top_10pct_cost) / count(*) as pct_top_10_cost,
        1000.0 * sum(mart.inpatient_claim_count) / count(*) as inpatient_claims_per_1000
    from {{ ref('mart_beneficiary_year_risk') }} as mart
    cross join lateral (values
        ('Alzheimer''s or related disorders', mart.alzheimers_or_related_disorder_code),
        ('Heart failure', mart.heart_failure_code),
        ('Chronic kidney disease', mart.chronic_kidney_disease_code),
        ('Cancer', mart.cancer_code),
        ('COPD', mart.copd_code),
        ('Depression', mart.depression_code),
        ('Diabetes', mart.diabetes_code),
        ('Ischemic heart disease', mart.ischemic_heart_disease_code),
        ('Osteoporosis', mart.osteoporosis_code),
        ('Rheumatoid arthritis or osteoarthritis', mart.rheumatoid_arthritis_or_osteoarthritis_code),
        ('Stroke or TIA', mart.stroke_or_tia_code)
    ) as flags(condition_name, condition_code)
    where mart.reporting_year between 2008 and 2010
        -- Compare explicit yes and no within each condition. Unknown codes are excluded.
        and flags.condition_code in ('1', '2')
    group by flags.condition_name, flags.condition_code
), condition_differences as (
    select
        *,
        max(avg_annual_reimbursement) filter (where condition_code = '1') over (partition by condition_name)
        - max(avg_annual_reimbursement) filter (where condition_code = '2') over (partition by condition_name)
            as reimbursement_difference
    from condition_groups
)

-- Keep full precision for differences and sorting, then round for export.
select
    condition_name,
    case condition_code when '1' then 'With condition' when '2' then 'Without condition' end as condition_status,
    beneficiary_years,
    round(avg_annual_reimbursement, 2) as avg_annual_reimbursement,
    round(pct_top_10_cost, 2) as pct_top_10_cost,
    round(inpatient_claims_per_1000, 1) as inpatient_claims_per_1000,
    round(reimbursement_difference, 2) as reimbursement_difference
from condition_differences
order by condition_differences.reimbursement_difference desc, condition_name, condition_code
