
\timing on
\pset format unaligned
begin;
set local statement_timeout='360s';
set local work_mem='96MB';
\ir cohort.sql

select count(*) n, count(*) filter(where top) baseline_top, count(*) filter(where next_top) next_top,
count(*) filter(where top and next_top) persistent, count(*) filter(where top and ip=0) focus
from cohort;

-- Extract claim rows and original billing slots only for relevant beneficiaries.
create temp table study_claim as
select f.claim_id, f.claim_type, f.beneficiary_id, f.claim_end_date, f.source_claim_segment,
       f.medicare_reimbursement_amount paid, f.primary_icd9_diagnosis_code primary_dx
from mart.fct_claims f join cohort c using(beneficiary_id)
where c.top and f.claim_end_date >= '2008-01-01'
and (f.claim_end_date < '2009-01-01' or (f.claim_end_date < '2010-01-01' and c.ip=0))
and f.claim_type in ('outpatient','carrier','inpatient');
analyze study_claim;
create temp table study_codes as
select c.claim_type, c.claim_id,c.beneficiary_id,c.claim_end_date,
slots.kind, replace(code,'.','') as code, null::numeric as line_paid
from study_claim c join raw.outpatient_claims r on r.clm_id=c.claim_id
cross join lateral (values ('hcpcs',array[nullif(upper(btrim(r.hcpcs_cd_1)), ''), nullif(upper(btrim(r.hcpcs_cd_2)), ''), nullif(upper(btrim(r.hcpcs_cd_3)), ''), nullif(upper(btrim(r.hcpcs_cd_4)), ''), nullif(upper(btrim(r.hcpcs_cd_5)), ''), nullif(upper(btrim(r.hcpcs_cd_6)), ''), nullif(upper(btrim(r.hcpcs_cd_7)), ''), nullif(upper(btrim(r.hcpcs_cd_8)), ''), nullif(upper(btrim(r.hcpcs_cd_9)), ''), nullif(upper(btrim(r.hcpcs_cd_10)), ''), nullif(upper(btrim(r.hcpcs_cd_11)), ''), nullif(upper(btrim(r.hcpcs_cd_12)), ''), nullif(upper(btrim(r.hcpcs_cd_13)), ''), nullif(upper(btrim(r.hcpcs_cd_14)), ''), nullif(upper(btrim(r.hcpcs_cd_15)), ''), nullif(upper(btrim(r.hcpcs_cd_16)), ''), nullif(upper(btrim(r.hcpcs_cd_17)), ''), nullif(upper(btrim(r.hcpcs_cd_18)), ''), nullif(upper(btrim(r.hcpcs_cd_19)), ''), nullif(upper(btrim(r.hcpcs_cd_20)), ''), nullif(upper(btrim(r.hcpcs_cd_21)), ''), nullif(upper(btrim(r.hcpcs_cd_22)), ''), nullif(upper(btrim(r.hcpcs_cd_23)), ''), nullif(upper(btrim(r.hcpcs_cd_24)), ''), nullif(upper(btrim(r.hcpcs_cd_25)), ''), nullif(upper(btrim(r.hcpcs_cd_26)), ''), nullif(upper(btrim(r.hcpcs_cd_27)), ''), nullif(upper(btrim(r.hcpcs_cd_28)), ''), nullif(upper(btrim(r.hcpcs_cd_29)), ''), nullif(upper(btrim(r.hcpcs_cd_30)), ''), nullif(upper(btrim(r.hcpcs_cd_31)), ''), nullif(upper(btrim(r.hcpcs_cd_32)), ''), nullif(upper(btrim(r.hcpcs_cd_33)), ''), nullif(upper(btrim(r.hcpcs_cd_34)), ''), nullif(upper(btrim(r.hcpcs_cd_35)), ''), nullif(upper(btrim(r.hcpcs_cd_36)), ''), nullif(upper(btrim(r.hcpcs_cd_37)), ''), nullif(upper(btrim(r.hcpcs_cd_38)), ''), nullif(upper(btrim(r.hcpcs_cd_39)), ''), nullif(upper(btrim(r.hcpcs_cd_40)), ''), nullif(upper(btrim(r.hcpcs_cd_41)), ''), nullif(upper(btrim(r.hcpcs_cd_42)), ''), nullif(upper(btrim(r.hcpcs_cd_43)), ''), nullif(upper(btrim(r.hcpcs_cd_44)), ''), nullif(upper(btrim(r.hcpcs_cd_45)), '')]),
 ('diagnosis',array[nullif(upper(btrim(r.icd9_dgns_cd_1)), ''), nullif(upper(btrim(r.icd9_dgns_cd_2)), ''), nullif(upper(btrim(r.icd9_dgns_cd_3)), ''), nullif(upper(btrim(r.icd9_dgns_cd_4)), ''), nullif(upper(btrim(r.icd9_dgns_cd_5)), ''), nullif(upper(btrim(r.icd9_dgns_cd_6)), ''), nullif(upper(btrim(r.icd9_dgns_cd_7)), ''), nullif(upper(btrim(r.icd9_dgns_cd_8)), ''), nullif(upper(btrim(r.icd9_dgns_cd_9)), ''), nullif(upper(btrim(r.icd9_dgns_cd_10)), ''),nullif(upper(btrim(r.admtng_icd9_dgns_cd)), '')]),
 ('procedure',array[nullif(upper(btrim(r.icd9_prcdr_cd_1)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_2)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_3)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_4)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_5)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_6)), '')])
) slots(kind,codes)
cross join lateral unnest(slots.codes) code
where c.claim_type='outpatient' and code is not null;
insert into study_codes
select c.claim_type, c.claim_id,c.beneficiary_id,c.claim_end_date,
slots.kind, replace(code,'.',''),null::numeric
from study_claim c join raw.inpatient_claims r on r.clm_id=c.claim_id
cross join lateral (values ('hcpcs',array[nullif(upper(btrim(r.hcpcs_cd_1)), ''), nullif(upper(btrim(r.hcpcs_cd_2)), ''), nullif(upper(btrim(r.hcpcs_cd_3)), ''), nullif(upper(btrim(r.hcpcs_cd_4)), ''), nullif(upper(btrim(r.hcpcs_cd_5)), ''), nullif(upper(btrim(r.hcpcs_cd_6)), ''), nullif(upper(btrim(r.hcpcs_cd_7)), ''), nullif(upper(btrim(r.hcpcs_cd_8)), ''), nullif(upper(btrim(r.hcpcs_cd_9)), ''), nullif(upper(btrim(r.hcpcs_cd_10)), ''), nullif(upper(btrim(r.hcpcs_cd_11)), ''), nullif(upper(btrim(r.hcpcs_cd_12)), ''), nullif(upper(btrim(r.hcpcs_cd_13)), ''), nullif(upper(btrim(r.hcpcs_cd_14)), ''), nullif(upper(btrim(r.hcpcs_cd_15)), ''), nullif(upper(btrim(r.hcpcs_cd_16)), ''), nullif(upper(btrim(r.hcpcs_cd_17)), ''), nullif(upper(btrim(r.hcpcs_cd_18)), ''), nullif(upper(btrim(r.hcpcs_cd_19)), ''), nullif(upper(btrim(r.hcpcs_cd_20)), ''), nullif(upper(btrim(r.hcpcs_cd_21)), ''), nullif(upper(btrim(r.hcpcs_cd_22)), ''), nullif(upper(btrim(r.hcpcs_cd_23)), ''), nullif(upper(btrim(r.hcpcs_cd_24)), ''), nullif(upper(btrim(r.hcpcs_cd_25)), ''), nullif(upper(btrim(r.hcpcs_cd_26)), ''), nullif(upper(btrim(r.hcpcs_cd_27)), ''), nullif(upper(btrim(r.hcpcs_cd_28)), ''), nullif(upper(btrim(r.hcpcs_cd_29)), ''), nullif(upper(btrim(r.hcpcs_cd_30)), ''), nullif(upper(btrim(r.hcpcs_cd_31)), ''), nullif(upper(btrim(r.hcpcs_cd_32)), ''), nullif(upper(btrim(r.hcpcs_cd_33)), ''), nullif(upper(btrim(r.hcpcs_cd_34)), ''), nullif(upper(btrim(r.hcpcs_cd_35)), ''), nullif(upper(btrim(r.hcpcs_cd_36)), ''), nullif(upper(btrim(r.hcpcs_cd_37)), ''), nullif(upper(btrim(r.hcpcs_cd_38)), ''), nullif(upper(btrim(r.hcpcs_cd_39)), ''), nullif(upper(btrim(r.hcpcs_cd_40)), ''), nullif(upper(btrim(r.hcpcs_cd_41)), ''), nullif(upper(btrim(r.hcpcs_cd_42)), ''), nullif(upper(btrim(r.hcpcs_cd_43)), ''), nullif(upper(btrim(r.hcpcs_cd_44)), ''), nullif(upper(btrim(r.hcpcs_cd_45)), '')]),
 ('diagnosis',array[nullif(upper(btrim(r.icd9_dgns_cd_1)), ''), nullif(upper(btrim(r.icd9_dgns_cd_2)), ''), nullif(upper(btrim(r.icd9_dgns_cd_3)), ''), nullif(upper(btrim(r.icd9_dgns_cd_4)), ''), nullif(upper(btrim(r.icd9_dgns_cd_5)), ''), nullif(upper(btrim(r.icd9_dgns_cd_6)), ''), nullif(upper(btrim(r.icd9_dgns_cd_7)), ''), nullif(upper(btrim(r.icd9_dgns_cd_8)), ''), nullif(upper(btrim(r.icd9_dgns_cd_9)), ''), nullif(upper(btrim(r.icd9_dgns_cd_10)), ''),nullif(upper(btrim(r.admtng_icd9_dgns_cd)), '')]),
 ('procedure',array[nullif(upper(btrim(r.icd9_prcdr_cd_1)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_2)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_3)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_4)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_5)), ''), nullif(upper(btrim(r.icd9_prcdr_cd_6)), '')])
) slots(kind,codes)
cross join lateral unnest(slots.codes) code
where c.claim_type='inpatient' and code is not null;

