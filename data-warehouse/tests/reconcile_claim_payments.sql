with actual as (
    select
        beneficiary_id,
        extract(year from claim_end_date)::integer as reporting_year,
        sum(medicare_reimbursement_amount) filter (where claim_type = 'inpatient') as inpatient_reimbursement,
        sum(medicare_reimbursement_amount) filter (where claim_type = 'outpatient') as outpatient_reimbursement
    from {{ ref('fct_claims') }}
    where claim_type in ('inpatient', 'outpatient')
        and not is_incomplete_claim
    group by 1, 2
),

expected as (
    select
        beneficiary_id,
        reporting_year,
        inpatient_medicare_reimbursement_amount as inpatient_reimbursement,
        outpatient_medicare_reimbursement_amount as outpatient_reimbursement
    from {{ ref('stg_beneficiary_summary') }}
)

select
    coalesce(expected.beneficiary_id, actual.beneficiary_id) as beneficiary_id,
    coalesce(expected.reporting_year, actual.reporting_year) as reporting_year,
    expected.inpatient_reimbursement as expected_inpatient_reimbursement,
    coalesce(actual.inpatient_reimbursement, 0) as actual_inpatient_reimbursement,
    expected.outpatient_reimbursement as expected_outpatient_reimbursement,
    coalesce(actual.outpatient_reimbursement, 0) as actual_outpatient_reimbursement
from expected
full outer join actual using (beneficiary_id, reporting_year)
where expected.beneficiary_id is null
    or expected.inpatient_reimbursement is distinct from coalesce(actual.inpatient_reimbursement, 0)
    or expected.outpatient_reimbursement is distinct from coalesce(actual.outpatient_reimbursement, 0)
