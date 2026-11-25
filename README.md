![Medicare Claims Analytics](https://raw.githubusercontent.com/Klove778/Klove778/main/assets/medicare-feature.png)

# Medicare Claims Analytics

**End-to-end data engineering and healthcare analytics**

[**View the interactive Tableau dashboards**](https://public.tableau.com/app/profile/kevin.love3952/viz/MedicarePopulationHealthCostAnalysis/ExecutiveOverview) · [Explore the dbt models](data-warehouse/models/marts/) · [Review the analysis SQL](data-warehouse/analyses/)

I built this project using CMS's **2008–2010 synthetic Medicare claims data**. It covers the full path from raw files and data modeling to quality checks, dashboards, and a closer look at healthcare utilization and spending.

**~5.6 million claims** · **343,644 beneficiary-year records** · **Inpatient, outpatient, and carrier claims**

## The problem

Claims data is useful for understanding healthcare costs, but it is not particularly easy to analyze straight from the source. Hospital claims can span multiple records. Carrier payments are scattered across numbered service-line fields. Beneficiary information is organized by reporting year.

If those details aren't handled correctly, it's easy to double-count payments or produce misleading utilization measures.

The aim was to demonstrate a decade+ of healthcare data experience by building a simplified claims data model and use it to ask questions a health plan or care-management team might ask: Where is spending concentrated? Which populations use more inpatient care? What changes when chronic conditions occur together?

## What the analysis found

- **Spending is concentrated.** The highest-spending 10% of beneficiary-years account for approximately **61% of reimbursement** in the analysis.
- **Chronic kidney disease stands out.** Beneficiary-years flagged for CKD average **$11,481 in annual reimbursement**, and **36.2%** fall in the highest-spending decile.
- **Combinations of conditions matter.** In an exploratory comparison grouped by age, year, and number of chronic conditions, beneficiary-years with **CKD + heart failure** averaged **$4,418 more reimbursement** and **260 additional inpatient claims per 1,000 beneficiary-years** than the comparison group.

These results are from *synthetic*, historical data. They describe associations, not causal effects or predicted savings. The CKD comparison is an exploratory stratified analysis—not a clinical risk-adjustment model.

**[Explore the dashboards in Tableau Public](https://public.tableau.com/app/profile/kevin.love3952/viz/MedicarePopulationHealthCostAnalysis/ExecutiveOverview)**

## How I built it

**Data ingestion.** A Python loader streams CMS CSVs into PostgreSQL using `COPY`, validates file structure and expected row counts, and records source metadata. Raw loads use transactions so a failed batch can roll back.

**Warehouse and transformations.** dbt staging views standardize fields and types. The marts combine inpatient, outpatient, and carrier data into a common claim fact; normalize diagnosis and procedure codes; and build a beneficiary-year view of reimbursement, utilization, and 11 chronic conditions.

**Claims-specific logic.** Hospital segments are consolidated without counting the same payment twice. Carrier reimbursements are rolled up from eligible service lines. Incomplete hospital claims are flagged instead of silently filled in.

**Reliability.** dbt tests check keys and relationships, and a reconciliation test compares calculated reimbursement with the CMS beneficiary summary. The claims fact also demonstrates incremental `merge` processing. Because the source is a set of static files, its change timestamps are **simulated**, not a live CDC feed.

**Reporting.** Tableau dashboards cover claim volumes and spend, utilization and cost drivers, and chronic-condition risk. Separate SQL analyses examine condition-level differences and CKD comorbidities.

## Explore the repository

| Area | What's there |
| --- | --- |
| [Python ingestion](data-pipeline/) | Raw file loading and source validation |
| [dbt staging](data-warehouse/models/staging/) | Source cleanup and standardization |
| [dbt marts](data-warehouse/models/marts/) | Claims, diagnoses, beneficiaries, and risk models |
| [Data quality tests](data-warehouse/tests/) | Payment reconciliation and other checks |
| [Analysis SQL](data-warehouse/analyses/) | Chronic-condition and comorbidity comparisons |
| [Local setup guide](docs/SETUP.md) | Database configuration, commands, and exports |

**Data source:** [CMS DE-SynPUF Sample 1](https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf/de10-sample-1). These are artificial records intended for research and development; the project does not use real patient data.