create temp table carrier_lines as
select c.claim_id,c.beneficiary_id,c.claim_end_date, ln.*,array[nullif(upper(btrim(r.icd9_dgns_cd_1)), ''), nullif(upper(btrim(r.icd9_dgns_cd_2)), ''), nullif(upper(btrim(r.icd9_dgns_cd_3)), ''), nullif(upper(btrim(r.icd9_dgns_cd_4)), ''), nullif(upper(btrim(r.icd9_dgns_cd_5)), ''), nullif(upper(btrim(r.icd9_dgns_cd_6)), ''), nullif(upper(btrim(r.icd9_dgns_cd_7)), ''), nullif(upper(btrim(r.icd9_dgns_cd_8)), '')] as header_dx
from study_claim c join raw.carrier_claims r on r.clm_id=c.claim_id
cross join lateral (values (1, nullif(upper(btrim(r.hcpcs_cd_1)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_1)),''), case when r.line_prcsg_ind_cd_1='A' or (r.line_prcsg_ind_cd_1 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_1),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_1),'')::numeric,0) else 0 end),
(2, nullif(upper(btrim(r.hcpcs_cd_2)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_2)),''), case when r.line_prcsg_ind_cd_2='A' or (r.line_prcsg_ind_cd_2 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_2),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_2),'')::numeric,0) else 0 end),
(3, nullif(upper(btrim(r.hcpcs_cd_3)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_3)),''), case when r.line_prcsg_ind_cd_3='A' or (r.line_prcsg_ind_cd_3 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_3),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_3),'')::numeric,0) else 0 end),
(4, nullif(upper(btrim(r.hcpcs_cd_4)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_4)),''), case when r.line_prcsg_ind_cd_4='A' or (r.line_prcsg_ind_cd_4 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_4),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_4),'')::numeric,0) else 0 end),
(5, nullif(upper(btrim(r.hcpcs_cd_5)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_5)),''), case when r.line_prcsg_ind_cd_5='A' or (r.line_prcsg_ind_cd_5 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_5),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_5),'')::numeric,0) else 0 end),
(6, nullif(upper(btrim(r.hcpcs_cd_6)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_6)),''), case when r.line_prcsg_ind_cd_6='A' or (r.line_prcsg_ind_cd_6 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_6),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_6),'')::numeric,0) else 0 end),
(7, nullif(upper(btrim(r.hcpcs_cd_7)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_7)),''), case when r.line_prcsg_ind_cd_7='A' or (r.line_prcsg_ind_cd_7 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_7),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_7),'')::numeric,0) else 0 end),
(8, nullif(upper(btrim(r.hcpcs_cd_8)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_8)),''), case when r.line_prcsg_ind_cd_8='A' or (r.line_prcsg_ind_cd_8 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_8),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_8),'')::numeric,0) else 0 end),
(9, nullif(upper(btrim(r.hcpcs_cd_9)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_9)),''), case when r.line_prcsg_ind_cd_9='A' or (r.line_prcsg_ind_cd_9 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_9),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_9),'')::numeric,0) else 0 end),
(10, nullif(upper(btrim(r.hcpcs_cd_10)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_10)),''), case when r.line_prcsg_ind_cd_10='A' or (r.line_prcsg_ind_cd_10 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_10),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_10),'')::numeric,0) else 0 end),
(11, nullif(upper(btrim(r.hcpcs_cd_11)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_11)),''), case when r.line_prcsg_ind_cd_11='A' or (r.line_prcsg_ind_cd_11 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_11),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_11),'')::numeric,0) else 0 end),
(12, nullif(upper(btrim(r.hcpcs_cd_12)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_12)),''), case when r.line_prcsg_ind_cd_12='A' or (r.line_prcsg_ind_cd_12 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_12),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_12),'')::numeric,0) else 0 end),
(13, nullif(upper(btrim(r.hcpcs_cd_13)),''), nullif(upper(btrim(r.line_icd9_dgns_cd_13)),''), case when r.line_prcsg_ind_cd_13='A' or (r.line_prcsg_ind_cd_13 in ('R','S') and nullif(btrim(r.line_alowd_chrg_amt_13),'')::numeric >0) then coalesce(nullif(btrim(r.line_nch_pmt_amt_13),'')::numeric,0) else 0 end)) ln(slot,hcpcs,line_dx,line_paid)
where c.claim_type='carrier';
insert into study_codes
select 'carrier',claim_id,beneficiary_id,claim_end_date,'hcpcs',hcpcs,line_paid
from carrier_lines where hcpcs is not null;
insert into study_codes
select 'carrier',claim_id,beneficiary_id,claim_end_date,'diagnosis',replace(line_dx,'.',''),null::numeric
from carrier_lines where line_dx is not null
union all
select 'carrier',claim_id,beneficiary_id,claim_end_date,'diagnosis',replace(dx,'.',''),null::numeric
from carrier_lines cross join lateral unnest(header_dx) dx where slot=1 and dx is not null;
analyze study_codes;
select sum(paid) as carrier_claim_paid, (select sum(line_paid) from carrier_lines) as line_paid
from study_claim where claim_type='carrier';


