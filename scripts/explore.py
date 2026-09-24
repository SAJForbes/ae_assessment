"""Open DuckDB's browser SQL editor on the project warehouse.

Run from the repo root:  uv run python scripts/explore.py
Stop it (Enter) before running `dbt build`: the open connection locks warehouse.duckdb.

The connection is read-write because the UI stores its notebooks in its own
database (_duckdb_ui), which it can't create from a read-only connection.
Anything you change here is overwritten by the next `dbt build`.
"""
import duckdb

con = duckdb.connect("warehouse.duckdb")
con.sql("INSTALL ui; LOAD ui;")
print(con.sql("CALL start_ui_server()").fetchone()[0])
input("Press Enter to stop the UI and release the database...")
