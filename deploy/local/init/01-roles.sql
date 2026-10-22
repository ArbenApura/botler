-- LOCAL DEV ONLY (passwords here are throwaway). Runs once, when the volume is first created.
-- The superuser "postgres" owns the tables and runs migrations. Requests connect as app_runtime, which owns nothing and cannot bypass row level security.
CREATE ROLE app_runtime LOGIN PASSWORD 'localruntimepassword' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

CREATE DATABASE botler OWNER postgres;
REVOKE ALL ON DATABASE botler FROM PUBLIC;
GRANT CONNECT ON DATABASE botler TO app_runtime;
