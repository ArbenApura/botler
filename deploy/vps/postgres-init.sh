#!/bin/sh
# Runs once, when the database folder is first made. Creates the owner role and the database, and installs pgvector.
#   botler_owner  owns the database and runs migrations. It is not a superuser, so forced row level security binds it too.
# The app itself connects as app_runtime, which the migration step makes and gives a login.
# The password is put into SQL text, so use letters and digits only.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
CREATE ROLE botler_owner LOGIN CREATEROLE PASSWORD '${BOTLER_OWNER_PASSWORD}';
CREATE DATABASE botler OWNER botler_owner;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname botler <<SQL
ALTER SCHEMA public OWNER TO botler_owner;
-- Installed here by the superuser, so the owner role (which cannot create extensions) only finds it present
CREATE EXTENSION IF NOT EXISTS vector;
SQL
