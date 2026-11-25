\set ON_ERROR_STOP on
-- CMS DE-SynPUF Sample 1 longitudinal exploration.
-- Run with psql against the existing claims_warehouse. This script creates
-- only session-local tables and rolls back. It returns aggregate data only.
-- Read cohort membership before comparing thresholds: spending ranks are
-- computed separately in each annual full A/B, zero HMO, alive-at-year-end cohort.

\timing on
begin;
set local statement_timeout='180s';
create temp table claim_year as
select beneficiary_id, extract(year from claim_end_date)::int yr,
count(*) filter(where claim_type='inpatient') ip,
count(*) filter(where claim_type='outpatient') op,
count(*) filter(where claim_type='carrier') car,
count(distinct date_trunc('month',claim_end_date)) filter(where claim_type='outpatient') op_months,
count(distinct date_trunc('month',claim_end_date)) filter(where claim_type='carrier') car_months,
count(*) filter(where claim_type in ('outpatient','carrier') and extract(month from claim_end_date)<=6) amb_h1,
count(*) filter(where claim_type in ('outpatient','carrier') and extract(month from claim_end_date)>6) amb_h2,
count(*) filter(where claim_type='inpatient' and extract(month from claim_end_date)<=6) ip_h1,
sum(medicare_reimbursement_amount) paid,
coalesce(sum(medicare_reimbursement_amount) filter(where claim_type='inpatient'),0) ip_paid,
coalesce(sum(medicare_reimbursement_amount) filter(where claim_type='outpatient'),0) op_paid,
coalesce(sum(medicare_reimbursement_amount) filter(where claim_type='carrier'),0) car_paid
from mart.fct_claims where claim_end_date >= date '2008-01-01' and claim_end_date < date '2011-01-01'
group by 1,2;
analyze claim_year;
create temp table byear as
select d.beneficiary_id, d.reporting_year yr, d.sex_code sex, d.death_date,
r.heart_failure_code chf, r.chronic_kidney_disease_code ckd, r.diabetes_code diabetes,
d.part_a_coverage_months=12 and d.part_b_coverage_months=12 and d.hmo_coverage_months=0 full_ab,
r.age, r.chronic_condition_count cc, r.is_top_10pct_cost all_top,
coalesce(c.ip,0) ip, coalesce(c.op,0) op, coalesce(c.car,0) car, coalesce(c.paid,0) paid,
coalesce(c.ip_paid,0) ip_paid, coalesce(c.op_paid,0) op_paid, coalesce(c.car_paid,0) car_paid,
coalesce(c.op_months,0) op_months, coalesce(c.car_months,0) car_months,
coalesce(c.amb_h1,0) amb_h1, coalesce(c.amb_h2,0) amb_h2, coalesce(c.ip_h1,0) ip_h1,
s.inpatient_medicare_reimbursement_amount sum_ip,
s.outpatient_medicare_reimbursement_amount sum_op, s.carrier_medicare_reimbursement_amount sum_car
from mart.dim_beneficiaries d
join mart.mart_beneficiary_year_risk r using (beneficiary_id,reporting_year)
join staging.stg_beneficiary_summary s using (beneficiary_id,reporting_year)
left join claim_year c on c.beneficiary_id=d.beneficiary_id and c.yr=d.reporting_year;
analyze byear;
select yr, count(*) n, sum(ip) ip, sum(op) op, sum(car) car,
round(sum(ip_paid)) ip_paid, round(sum(op_paid)) op_paid, round(sum(car_paid)) car_paid,
round(sum(sum_ip)) sum_ip, round(sum(sum_op)) sum_op, round(sum(sum_car)) sum_car,
count(*) filter(where sum_ip>0 and ip=0) summary_ip_no_detail,
count(*) filter(where sum_op>0 and op=0) summary_op_no_detail,
count(*) filter(where sum_car>0 and car=0) summary_car_no_detail
from byear group by yr order by yr;
create temp table pairs as
with ranked as (
 select *, row_number() over(partition by yr order by paid desc, beneficiary_id) rn,
 count(*) over(partition by yr) ny
 from byear where full_ab and (death_date is null or death_date>=make_date(yr+1,1,1))
)
select b.beneficiary_id,b.yr,b.age,b.sex,b.cc,b.chf,b.ckd,b.diabetes,b.ip,b.op,b.car,b.paid,b.ip_paid,b.op_paid,b.car_paid,
b.op_months,b.car_months,b.amb_h1,b.amb_h2,
b.rn<=ceil(b.ny/10.0) top, f.rn<=ceil(f.ny/10.0) next_top,
b.rn>ceil(b.ny/2.0) bottom_half,
f.op_paid next_op_paid, f.car_paid next_car_paid, f.ip_paid next_ip_paid, f.ip next_ip_count, f.op next_op_count, f.car next_car_count, f.ip>0 next_ip, f.ip_h1>0 next_ip_h1, f.paid next_paid, f.sum_ip>0 next_summary_ip,
f.paid-b.paid>=5000 next_jump
from ranked b join ranked f on f.beneficiary_id=b.beneficiary_id and f.yr=b.yr+1;
analyze pairs;
select yr, count(*) n, count(*) filter(where next_ip) next_ip, count(*) filter(where next_top) next_top,
count(*) filter(where top) top_n, count(*) filter(where top and next_top) stay_top,
count(*) filter(where bottom_half) low_n,count(*) filter(where bottom_half and next_top) low_to_top,
count(*) filter(where bottom_half and ip=0 and next_top) low_no_ip_to_top,
min(paid) filter(where top) top_min,min(next_paid) filter(where next_top) next_top_min
from pairs group by yr order by yr;