create temp table marks as
select claim_type, claim_id, beneficiary_id,
bool_or(kind='hcpcs' and code in ('90935','90937','90945','90947','90989','90993','90997','90999','G0257','G0491')) or
bool_or(kind='procedure' and code in ('3995','5498')) as procedure_dialysis,
bool_or(kind='hcpcs' and (code ~ '^G03(0[89]|1[0-9]|2[0-7])$' or code ~ '^909(5[1-9]|6[0-9]|70)$')) as dialysis_management,
bool_or(kind='diagnosis' and code in ('5856','V4511','V4512','V560','V561','V562','V5631','V5632','V568')) as renal_dx,
bool_or(kind='hcpcs' and (code in ('J0881','J0882','J0885','J0886','Q4081','J1750','J1756','J2916'))) as anemia_med,
bool_or(kind='hcpcs' and (code ~ '^964[0-9][0-9]$' or code ~ '^965[0-9][0-9]$' or code ~ '^J9[0-9][0-9][0-9]$')) as oncology,
bool_or(kind='hcpcs' and (code in ('A4657','A4680','A4690','A4706','A4707','A4708','A4714','A4719','A4720','A4721','A4722','A4723','A4724','A4725','A4726','A4728','A4730','A4736','A4737','A4740','A4750','A4755','A4760','A4765','A4800','A4860','A4870','A4890','A4911','A4913','A4918','E1500','E1510','E1520','E1530','E1540','E1550','E1560','E1570','E1575','E1580','E1590','E1592','E1594','Q4081','J0882'))) as dialysis_support,
count(*) filter(where kind='hcpcs' and code ~ '^[A-Z0-9]{5}$' and code not in ('XXXXX','00000')) has_hcpcs,
sum(line_paid) filter(where kind='hcpcs' and (code in ('90935','90937','90945','90947','90989','90993','90997','90999','G0257','G0491')
or code ~ '^G03(0[89]|1[0-9]|2[0-7])$' or code ~ '^909(5[1-9]|6[0-9]|70)$')) line_dialysis
from study_codes group by 1,2,3;
analyze marks;
create temp table tagged as
select a.*, coalesce(m.procedure_dialysis,false) procedure_dialysis, coalesce(m.dialysis_management,false) dialysis_management,
coalesce(m.renal_dx,false) renal_dx, coalesce(m.anemia_med,false) anemia_med, coalesce(m.oncology,false) oncology,
coalesce(m.dialysis_support,false) dialysis_support, coalesce(m.has_hcpcs,0)>0 has_hcpcs,
coalesce(m.line_dialysis,0) line_dialysis,
extract(year from a.claim_end_date)::int yr, c.ip=0 focus
from study_claim a left join marks m using(claim_type,claim_id,beneficiary_id) join cohort c using(beneficiary_id);
analyze tagged;
create temp table profile as
select c.beneficiary_id, c.ip=0 focus, c.ckd, c.esrd, c.next_esrd, c.next_top, c.next_paid, c.paid,
count(*) filter(where t.claim_type='outpatient') op_n,
count(distinct date_trunc('month',t.claim_end_date)) filter(where t.claim_type='outpatient') op_months,
count(distinct date_trunc('month',t.claim_end_date)) filter(where t.claim_type='outpatient' and (t.procedure_dialysis or t.dialysis_management)) dialysis_months,
count(distinct date_trunc('month',t.claim_end_date)) filter(where t.claim_type='outpatient' and t.oncology) oncology_months,
coalesce(sum(t.paid) filter(where t.claim_type='outpatient'),0) op_paid,
coalesce(sum(t.paid) filter(where t.claim_type='outpatient' and (t.procedure_dialysis or t.dialysis_management)),0) op_dialysis_paid,
bool_or(t.procedure_dialysis or t.dialysis_management) dialysis_marker,
bool_or(t.procedure_dialysis) direct_dialysis,
bool_or(t.renal_dx) renal_dx,
bool_or(t.dialysis_support) dialysis_support,
bool_or(t.anemia_med) anemia,
bool_or(t.oncology) oncology
from cohort c join tagged t using(beneficiary_id) where c.top and t.yr=2008
group by 1,2,3,4,5,6,7,8;
select focus,esrd,ckd,dialysis_marker,count(*) n,count(*) filter (where next_top) persists, round(sum(paid)) paid
from profile group by 1,2,3,4 order by 1,2,3,4;
select yr,claim_type,count(*) n,count(distinct beneficiary_id) n_bene,round(sum(paid)) total,
count(*) filter(where has_hcpcs) hcpcs_claims,round(sum(paid) filter(where has_hcpcs)) hcpcs_claim_paid,
count(*) filter(where procedure_dialysis) procedure_n, count(distinct beneficiary_id) filter(where procedure_dialysis) procedure_bene,
round(sum(paid) filter(where procedure_dialysis)) procedure_claim_paid,
count(*) filter(where procedure_dialysis or dialysis_management) dialysis_n,
count(distinct beneficiary_id) filter(where procedure_dialysis or dialysis_management) dialysis_bene,
round(sum(paid) filter(where procedure_dialysis or dialysis_management)) dialysis_claim_paid,round(sum(line_dialysis),2) dialysis_carrier_line_paid,
count(distinct beneficiary_id) filter(where renal_dx) renal_dx_bene,
round(sum(paid) filter(where renal_dx and not (procedure_dialysis or dialysis_management))) renal_only_claim_paid,
count(distinct beneficiary_id) filter(where oncology) oncology_bene,
round(sum(paid) filter(where oncology)) oncology_claim_paid
from tagged where focus group by 1,2 order by 1,2;

