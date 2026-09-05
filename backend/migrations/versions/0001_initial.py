"""Create commerce storage, vector extension and immutable audit ledger."""

from alembic import op
from sqlalchemy import inspect, text

from backend.app.db import Base

revision = "0001_initial"
down_revision = None


def upgrade():
    connection = op.get_bind()
    postgres = connection.dialect.name == "postgresql"
    if postgres:
        connection.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    Base.metadata.create_all(connection)
    if "search_vector" not in {c["name"] for c in inspect(connection).get_columns("products")}:
        connection.execute(
            text("ALTER TABLE products ADD COLUMN search_vector " + ("vector" if postgres else "JSON"))
        )
    if postgres:
        connection.execute(
            text(
                "CREATE OR REPLACE FUNCTION acg_immutable_audit() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'Audit records are append-only'; END; $$ LANGUAGE plpgsql"
            )
        )
        connection.execute(
            text(
                "CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_events FOR EACH ROW EXECUTE FUNCTION acg_immutable_audit()"
            )
        )
    else:
        for operation in ["UPDATE", "DELETE"]:
            connection.execute(
                text(
                    f"CREATE TRIGGER IF NOT EXISTS audit_no_{operation.lower()} BEFORE {operation} ON audit_events BEGIN SELECT RAISE(ABORT, 'Audit records are append-only'); END"
                )
            )


def downgrade():
    raise RuntimeError(
        "Financial and audit history must not be destructively downgraded. Restore a reviewed backup instead."
    )
