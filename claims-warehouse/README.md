# Medicare claims warehouse · raw ingestion

Load the eight CSVs in [CMS DE-SynPUF Sample 1](https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf/de10-sample-1) into PostgreSQL. These are synthetic Medicare records covering 2008–2010. The source files stay on your machine.

## Run on Windows

Install Python 3.10 or newer and start PostgreSQL. The database `claims_warehouse` must exist. From this directory in PowerShell:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe load_raw.py "$HOME\Documents\ClaimsWarehouse\raw" --ask-password
```

Point the command at the directory containing the **extracted CSV files**. To try inpatient claims alone, append `--table inpatient_claims`. The connection defaults to `postgres@localhost:5432/claims_warehouse`. Override individual settings with `PGHOST`, `PGPORT`, `PGDATABASE`, or `PGUSER`. Omit `--ask-password` to use your configured PostgreSQL password file.

## Raw tables

| Table | Inputs | Expected source rows |
|---|---|---:|
| raw.beneficiary_summary | Three annual beneficiary files | 343,644 |
| raw.inpatient_claims | Inpatient | 66,773 |
| raw.outpatient_claims | Outpatient | 790,790 |
| raw.carrier_claims | Carrier A and B | 4,741,335 |
| raw.prescription_drug_events | Prescription drug events | 5,552,421 |

The loader streams each CSV with PostgreSQL COPY. Source fields use lowercase names and text types to preserve codes and leading zeros. Unquoted empty fields become SQL NULL. Every row retains its source filename and load timestamp. The beneficiary filename identifies its reporting year. Counts here refer to file rows, which may include multiple segments for a claim.

The checked-in release manifest lists the expected columns and record count for each file. Each run replaces only rows belonging to its selected source files. All selected files commit together. A failed run rolls back, and concurrent runs wait for one another.

## Verify in pgAdmin

Open the Query Tool for `claims_warehouse` and run:

```sql
SELECT source_file, count(*) AS rows_loaded
FROM raw.inpatient_claims
GROUP BY source_file;
```

For Sample 1, expect 66,773 rows.