-- Code frequency at the claim level so repeated slots do not inflate counts.
create temp table focus_code as
select distinct s.claim_type,s.claim_id,s.beneficiary_id,s.kind,s.code
from study_codes s join profile p using(beneficiary_id)
where p.focus and s.claim_end_date >= '2008-01-01' and s.claim_end_date < '2009-01-01'
and s.code ~ '^[A-Z0-9]{3,5}$' and s.code not in ('XXXXX','00000');
analyze focus_code;
with frequency as (
select fc.claim_type,fc.kind,fc.code, count(*) claims,count(distinct fc.beneficiary_id) beneficiaries,
sum(t.paid) dollars_on_claims
from focus_code fc join tagged t using(claim_type,claim_id,beneficiary_id)
where fc.kind in ('hcpcs','diagnosis')
group by 1,2,3
), ranked as (
select *, row_number() over(partition by claim_type,kind order by claims desc,code) rk from frequency
)
select t.claim_type,t.kind,t.code,d.diagnosis_description,t.claims,t.beneficiaries,round(t.dollars_on_claims)
from ranked t left join mart.dim_diagnosis_codes d on t.kind='diagnosis' and t.code=d.diagnosis_code
where rk<=15 order by t.claim_type,t.kind,t.rk;

select claim_type,t.primary_dx, d.diagnosis_description,count(*) claims,count(distinct t.beneficiary_id) beneficiaries,round(sum(t.paid)) paid
from tagged t left join mart.dim_diagnosis_codes d on replace(t.primary_dx,'.','')=d.diagnosis_code
where t.focus and yr=2008 and t.claim_type='outpatient'
group by 1,2,3 order by paid desc nulls last limit 15;

