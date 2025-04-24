BEGIN TRANSACTION;
CREATE SEQUENCE events_id_seq;

-- Table
CREATE TABLE events (
    Id bigint NOT NULL DEFAULT NEXTVAL('events_id_seq'::regclass),
    Time timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    EventType varchar NOT NULL,
    Properties jsonb DEFAULT '{}',
    CONSTRAINT pk_events PRIMARY KEY (id)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_events_timeeventtype ON events USING btree (Time, EventType COLLATE pg_catalog.default varchar_ops) TABLESPACE pg_default;

CREATE OR REPLACE FUNCTION AddAuditEvents (_events json)
    RETURNS VOID
    AS $$
DECLARE
BEGIN
    INSERT INTO public.Events (EventType, Properties)
    SELECT
        eventtype,
        properties
    FROM
        JSON_TO_RECORDSET(_events) AS s (EventType VARCHAR,
        Properties JSON);
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

COMMIT TRANSACTION;
