\set ON_ERROR_STOP on

\timing on
\pset format unaligned
begin;
set local statement_timeout='240s';
\ir cohort.sql

select count(*) n, count(*) filter(where top) baseline_top, count(*) filter(where next_top) next_top,
count(*) filter(where top and next_top) persistent, count(*) filter(where top and ip=0) focus
from cohort;

create temp table features as
select c.beneficiary_id,
count(*) filter(where f.claim_type='inpatient') n_ip,
count(*) filter(where f.claim_type='outpatient') n_op,
count(*) filter(where f.claim_type='carrier') n_car,
coalesce(sum(f.medicare_reimbursement_amount) filter(where f.claim_type='inpatient'),0) ip_paid,
coalesce(sum(f.medicare_reimbursement_amount) filter(where f.claim_type='outpatient'),0) op_paid,
coalesce(sum(f.medicare_reimbursement_amount) filter(where f.claim_type='carrier'),0) car_paid
from cohort c join mart.fct_claims f on c.beneficiary_id=f.beneficiary_id
where f.claim_end_date >= '2008-01-01' and f.claim_end_date < '2009-01-01'
group by 1;
select count(*) filter(where c.paid<>coalesce(f.ip_paid+f.op_paid+f.car_paid,0) or c.ip<>coalesce(f.n_ip,0)) discrepant
from cohort c left join features f using(beneficiary_id);
\o :output_csv
copy (select md5(c.beneficiary_id || ':persistence-2008-v1') as split_hash, c.top::int as prior_top, c.next_top::int as subsequent_top, c.paid, coalesce(f.ip_paid,0) ip_paid, coalesce(f.op_paid,0) op_paid, coalesce(f.car_paid,0) car_paid, coalesce(f.n_ip,0) ip_count, coalesce(f.n_op,0) op_count, coalesce(f.n_car,0) carrier_count, c.esrd as esrd_flag from cohort c left join features f using(beneficiary_id)) to stdout with (format csv, header true);
\o
rollback;
