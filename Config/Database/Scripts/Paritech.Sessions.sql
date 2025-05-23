BEGIN TRANSACTION;
CREATE SCHEMA sms;

CREATE TABLE sms.Entity (
	 EntityID INTEGER GENERATED BY DEFAULT AS IDENTITY NOT NULL

	,Name TEXT NOT NULL

	,CONSTRAINT PkEntity PRIMARY KEY (EntityID)
);

CREATE UNIQUE INDEX UqEntityName ON sms.Entity (Name);

CREATE TABLE sms.EntityPool (
	 EntityID INTEGER
	,PoolID INTEGER

	,Config BYTEA NOT NULL

	,CONSTRAINT PkEntityPool PRIMARY KEY (EntityID, PoolID)
);

CREATE TABLE sms.EntityPoolResource (
	 EntityID INTEGER
	,PoolID INTEGER
	,ResourceID INTEGER

	,Config BYTEA NOT NULL

	,CONSTRAINT PkEntityPoolResource PRIMARY KEY (EntityID, PoolID, ResourceID)
);

CREATE TABLE sms.Pool (
	 PoolID INTEGER GENERATED BY DEFAULT AS IDENTITY NOT NULL

	,Name TEXT
	,Config BYTEA NOT NULL

	,CONSTRAINT PkPool PRIMARY KEY (PoolID)
);

CREATE UNIQUE INDEX UqPoolName ON sms.Pool (Name);

CREATE TABLE sms.PoolResource (
	 PoolID INTEGER
	,ResourceID INTEGER

	,Config BYTEA NOT NULL

	,CONSTRAINT PkPoolResource PRIMARY KEY (PoolID, ResourceID)
);

CREATE TABLE sms.Resource (
	 ResourceID INTEGER GENERATED BY DEFAULT AS IDENTITY NOT NULL

	,Name TEXT NOT NULL
	,Config BYTEA NOT NULL

	,CONSTRAINT PkResource PRIMARY KEY (ResourceID)
);

CREATE UNIQUE INDEX UqResourceName ON sms.Resource (Name);

ALTER TABLE ONLY sms.EntityPool
	ADD CONSTRAINT FkEntityPoolEntity FOREIGN KEY (EntityID) REFERENCES sms.Entity (EntityID);

ALTER TABLE ONLY sms.EntityPool
	ADD CONSTRAINT FkEntityPoolPool FOREIGN KEY (PoolID) REFERENCES sms.Pool (PoolID);

ALTER TABLE ONLY sms.EntityPoolResource
	ADD CONSTRAINT FkEntityPoolResourceEntity FOREIGN KEY (EntityID) REFERENCES sms.Entity (EntityID);

ALTER TABLE ONLY sms.EntityPoolResource
	ADD CONSTRAINT FkEntityPoolResourcePool FOREIGN KEY (PoolID) REFERENCES sms.Pool (PoolID);

ALTER TABLE ONLY sms.EntityPoolResource
	ADD CONSTRAINT FkEntityPoolResourceResource FOREIGN KEY (ResourceID) REFERENCES sms.Resource (ResourceID);

ALTER TABLE ONLY sms.PoolResource
	ADD CONSTRAINT FkPoolResourcePool FOREIGN KEY (PoolID) REFERENCES sms.Pool (PoolID);

ALTER TABLE ONLY sms.PoolResource
	ADD CONSTRAINT FkPoolResourceResource FOREIGN KEY (ResourceID) REFERENCES sms.Resource (ResourceID);