\pset format unaligned
create temp table focus as
select *,
case when age<65 then 0 when age>=85 then 5 else (age-65)/5+1 end age_band,
case when paid>=30000 then 30000 else (paid::int/1000)*1000 end fine_spend,
case when paid>=40000 then 40000 else (paid::int/2500)*2500 end spend_band,
case when paid>=40000 then 40000 else (paid::int/5000)*5000 end coarse_spend,
case when age<65 then '<65' when age<75 then '65-74' when age<85 then '75-84' else '85+' end broad_age,
case when cc<=2 then '0-2' when cc<=5 then '3-5' else '6+' end broad_cc,
case when ip=0 then 'no IP' when ip_paid>paid/2 then 'IP majority' else 'IP and other mix' end mix,
case when op_paid>paid/2 then 'OP majority' when car_paid>paid/2 then 'carrier majority' when ip_paid>paid/2 then 'IP majority' else 'mixed' end dominant
from pairs;
select yr,mix,dominant,count(*) n,count(*) filter(where next_top) next_top,count(*) filter(where next_ip) next_ip,
count(*) filter(where next_paid>=12000) next_12k,
count(*) filter(where next_op_paid+next_car_paid>=5000) nonip_next_5k,
count(*) filter(where next_op_paid+next_car_paid>next_paid/2 and next_top) nonip_dominant_next_top,
round(avg(paid)) avg_base,round(percentile_cont(.5) within group(order by paid)::numeric) med_base,
round(avg(next_paid)) avg_next,round(avg(op)) avg_op,round(avg(car)) avg_car,round(avg(cc),2) avg_cc,
round(100*avg((ckd='1')::int),1) pct_ckd
from focus where top group by 1,2,3 order by 1,2,3;

select yr, case when top then 'top decile' when paid>=5000 then '$5K to cutoff' else '$3K to <$5K' end range, ip>0 prior_ip,
count(*) n,count(*) filter(where next_top) next_top,count(*) filter(where next_ip) next_ip,
count(*) filter(where next_paid>=12000) next_12k,round(avg(paid)) avg_base,round(avg(next_paid)) avg_next
from focus where top or paid>=3000 group by 1,2,3 order by 1,2,3;

