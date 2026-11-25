-- Shared 2008-2009 study cohort. Include inside a transaction.
create temp table yearly as
select d.beneficiary_id, d.reporting_year yr, r.age, d.sex_code sex, r.chronic_condition_count cc,
r.chronic_kidney_disease_code='1' ckd, d.esrd_indicator esrd,
r.total_medicare_reimbursement paid, r.inpatient_claim_count ip,
row_number() over(partition by d.reporting_year order by r.total_medicare_reimbursement desc, d.beneficiary_id)
 <=ceil(count(*) over(partition by d.reporting_year)/10.0) top
from mart.dim_beneficiaries d join mart.mart_beneficiary_year_risk r using (beneficiary_id,reporting_year)
where d.reporting_year in (2008,2009) and d.part_a_coverage_months=12 and d.part_b_coverage_months=12
and d.hmo_coverage_months=0 and (d.death_date is null or d.death_date>=make_date(d.reporting_year+1,1,1));
analyze yearly;
create temp table cohort as
select a.*, b.top next_top, b.paid next_paid, b.ip next_ip, b.esrd next_esrd
from yearly a join yearly b on a.beneficiary_id=b.beneficiary_id and b.yr=2009
where a.yr=2008;
analyze cohort;