create temp table top_hcpcs as
select claim_type,code,row_number() over(partition by claim_type order by count(*) desc,code) rank
from focus_code where kind='hcpcs' group by 1,2;
with dollars as (
select t.claim_type,t.claim_id,t.beneficiary_id,t.paid,min(h.rank) first_rank
from tagged t left join focus_code c on c.claim_type=t.claim_type and c.claim_id=t.claim_id and c.beneficiary_id=t.beneficiary_id and c.kind='hcpcs'
left join top_hcpcs h on c.claim_type=h.claim_type and c.code=h.code
where t.focus and t.yr=2008 group by 1,2,3,4
)
select claim_type,round(sum(paid)) total,
count(*) filter(where first_rank<=5) top5_claims,
round(sum(paid) filter(where first_rank<=1)) on_top1,
round(sum(paid) filter(where first_rank<=5)) on_top5,
round(sum(paid) filter(where first_rank<=10)) on_top10
from dollars group by 1 order by 1;
select h.rank,l.hcpcs,sum(l.line_paid) eligible_line_paid
from carrier_lines l join profile p using(beneficiary_id)
join top_hcpcs h on h.claim_type='carrier' and l.hcpcs=h.code
where p.focus and l.claim_end_date < '2009-01-01' and h.rank<=10 group by 1,2 order by 1;