select yr, count(*) filter(where not top and next_top) new_top,
count(*) filter(where not top and next_top and ip=0) new_top_no_ip,
count(*) filter(where not top and next_top and ip=0 and next_ip) new_top_no_ip_then_ip,
count(*) filter(where not top and next_top and ip=0 and car>=20) new_top_no_ip_high_car,
count(*) filter(where not top and ip=0 and car>=20) high_car_n,
count(*) filter(where not top and next_top and ip=0 and car>=20 and next_ip) high_car_new_top_ip,
count(*) filter(where not top and ip=0 and next_ip) low_ip_cases,
count(*) filter(where not top and ip=0 and car>=20 and next_ip) high_car_ip_cases,
count(*) filter(where next_paid>=12000) all_next12k,
count(*) filter(where not top and next_paid>=12000) new_next12k,
count(*) filter(where bottom_half and next_paid>=12000) bottom_next12k,
min(paid) filter(where not bottom_half) median_boundary
from focus group by 1 order by 1;

select yr,coarse_spend,ip>0 prior_ip,count(*) n,count(*) filter(where next_top) next_top, count(*) filter(where next_paid>=12000) next_12k
from focus where top and coarse_spend<30000 group by 1,2,3 order by 1,2,3;

-- Standardize the comparison to the no-inpatient distribution, with block-specific variance.
with groups as (
 select yr, 'Top 10%' as scope, age_band, sex, cc, spend_band, ip=0 as exposed,
        count(*) n, sum(next_top::int) hits, sum((next_paid>=12000)::int) hits12k,
        sum(next_ip::int) hospital
 from focus where top group by 1,2,3,4,5,6,7
 union all
 select yr, '$3K to cutoff', age_band, sex, cc, (paid::int/500)*500, ip=0,
        count(*), sum(next_top::int), sum((next_paid>=12000)::int), sum(next_ip::int)
 from focus where not top and paid>=3000 group by 1,2,3,4,5,6,7
), common as (
 select a.yr, a.scope, a.n, b.n bn, x.metric, x.ah, x.bh,
 x.ah::numeric/a.n ar, x.bh::numeric/b.n br
 from groups a join groups b using(yr,scope,age_band,sex,cc,spend_band)
 cross join lateral (values ('next_top',a.hits,b.hits),('next_12k',a.hits12k,b.hits12k),('next_ip',a.hospital,b.hospital)) x(metric,ah,bh)
 where a.exposed and not b.exposed and a.n>=1 and b.n>=3
), summary as (
 select yr,scope,metric,sum(n) a_n,sum(bn) b_n,sum(ah) actual_a,sum(bh) actual_b,
 sum(n*ar)/sum(n) a_rate,sum(n*br)/sum(n) b_rate,
 sqrt(sum(n*ar*(1-ar)+n*n*br*(1-br)/bn))/sum(n) se
 from common group by 1,2,3
)
select yr,scope,metric,a_n,b_n,actual_a,actual_b,
round(100*a_rate,2) a_pct,round(100*b_rate,2) b_pct,round(a_rate/nullif(b_rate,0),2) rr,
round(100*(a_rate-b_rate),2) pp,round(100*(a_rate-b_rate-1.96*se),2) lower,round(100*(a_rate-b_rate+1.96*se),2) upper
from summary order by 2,3,1;

