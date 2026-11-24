"""
Ria Financial Intelligence - deployment runner.

Runs the numbered SQL scripts in order against a Snowflake connection defined
in ~/.snowflake/connections.toml. Each SQL file runs in a single session so
temporary tables created in a script are visible to later statements.
Step 7 is the ML notebook (notebooks/07_ml_models.py); it is run as a Python
script. If step 3 (data generation) is rerun without step 7, the notebook is
rerun automatically afterwards so the score tables are never left empty.

Usage:
    python scripts/deploy.py --connection AWS161                 # all steps 1-9
    python scripts/deploy.py --connection AWS161 --steps 3 4     # selected steps
"""
import argparse
import io
import pathlib
import re
import subprocess
import sys
import time

import snowflake.connector
from snowflake.connector.util_text import split_statements

ROOT = pathlib.Path(__file__).resolve().parent.parent
STEPS = {
    1: "sql/setup/01_database_and_schema.sql",
    2: "sql/setup/02_create_tables.sql",
    3: "sql/data/03_generate_synthetic_data.sql",
    4: "sql/views/04_create_views.sql",
    5: "sql/views/05_create_semantic_views.sql",
    6: "sql/search/06_create_cortex_search.sql",
    7: "notebooks/07_ml_models.py",
    8: "sql/ml/08_ml_wrapper_functions.sql",
    9: "sql/agent/09_create_agent.sql",
}


def is_comment_only(stmt):
    stripped = re.sub(r"/\*.*?\*/", "", stmt, flags=re.S)
    stripped = re.sub(r"--[^\n]*", "", stripped)
    return not stripped.strip().strip(";").strip()


def run_notebook(path):
    start = time.time()
    print(f"Step 7: {path.relative_to(ROOT)} (trains 10 models, registers them, writes scores; 10 to 20 minutes) ...", flush=True)
    subprocess.run([sys.executable, str(path)], check=True, cwd=ROOT)
    print(f"  done in {time.time() - start:.1f}s")


def feature_views_exist(conn):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM RIA_FINANCIAL_INTELLIGENCE.INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'ANALYTICS' AND TABLE_NAME = 'V_TRANSFER_BASE'")
    return cur.fetchone()[0] > 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="AWS161")
    parser.add_argument("--steps", nargs="*", type=int, default=sorted(STEPS))
    args = parser.parse_args()

    conn = snowflake.connector.connect(connection_name=args.connection)
    try:
        for step in args.steps:
            path = ROOT / STEPS[step]
            if path.suffix == ".py":
                run_notebook(path)
                continue
            start = time.time()
            print(f"Step {step}: {path.relative_to(ROOT)} ...", flush=True)
            # Split ourselves so comment-only trailers (e.g. generated block
            # markers after the last statement) are skipped, not sent as empty SQL.
            for stmt, _ in split_statements(io.StringIO(path.read_text()), remove_comments=False):
                if not is_comment_only(stmt):
                    conn.cursor().execute(stmt).close()
            print(f"  done in {time.time() - start:.1f}s")

        if 3 in args.steps and 7 not in args.steps and feature_views_exist(conn):
            print("Step 3 regenerated the data, so the model scores are stale. Rerunning step 7 to retrain and rescore.", flush=True)
            run_notebook(ROOT / STEPS[7])
    finally:
        conn.close()


if __name__ == "__main__":
    main()