with categories as (
select *, case when direct_dialysis then 'dialysis procedure'
when dialysis_marker then 'dialysis management only'
when esrd='Y' or renal_dx or dialysis_support then 'ESRD or other renal evidence only'
when oncology_months>=2 then 'repeated outpatient oncology markers'
when op_paid>paid/2 and op_months>=6 then 'outpatient majority in 6+ active months'
when op_paid>paid/2 then 'other outpatient majority'
else 'carrier majority' end as category
from profile where focus
)
select category,count(*) n,count(*) filter(where next_top) persist,count(*) filter(where ckd) ckd_n,
count(*) filter(where esrd='Y') esrd_n,
round(sum(paid)) paid,round(sum(op_paid)) op_paid,round(sum(op_dialysis_paid)) tagged_op_dialysis,
round(avg(op_months),2) avg_op_months,round(avg(dialysis_months),2) avg_dialysis_months
from categories group by 1 order by n desc;

create temp table persistence_comparison as
with groups as (
 select p.focus,p.next_top,p.ckd,p.esrd,p.next_esrd,p.dialysis_marker,p.renal_dx,p.dialysis_support,
 c.sex, c.cc, case when c.age<65 then 0 when c.age>=85 then 5 else (c.age-65)/5+1 end age_band,
 least(40000, floor(c.paid/2500)*2500) spend_band
 from profile p join cohort c using(beneficiary_id)
), statuses as (
 select g.*, v.scope from groups g cross join lateral (values
 ('all', true),
 ('no ESRD flag',esrd='0'),
 ('no ESRD flag or directly coded dialysis/management',esrd='0' and not dialysis_marker),
 ('also exclude ESRD/dialysis diagnosis and dialysis-specific supplies/drugs',esrd='0' and not dialysis_marker and not renal_dx and not dialysis_support),
 ('no baseline CKD or ESRD or dialysis/management', not ckd and esrd='0' and not dialysis_marker)
 ) v(scope,eligible) where v.eligible
), unadjusted as (
 select scope, count(*) filter(where focus) raw_n_a, count(*) filter(where not focus) raw_n_b,
 count(*) filter(where focus and next_top) raw_events_a,count(*) filter(where not focus and next_top) raw_events_b
 from statuses group by 1
), strata as (
 select scope,age_band,cc,sex,spend_band,
 count(*) filter(where focus) a,count(*) filter(where not focus) b,
 count(*) filter(where focus and next_top) ay,count(*) filter(where not focus and next_top) by
 from statuses group by 1,2,3,4,5
), matched as (
 select scope,sum(a) n_a,sum(b) n_b,sum(ay) hits_a,sum(by) hits_b,
 sum(ay)::numeric/sum(a) ra,sum(a*by::numeric/b)/sum(a) rb,
 sqrt(sum(a*(ay+0.5)/(a+1)*(1-(ay+0.5)/(a+1)) + a*a*(by+0.5)/(b+1)*(1-(by+0.5)/(b+1))/b))/sum(a) se
 from strata where a>0 and b>=3 group by 1
)
select u.*,n_a,n_b,hits_a,hits_b,round(100*ra,2) a_pct,round(100*rb,2) b_pct,
round(100*(ra-rb),2) pp,round(ra/nullif(rb,0),2) rr,
round(100*(ra-rb-1.96*se),2) ci_low, round(100*(ra-rb+1.96*se),2) ci_high
from unadjusted u left join matched m using(scope) order by raw_n_a desc;
select * from persistence_comparison;