\pset format unaligned
select yr, ckd, case when ip=0 then 'no inpatient' else 'inpatient' end baseline,
count(*) n,count(*) filter(where next_top) next_top,
count(*) filter(where next_paid>=12000) next12k,
count(*) filter(where next_top and not next_ip) next_top_no_ip,
count(*) filter(where next_top and next_op_paid>next_paid/2) next_top_op_majority
from pairs where top group by 1,2,3 order by 1,2,3;
with risk as (
 select yr, age/10 age_band, cc, sex, ckd, chf, diabetes,
 case when paid>=40000 then 40000 else floor(paid/5000)*5000 end spend_band,
 count(*) filter(where ip=0) a, count(*) filter(where ip>0) b,
 count(*) filter(where ip=0 and next_top) atop,count(*) filter(where ip>0 and next_top) btop,
 count(*) filter(where ip=0 and next_paid>=12000) a12k,count(*) filter(where ip>0 and next_paid>=12000) b12k
 from pairs where top group by 1,2,3,4,5,6,7,8
), common as (
 select yr, a,b, metric, ah,bh, ah::numeric/a ar, bh::numeric/b br,
 (ah+0.5)/(a+1) ap,(bh+0.5)/(b+1) bp
 from risk cross join lateral(values ('next_top',atop,btop),('next_12k',a12k,b12k)) m(metric,ah,bh)
 where a>=1 and b>=3
), summary as (
 select yr,metric,sum(a) na,sum(b) nb,sum(ah) ah,sum(bh) bh,
 sum(a*ar)/sum(a) ar,sum(a*br)/sum(a) br,
 sqrt(sum(a*ap*(1-ap)+a*a*bp*(1-bp)/b))/sum(a) se
 from common group by 1,2
)
select yr,metric,na,nb,ah,bh,round(100*ar,2) a_pct,round(100*br,2) b_pct,
round(ar/nullif(br,0),2) rr,round(100*(ar-br),2) pp,
round(100*(ar-br-1.96*se),2) lower,round(100*(ar-br+1.96*se),2) upper
from summary order by metric,yr;

\pset format unaligned
create temp table operational as
select *, case when age<65 then 0 when age>=85 then 5 else (age-65)/5+1 end age_band,
case when paid<1000 then (paid::int/250)*250 when paid<6000 then (paid::int/1000)*1000 else (paid::int/2000)*2000 end spend_band,
case when op=0 then 0 when op<=2 then 1 when op<=5 then 2 when op<=9 then 3 else 4 end op_band,
case when age<65 then '<65' when age<75 then '65-74' when age<85 then '75-84' else '85+' end broad_age,
case when cc<=2 then '0-2' when cc<=5 then '3-5' else '6+' end broad_cc
from pairs where not top and ip=0;
select yr,car>=20 dense,count(*) n,count(*) filter(where next_top) next_top,
count(*) filter(where next_paid>=12000) next12k,count(*) filter(where next_ip) next_ip,
count(*) filter(where next_jump) next_jump,round(avg(paid)) avg_base,round(avg(cc),2) avg_cc
from operational group by 1,2 order by 1,2;
with ranked as (
 select *, count(*) filter(where car>=20) over(partition by yr) as capacity,
 row_number() over(partition by yr order by paid desc,beneficiary_id) by_spend
 from operational
)
select yr, queue, count(*) n,count(*) filter(where next_top) next_top, count(*) filter(where next_paid>=12000) next12k,
count(*) filter(where next_ip) next_ip,count(*) filter(where next_jump) next_jump,
round(avg(paid)) avg_baseline, count(*) filter(where car>=20 and by_spend<=capacity) overlap
from ranked
cross join lateral (values ('carrier 20+',car>=20),('same-size spending',by_spend<=capacity)) q(queue,included)
where included group by 1,2 order by 1,2;
create temp table op_blocks as
select yr,age_band,sex,cc,spend_band,op_band,
count(*) filter(where car>=20) a,count(*) filter(where car<20) b,
count(*) filter(where car>=20 and next_top) atop,count(*) filter(where car<20 and next_top) btop,
count(*) filter(where car>=20 and next_paid>=12000) a12k,count(*) filter(where car<20 and next_paid>=12000) b12k,
count(*) filter(where car>=20 and next_ip) aip,count(*) filter(where car<20 and next_ip) bip,
count(*) filter(where car>=20 and next_ip_h1) ah1,count(*) filter(where car<20 and next_ip_h1) bh1,
count(*) filter(where car>=20 and next_jump) ajump,count(*) filter(where car<20 and next_jump) bjump,
count(*) filter(where car>=20 and next_top and next_ip) a_joint,count(*) filter(where car<20 and next_top and next_ip) b_joint
from operational group by 1,2,3,4,5,6;
with risks as (
select yr,metric,a,b, ah,bh, ah::numeric/a ar,bh::numeric/b br
from op_blocks cross join lateral (values ('next_top',atop,btop),('next_12k',a12k,b12k),('next_ip',aip,bip),('next_ip_H1',ah1,bh1),('jump_5k',ajump,bjump),('next_top_and_ip',a_joint,b_joint)) x(metric,ah,bh)
where a>=5 and b>=5
), agg as (
select yr,metric,sum(a) na,sum(b) nb,sum(ah) actual_a,sum(bh) actual_b,sum(a*ar)/sum(a) ar,sum(a*br)/sum(a) br,
sqrt(sum(a*ar*(1-ar)+a*a*br*(1-br)/b))/sum(a) se from risks group by 1,2
)
select yr,metric,na,nb,actual_a,actual_b,
round(100*ar,2) exposed_pct,round(100*br,2) standardized_cmp_pct,round(ar/nullif(br,0),2) rr,
round(100*(ar-br),2) pp,round(100*(ar-br-1.96*se),2) lower,round(100*(ar-br+1.96*se),2) upper from agg order by metric,yr;

