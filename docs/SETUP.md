# Local setup and technical notes

This document contains the full ingestion, database configuration, dbt, and Tableau export instructions for the Medicare Claims Analytics project. The [project overview](../README.md) covers the architecture, engineering decisions, and analysis.

## Data pipeline

Load the eight CSVs in [CMS DE-SynPUF Sample 1](https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf/de10-sample-1) into PostgreSQL. These are synthetic Medicare records covering 2008–2010. The source files stay on your machine.

### Run on Windows

Install Python 3.10 or newer and start PostgreSQL. The database `claims_warehouse` must exist. Place your local `.env` in the repository root or inside `data-pipeline`. Set all five PostgreSQL connection variables. The loader reports missing names before it opens a CSV or connects.

```dotenv
PGHOST=localhost
PGPORT=5432
PGDATABASE=claims_warehouse
PGUSER=postgres
PGPASSWORD=your_local_password
```

From the repository root in PowerShell:

```powershell
cd data-pipeline
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe load_raw.py "$HOME\Documents\ClaimsWarehouse\raw"
```

Point the command at the directory containing the **extracted CSV files**. To try inpatient claims alone, append `--table inpatient_claims`. For a file elsewhere, add `--env-file "C:\path\to\.env"`. The loader checks the pipeline directory first, then the repository root. Existing environment variables take precedence. Use `--ask-password` for an interactive password override.

### Raw tables

| Table | Inputs | Expected source rows |
|---|---|---:|
| raw.beneficiary_summary | Three annual beneficiary files | 343,644 |
| raw.inpatient_claims | Inpatient | 66,773 |
| raw.outpatient_claims | Outpatient | 790,790 |
| raw.carrier_claims | Carrier A and B | 4,741,335 |
| raw.prescription_drug_events | Prescription drug events | 5,552,421 |

The loader streams each CSV with PostgreSQL COPY. Source fields use lowercase names and text types to preserve codes and leading zeros. Unquoted empty fields become SQL NULL. Every row retains its source filename and load timestamp. The beneficiary filename identifies its reporting year. Counts here refer to file rows, which may include multiple segments for a claim.

The checked-in release manifest lists the expected columns and record count for each file. Each run replaces only rows belonging to its selected source files. All selected files commit together. A failed run rolls back, and concurrent runs wait for one another.

The CMS files supply no source creation or modification timestamps. The loader
simulates them as `created_on` and `updated_at`. It backfills existing raw rows
from their original `loaded_at` before replacing any rows. A reload preserves the
simulated timestamps for each source record in the file, including the segment
for hospital claims. New records start with equal simulated timestamps.
`loaded_at` continues to record the PostgreSQL load time on every load.

After upgrading an existing warehouse, run the loader for all raw tables once.
Then rebuild the staging views and claims fact once to initialize the new
watermark.

```powershell
.\.venv\Scripts\dbt.exe run --project-dir data-warehouse --profiles-dir data-warehouse --select path:models/staging fct_claims --full-refresh
```

For later runs, `fct_claims` merges by `claim_key` using `updated_at`. To simulate
a source correction, change the raw claim and set its `updated_at` to a timestamp
later than the current claims watermark, then run the model incrementally.
Reloading a CMS file carries timestamps forward by record ID. A source payload
correction needs an explicit timestamp change. Hospital claims use the latest
update across segments 1 and 2 and keep the existing segment 1 payment logic.

### Verify in pgAdmin

Open the Query Tool for `claims_warehouse` and run:

```sql
SELECT source_file, count(*) AS rows_loaded
FROM raw.inpatient_claims
GROUP BY source_file;
```

For Sample 1, expect 66,773 rows.

## Data warehouse

From the repository root in PowerShell, use the project's virtual environment
and the same root `.env` file. dbt Core reads `.env` from the directory where
you run the command. Shell environment variables take precedence.

```powershell
.\.venv\Scripts\python.exe -m pip install -r data-warehouse\requirements.txt
.\.venv\Scripts\dbt.exe debug --project-dir data-warehouse --profiles-dir data-warehouse
.\.venv\Scripts\dbt.exe parse --project-dir data-warehouse --profiles-dir data-warehouse
.\.venv\Scripts\dbt.exe build --project-dir data-warehouse --profiles-dir data-warehouse --select stg_carrier_claims
```

`dbt debug` checks the PostgreSQL connection. `dbt parse` validates the project
without connecting. After loading `raw.carrier_claims`, the build creates the
`staging.stg_carrier_claims` view with typed dates and amounts. It preserves one
row per source record, the numbered claim line positions, and load metadata.

### Hospital diagnosis descriptions for Tableau

The checked-in ICD-9-CM seed uses the [CMS diagnosis code titles](https://www.cms.gov/medicare/coding-billing/icd-10-codes/icd-9-cm-diagnosis-procedure-codes-abbreviated-and-full-code-titles) for releases 25 through 28, covering the 2008–2010 claims period. It uses full titles from version 28 and earlier abbreviated titles for codes absent from that release. When a code appears in multiple releases, the dimension uses the newest included title.

With `mart.fct_claim_codes` already built, run from the repository root:

```powershell
.\.venv\Scripts\dbt.exe build --project-dir data-warehouse --profiles-dir data-warehouse --select +dim_diagnosis_codes tableau_hospital_claim_codes --indirect-selection cautious
```

The coverage test warns about hospital diagnosis codes with no lookup match. Unmatched diagnoses, procedure codes, and HCPCS codes remain in the export with a blank diagnosis description.

With PostgreSQL's `psql` on your PATH and the same `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, and `PGPASSWORD` values set in your shell, export the tested view:

```powershell
psql -v ON_ERROR_STOP=1 -c "\copy mart.tableau_hospital_claim_codes TO 'tableau-exports/fct_claim_codes_hospital.csv.part' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"
if ($LASTEXITCODE -eq 0) {
    Move-Item -LiteralPath 'tableau-exports/fct_claim_codes_hospital.csv.part' -Destination 'tableau-exports/fct_claim_codes_hospital.csv' -Force
}
```

Refresh the hospital code data source in Tableau. Its relationship to the claims CSV still uses `claim_key`.
