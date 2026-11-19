# klove778.github.io
Kevin Love’s data engineering and analytics portfolio

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
```

`dbt debug` checks the PostgreSQL connection. `dbt parse` validates the project
without connecting. The project registers the five `raw` tables as dbt sources
and uses `analytics` as the target schema for future models.
