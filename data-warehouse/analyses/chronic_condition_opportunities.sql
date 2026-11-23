-- A beneficiary-year contributes to each of its positive condition groups.
select
    flags.condition_name,
    count(*) as beneficiary_years,
    round(100.0 * count(*) filter (where mart.is_top_10pct_cost) / count(*), 2) as pct_top_10_cost,
    round(avg(mart.total_medicare_reimbursement), 2) as avg_annual_reimbursement,
    round(1000.0 * sum(mart.inpatient_claim_count) / count(*), 1) as inpatient_claims_per_1000,
    sum(mart.total_medicare_reimbursement) as total_reimbursement
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
    and flags.condition_code = '1'
group by flags.condition_name
order by flags.condition_name