CREATE OR REPLACE FUNCTION sms.EntityCreate(_entityName TEXT, _poolName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	IF _poolID IS NULL OR (_entityID IS NOT NULL AND EXISTS (SELECT 1 FROM sms.EntityPool EP WHERE EP.EntityID = _entityID AND EP.PoolID = _poolID)) THEN
		RETURN FALSE;
	END IF;

	IF _entityID IS NULL THEN
		INSERT INTO sms.Entity (Name)
			VALUES (_entityName)
			RETURNING EntityID INTO _entityID;
	END IF;

	INSERT INTO sms.EntityPool (EntityID, PoolID, Config) VALUES (_entityID, _poolID, _config);

	RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityCreateResource(_entityName TEXT, _poolName TEXT, _resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
	_resourceID INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _poolID IS NULL OR _resourceID IS NULL OR (_entityID IS NOT NULL AND EXISTS (SELECT 1 FROM sms.EntityPoolResource WHERE EntityID = _entityID AND PoolID = _poolID AND ResourceID = _resourceID)) THEN
		RETURN FALSE;
	END IF;

	IF _entityID IS NULL THEN
		INSERT INTO sms.Entity (Name)
			VALUES (_entityName)
			RETURNING EntityID INTO _entityID;
	END IF;

	INSERT INTO sms.EntityPoolResource (EntityID, PoolID, ResourceID, Config) VALUES (_entityID, _poolID, _resourceID, _config);

	RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityDelete(_entityName TEXT, _poolName TEXT) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
	_records INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	IF _entityID IS NULL OR _poolID IS NULL THEN
		RETURN FALSE;
	END IF;

	DELETE
	FROM	sms.EntityPool
	WHERE	EntityID = _entityID AND PoolID = _poolID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	-- If there are no more configuration records attached to this Entity at all, remove them entirely
	IF NOT EXISTS (SELECT 1 FROM sms.EntityPool WHERE EntityID = _entityID) AND NOT EXISTS (SELECT 1 FROM sms.EntityPoolResource WHERE EntityID = _entityID) THEN
		DELETE
		FROM	sms.Entity
		WHERE	EntityID = _entityID;
	END IF;

	RETURN _records > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityDeleteResource(_entityName TEXT, _poolName TEXT, _resourceName TEXT) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
	_resourceID INTEGER;
	_records INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _entityID IS NULL OR _poolID IS NULL OR _resourceID IS NULL THEN
		RETURN FALSE;
	END IF;

	DELETE
	FROM	sms.EntityPoolResource
	WHERE	EntityID = _entityID AND PoolID = _poolID AND ResourceID = _resourceID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	-- If there are no more configuration records attached to this Entity at all, remove them entirely
	IF NOT EXISTS (SELECT 1 FROM sms.EntityPool WHERE EntityID = _entityID) AND NOT EXISTS (SELECT 1 FROM sms.EntityPoolResource WHERE EntityID = _entityID) THEN
		DELETE
		FROM	sms.Entity
		WHERE	EntityID = _entityID;
	END IF;

	RETURN _records > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityGetAll(_prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	EN.Name
	FROM	sms.Entity EN
	WHERE	_prefix IS NULL OR STARTS_WITH(EN.Name, _prefix)
	ORDER BY EN.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityGetConfig(_entityName TEXT, _poolName TEXT)
	RETURNS TABLE (
	 Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	EP.Config
	FROM	sms.Entity EN
			JOIN sms.EntityPool EP USING (EntityID)
			JOIN sms.Pool PO USING (PoolID)
	WHERE	EN.Name = _entityName AND PO.Name = _poolName;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityGetPools(_entityName TEXT, _prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	PO.Name
	FROM	sms.Entity EN
			JOIN (
			SELECT	EP.EntityID, EP.PoolID
			FROM	sms.EntityPool EP
			UNION
			SELECT	EP.EntityID, EPR.PoolID
			FROM	sms.EntityPoolResource EPR
			) POOL USING (EntityID)
			JOIN sms.Pool PO USING (PoolID)
	WHERE	EN.Name = _entityName AND (_prefix IS NULL OR STARTS_WITH(PO.Name, _prefix))
	ORDER BY PO.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityGetResourceConfig(_entityName TEXT, _poolName TEXT, _resourceName TEXT)
	RETURNS TABLE (
	 Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	EPR.Config
	FROM	sms.Entity EN
			JOIN sms.EntityPoolResource EPR USING (EntityID)
			JOIN sms.Resource RE USING (ResourceID)
			JOIN sms.Pool PO USING (PoolID)
	WHERE	EN.Name = _entityName AND PO.Name = _poolName AND RE.Name = _resourceName;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityGetResources(_entityName TEXT, _poolName TEXT, _prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	,Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	RE.Name, EPR.Config
	FROM	sms.Entity EN
			JOIN sms.EntityPoolResource EPR USING (EntityID)
			JOIN sms.Resource RE USING (ResourceID)
			JOIN sms.Pool PO USING (PoolID)
	WHERE	EN.Name = _entityName AND PO.Name = _poolName AND (_prefix IS NULL OR STARTS_WITH(RE.Name, _prefix))
	ORDER BY RE.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityUpdate(_entityName TEXT, _poolName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
	_records INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	IF _entityID IS NULL OR _poolID IS NULL THEN
		RETURN FALSE;
	END IF;

	UPDATE	sms.EntityPool
	SET		Config = _config
	WHERE	EntityID = _entityID AND PoolID = _poolID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	RETURN ROW_COUNT > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.EntityUpdateResource(_entityName TEXT, _poolName TEXT, _resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_entityID INTEGER;
	_poolID INTEGER;
	_resourceID INTEGER;
	_records INTEGER;
BEGIN
	SELECT	EN.EntityID INTO _entityID
	FROM	sms.Entity EN
	WHERE	EN.Name = _entityName;

	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _entityID IS NULL OR _poolID IS NULL OR _resourceID IS NULL THEN
		RETURN FALSE;
	END IF;

	UPDATE	sms.EntityPoolResource
	SET		Config = _config
	WHERE	EntityID = _entityID AND PoolID = _poolID AND ResourceID = _resourceID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	RETURN ROW_COUNT > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolCreate(_poolName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM sms.Pool WHERE Name = _poolName) THEN
		RETURN FALSE;
	END IF;

	INSERT INTO sms.Pool (Name, Config) VALUES (_poolName, _config);

	RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolCreateResource(_poolName TEXT, _resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_poolID INTEGER;
	_resourceID INTEGER;
BEGIN
	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _poolID IS NULL OR _resourceID IS NULL OR EXISTS (SELECT 1 FROM sms.PoolResource WHERE PoolID = _poolID AND ResourceID = _resourceID) THEN
		RETURN FALSE;
	END IF;

	INSERT INTO sms.PoolResource (PoolID, ResourceID, Config) VALUES (_poolID, _resourceID, _config);

	RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolDelete(_poolName TEXT) RETURNS BOOLEAN AS $$
DECLARE
	_oldPoolID INTEGER;
BEGIN
	DELETE
	FROM	sms.Pool
	WHERE	Name = _poolName
	RETURNING PoolID INTO _oldPoolID;

	RETURN _oldPoolID IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolDeleteResource(_poolName TEXT, _resourceName TEXT) RETURNS BOOLEAN AS $$
DECLARE
	_records INTEGER;
	_poolID INTEGER;
	_resourceID INTEGER;
BEGIN
	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _poolID IS NULL OR _resourceID IS NULL THEN
		RETURN FALSE;
	END IF;

	DELETE
	FROM	sms.PoolResource
	WHERE	PoolID = _poolID AND ResourceID = _resourceID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	RETURN _records > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolGetAll(_prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	PO.Name
	FROM	sms.Pool PO
	WHERE	_prefix IS NULL OR STARTS_WITH(PO.Name, _prefix)
	ORDER BY PO.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolGetConfig(_poolName TEXT)
	RETURNS TABLE (
	 Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	PO.Config
	FROM	sms.Pool PO
	WHERE	PO.Name = _poolName;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolGetResourceConfig(_poolName TEXT, _resourceName TEXT)
	RETURNS TABLE (
	 Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	PR.Config
	FROM	sms.Pool PO
			JOIN sms.PoolResource PR USING (PoolID)
			JOIN sms.Resource RE USING (ResourceID)
	WHERE	PO.Name = _poolName AND RE.Name = _resourceName;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolGetResources(_poolName TEXT, _prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	RE.Name
	FROM	sms.Pool PO
			JOIN sms.PoolResource PR USING (PoolID)
			JOIN sms.Resource RE USING (ResourceID)
	WHERE	PO.Name = _poolName AND (_prefix IS NULL OR STARTS_WITH(RE.Name, _prefix))
	ORDER BY RE.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolUpdate(_poolName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_oldPoolID INTEGER;
BEGIN
	UPDATE	sms.Pool PO
	SET		Config = _config
	WHERE	PO.Name = _poolName
	RETURNING PoolID INTO _oldPoolID;

	RETURN _oldPoolID IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.PoolUpdateResource(_poolName TEXT, _resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_records INTEGER;
	_poolID INTEGER;
	_resourceID INTEGER;
BEGIN
	SELECT	PO.PoolID INTO _poolID
	FROM	sms.Pool PO
	WHERE	PO.Name = _groupName;

	SELECT	RE.ResourceID INTO _resourceID
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;

	IF _poolID IS NULL OR _resourceID IS NULL THEN
		RETURN FALSE;
	END IF;

	UPDATE	sms.PoolResource
	SET		Config = _config
	WHERE	PoolID = _poolID AND ResourceID = _resourceID;

	GET DIAGNOSTICS _records = ROW_COUNT;

	RETURN ROW_COUNT > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.ResourceCreate(_resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM sms.Resource WHERE Name = _resourceName) THEN
		RETURN FALSE;
	END IF;

	INSERT INTO sms.Resource (Name, Config) VALUES (_resourceName, _config);

	RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.ResourceDelete(_resourceName TEXT) RETURNS BOOLEAN AS $$
DECLARE
	_oldResourceID INTEGER;
BEGIN
	DELETE
	FROM	sms.Resource
	WHERE	Name = _resourceName
	RETURNING ResourceID INTO _oldResourceID;

	RETURN _oldResourceID IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.ResourceGetAll(_prefix TEXT, _offset INTEGER, _count INTEGER)
	RETURNS TABLE (
	 Name TEXT
	,Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	RE.Name, RE.Config
	FROM	sms.Resource RE
	WHERE	_prefix IS NULL OR STARTS_WITH(RE.Name, _prefix)
	ORDER BY RE.Name ASC
	OFFSET (_offset) FETCH NEXT (_count) ROWS ONLY;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.ResourceGetConfig(_resourceName TEXT)
	RETURNS TABLE (
	 Config BYTEA
	) AS $$
BEGIN
	RETURN QUERY
	SELECT	RE.Config
	FROM	sms.Resource RE
	WHERE	RE.Name = _resourceName;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sms.ResourceUpdate(_resourceName TEXT, _config BYTEA) RETURNS BOOLEAN AS $$
DECLARE
	_oldResourceID INTEGER;
BEGIN
	UPDATE	sms.Resource
	SET		Config = _config
	WHERE	Name = _resourceName
	RETURNING ResourceID INTO _oldResourceID;

	RETURN _oldResourceID IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT TRANSACTION;