-- Sensitivity to restricting follow-up enrollment. Baseline rank is held fixed.
with eligible_baseline as (
    select *, row_number() over (partition by yr order by paid desc, beneficiary_id)
        <= ceil(count(*) over (partition by yr) / 10.0) as top
    from byear
    where full_ab and (death_date is null or death_date >= make_date(yr + 1, 1, 1))
),
followup_status as (
    select b.yr, b.ip = 0 as no_baseline_ip,
        case
            when f.beneficiary_id is null then 'no follow-up row'
            when f.full_ab and (f.death_date is null or f.death_date >= make_date(f.yr + 1, 1, 1))
                then 'full observation'
            else 'other follow-up row'
        end as status,
        f.paid
    from eligible_baseline b
    left join byear f on f.beneficiary_id = b.beneficiary_id and f.yr = b.yr + 1
    where b.top and b.yr < 2010
)
select yr, no_baseline_ip, status, count(*) as n,
    count(*) filter (where paid >= 12000) as outcomes_12k
from followup_status
group by 1, 2, 3
order by 1, 2, 3;

-- Count events in the overlap and in each exclusive queue.
with ranked as (
    select *, count(*) filter (where car >= 20) over (partition by yr) as capacity,
        row_number() over (partition by yr order by paid desc, beneficiary_id) as by_spend
    from operational
)
select yr, car >= 20 as carrier_queue, by_spend <= capacity as spend_queue,
    count(*) as n, count(*) filter (where next_top) as next_top,
    count(*) filter (where next_paid >= 12000) as next_12k,
    count(*) filter (where next_ip) as next_ip
from ranked
group by 1, 2, 3
order by 1, 2, 3;

