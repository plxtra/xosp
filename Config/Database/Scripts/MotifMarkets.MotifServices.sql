BEGIN TRANSACTION;
-- Sequences
CREATE SEQUENCE public.UserSettings_Id_seq;

-- Table
CREATE TABLE public.UserSettings (
    Id bigint NOT NULL DEFAULT nextval('UserSettings_Id_seq'::regclass),
    Zone varchar COLLATE pg_catalog.default NOT NULL,
    Identity varchar COLLATE pg_catalog.default NOT NULL,
    IdentityName varchar COLLATE pg_catalog.default,
    Key VARCHAR COLLATE pg_catalog.default NOT NULL,
    Value varchar COLLATE pg_catalog.default,
    CONSTRAINT UserSettings_pkey PRIMARY KEY (Id)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX IX_UserSettings_Keys ON public.UserSettings USING btree (Zone COLLATE pg_catalog.default varchar_ops, IDENTITY COLLATE
    pg_catalog.default varchar_ops, KEY COLLATE pg_catalog.default varchar_ops) TABLESPACE pg_default;

CREATE OR REPLACE FUNCTION AddOrUpdateKeyValue (_zone varchar, _identityId varchar, _key varchar, _value varchar, _identityName varchar = NULL)
    RETURNS int
    AS $$
    --  1 = Inserted
    --  2 = Updated
DECLARE
    _settingId bigint;
BEGIN
    SELECT
        Id INTO _settingId
    FROM
        public.UserSettings
    WHERE
        UPPER(Zone) = UPPER(_zone)
        AND UPPER(IDENTITY) = UPPER(_identityId)
        AND Upper(KEY) = UPPER(_key);
    IF (_settingId IS NOT NULL) THEN
        UPDATE
            public.UserSettings
        SET
            Value = _value
        WHERE
            Id = _settingId;
        RETURN 2;
    ELSE
        INSERT INTO public.UserSettings (Zone, IDENTITY, IdentityName, KEY, Value)
            VALUES (_zone, _identityId, _identityName, _key, _value);
        RETURN 1;
    END IF;
END
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteKeyValue (_zone varchar, _identityId varchar, _key varchar)
    RETURNS int
    AS $$
DECLARE
    _deleted int;
BEGIN
    WITH deleted AS (
        DELETE FROM public.UserSettings
        WHERE UPPER(Zone) = UPPER(_zone)
            AND UPPER(IDENTITY) = UPPER(_identityId)
            AND Upper(KEY) = UPPER(_key)
        RETURNING
            *
)
    SELECT
        COUNT(*) INTO _deleted
    FROM
        deleted;
    RETURN _deleted;
END
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION FindKeyValue (_zone varchar, _identityId varchar, _key varchar)
    RETURNS varchar
    AS $$
DECLARE
    _value varchar;
BEGIN
    SELECT
        Value INTO _value
    FROM
        public.UserSettings
    WHERE
        UPPER(Zone) = UPPER(_zone)
        AND UPPER(IDENTITY) = UPPER(_identityId)
        AND Upper(KEY) = UPPER(_key);
    RETURN _value;
END
$$
LANGUAGE plpgsql 
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION SearchKeys(
    _zone varchar, 
    _identityId varchar, 
    _searchkey varchar
)
RETURNS table (
    Key varchar
)
AS $$
DECLARE
    _value varchar;
BEGIN
    RETURN QUERY
    SELECT
        us.Key
    FROM
        public.UserSettings us
    WHERE
        UPPER(us.Zone) = UPPER(_zone)
        AND UPPER(us.Identity) = UPPER(_identityId)
        AND us.Key ILIKE _searchkey;
END
$$
LANGUAGE plpgsql 
SECURITY DEFINER;

COMMIT TRANSACTION;
