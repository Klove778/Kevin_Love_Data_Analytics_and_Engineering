# Predicting Persistent High-Cost Beneficiaries

If a team can review only 485 of last year's expensive members, can it identify more of those whose costs will remain high next year? The original hypothesis was that two similar spending totals could represent different patterns. A year dominated by recurring treatment might repeat more often than one dominated by a hospital episode.

In the original held-out evaluation, ranking by **outpatient plus carrier spending** identified **260 of 485** persistent high-cost beneficiaries (**53.6% precision**). Ranking by total spending identified **163 of 485** (**33.6%**). The full model identified **268** (**55.3%**). The simple rule added 97 cases over total spending and captured 97 of the full model's 105 additional cases.

## Cohort and outcome

- Source data are CMS DE-SynPUF Sample 1 in the existing PostgreSQL warehouse. Reimbursement is the sum of inpatient, institutional outpatient, and carrier claims. Claim calendar year comes from the claim end date.
- Rank each year's beneficiaries separately. Require 12 months each of Parts A and B, zero recorded HMO months, and survival through that year-end. Sort by reimbursement descending and use beneficiary ID to break ties. The top decile is the first 10% of rows, rounded up.
- Link the eligible 2008 and 2009 rows and keep the 2008 top decile. Of 63,034 linked beneficiaries, 6,368 were in the 2008 top decile. The outcome was membership in the 2009 top decile, whose minimum reimbursement was $12,150. There were 1,945 persistent high-cost beneficiaries among the 6,368.
- The deterministic beneficiary hash split produced 4,430 training and 1,938 held-out beneficiaries. The held-out group contained 579 persistent cases. Predictors used 2008 claims and flags. The 2009 cohort and ranks supplied the outcome, and full 2009 observation was a retrospective inclusion requirement.

## Original evaluation

| Ranking | Correct / reviewed | Precision | Recall |
| --- | ---: | ---: | ---: |
| Total prior-year spending | 163 / 485 | 33.6% | 28.2% |
| Total spending plus ESRD | 243 / 485 | 50.1% | 42.0% |
| Outpatient plus carrier spending | 260 / 485 | 53.6% | 44.9% |
| Full service-mix model | 268 / 485 | 55.3% | 46.3% |

For the spending rules, rank in descending order by total reimbursement or by the sum of outpatient and carrier reimbursement. Carrier claims cover professional and supplier billing. The ESRD comparison fits a regularized logistic regression using log spending and the annual ESRD flag. The full model uses log spending, the share of spending in each setting, log claim counts by setting, and an indicator for zero inpatient claims. The model learns how those values combine to predict the 2009 outcome and ranks members by the resulting score. Feature scaling and fitting use training beneficiaries only.

Review the first 485 ranked beneficiaries from each method, with the beneficiary hash as the tie-breaker. Precision is correct identifications divided by 485 slots. Recall divides the same numerator by the 579 persistent cases in the held-out group. The full model found 164 cases outside the total-spend list and gave up 59 cases from that list. Its approximate paired bootstrap interval for the gain over total spending was +17.5 to +26.6 percentage points in precision, conditional on the fitted rankings.

## Why the spending mix mattered

Among the 275 baseline high spenders without an institutional inpatient claim, 229 had a CKD flag, 210 had an ESRD flag, and 204 had a dialysis procedure or ESRD management code. The ESRD-flagged group accounted for 194 of the 218 persistent cases. The most frequent institutional outpatient codes included dialysis, renal medications, and dialysis supplies. Outpatient claims carrying a dialysis procedure or management code represented $3.04 million of $4.19 million in outpatient reimbursement. Eligible carrier lines with those codes added $157,280. Outpatient reimbursement is available at the whole-claim level, so overlapping code payments cannot be separated within a claim.

Observed persistence was 218/275 (79.3%) without baseline inpatient claims and 1,727/6,093 (28.3%) with them. After excluding the ESRD flag and identifiable baseline dialysis procedures or management codes in both groups, the rates were 21/57 (36.8%) and 865/3,895 (22.2%). Standardizing by shared age bands, sex, chronic-condition count, and $2,500 baseline spending bands reduced the gap from **52.2 to 18.6 points**. The latter comparison used 42 and 295 beneficiaries and had an approximate interval of +4.6 to +32.7 points. A broader exclusion for selected renal diagnoses, supplies, and drugs left a +17.9-point gap. The residual samples were small, and some beneficiaries without baseline dialysis evidence had a dialysis code the next year.

## Complexity versus value

The later investigation used the original 4,430 training beneficiaries only. The already-reviewed holdout results had influenced the study direction and stayed outside this round. Five outer folds each made predictions for their own validation beneficiaries. Three inner folds selected the model family using equal-capacity review yield. Across the outer folds, every method had 1,108 slots and 1,366 actual persistent cases.

The outpatient-plus-carrier rule found 647 cases (58.4% precision, 47.4% recall). The strongest fixed model used separate ESRD and non-ESRD models and found 659 (59.5%, 48.2%). The highest-yield inner selection procedure found 651 (58.8%, 47.7%), with an approximate precision gain interval of −1.7 to +2.5 points versus the simple rule. The interval uses paired resampling at fixed capacity and conditions on the fitted scores. Recurrence, chronic flags, and billing codes were reasonable candidates. Their incremental yield was small relative to the improvement from decomposing total spending.

