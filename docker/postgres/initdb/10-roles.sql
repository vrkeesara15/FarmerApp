-- Dev/CI login users (SEC-011). Runs once on a fresh volume via docker-entrypoint-initdb.d;
-- `make db` re-applies it (idempotent) so existing volumes get the role too.
--
--   farmerapp      POSTGRES_USER: owner, runs Alembic (MIGRATION_DATABASE_URL). Superuser here;
--                  Cloud SQL's migrate user is not, which is why migration 0003 also creates the
--                  NOLOGIN groups farmerapp_migrate / farmerapp_auth and grants them explicitly.
--   farmerapp_app  runtime login for api / worker / jobs (DATABASE_URL): DML only, subject to
--                  RLS, no DDL. Migration 0003 grants it the table privileges.
--
-- Passwords are dev-only placeholders (compose network); Cloud SQL uses IAM authentication.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'farmerapp_app') THEN
        CREATE ROLE farmerapp_app LOGIN PASSWORD 'farmerapp'
            NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    ELSE
        ALTER ROLE farmerapp_app LOGIN PASSWORD 'farmerapp'
            NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    END IF;
END $$;
