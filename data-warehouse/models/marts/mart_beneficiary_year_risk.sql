with claims_by_beneficiary_year as (
    select
        beneficiary_id,
        extract(year from claim_end_date)::integer as reporting_year,
        sum(medicare_reimbursement_amount) as total_medicare_reimbursement,
        count(*) filter (where claim_type = 'inpatient') as inpatient_claim_count,
        sum(medicare_reimbursement_amount) filter (where claim_type = 'inpatient') as inpatient_reimbursement
    from {{ ref('fct_claims') }}
    where claim_end_date is not null
    group by beneficiary_id, extract(year from claim_end_date)::integer
), beneficiary_year_metrics as (
    select
        beneficiaries.beneficiary_id,
        beneficiaries.reporting_year,
        extract(year from age(make_date(beneficiaries.reporting_year, 12, 31), beneficiaries.birth_date))::integer as age,
        alzheimers_or_related_disorder_code,
        heart_failure_code,
        chronic_kidney_disease_code,
        cancer_code,
        copd_code,
        depression_code,
        diabetes_code,
        ischemic_heart_disease_code,
        osteoporosis_code,
        rheumatoid_arthritis_or_osteoarthritis_code,
        stroke_or_tia_code,
        -- Any missing or unrecognized code makes the total unknown.
        (case alzheimers_or_related_disorder_code when '1' then 1 when '2' then 0 end)
            + (case heart_failure_code when '1' then 1 when '2' then 0 end)
            + (case chronic_kidney_disease_code when '1' then 1 when '2' then 0 end)
            + (case cancer_code when '1' then 1 when '2' then 0 end)
            + (case copd_code when '1' then 1 when '2' then 0 end)
            + (case depression_code when '1' then 1 when '2' then 0 end)
            + (case diabetes_code when '1' then 1 when '2' then 0 end)
            + (case ischemic_heart_disease_code when '1' then 1 when '2' then 0 end)
            + (case osteoporosis_code when '1' then 1 when '2' then 0 end)
            + (case rheumatoid_arthritis_or_osteoarthritis_code when '1' then 1 when '2' then 0 end)
            + (case stroke_or_tia_code when '1' then 1 when '2' then 0 end) as chronic_condition_count,
        coalesce(claims.total_medicare_reimbursement, 0) as total_medicare_reimbursement,
        coalesce(claims.inpatient_claim_count, 0) as inpatient_claim_count,
        coalesce(claims.inpatient_reimbursement, 0) as inpatient_reimbursement
    from {{ ref('dim_beneficiaries') }} as beneficiaries
    left join claims_by_beneficiary_year as claims
        on beneficiaries.beneficiary_id = claims.beneficiary_id
        and beneficiaries.reporting_year = claims.reporting_year
)

select
    *,
    row_number() over (
        partition by reporting_year
        order by total_medicare_reimbursement desc, beneficiary_id
    ) <= ceil(count(*) over (partition by reporting_year) / 10.0) as is_top_10pct_cost
from beneficiary_year_metrics