-- Subsequent claims are used to describe recurrence only. They never define baseline exclusion.
select p.focus,p.esrd,p.dialysis_marker,count(*) n,count(*) filter(where t.has_dialysis) dialysis_2009,
count(*) filter(where p.next_top) top_2009,round(sum(t.op_dialysis_paid)) paid_on_dialysis_op_2009,
round(sum(t.op_paid)) op_paid_2009
from profile p left join (
 select beneficiary_id,bool_or(procedure_dialysis or dialysis_management) has_dialysis,
 sum(paid) filter(where claim_type='outpatient' and (procedure_dialysis or dialysis_management)) op_dialysis_paid,
 sum(paid) filter(where claim_type='outpatient') op_paid
 from tagged where yr=2009 group by 1
) t using(beneficiary_id)
where p.focus group by 1,2,3 order by 1,2,3;
select yr,claim_type,kind,code,count(distinct s.claim_id) claims,count(distinct s.beneficiary_id) benes
from study_codes s join profile p using(beneficiary_id)
cross join lateral (select extract(year from s.claim_end_date)::int yr) y
where p.focus and
 (kind='hcpcs' and (code in ('90935','90937','90945','90947','90989','90993','90997','90999','G0257','G0491','Q4081','J0882','J1756')
 or code ~ '^G03(0[89]|1[0-9]|2[0-7])$' or code ~ '^909(5[1-9]|6[0-9]|70)$')
 or kind='procedure' and code in ('3995','5498'))
group by 1,2,3,4 order by 1,2,3,5 desc;

select count(*) filter(where p.focus) members, count(*) filter(where p.focus and p.ckd) ckd,
count(*) filter(where p.focus and p.esrd='Y') esrd, count(*) filter(where p.focus and (p.ckd or p.esrd='Y')) either,
count(*) filter(where p.focus and p.ckd and p.esrd='Y') both,
count(*) filter(where p.focus and p.dialysis_marker) dialysis_any,
count(*) filter(where p.focus and p.direct_dialysis) dialysis_direct,
count(*) filter(where p.focus and p.dialysis_months>=6) dialysis_six_months,
count(*) filter(where p.focus and p.dialysis_months>=6 and p.next_top) repeat_top_six_months,
round(sum(p.op_dialysis_paid) filter(where p.focus and p.dialysis_months>=6)) op_tagged_dollars_6mo
from profile p;


