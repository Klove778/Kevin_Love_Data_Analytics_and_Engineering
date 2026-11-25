"""Rebuild the three aggregate Tableau exports from the existing PostgreSQL warehouse."""

import argparse
import csv
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

sys.dont_write_bytecode = True
from holdout_baselines import compare
from holdout_evaluation import read_input
from nested_cv import evaluate

ANALYSIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = ANALYSIS_DIR.parents[2]
EXPORT_DIR = REPO_ROOT / 'tableau-exports' / 'persistent-high-cost'


def query(psql, script, output):
    subprocess.run([
        psql, '-X', '-w', '-v', 'ON_ERROR_STOP=1',
        '-v', f'output_csv={output.as_posix()}', '-P', 'pager=off',
        '-f', str(ANALYSIS_DIR / script),
    ], check=True)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError(f'{script} did not produce an output file')


def write_rows(path, rows):
    with path.open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=tuple(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def validate_dialysis(path):
    with path.open(newline='', encoding='utf-8') as file:
        rows = {int(row['sort_order']): row for row in csv.DictReader(file)}
    expected = {
        2: (210, 275), 5: (204, 275), 6: (194, 218),
        10: (218, 275), 11: (1727, 6093), 30: (21, 57), 31: (865, 3895),
        40: (20, 55), 41: (737, 3449),
    }
    for order, (numerator, denominator) in expected.items():
        row = rows[order]
        if (int(row['numerator']), int(row['denominator'])) != (numerator, denominator):
            raise RuntimeError(f'Dialysis audit differs from the published result at row {order}')
    for order, gap in {12: 52.15, 32: 18.64, 42: 17.93}.items():
        if float(rows[order]['standardized_gap_pp']) != gap:
            raise RuntimeError(f'Dialysis comparison differs from the published result at row {order}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--psql', default='psql', help='Path to the PostgreSQL psql executable')
    parser.add_argument('--output-dir', type=Path, default=EXPORT_DIR)
    parser.add_argument('--only', choices=('models', 'dialysis'), help='Run only the selected stage')
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # Stage files beside the destination so published CSVs can be replaced on the same filesystem.
    # Beneficiary-level extracts live in a separate private system scratch directory.
    with (TemporaryDirectory(prefix='persistent-cost-input-') as scratch,
          TemporaryDirectory(prefix='.persistent-cost-export-', dir=args.output_dir) as staged):
        input_dir = Path(scratch)
        staged_dir = Path(staged)
        if args.only != 'dialysis':
            holdout = input_dir / 'holdout_features.csv'
            development = input_dir / 'cv_features.csv'
            query(args.psql, 'holdout_features.sql', holdout)
            query(args.psql, 'cv_features.sql', development)
            write_rows(staged_dir / 'model_comparison_holdout.csv', compare(read_input(holdout)))
            write_rows(staged_dir / 'model_comparison_cv.csv', evaluate(development))
        if args.only != 'models':
            dialysis = staged_dir / 'dialysis_investigation.csv'
            query(args.psql, 'dialysis_audit.sql', dialysis)
            validate_dialysis(dialysis)
            # Normalize line endings for consistent version control across operating systems.
            dialysis.write_text(dialysis.read_text(encoding='utf-8'), encoding='utf-8', newline='\n')
        for file in sorted(staged_dir.iterdir()):
            destination = args.output_dir / file.name
            os.replace(file, destination)
            print(f'Wrote {destination}')


if __name__ == '__main__':
    main()
