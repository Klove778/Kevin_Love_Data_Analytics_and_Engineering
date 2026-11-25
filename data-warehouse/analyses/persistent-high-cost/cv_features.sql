\set ON_ERROR_STOP on

\timing on
\pset format unaligned
begin;
set local statement_timeout='240s';
set local work_mem='96MB';
\ir cohort.sql


-- Original training partition only. The old holdout never enters this extract.
create temp table development as
select c.beneficiary_id, md5(c.beneficiary_id || ':persistence-2008-v1') as split_hash,
       c.next_top::int as y, (c.esrd='Y')::int as esrd, c.paid, (d.alzheimers_or_related_disorder_code='1')::int as alzheimers_or_related_disorder, (d.heart_failure_code='1')::int as heart_failure, (d.chronic_kidney_disease_code='1')::int as chronic_kidney_disease, (d.cancer_code='1')::int as cancer, (d.copd_code='1')::int as copd, (d.depression_code='1')::int as depression, (d.diabetes_code='1')::int as diabetes, (d.ischemic_heart_disease_code='1')::int as ischemic_heart_disease, (d.osteoporosis_code='1')::int as osteoporosis, (d.rheumatoid_arthritis_or_osteoarthritis_code='1')::int as rheumatoid_arthritis_or_osteoarthritis, (d.stroke_or_tia_code='1')::int as stroke_or_tia
from cohort c join mart.dim_beneficiaries d on d.beneficiary_id=c.beneficiary_id and d.reporting_year=2008
where c.top and get_byte(decode(md5(c.beneficiary_id || ':persistence-2008-v1'),'hex'),0)<179;
analyze development;
select count(*) n, sum(y) positives, sum(esrd) esrd, sum(y) filter(where esrd=1) esrd_positives from development;

create temp table history as
select f.claim_id, f.claim_type, f.beneficiary_id, f.claim_end_date,
 extract(month from f.claim_end_date)::int as mon, f.medicare_reimbursement_amount as dollars,
 nullif(upper(trim(f.first_hcpcs_code)),'') as hcpcs,
 replace(nullif(upper(trim(f.primary_icd9_diagnosis_code)),''),'.','') as dx
from mart.fct_claims f join development d using(beneficiary_id)
where f.claim_end_date >= date '2008-01-01' and f.claim_end_date < date '2009-01-01';
analyze history;
create temp table monthly_features as
with monthly as (
 select beneficiary_id, mon,
 count(*) filter(where claim_type='outpatient') op_n,
 count(*) filter(where claim_type='carrier') car_n,
 count(*) filter(where claim_type='inpatient') ip_n,
 coalesce(sum(dollars) filter(where claim_type='inpatient'),0) ip_paid,
 coalesce(sum(dollars) filter(where claim_type='outpatient'),0) op_paid,
 coalesce(sum(dollars) filter(where claim_type='carrier'),0) car_paid,
 coalesce(max(dollars) filter(where claim_type='outpatient'),0) max_op_claim,
 coalesce(max(dollars) filter(where claim_type='carrier'),0) max_car_claim
 from history group by 1,2
), quarters as (
 select beneficiary_id, (mon-1)/3 as q, sum(op_paid) as op, sum(car_paid) as car
 from monthly group by 1,2
), quarter_features as (
 select beneficiary_id, max(op) as max_op_quarter, max(car) as max_car_quarter,
 count(*) filter(where op>0) as op_paid_quarters, count(*) filter(where car>0) as car_paid_quarters
 from quarters group by 1
), yearly_features as (
 select beneficiary_id, sum(ip_n) ip_n, sum(op_n) op_n, sum(car_n) car_n,
 sum(ip_paid) ip_paid, sum(op_paid) op_paid, sum(car_paid) car_paid,
 max(max_op_claim) max_op_claim, max(max_car_claim) max_car_claim,
 count(*) filter(where op_paid>0) op_paid_months, count(*) filter(where car_paid>0) car_paid_months,
 coalesce(sum(op_paid) filter(where mon>6),0) op_late, coalesce(sum(car_paid) filter(where mon>6),0) car_late
 from monthly group by 1
)
select * from yearly_features join quarter_features using(beneficiary_id);

