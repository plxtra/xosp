#!/bin/bash
set -e
if [ -f /docker-entrypoint-initdb.d/credentials ]; then
  while read -r line; do declare  "$line"; done < /docker-entrypoint-initdb.d/credentials
fi
echo "Preparing Paritech.Audit..."
DatabaseName=${DBNAME_AUDIT:-Audit}
DatabaseUser=${DBUSER_AUDIT:-audit}
DatabasePass=${DBPASS_AUDIT:-audit}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Audit.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA public TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO "$DatabaseUser";
EOSQL
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
echo "Preparing Paritech.Doppler..."
DatabaseName=${DBNAME_DOPPLER:-Doppler}
DatabaseUser=${DBUSER_DOPPLER:-doppler}
DatabasePass=${DBPASS_DOPPLER:-doppler}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Doppler.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA doppler TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA doppler TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.Foundry..."
DatabaseName=${DBNAME_FOUNDRY:-Foundry}
DatabaseUser=${DBUSER_FOUNDRY:-foundry}
DatabasePass=${DBPASS_FOUNDRY:-foundry}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Foundry.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA foundry TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA foundry TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.Herald..."
DatabaseName=${DBNAME_HERALD:-Herald}
DatabaseUser=${DBUSER_HERALD:-herald}
DatabasePass=${DBPASS_HERALD:-herald}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Herald.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA herald TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA herald TO "$DatabaseUser";
EOSQL
echo "Preparing MotifMarkets.MarketHoliday..."
DatabaseName=${DBNAME_MARKETHOLIDAY:-MarketHoliday}
DatabaseUser=${DBUSER_MARKETHOLIDAY:-marketholiday}
DatabasePass=${DBPASS_MARKETHOLIDAY:-marketholiday}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/MotifMarkets.MarketHoliday.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA public TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO "$DatabaseUser";
EOSQL
echo "Preparing MotifMarkets.MotifServices..."
DatabaseName=${DBNAME_MOTIF:-Motif}
DatabaseUser=${DBUSER_MOTIF:-motif}
DatabasePass=${DBPASS_MOTIF:-motif}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/MotifMarkets.MotifServices.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA public TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.OMS2..."
DatabaseName=${DBNAME_OMS:-OMS}
DatabaseUser=${DBUSER_OMS:-oms}
DatabasePass=${DBPASS_OMS:-oms}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.OMS2.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA oms TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA oms TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.Prodigy..."
DatabaseName=${DBNAME_PRODIGY:-Prodigy}
DatabaseUser=${DBUSER_PRODIGY:-prodigy}
DatabasePass=${DBPASS_PRODIGY:-prodigy}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Prodigy.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA fix TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA fix TO "$DatabaseUser";
  GRANT USAGE ON SCHEMA phist TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA phist TO "$DatabaseUser";
  GRANT USAGE ON SCHEMA prodigy TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA prodigy TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.Sessions..."
DatabaseName=${DBNAME_SESSIONS:-Sessions}
DatabaseUser=${DBUSER_SESSIONS:-sessions}
DatabasePass=${DBPASS_SESSIONS:-sessions}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Sessions.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA sms TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sms TO "$DatabaseUser";
EOSQL
echo "Preparing Paritech.Watchmaker..."
DatabaseName=${DBNAME_WATCHMAKER:-Watchmaker}
DatabaseUser=${DBUSER_WATCHMAKER:-watchmaker}
DatabasePass=${DBPASS_WATCHMAKER:-watchmaker}
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER "$DatabaseUser" WITH PASSWORD '$DatabasePass';
  CREATE DATABASE "$DatabaseName";
  GRANT CONNECT, TEMPORARY ON DATABASE "$DatabaseName" TO "$DatabaseUser";
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" --file "/docker-entrypoint-initdb.d/Scripts/Paritech.Watchmaker.sql"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DatabaseName" <<-EOSQL
  GRANT USAGE ON SCHEMA public TO "$DatabaseUser";
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO "$DatabaseUser";
EOSQL