-- Dashboard rows keep each numerator and denominator explicit.
\if :{?output_csv}
\o :output_csv
copy (
    with cohorts as (
        select count(*) filter (where focus) as n,
            count(*) filter (where focus and ckd) as ckd,
            count(*) filter (where focus and esrd = 'Y') as esrd,
            count(*) filter (where focus and (ckd or esrd = 'Y')) as either,
            count(*) filter (where focus and ckd and esrd = 'Y') as both_flags,
            count(*) filter (where focus and dialysis_marker) as dialysis,
            count(*) filter (where focus and esrd = 'Y' and next_top) as persistent_esrd,
            count(*) filter (where focus and next_top) as persistent_total
        from profile
    ), prevalence as (
        select x.sort_order, 'Baseline prevalence' as section, x.population, x.metric,
            x.numerator, x.denominator, null::numeric as ci_low_pp, null::numeric as ci_high_pp
        from cohorts
        cross join lateral (values
            (1, 'All 275 without inpatient claims', 'CKD flag', ckd, n),
            (2, 'All 275 without inpatient claims', 'ESRD flag', esrd, n),
            (3, 'All 275 without inpatient claims', 'CKD or ESRD flag', either, n),
            (4, 'All 275 without inpatient claims', 'Both CKD and ESRD flags', both_flags, n),
            (5, 'All 275 without inpatient claims', 'Dialysis procedure or management', dialysis, n),
            (6, 'Persistent cases without baseline inpatient claims', 'ESRD flag', persistent_esrd, persistent_total)
        ) x(sort_order, population, metric, numerator, denominator)
    ), cost as (
        select sum(paid) filter (where claim_type = 'outpatient') as outpatient,
            sum(paid) filter (where claim_type = 'outpatient' and (procedure_dialysis or dialysis_management)) as tagged_outpatient,
            sum(line_dialysis) as tagged_carrier, sum(paid) as total
        from tagged where focus and yr = 2008
    ), cost_rows as (
        select x.sort_order, 'Spending concentration', 'All 275 without inpatient claims', x.metric,
            x.numerator, x.denominator, null::numeric, null::numeric
        from cost cross join lateral (values
            (7, 'Outpatient reimbursement on dialysis-coded claims', tagged_outpatient, outpatient),
            (8, 'Dialysis-coded outpatient claims and eligible carrier lines', tagged_outpatient + tagged_carrier, total)
        ) x(sort_order, metric, numerator, denominator)
    ), matched_scopes as (
        select p.*, case scope
            when 'all' then 10
            when 'no ESRD flag' then 20
            when 'no ESRD flag or directly coded dialysis/management' then 30
            when 'also exclude ESRD/dialysis diagnosis and dialysis-specific supplies/drugs' then 40
            else 50
        end as scope_order
        from persistence_comparison p
    ), observed as (
        select scope_order + x.offset_order, 'Observed persistence', x.population, scope,
            x.numerator, x.denominator, null::numeric, null::numeric
        from matched_scopes cross join lateral (values
            (0, 'No baseline inpatient claim', raw_events_a, raw_n_a),
            (1, 'Baseline inpatient claim', raw_events_b, raw_n_b)
        ) x(offset_order, population, numerator, denominator)
    ), measured as (
        select * from prevalence
        union all select * from cost_rows
        union all select * from observed
    ), combined as (
        select sort_order, section, population, metric, numerator, denominator,
            round(100 * numerator::numeric / nullif(denominator, 0), 2) as value_pct,
            null::numeric as standardized_gap_pp, ci_low_pp, ci_high_pp,
            null::numeric as standardized_rate_no_inpatient_pct,
            null::numeric as standardized_rate_with_inpatient_pct,
            null::bigint as matched_without_inpatient,
            null::bigint as matched_with_inpatient
        from measured
        union all
        select scope_order + 2, 'Standardized persistence gap', 'Comparable strata', scope,
            null, null, null, pp, ci_low, ci_high, a_pct, b_pct, n_a, n_b
        from matched_scopes
    )
    select *, 2008 as baseline_year, 2009 as outcome_year,
        case when section = 'Spending concentration' then 'USD' else 'beneficiaries' end as unit
    from combined order by sort_order
) to stdout with (format csv, header true);
\o
\endif

rollback;