create temp table screen as
select p.*, case when age<65 then 0 when age>=85 then 5 else (age-65)/5+1 end age_band,
case when paid=0 then 0 when paid<250 then 1 when paid<500 then 2 when paid<1000 then 3
when paid<2000 then 4 when paid<3500 then 5 when paid<6000 then 6 when paid<10000 then 7
when paid<15000 then 8 when paid<25000 then 9 else 10 end spend_band,
case when op<=1 then op when op<=3 then 2 when op<=6 then 3 when op<=12 then 4 else 5 end op_band,
case when car=0 then 0 when car<=5 then 1 when car<=12 then 2 when car<=25 then 3 when car<=50 then 4 else 5 end car_band,
width_bucket(amb_h1+amb_h2,array[6,11,16,26,41,61,101]) amb_band
from pairs p;
analyze screen;
create temp table strata as
select yr, test, age_band, cc, sex, spend_band, extra,
count(*) filter(where exposed) a, count(*) filter(where not exposed) b,
count(*) filter(where exposed and next_ip) aip, count(*) filter(where not exposed and next_ip) bip,
count(*) filter(where exposed and next_top) atop, count(*) filter(where not exposed and next_top) btop,
count(*) filter(where exposed and next_jump) ajump, count(*) filter(where not exposed and next_jump) bjump,
count(*) filter(where exposed and next_ip_h1) ahalf, count(*) filter(where not exposed and next_ip_h1) bhalf,
count(*) filter(where exposed and next_summary_ip) asum, count(*) filter(where not exposed and next_summary_ip) bsum
from screen
cross join lateral (values
 ('OP spread, no IP, below median', op_months>=3, ip=0 and bottom_half, 0),
 ('OP spread, same rough OP volume', op_months>=4, ip=0 and op>=4 and not top, op_band),
 ('OP vs carrier only', op>0, ip=0 and car>0 and not top, car_band),
 ('High carrier intensity, no IP', car>=20, ip=0 and not top, op_band),
 ('Late acceleration, no IP', amb_h2>=2*amb_h1 and amb_h2>amb_h1, ip=0 and not top and amb_h1+amb_h2>=6 and (amb_h2>=2*amb_h1 or amb_h2<=amb_h1), amb_band),
 ('Early concentration, no IP', amb_h1>=2*amb_h2 and amb_h1>amb_h2, ip=0 and not top and amb_h1+amb_h2>=6 and (amb_h1>=2*amb_h2 or amb_h1<=amb_h2), amb_band),
 ('Late collapse, no IP, dense history', amb_h2=0, ip=0 and not top and amb_h1>=6 and (amb_h2=0 or amb_h2>=amb_h1), amb_band),
 ('No IP among top decile', ip=0, top, 0),
 ('OP majority among top decile', op_paid>paid/2, top and (op_paid>paid/2 or ip_paid>paid/2), 0),
 ('Carrier majority among top decile', car_paid>paid/2, top and (car_paid>paid/2 or ip_paid>paid/2), 0),
 ('No carrier despite OP', car=0, ip=0 and op>0 and not top, op_band),
 ('No OP despite active carrier', op=0, ip=0 and car>=10 and not top, car_band),
 ('Prior IP below top decile', ip>0, not top, 0)
) as hypotheses(test,exposed,eligible,extra)
where eligible
group by 1,2,3,4,5,6,7;
\pset format unaligned
select yr,test,sum(a) all_a,sum(b) all_b,
sum(a) filter(where a>=5 and b>=5) matched_a,sum(b) filter(where a>=5 and b>=5) matched_b,
round(100*sum(aip)::numeric/sum(a),2) raw_aip,round(100*sum(bip)::numeric/sum(b),2) raw_bip,
round(100*sum(aip) filter(where a>=5 and b>=5)::numeric / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_aip,
round(100*sum(a*bip::numeric/nullif(b,0)) filter(where a>=5 and b>=5) / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_bip,
round(100*sum(atop) filter(where a>=5 and b>=5)::numeric / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_atop,
round(100*sum(a*btop::numeric/nullif(b,0)) filter(where a>=5 and b>=5) / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_btop,
round(100*sum(ajump) filter(where a>=5 and b>=5)::numeric / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_ajump,
round(100*sum(a*bjump::numeric/nullif(b,0)) filter(where a>=5 and b>=5) / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_bjump,
round(100*sum(ahalf) filter(where a>=5 and b>=5)::numeric / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_ahalf,
round(100*sum(a*bhalf::numeric/nullif(b,0)) filter(where a>=5 and b>=5) / nullif(sum(a) filter(where a>=5 and b>=5),0),2) adj_bhalf
from strata group by yr,test order by test,yr;

rollback;
