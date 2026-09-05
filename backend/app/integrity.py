from sqlalchemy import inspect, text

from .db import Base


def initialize_database(engine):
    if engine.dialect.name == "postgresql":
        with engine.begin() as db:
            db.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    Base.metadata.create_all(engine)
    # Supports local databases created by the initial preview before the first migration.
    if "search_vector" not in {c["name"] for c in inspect(engine).get_columns("products")}:
        with engine.begin() as db:
            db.execute(
                text(
                    "ALTER TABLE products ADD COLUMN search_vector "
                    + ("vector" if engine.dialect.name == "postgresql" else "JSON")
                )
            )
    with engine.begin() as db:
        if engine.dialect.name == "sqlite":
            for operation in ["UPDATE", "DELETE"]:
                db.execute(
                    text(
                        f"CREATE TRIGGER IF NOT EXISTS audit_no_{operation.lower()} BEFORE {operation} ON audit_events BEGIN SELECT RAISE(ABORT, 'Audit records are append-only'); END"
                    )
                )
        else:
            db.execute(
                text(
                    "CREATE OR REPLACE FUNCTION acg_immutable_audit() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'Audit records are append-only'; END; $$ LANGUAGE plpgsql"
                )
            )
            db.execute(text("DROP TRIGGER IF EXISTS audit_immutable ON audit_events"))
            db.execute(
                text(
                    "CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_events FOR EACH ROW EXECUTE FUNCTION acg_immutable_audit()"
                )
            )
