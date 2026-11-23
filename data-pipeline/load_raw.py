"""Load the CMS DE-SynPUF Sample 1 CSV release into PostgreSQL."""
import argparse
import csv
import getpass
import json
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg import sql


RELEASE = json.loads(Path(__file__).with_name("sample_1.json").read_text())
CHUNK_SIZE = 1024 * 1024
SOURCE_KEYS = {
    "beneficiary_summary": ("desynpuf_id",),
    "carrier_claims": ("clm_id",),
    "inpatient_claims": ("clm_id", "segment"),
    "outpatient_claims": ("clm_id", "segment"),
    "prescription_drug_events": ("pde_id",),
}


def check_header(stream, expected, filename):
    header = next(csv.reader([stream.readline().decode("utf-8-sig")]), [])
    if header != expected:
        raise ValueError(f"{filename}: CSV columns differ from Sample 1")


def ensure_source_timestamps(cur, target):
    cur.execute("""
        SELECT count(*) = 2
        FROM pg_attribute
        WHERE attrelid = %s::regclass
          AND attname IN ('created_on', 'updated_at')
          AND attnotnull AND NOT attisdropped
    """, (target.as_string(cur),))
    if cur.fetchone()[0]:
        return

    cur.execute(sql.SQL("""
        ALTER TABLE {}
            ADD COLUMN IF NOT EXISTS created_on timestamptz,
            ADD COLUMN IF NOT EXISTS updated_at timestamptz
    """).format(target))
    cur.execute(sql.SQL("""
        UPDATE {}
        SET created_on = coalesce(created_on, loaded_at),
            updated_at = coalesce(updated_at, created_on, loaded_at)
        WHERE created_on IS NULL OR updated_at IS NULL
    """).format(target))
    cur.execute(sql.SQL("""
        ALTER TABLE {}
            ALTER COLUMN created_on SET NOT NULL,
            ALTER COLUMN updated_at SET NOT NULL
    """).format(target))


def load_table(cur, folder, table, spec):
    names = [name.lower() for name in spec["columns"]]
    columns = sql.SQL(", ").join(sql.Identifier(name) for name in names)
    key_columns = sql.SQL(", ").join(map(sql.Identifier, SOURCE_KEYS[table]))
    incoming_columns = sql.SQL(", ").join(sql.Identifier("incoming", name) for name in names)
    definitions = sql.SQL(", ").join(
        sql.SQL("{} text").format(sql.Identifier(name)) for name in names
    )
    target = sql.Identifier("raw", table)
    cur.execute(sql.SQL("""
        CREATE TABLE IF NOT EXISTS {} (
            {}, source_file text NOT NULL, loaded_at timestamptz NOT NULL DEFAULT now(),
            created_on timestamptz NOT NULL, updated_at timestamptz NOT NULL
        )
    """).format(target, definitions))
    ensure_source_timestamps(cur, target)
    cur.execute(sql.SQL("CREATE TEMP TABLE incoming ({}) ON COMMIT DROP").format(definitions))
    for filename, expected in spec["files"].items():
        with (folder / filename).open("rb") as stream:
            check_header(stream, spec["columns"], filename)
            # The header has already been consumed. PostgreSQL parses the CSV records.
            with cur.copy("COPY pg_temp.incoming FROM STDIN WITH (FORMAT CSV, ENCODING 'UTF8')") as copy:
                while chunk := stream.read(CHUNK_SIZE):
                    copy.write(chunk)
        cur.execute("SELECT count(*) FROM pg_temp.incoming")
        count = cur.fetchone()[0]
        if count != expected:
            raise ValueError(f"{filename}: expected {expected:,} records, received {count:,}")
        # CMS files have no source timestamps. Preserve the simulation on a file reload.
        cur.execute(sql.SQL("""
            WITH replaced AS (
                DELETE FROM {} WHERE source_file = %s
                RETURNING {}, created_on, updated_at
            ), source_timestamps AS (
                SELECT {}, min(created_on) AS created_on, max(updated_at) AS updated_at
                FROM replaced
                GROUP BY {}
            )
            INSERT INTO {} ({}, source_file, created_on, updated_at)
            SELECT {}, %s,
                coalesce(source_timestamps.created_on, statement_timestamp()),
                coalesce(source_timestamps.updated_at, statement_timestamp())
            FROM pg_temp.incoming AS incoming
            LEFT JOIN source_timestamps USING ({})
        """).format(
            target, key_columns, key_columns, key_columns,
            target, columns, incoming_columns, key_columns,
        ), (filename, filename))
        print(f"  {filename}: {cur.rowcount:,} rows", flush=True)
        cur.execute("TRUNCATE pg_temp.incoming")
    cur.execute("DROP TABLE pg_temp.incoming")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Folder containing the extracted CMS CSVs")
    parser.add_argument("--table", choices=RELEASE, help="Load just this claims or beneficiary table")
    parser.add_argument("--ask-password", action="store_true", help="Prompt for the database password")
    parser.add_argument("--env-file", type=Path, help="Use a specific local .env file")
    args = parser.parse_args()
    if args.env_file:
        if not args.env_file.is_file():
            parser.error(f"Environment file does not exist: {args.env_file}")
        load_dotenv(args.env_file, interpolate=False, encoding="utf-8-sig")
    else:
        directory = Path(__file__).resolve().parent
        for candidate in (directory / ".env", directory.parent / ".env"):
            if candidate.is_file():
                load_dotenv(candidate, interpolate=False, encoding="utf-8-sig")
                break
    # libpq reads its connection parameters directly from the environment.
    required = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER"]
    settings = {}
    if args.ask_password:
        settings["password"] = getpass.getpass("PostgreSQL password: ")
    else:
        required.append("PGPASSWORD")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        parser.error("Set the following in .env or the environment: " + ", ".join(missing))

    tables = [args.table] if args.table else list(RELEASE)
    for table in tables:
        for filename in RELEASE[table]["files"]:
            with (args.folder / filename).open("rb") as stream:
                check_header(stream, RELEASE[table]["columns"], filename)

    with psycopg.connect(**settings) as conn, conn.cursor() as cur:
        # Serialize runs so overlapping refreshes cannot insert duplicate copies.
        cur.execute("SELECT pg_advisory_xact_lock(480031, 1)")
        cur.execute("CREATE SCHEMA IF NOT EXISTS raw")
        for table in tables:
            load_table(cur, args.folder, table, RELEASE[table])
    print("Load committed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, csv.Error, psycopg.Error) as exc:
        raise SystemExit(f"Load failed: {exc}") from exc