-- All outpatient code slots, including both source segments. No payment is
-- assigned to individual outpatient codes. Other settings use first slots.
create temp table outpatient_clinical as
with codes as (
 select h.beneficiary_id, h.mon, h.dollars,
 array(select replace(upper(trim(c)),'.','') from unnest(array[r.icd9_dgns_cd_1,r.icd9_dgns_cd_2,r.icd9_dgns_cd_3,r.icd9_dgns_cd_4,r.icd9_dgns_cd_5,r.icd9_dgns_cd_6,r.icd9_dgns_cd_7,r.icd9_dgns_cd_8,r.icd9_dgns_cd_9,r.icd9_dgns_cd_10,r.admtng_icd9_dgns_cd]) c) dx,
 array(select upper(trim(c)) from unnest(array[r.hcpcs_cd_1,r.hcpcs_cd_2,r.hcpcs_cd_3,r.hcpcs_cd_4,r.hcpcs_cd_5,r.hcpcs_cd_6,r.hcpcs_cd_7,r.hcpcs_cd_8,r.hcpcs_cd_9,r.hcpcs_cd_10,r.hcpcs_cd_11,r.hcpcs_cd_12,r.hcpcs_cd_13,r.hcpcs_cd_14,r.hcpcs_cd_15,r.hcpcs_cd_16,r.hcpcs_cd_17,r.hcpcs_cd_18,r.hcpcs_cd_19,r.hcpcs_cd_20,r.hcpcs_cd_21,r.hcpcs_cd_22,r.hcpcs_cd_23,r.hcpcs_cd_24,r.hcpcs_cd_25,r.hcpcs_cd_26,r.hcpcs_cd_27,r.hcpcs_cd_28,r.hcpcs_cd_29,r.hcpcs_cd_30,r.hcpcs_cd_31,r.hcpcs_cd_32,r.hcpcs_cd_33,r.hcpcs_cd_34,r.hcpcs_cd_35,r.hcpcs_cd_36,r.hcpcs_cd_37,r.hcpcs_cd_38,r.hcpcs_cd_39,r.hcpcs_cd_40,r.hcpcs_cd_41,r.hcpcs_cd_42,r.hcpcs_cd_43,r.hcpcs_cd_44,r.hcpcs_cd_45]) c) hcpcs,
 array(select replace(upper(trim(c)),'.','') from unnest(array[r.icd9_prcdr_cd_1,r.icd9_prcdr_cd_2,r.icd9_prcdr_cd_3,r.icd9_prcdr_cd_4,r.icd9_prcdr_cd_5,r.icd9_prcdr_cd_6]) c) proc
 from history h join raw.outpatient_claims r on r.clm_id=h.claim_id
 where h.claim_type='outpatient'
), markers as (
 select beneficiary_id, mon,
 (hcpcs && array['90935','90937','90945','90947','90989','90993','90999','G0257'] or proc && array['3995','5498']) dialysis,
 (dx && array['5856','V451','V4511','V4512','V560','V561','V562','V5631','V5632','V568','99673']) renal,
 (hcpcs && array['A4657','J0882','Q4081']) renal_treatment,
 exists(select 1 from unnest(hcpcs) c where c ~ '^(964[0-9]{2}|965[0-9]{2}|J9[0-9]{3})$') oncology
 from codes
)
select beneficiary_id, bool_or(dialysis)::int op_dialysis, bool_or(renal)::int op_renal,
 bool_or(renal_treatment)::int op_renal_therapy, bool_or(oncology)::int op_oncology,
 count(distinct mon) filter(where dialysis) dialysis_months,
 count(distinct mon) filter(where oncology) oncology_months
from markers group by 1;

create temp table other_clinical as
select beneficiary_id,
 bool_or(coalesce(dx in ('5856','V451','V4511','V4512','V560','V561','V562','V5631','V5632','V568','99673'),false))::int other_renal,
 bool_or(coalesce(hcpcs in ('90935','90937','90945','90947','90999','G0257') or hcpcs ~ '^G03(0[89]|1[0-9]|2[0-7])$' or hcpcs ~ '^909(5[1-9]|6[0-9]|70)$',false))::int other_dialysis
from history where claim_type in ('inpatient','carrier') group by 1;

create temp table cv_features as
select d.split_hash,d.y,d.esrd,d.paid, alzheimers_or_related_disorder, heart_failure, chronic_kidney_disease, cancer, copd, depression, diabetes, ischemic_heart_disease, osteoporosis, rheumatoid_arthritis_or_osteoarthritis, stroke_or_tia,
 ip_n,op_n,car_n,ip_paid,op_paid,car_paid,max_op_claim,max_car_claim,op_paid_months,car_paid_months,
 op_late,car_late,max_op_quarter,max_car_quarter,op_paid_quarters,car_paid_quarters,
 coalesce(op_dialysis,0) op_dialysis,coalesce(op_renal,0) op_renal,coalesce(op_renal_therapy,0) op_renal_therapy,
 coalesce(op_oncology,0) op_oncology,coalesce(dialysis_months,0) dialysis_months,coalesce(oncology_months,0) oncology_months,
 coalesce(other_renal,0) other_renal,coalesce(other_dialysis,0) other_dialysis
from development d join monthly_features m using(beneficiary_id)
left join outpatient_clinical oc using(beneficiary_id) left join other_clinical xc using(beneficiary_id);
select count(*) n,count(distinct split_hash) unique_keys,
 count(*) filter(where paid<>ip_paid+op_paid+car_paid) payment_discrepancies,
 sum(op_dialysis) have_dialysis, sum(op_renal) have_renal, sum(op_oncology) have_oncology
from cv_features;
\o :output_csv
copy (select * from cv_features) to stdout with (format csv, header true);
\o
rollback;