## Interpretation and limits

This is a historical synthetic-data case study about retrospective prioritization and forecasting. Real-claims use would require an out-of-time evaluation with eligibility as of the scoring date, claims runout, and explicit handling of death and disenrollment. The analysis does not establish intervention effects, preventability, or savings.

CMS altered claim dates, codes, and relationships between variables during disclosure treatment. The ESRD flag is derived from synthetic claims. We found some 2009-era ESRD management codes on claims dated in 2008. In the 2009→2010 warehouse comparison, beneficiary rows fell 1.6% while dated inpatient, outpatient, and carrier claims fell about 45%, 46%, and 38%. CMS documents attrition and disclosure effects in 2010. The featured predictive evaluation uses 2008→2009 only. [CMS DE-SynPUF user manual](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/Downloads/SynPUF_DUG.pdf), [CMS codebook](https://www.cms.gov/files/document/cms08-10desynpufcodebookpdf), [CMS ESRD coding transition](https://www.cms.gov/Regulations-and-Guidance/Guidance/Transmittals/Downloads/R419OTN.pdf)

## Reproduce the exports

Use the existing CMS DE-SynPUF Sample 1 warehouse described in the [project README](../../../README.md). The runner requires Python 3.10 or later and PostgreSQL's `psql`. Python uses only the standard library. The SQL reads `mart.dim_beneficiaries`, `mart.mart_beneficiary_year_risk`, `mart.fct_claims`, `mart.dim_diagnosis_codes`, the raw hospital and carrier tables, and the existing staging summary for the optional longitudinal analysis. The database role needs read access and permission to create session-local temporary tables. Set the usual PostgreSQL connection variables in the launching shell, or configure an equivalent libpq connection. Use a password file or environment variable for noninteractive authentication.

Run this from the repository root with the project interpreter and `psql` on PATH.

```sh
python data-warehouse/analyses/persistent-high-cost/run_case_study.py
```

Use `--psql PATH` if the executable is outside PATH, `--output-dir PATH` to write to a separate directory, or `--only models` and `--only dialysis` to run the two stages independently. The dialysis audit scans large source tables and can take several minutes. The runner stages the three small CSVs and validates published counts before replacing them. Its model inputs are beneficiary-grain CSVs in a system-managed temporary directory, removed when the command exits normally. SQL creates only session-local tables and rolls back each analysis.

| Order | Files | Purpose |
| --- | --- | --- |
| 1 | `cohort.sql` | Common annual eligibility, ranking, and linked cohort. The feature and audit scripts include it automatically. |
| 2 | `holdout_features.sql`, `cv_features.sql` | Prepare 2008 predictors and the 2009 label. The CV extract contains the original training partition only. |
| 3 | `holdout_baselines.py`, `holdout_evaluation.py`, `nested_cv.py` | Reproduce the four holdout rankings, original scope and capacity checks, and nested CV, respectively. The runner invokes the holdout and CV comparisons. |
| 4 | `dialysis_audit.sql` | Reproduce diagnosis and procedure frequencies, payment concentration, and persistence after exclusions. |
| Optional | `longitudinal_exploration.sql` | Preserve the earlier year-to-year screening and 2010 sensitivity results. Run directly with `psql -X -v ON_ERROR_STOP=1 -f`. |

For the original additional holdout checks, run `holdout_features.sql` with `psql -v output_csv=PATH -f` and pass that CSV to `holdout_evaluation.py`. For a stand-alone dialysis audit, omit `output_csv` to print the detailed results, or supply it to also write the aggregate CSV. Keep individual-level extracts outside version control.

## Tableau handoff

Connect to [model_comparison_holdout.csv](../../../tableau-exports/persistent-high-cost/model_comparison_holdout.csv) first. Add the other two as separate sources because their grains and denominators differ. Fields ending in `_pct` or `_pp` use a 0–100 scale. In Tableau, display them as numbers with a percent suffix, or divide by 100 before applying the percentage format.

1. **Business result.** Use four horizontal bars in `method_order` at a fixed 485-slot capacity. Label each bar with both correct cases and precision. Emphasize 163 to 260, and place 268 on the same scale.
2. **Why it works.** Show 210/275 with ESRD, 204/275 with dialysis evidence, and 194/218 persistent cases with ESRD. Use paired dots for observed persistence before and after the main exclusions. Expose denominators and the standardized gap in the tooltip. Filter [dialysis_investigation.csv](../../../tableau-exports/persistent-high-cost/dialysis_investigation.csv) by `section` and use `sort_order` to keep definitions in order.
3. **Complexity versus value.** Use a small dot-and-interval view from [model_comparison_cv.csv](../../../tableau-exports/persistent-high-cost/model_comparison_cv.csv) with precision change relative to the outpatient-plus-carrier rule. Label it “training cross-validation · 1,108 slots.” Show the zero line prominently and keep 260 versus 268 as the holdout callout.
