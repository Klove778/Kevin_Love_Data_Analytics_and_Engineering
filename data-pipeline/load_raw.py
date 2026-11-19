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


def check_header(stream, expected, filename):
    header = next(csv.reader([stream.readline().decode("utf-8-sig")]), [])
    if header != expected:
        raise ValueError(f"{filename}: CSV columns differ from Sample 1")


def load_table(cur, folder, table, spec):
    names = [name.lower() for name in spec["columns"]]
    columns = sql.SQL(", ").join(sql.Identifier(name) for name in names)
    definitions = sql.SQL(", ").join(
        sql.SQL("{} text").format(sql.Identifier(name)) for name in names
    )
    target = sql.Identifier("raw", table)
    cur.execute(sql.SQL("""
        CREATE TABLE IF NOT EXISTS {} (
            {}, source_file text NOT NULL, loaded_at timestamptz NOT NULL DEFAULT now()
        )
    """).format(target, definitions))
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
        cur.execute(sql.SQL("DELETE FROM {} WHERE source_file = %s").format(target), (filename,))
        cur.execute(sql.SQL("""
            INSERT INTO {} ({}, source_file)
            SELECT {}, %s FROM pg_temp.incoming
        """).format(target, columns, columns), (filename,))
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
    tables = [args.table] if args.table else list(RELEASE)
    for table in tables:
        for filename in RELEASE[table]["files"]:
            with (args.folder / filename).open("rb") as stream:
                check_header(stream, RELEASE[table]["columns"], filename)

    settings = {
        "host": os.getenv("PGHOST", "localhost"),
        "port": os.getenv("PGPORT", "5432"),
        "dbname": os.getenv("PGDATABASE", "claims_warehouse"),
        "user": os.getenv("PGUSER", "postgres"),
    }
    if args.ask_password:
        settings["password"] = getpass.getpass("PostgreSQL password: ")
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
