BEGIN TRANSACTION;
-- Sequences
CREATE SEQUENCE entity_id_seq;

-- Table
CREATE TABLE entity (
    Id bigint NOT NULL DEFAULT NEXTVAL('entity_id_seq'::regclass),
    Key varchar COLLATE pg_catalog.default NOT NULL,
    CONSTRAINT entity_pkey PRIMARY KEY (Id),
    CONSTRAINT uq_entity_key UNIQUE (Key)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_entity_key ON entity USING btree (KEY COLLATE pg_catalog.default varchar_ops) TABLESPACE pg_default;

-- Sequences
CREATE SEQUENCE watchlist_id_seq;

-- Table
CREATE TABLE watchlist (
    Id bigint NOT NULL DEFAULT NEXTVAL('watchlist_id_seq'::regclass),
    OwnerEntityId bigint not null,
    OwnerCanModify boolean not null default true,
    GroupEntityId bigint not null,
    GroupCanModify boolean not null default false,
    Name varchar COLLATE pg_catalog.default NOT NULL,
    Description varchar COLLATE pg_catalog.default NOT NULL,
    Category varchar COLLATE pg_catalog.default NOT NULL DEFAULT '',
    Version int NOT NULL DEFAULT 1,
    LastUpdated timestamptz DEFAULT CURRENT_TIMESTAMP,
    Constituents varchar[] COLLATE pg_catalog.default DEFAULT '{}',
    CONSTRAINT watchlist_pkey PRIMARY KEY (Id)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_watchlist_owner ON watchlist USING btree (OwnerEntityId) TABLESPACE pg_default;
CREATE INDEX ix_watchlist_group ON watchlist USING btree (GroupEntityId) TABLESPACE pg_default;

ALTER TABLE ONLY watchlist
	ADD CONSTRAINT watchlist_groupentityid_fkey FOREIGN KEY (GroupEntityId)
	REFERENCES entity (Id);

ALTER TABLE ONLY watchlist
	ADD CONSTRAINT watchlist_ownerentityid_fkey FOREIGN KEY (OwnerEntityId)
	REFERENCES entity (Id);

CREATE OR REPLACE FUNCTION AddWatchlist (
    _identityKey varchar,
    _watchlistName varchar,
    _watchlistDescription varchar,
    _category varchar
)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _entityId bigint;
BEGIN
    _entityId = RegisterEntity (_identityKey);
    RETURN query INSERT INTO Watchlist (OwnerEntityId, GroupEntityId, Name, Description, Category)
        VALUES (_entityId, _entityId, _watchlistName, _watchlistDescription, _category)
    RETURNING
        Watchlist.Id,
        Watchlist.Name,
        Watchlist.Description,
        Watchlist.Category,
        Watchlist.Version,
        Watchlist.OwnerCanModify,
        Watchlist.LastUpdated,
        _identityKey,
        _identityKey;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AvailableWatchlists (_identityKey varchar, _groupKeys varchar)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
BEGIN
    RETURN query
    SELECT
        wl.Id,
        wl.Name,
        wl.Description,
        wl.Category,
        wl.Version,
        wl.OwnerCanModify AS CanModify,
        wl.LastUpdated,
        e.Key AS AffectedOwnerEntity,
        eg.Key AS AffectedGroupEntity
    FROM
        Entity e
    JOIN Watchlist wl ON wl.OwnerEntityId = e.ID
    LEFT OUTER JOIN Entity eg ON eg.Id = wl.GroupEntityId
    WHERE
        UPPER(e.Key) = UPPER(_identityKey)
    UNION
    SELECT
        wl.Id,
        wl.Name,
        wl.Description,
        wl.Category,
        wl.Version,
        wl.GroupCanModify AS CanModify,
        wl.LastUpdated,
        loopback.Key AS AffectedOwnerEntity,
        e.Key AS AffectedGroupEntity
    FROM
        Entity e
    JOIN UNNEST(string_to_array(_groupKeys, ',')) filt (entId) ON UPPER(TRIM(filt.entId)) = UPPER(e.Key)
    JOIN Watchlist wl ON wl.GroupEntityId = e.ID
    JOIN Entity loopback ON loopback.Id = wl.OwnerEntityId
    WHERE
        UPPER(loopback.Key) <> UPPER(_identityKey);
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION CopyWatchlist (_identityKey varchar, _groupKeys varchar, _id bigint, _expectedversion int, _newWatchlistName
    varchar, _newWatchlistDescription varchar, _newCategory varchar)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _sourceid bigint;
    _entityId bigint;
BEGIN
    SELECT
        wl.Id INTO _sourceid
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
    WHERE
        wl.Id = _id
            AND wl.Version = _expectedversion
    FOR UPDATE;
    IF (_sourceid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=% v=%', _id, _expectedversion;
    END IF;
    _entityId = RegisterEntity (_identityKey);
    RETURN query 
    INSERT INTO Watchlist (OwnerEntityId, GroupEntityId, Name, Description, Category, Constituents)
    (
        SELECT
            _entityId AS OwnerEntityId,
            _entityId AS GroupEntityId,
            COALESCE(_newWatchlistName, src.Name) AS Name,
            COALESCE(_newWatchlistDescription, src.Description) AS Description,
            COALESCE(_newCategory, src.Category) AS Category,
            src.Constituents
        FROM
            Watchlist src
        WHERE
            src.id = _sourceId
    )
    RETURNING
        Watchlist.Id,
        Watchlist.Name,
        Watchlist.Description,
        Watchlist.Category,
        Watchlist.Version,
        Watchlist.OwnerCanModify,
        Watchlist.LastUpdated,
        _identityKey,
        _identityKey;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteWatchlistById (
    _identityKey varchar,
    _groupKeys varchar,
    _id bigint
)
RETURNS TABLE (
    Id bigint,
    RecCount int,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _count int;
    _targetid bigint;
    _entityId bigint;
    _ownerEntity varchar;
    _groupEntity varchar;
BEGIN
    _entityId = RegisterEntity (_identityKey);
    SELECT
        wl.Id, wl.AffectedOwnerEntity, wl.AffectedGroupEntity INTO _targetid, _ownerEntity, _groupEntity
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
    JOIN Watchlist w ON w.Id = wl.Id
    WHERE
        wl.Id = _id
        AND wl.CanModify
        AND w.OwnerEntityId = _entityId
    FOR UPDATE;
    IF (_targetid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=%', _id;
    END IF;
    WITH deleted AS (
        DELETE FROM Watchlist
        WHERE Watchlist.Id = _targetid
        RETURNING *
    )
    SELECT
        count(*) INTO _count
    FROM
        deleted;
    RETURN query
        SELECT
            _targetid,
            _count,
            _ownerEntity,
            _groupEntity;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION GrantAccessToWatchlistById (_identityKey varchar, _groupKeys varchar, _id bigint, _expectedversion int, _groupKey varchar, _groupCanModify BOOLEAN)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _targetid bigint;
    _entityId bigint;
    _groupEntityId bigint;
    _ownerEntity varchar;
BEGIN
    _entityId = RegisterEntity (_identityKey);
    SELECT
        wl.Id, wl.AffectedOwnerEntity INTO _targetid, _ownerEntity
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
        JOIN Watchlist w ON w.Id = wl.Id
    WHERE
        wl.Id = _id
        AND wl.Version = _expectedversion
        AND wl.CanModify
        AND w.OwnerEntityId = _entityId
    FOR UPDATE;
    IF (_targetid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=% v=%', _id, _expectedversion;
    END IF;
    _groupEntityId = RegisterEntity (_groupKey);
    RETURN query UPDATE
        Watchlist
    SET
        GroupEntityId = _groupEntityId,
        GroupCanModify = _groupCanModify,
        Version = Watchlist.Version + 1,
        LastUpdated = CURRENT_TIMESTAMP
    WHERE
        Watchlist.Id = _targetid
    RETURNING
        Watchlist.Id,
        Watchlist.Name,
        Watchlist.Description,
        Watchlist.Category,
        Watchlist.Version,
        (Watchlist.OwnerCanModify OR Watchlist.GroupCanModify),
        Watchlist.LastUpdated,
        _ownerEntity,
        _groupKey;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RegisterEntity (_key varchar)
RETURNS bigint
AS $$
DECLARE
    _id bigint;
BEGIN
    LOCK TABLE Entity IN SHARE ROW EXCLUSIVE MODE;
    IF (NOT EXISTS (
        SELECT
            NULL
        FROM
            Entity
        WHERE
            UPPER(KEY) = UPPER(_key))) THEN
        INSERT INTO Entity (KEY)
            VALUES (_key)
        RETURNING
            id INTO _id;
    ELSE
        SELECT
            e.id INTO _id
        FROM
            Entity e
        WHERE
            UPPER(KEY) = UPPER(_key);
    END IF;
    RETURN _id;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RetrieveWatchlistById (_identityKey varchar, _groupKeys varchar, _id bigint)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    Constituents varchar[]
)
AS $$
DECLARE
    _targetid bigint;
BEGIN
    SELECT
        wl.Id INTO _targetid
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
    WHERE
        wl.Id = _id
    FOR UPDATE;
    IF (_targetid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=%', _id;
    END IF;
    RETURN QUERY
    SELECT
        w.Id,
        w.Name,
        w.Description,
        w.Category,
        w.Version,
        w.CanModify,
        w.LastUpdated,
        wl.Constituents
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) AS w
    JOIN Watchlist wl ON wl.Id = w.Id
    WHERE
        w.Id = _targetid;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RevokeAccessToWatchlistById (_identityKey varchar, _groupKeys varchar, _id bigint, _expectedversion int)
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _targetid bigint;
    _entityId bigint;
    _ownerEntity varchar;
    _groupEntity varchar;
BEGIN
    _entityId = RegisterEntity (_identityKey);
    SELECT
        wl.Id, wl.AffectedOwnerEntity, wl.AffectedGroupEntity INTO _targetid, _ownerEntity, _groupEntity
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
        JOIN Watchlist w ON w.Id = wl.Id
    WHERE
        wl.Id = _id
        AND wl.Version = _expectedversion
        AND wl.CanModify
        AND w.OwnerEntityId = _entityId
    FOR UPDATE;
    IF (_targetid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=% v=%', _id, _expectedversion;
    END IF;
    RETURN query UPDATE
        Watchlist
    SET
        GroupEntityId = _entityId,
        GroupCanModify = false,
        Version = Watchlist.Version + 1,
        LastUpdated = CURRENT_TIMESTAMP
    WHERE
        Watchlist.Id = _targetid
    RETURNING
        Watchlist.Id,
        Watchlist.Name,
        Watchlist.Description,
        Watchlist.Category,
        Watchlist.Version,
        (Watchlist.OwnerCanModify OR Watchlist.GroupCanModify),
        Watchlist.LastUpdated,
        _ownerEntity,
        _groupEntity;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION UpdateWatchlistById (_identityKey varchar, _groupKeys varchar,_id bigint, _expectedversion int, _watchlistName varchar, _watchlistDescription varchar,
    _category varchar, _constituents varchar[])
RETURNS TABLE (
    Id bigint,
    Name varchar,
    Description varchar,
    Category varchar,
    Version int,
    CanModify boolean,
    LastUpdated timestamptz,
    AffectedOwnerEntity varchar,
    AffectedGroupEntity varchar
)
AS $$
DECLARE
    _targetid bigint;
    _ownerEntity varchar;
    _groupEntity varchar;
BEGIN
    SELECT
        wl.Id, wl.AffectedOwnerEntity, wl.AffectedGroupEntity INTO _targetid, _ownerEntity, _groupEntity
    FROM
        AvailableWatchlists (_identityKey, _groupKeys) wl
    WHERE
        wl.Id = _id
        AND wl.Version = _expectedversion
        AND wl.CanModify
    FOR UPDATE;
    IF (_targetid IS NULL) THEN
        RAISE EXCEPTION 'Watchlist not available: id=% v=%', _id, _expectedversion;
    END IF;
    RETURN query UPDATE
        Watchlist
    SET
        Name = COALESCE(_watchlistName, Watchlist.Name),
        Description = COALESCE(_watchlistDescription, Watchlist.Description),
        Category = COALESCE(_category, Watchlist.Category),
        Version = Watchlist.Version + 1,
        LastUpdated = CURRENT_TIMESTAMP,
        Constituents = COALESCE(_constituents, Watchlist.Constituents)
    WHERE
        Watchlist.Id = _targetid
    RETURNING
        Watchlist.Id,
        Watchlist.Name,
        Watchlist.Description,
        Watchlist.Category,
        Watchlist.Version,
        (Watchlist.OwnerCanModify OR Watchlist.GroupCanModify),
        Watchlist.LastUpdated,
        _ownerEntity,
        _groupEntity;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

COMMIT TRANSACTION;
