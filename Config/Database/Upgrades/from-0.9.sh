#!/bin/bash
set -e
if [ -f /docker-entrypoint-initdb.d/credentials ]; then
  while read -r line; do declare  "$line"; done < /docker-entrypoint-initdb.d/credentials
fi
echo "Preparing Paritech.Authority..."
DatabaseName=${DBNAME_AUTHORITY:-Authority}
DatabaseUser=${DBUSER_AUTHORITY:-authority}
DatabasePass=${DBPASS_AUTHORITY:-authority}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Authority.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA auth TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO "$DatabaseUser";
EOSQL
echo "Removing MotifMarkets.Vault..."
DatabaseName=${DBNAME_VAULT:-Vault}
DatabaseUser=${DBUSER_VAULT:-vault}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  DROP DATABASE "$DatabaseName";
  DROP USER "$DatabaseUser";
EOSQL