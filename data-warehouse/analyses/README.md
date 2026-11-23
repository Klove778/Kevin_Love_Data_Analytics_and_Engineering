# Tableau dashboard analyses

These dbt analyses query `mart_beneficiary_year_risk` for reporting years 2008–2010. Each source row represents a beneficiary-year. The mart identifies the highest-cost 10% within each year. Spending percentages in the exports use a 0–100 scale, and inpatient utilization counts claims per 1,000 beneficiary-years.

| Analysis | Business question |
| --- | --- |
| `chronic_condition_comparison.sql` | How do reimbursement, high-cost share, and inpatient utilization differ between beneficiary-years with and without each condition? Compare flag `1` with flag `2` and exclude other codes from that condition's comparison. |
| `chronic_condition_opportunities.sql` | How large is each condition's population and spending footprint? Include flag `1` and report both total reimbursement and per-beneficiary-year measures. |
| `ckd_care_management_comparison.sql` | How do three CKD pairs compare with beneficiary-years of the same age, reporting year, and chronic condition count? |

For each CKD pair, both flags must equal `1`. Comparators can have one or neither condition in the pair. The analysis includes strata with known age and a chronic condition count of at least two. The total pair count includes pair rows in all such strata. The eligible pair count includes only strata with at least 10 comparator beneficiary-years. Both groups' outcomes are weighted by the number of pair rows in each eligible stratum. Differences use unrounded outcomes. These exploratory associations cannot establish causal effects or expected savings. Condition groups overlap, so counts and costs should not be added across rows.

## Compile and run

From the repository root, with the PostgreSQL mart already built and dbt configured as described in the [project README](../../README.md), compile all three analyses.

```powershell
.\.venv\Scripts\dbt.exe compile --project-dir data-warehouse --profiles-dir data-warehouse --select chronic_condition_comparison chronic_condition_opportunities ckd_care_management_comparison
```

Run the compiled SQL with `psql` using the same PostgreSQL connection settings. Replace the filename to run either of the other analyses.

```powershell
psql -X -v ON_ERROR_STOP=1 --csv -f data-warehouse/target/compiled/claims_warehouse/analyses/chronic_condition_comparison.sql
```

The corresponding files in [`tableau-exports`](../../tableau-exports/) contain 22, 11, and 3 data rows, respectively.
