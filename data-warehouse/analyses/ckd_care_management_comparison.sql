with pair_membership as (
    select
        pairs.pair_order,
        pairs.condition_pair,
        mart.age,
        mart.reporting_year,
        mart.chronic_condition_count,
        mart.total_medicare_reimbursement,
        mart.inpatient_claim_count,
        mart.is_top_10pct_cost,
        mart.chronic_kidney_disease_code = '1' and pairs.condition_code = '1' as has_pair
    from {{ ref('mart_beneficiary_year_risk') }} as mart
    cross join lateral (values
        (1, 'CKD + Heart Failure', mart.heart_failure_code),
        (2, 'CKD + Ischemic Heart Disease', mart.ischemic_heart_disease_code),
        (3, 'CKD + Diabetes', mart.diabetes_code)
    ) as pairs(pair_order, condition_pair, condition_code)
    where mart.reporting_year between 2008 and 2010
        and mart.age is not null
        and mart.chronic_condition_count >= 2
), stratum_outcomes as (
    -- Comparators can have one or neither condition in the pair.
    select
        pair_order,
        condition_pair,
        count(*) filter (where has_pair) as pair_rows,
        count(*) filter (where not has_pair) as comparator_rows,
        avg(total_medicare_reimbursement) filter (where has_pair) as pair_reimbursement,
        avg(total_medicare_reimbursement) filter (where not has_pair) as comparator_reimbursement,
        1000 * avg(inpatient_claim_count) filter (where has_pair) as pair_inpatient_rate,
        1000 * avg(inpatient_claim_count) filter (where not has_pair) as comparator_inpatient_rate,
        100 * avg(is_top_10pct_cost::integer) filter (where has_pair) as pair_top_decile_pct,
        100 * avg(is_top_10pct_cost::integer) filter (where not has_pair) as comparator_top_decile_pct
    from pair_membership
    group by pair_order, condition_pair, age, reporting_year, chronic_condition_count
    having count(*) filter (where has_pair) > 0
), eligible_strata as (
    select *, comparator_rows >= 10 as is_eligible
    from stratum_outcomes
), weighted_outcomes as (
    -- Weight both groups by pair rows so they use the same distribution of eligible strata.
    select
        pair_order,
        condition_pair,
        sum(pair_rows) as total_pair_beneficiary_years,
        sum(pair_rows) filter (where is_eligible) as eligible_pair_beneficiary_years,
        sum(pair_rows * pair_reimbursement) filter (where is_eligible) as weighted_pair_reimbursement,
        sum(pair_rows * comparator_reimbursement) filter (where is_eligible) as weighted_comparator_reimbursement,
        sum(pair_rows * pair_inpatient_rate) filter (where is_eligible) as weighted_pair_inpatient_rate,
        sum(pair_rows * comparator_inpatient_rate) filter (where is_eligible) as weighted_comparator_inpatient_rate,
        sum(pair_rows * pair_top_decile_pct) filter (where is_eligible) as weighted_pair_top_decile_pct,
        sum(pair_rows * comparator_top_decile_pct) filter (where is_eligible) as weighted_comparator_top_decile_pct
    from eligible_strata
    group by pair_order, condition_pair
), comparison as (
    select
        pair_order,
        condition_pair,
        total_pair_beneficiary_years,
        eligible_pair_beneficiary_years,
        weighted_pair_reimbursement / eligible_pair_beneficiary_years as average_reimbursement_pair,
        weighted_comparator_reimbursement / eligible_pair_beneficiary_years as average_reimbursement_comparator,
        weighted_pair_inpatient_rate / eligible_pair_beneficiary_years as inpatient_claims_per_1000_pair,
        weighted_comparator_inpatient_rate / eligible_pair_beneficiary_years as inpatient_claims_per_1000_comparator,
        weighted_pair_top_decile_pct / eligible_pair_beneficiary_years as top_decile_pct_pair,
        weighted_comparator_top_decile_pct / eligible_pair_beneficiary_years as top_decile_pct_comparator
    from weighted_outcomes
)

-- Calculate differences before rounding either group's outcome.
select
    condition_pair,
    round(average_reimbursement_pair - average_reimbursement_comparator, 2) as reimbursement_difference,
    round(average_reimbursement_pair, 2) as average_reimbursement_pair,
    round(average_reimbursement_comparator, 2) as average_reimbursement_comparator,
    round(inpatient_claims_per_1000_pair, 1) as inpatient_claims_per_1000_pair,
    round(inpatient_claims_per_1000_comparator, 1) as inpatient_claims_per_1000_comparator,
    round(inpatient_claims_per_1000_pair - inpatient_claims_per_1000_comparator, 1)
        as inpatient_claims_per_1000_difference,
    round(top_decile_pct_pair, 2) as top_decile_pct_pair,
    round(top_decile_pct_comparator, 2) as top_decile_pct_comparator,
    round(top_decile_pct_pair - top_decile_pct_comparator, 2) as top_decile_percentage_point_difference,
    total_pair_beneficiary_years,
    eligible_pair_beneficiary_years
from comparison
order by pair_order
