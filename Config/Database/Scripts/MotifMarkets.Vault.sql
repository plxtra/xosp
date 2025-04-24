BEGIN TRANSACTION;
-- Sequences
CREATE SEQUENCE public.asset_id_seq;

-- Table
CREATE TABLE public.asset (
	id BIGINT NOT NULL DEFAULT nextval('asset_id_seq'::regclass),
	code VARCHAR NOT NULL,
	assettypeid BIGINT NOT NULL,
	CONSTRAINT pk_asset PRIMARY KEY (id),
    CONSTRAINT uq_asset_codetype UNIQUE (code, assettypeid)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_asset_codetype
ON public.asset USING btree
(
    code COLLATE pg_catalog.default varchar_ops,
    assettypeid
)
TABLESPACE pg_default;

-- Sequences
CREATE SEQUENCE public.assettype_id_seq;

-- Table
CREATE TABLE public.assettype (
	id BIGINT NOT NULL DEFAULT nextval('assettype_id_seq'::regclass),
	code VARCHAR NOT NULL,
	CONSTRAINT pk_assettype PRIMARY KEY (id),
    CONSTRAINT uq_assettype_code UNIQUE (code)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_assettype_code
ON public.assettype USING hash
(
    code COLLATE pg_catalog.default varchar_ops
)
TABLESPACE pg_default;

-- Table
CREATE TABLE public.association (
	assetid BIGINT NOT NULL,
	parentassetid BIGINT NOT NULL,
	CONSTRAINT pk_association PRIMARY KEY (assetid, parentassetid)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

-- Sequences
CREATE SEQUENCE public.attribute_id_seq;

-- Table
CREATE TABLE public.attribute (
	id BIGINT NOT NULL DEFAULT nextval('attribute_id_seq'::regclass),
    assetid BIGINT NOT NULL,
	key VARCHAR NOT NULL,
	value VARCHAR,
	CONSTRAINT pk_attribute PRIMARY KEY (id),
    CONSTRAINT uq_attribute_assetidkey UNIQUE (assetid, key)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

-- Indexes
CREATE INDEX ix_attribute_asset
ON public.attribute USING btree
(
    assetid,
    id
)
TABLESPACE pg_default;

-- Sequences
CREATE SEQUENCE public.changeaudit_id_seq;

-- Table
CREATE TABLE public.changeaudit (
	id BIGINT NOT NULL DEFAULT nextval('ChangeAudit_Id_seq'::regclass),
	actioned TIMESTAMPTZ NOT NULL,
	operator VARCHAR NOT NULL,
	operation VARCHAR NOT NULL,
	tablename VARCHAR,
	keyvalue VARCHAR,
	CONSTRAINT pk_changeaudit PRIMARY KEY (Id)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE ONLY public.Asset
	ADD CONSTRAINT asset_assettype_fkey FOREIGN KEY (AssetTypeId)
	REFERENCES public.AssetType (id)
	ON DELETE RESTRICT;

ALTER TABLE ONLY public.Association
	ADD CONSTRAINT association_assetid_fkey FOREIGN KEY (AssetId)
	REFERENCES public.Asset (id)
	ON DELETE RESTRICT;

ALTER TABLE ONLY public.Association
	ADD CONSTRAINT association_parentassetid_fkey FOREIGN KEY (ParentAssetId)
	REFERENCES public.Asset (id)
	ON DELETE RESTRICT;

ALTER TABLE ONLY public.Attribute
	ADD CONSTRAINT attribute_assetid_fkey FOREIGN KEY (AssetId)
	REFERENCES public.Asset (id)
	ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION AddAsset(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _attributes JSON = NULL
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    IF (_assetcode IS NULL OR _assetcode = '') THEN
        RAISE EXCEPTION 'Asset has no code';
    END IF;

    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;
    IF (_assetid IS NOT NULL) THEN
        RAISE EXCEPTION 'Asset already exists: %', _assetcode;
    END IF;

    INSERT INTO public.asset (code, assettypeid)
    VALUES (_assetcode, _assettypeid)
    ON CONFLICT DO NOTHING
    RETURNING id INTO _assetid;

    PERFORM public.UpdateAttributes(_operator, _assettypecode, _assetcode, _attributes);

    PERFORM public.AddChangeAudit(_operator, 'INSERT', 'asset', _assetcode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AddAssetType(
    _operator VARCHAR,
    _assettypecode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assettypeid BIGINT;
BEGIN
    IF (_assettypecode IS NULL OR _assettypecode = '') THEN
        RAISE EXCEPTION 'AssetType has no code';
    END IF;

    -- Normalise
    _assettypecode = UPPER(_assettypecode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NOT NULL) THEN
        RAISE EXCEPTION 'AssetType already exists: %', _assettypecode;
    END IF;

    INSERT INTO public.assettype (code)
    VALUES (_assettypecode)
    ON CONFLICT DO NOTHING;

    PERFORM public.AddChangeAudit(_operator, 'INSERT', 'assettype', _assettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AddAssociation(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _associatedassettypecode VARCHAR, -- child
    _associatedassetcode VARCHAR -- child
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
    _associatedassetid BIGINT;
    _associatedassettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _associatedassettypecode = UPPER(_associatedassettypecode);
    _associatedassetcode = UPPER(_associatedassetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    SELECT at.id INTO _associatedassettypeid
    FROM public.assettype at
    WHERE at.code = _associatedassettypecode
    FOR UPDATE;
    IF (_associatedassettypeid IS NULL) THEN
        RAISE EXCEPTION 'Associated AssetType is unknown: %', _associatedassettypecode;
    END IF;

    SELECT a.id INTO _associatedassetid
    FROM public.asset a
    WHERE a.assettypeid = _associatedassettypeid AND a.code = _associatedassetcode
    FOR UPDATE;
    IF (_associatedassetid IS NULL) THEN
        RAISE EXCEPTION 'Associated Asset is unknown: %', _associatedassetcode;
    END IF;

    IF (NOT EXISTS (SELECT NULL FROM public.association a WHERE a.assetid = _associatedassetid AND a.parentassetid = _assetid)) THEN
        INSERT INTO public.association (assetid, parentassetid)
        VALUES (_associatedassetid, _assetid)
        ON CONFLICT DO NOTHING;

        PERFORM public.AddChangeAudit(_operator, 'INSERT', 'association', 'From: ' || _assetcode || '|' || _assettypecode || ' to ' || _associatedassetcode || '|' || _associatedassettypecode);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AddChangeAudit(
    _operator  VARCHAR,
    _operation VARCHAR,
    _tablename VARCHAR  = NULL,
    _keyValue  VARCHAR = NULL
)
RETURNS VOID
AS $$
DECLARE
    _date TIMESTAMPTZ;
BEGIN
    _date = current_timestamp;

    IF (_operator IS NULL) THEN
        RAISE EXCEPTION 'No Operator supplied';
    END IF;
    IF (_operation IS NULL) THEN
        RAISE EXCEPTION 'No Operation supplied';
    END IF;

    INSERT INTO public.ChangeAudit (Actioned, Operator, Operation, Tablename, KeyValue)
    VALUES (_date, _operator, _operation, _tablename, _keyValue);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION BulkUpdateAssetAttributes(
    _operator VARCHAR,
    _assetAttributes JSON
)
RETURNS VOID
AS $$
DECLARE
BEGIN

    INSERT INTO public.attribute (assetid, key, value)
    SELECT
        a.id AS assetid,
        UPPER(j.key) AS key,
        j.value AS value
    FROM json_to_recordset(_assetAttributes) as j(
        assettypecode VARCHAR,
        assetcode VARCHAR,
        key VARCHAR,
        value VARCHAR
    )
    JOIN public.AssetType aty ON UPPER(aty.Code) = UPPER(j.assettypecode)
    JOIN public.Asset a ON a.assettypeid = aty.id AND UPPER(a.code) = UPPER(j.assetcode)
    ON CONFLICT (assetid, key) DO
    UPDATE
        SET value = excluded.value;

    PERFORM public.AddChangeAudit(_operator, 'UPDATE', 'attribute', 'Multiple');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ClearAssociations(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
	_filterassettypes VARCHAR = NULL -- csv
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _filterassettypes = UPPER(_filterassettypes);

	IF ((_filterassettypes <> '') IS NOT TRUE) THEN
		_filterassettypes = (SELECT array_to_string(array_agg(code), ',') FROM public.assettype);
	END IF;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    DELETE FROM public.association
    WHERE parentassetid = _assetid
        AND assetid IN (
            SELECT ass.assetid
            FROM public.asset a
            JOIN public.assettype t ON t.id = a.assettypeid
            JOIN UNNEST(string_to_array(_filterassettypes, ',')) filt(assettype) ON TRIM(filt.assettype) = t.code
            JOIN public.association ass ON ass.assetid = a.id
            WHERE ass.parentassetid = _assetid
        );
    PERFORM public.AddChangeAudit(_operator, 'CLEAR', 'association', 'From: ' || _assetcode || '|' || _assettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteAsset(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    IF (EXISTS (SELECT NULL FROM public.association WHERE parentassetid = _assetid OR assetid = _assetid)) THEN
        RAISE EXCEPTION 'Asset has associations: %|%', _assetcode, _assettypecode;
    END IF;

    PERFORM public.DeleteAttributes(_operator,_assettypecode, _assetcode);

    DELETE FROM public.asset
    WHERE id = _assetid;

    PERFORM public.AddChangeAudit(_operator, 'DELETE', 'asset', _assetcode || '|' || _assettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteAssetType(
    _operator VARCHAR,
    _assettypecode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    IF (EXISTS (SELECT NULL FROM public.asset WHERE assettypeid = _assettypeid)) THEN
        RAISE EXCEPTION 'AssetType has assets: %', _assettypecode;
    END IF;

    DELETE FROM public.assettype
    WHERE id = _assettypeid;

    PERFORM public.AddChangeAudit(_operator, 'DELETE', 'assettype', _assettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteAssociation(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _associatedassettypecode VARCHAR,
    _associatedassetcode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
    _associatedassetid BIGINT;
    _associatedassettypeid BIGINT;
BEGIN
     -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _associatedassettypecode = UPPER(_associatedassettypecode);
    _associatedassetcode = UPPER(_associatedassetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    SELECT at.id INTO _associatedassettypeid
    FROM public.assettype at
    WHERE at.code = _associatedassettypecode
    FOR UPDATE;
    IF (_associatedassettypeid IS NULL) THEN
        RAISE EXCEPTION 'Associated AssetType is unknown: %', _associatedassettypecode;
    END IF;

    SELECT a.id INTO _associatedassetid
    FROM public.asset a
    WHERE a.assettypeid = _associatedassettypeid AND a.code = _associatedassetcode
    FOR UPDATE;
    IF (_associatedassetid IS NULL) THEN
        RAISE EXCEPTION 'Associated Asset is unknown: %', _associatedassetcode;
    END IF;

    IF (EXISTS (SELECT NULL FROM public.association a WHERE a.assetid = _associatedassetid AND a.parentassetid = _assetid)) THEN
        DELETE FROM public.association
        WHERE assetid = _associatedassetid AND parentassetid = _assetid;

        PERFORM public.AddChangeAudit(_operator, 'DELETE', 'association', 'From: ' || _assetcode || '|' || _assettypecode || ' to ' || _associatedassetcode || '|' || _associatedassettypecode);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION DeleteAttributes(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    IF (_assetcode IS NULL OR _assetcode = '') THEN
        RAISE EXCEPTION 'Asset has no code';
    END IF;

    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    DELETE FROM public.attribute
    WHERE assetid = _assetid;

    PERFORM public.AddChangeAudit(_operator, 'DELETE', 'attribute', _assetcode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION EnsureAsset(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _attributes JSON = NULL
)
RETURNS BIGINT
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    IF (_assetcode IS NULL OR _assetcode = '') THEN
        RAISE EXCEPTION 'Asset has no code';
    END IF;

    _assettypeid = public.EnsureAssetType(_operator, _assettypecode);

    LOCK TABLE public.asset IN SHARE ROW EXCLUSIVE MODE;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;
    IF (_assetid IS NOT NULL) THEN
        RETURN _assetid;
    END IF;

    INSERT INTO public.asset (code, assettypeid)
    VALUES (_assetcode, _assettypeid)
    RETURNING id INTO _assetid;

    PERFORM public.UpdateAttributes(_operator, _assettypecode, _assetcode, _attributes);

    PERFORM public.AddChangeAudit(_operator, 'INSERT', 'asset', _assetcode);

    RETURN _assetid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION EnsureAssetType(
    _operator VARCHAR,
    _assettypecode VARCHAR
)
RETURNS BIGINT
AS $$
DECLARE
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);

    IF (_assettypecode IS NULL OR _assettypecode = '') THEN
        RAISE EXCEPTION 'AssetType has no code';
    END IF;

    LOCK TABLE public.assettype IN SHARE ROW EXCLUSIVE MODE;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NOT NULL) THEN
        RETURN _assettypeid;
    END IF;

    INSERT INTO public.assettype (code)
    VALUES (_assettypecode)
    RETURNING id INTO _assettypeid;

    PERFORM public.AddChangeAudit(_operator, 'INSERT', 'assettype', _assettypecode);

    RETURN _assettypeid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION EnsureAssociations(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _associatedassettypecode VARCHAR, -- child
    _associatedassetcodelist VARCHAR -- child
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
    _associatedassetid BIGINT;
    _associatedassettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _associatedassettypecode = UPPER(_associatedassettypecode);
    _associatedassetcodelist = UPPER(_associatedassetcodelist);

    LOCK TABLE public.asset, public.assettype IN SHARE ROW EXCLUSIVE MODE;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NULL) THEN
        INSERT INTO public.assettype (code)
        VALUES (_assettypecode)
        RETURNING id INTO _assettypeid;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;
    IF (_assetid IS NULL) THEN
        INSERT INTO public.asset (assettypeid, code)
        VALUES (_assettypeid, _assetcode)
        RETURNING id INTO _assetid;
    END IF;

    SELECT at.id INTO _associatedassettypeid
    FROM public.assettype at
    WHERE at.code = _associatedassettypecode;
    IF (_associatedassettypeid IS NULL) THEN
        INSERT INTO public.assettype (code)
        VALUES (_associatedassettypecode)
        RETURNING id INTO _associatedassettypeid;
    END IF;

    WITH source AS
    (
        SELECT assetcodes.assetcode AS assetcode, _associatedassettypeid AS assettypeid
        FROM UNNEST(string_to_array(_associatedassetcodelist, ',')) assetcodes(assetcode)
    )
    INSERT INTO public.asset (assettypeid, code)
        SELECT src.assettypeid, src.assetcode
        FROM source src
    ON CONFLICT (assettypeid, code) DO NOTHING;

    -- Assign
    INSERT INTO public.association (assetid, parentassetid)
    SELECT a.id, _assetid
    FROM public.asset a
    JOIN UNNEST(string_to_array(_associatedassetcodelist, ',')) assetcodes(assetcode) ON assetcodes.assetcode = a.code
    WHERE a.assettypeid = _associatedassettypeid
    ON CONFLICT (assetid, parentassetid) DO NOTHING;

    PERFORM public.AddChangeAudit(_operator, 'ENSURE', 'association', 'From: ' || _assetcode || '|' || _assettypecode || ' to ' || _associatedassetcodelist || '|' || _associatedassettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION GetAttributes(
    _assettypecode VARCHAR,
    _assetcode VARCHAR
)
RETURNS TABLE (
    AssetId BIGINT,
    Attributes JSON
)
AS $$
DECLARE
    _assettypeid BIGINT;
    _assetid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    RETURN QUERY
        SELECT
            _assetid AS AssetId,
            attr AS Attributes
        FROM
        (
            SELECT json_agg(json_build_object('key', a.key, 'value',  a.value) ORDER BY key) AS attr
            FROM public.attribute a
            WHERE a.assetid = _assetid
        ) attr;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ListAssets(
    _filterassettypes VARCHAR = NULL -- csv
)
RETURNS TABLE (
    AssetCode VARCHAR,
    AssetTypeCode VARCHAR,
    Attributes JSON
)
AS $$
DECLARE
BEGIN
    -- Normalise
    _filterassettypes = UPPER(_filterassettypes);

	IF ((_filterassettypes <> '') IS NOT TRUE) THEN
		_filterassettypes = (SELECT array_to_string(array_agg(code), ',') FROM public.assettype);
	END IF;

    RETURN QUERY
        SELECT
            a.code AS AssetCode,
            t.code AS AssetTypeCode,
            attr.attributes AS attributes
        FROM public.asset a
        JOIN public.assettype t ON t.id = a.assettypeid
		JOIN UNNEST(string_to_array(_filterassettypes, ',')) filt(assettype) ON TRIM(filt.assettype) = t.code
        JOIN public.GetAttributes(t.code, a.code) attr ON attr.assetid = a.id
		ORDER BY t.code, a.code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ListAssetTypes(
)
RETURNS TABLE (
    AssetTypeCode VARCHAR
)
AS $$
DECLARE
BEGIN
    RETURN QUERY
        SELECT at.code AS AssetTypeCode
        FROM public.assettype at
        ORDER BY at.code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ListAssociations(
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _filterassettypes VARCHAR = NULL -- CSV
)
RETURNS TABLE (
    AssetCode VARCHAR,
    AssetTypeCode VARCHAR,
    Attributes JSON
)
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _filterassettypes = UPPER(_filterassettypes);

	IF ((_filterassettypes <> '') IS NOT TRUE) THEN
		_filterassettypes = (SELECT array_to_string(array_agg(code), ',') FROM public.assettype);
	END IF;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;

    RETURN QUERY
        SELECT
            a.code AS AssetCode,
            t.code AS AssetTypeCode,
            attr.attributes AS attributes
        FROM public.asset a
        JOIN public.assettype t ON t.id = a.assettypeid
		JOIN UNNEST(string_to_array(_filterassettypes, ',')) filt(assettype) ON TRIM(filt.assettype) = t.code
        JOIN public.association ass ON ass.assetid = a.id
        JOIN public.GetAttributes(t.code, a.code) attr ON attr.assetid = a.id
        WHERE ass.parentassetid = _assetid
		ORDER BY t.code, a.code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ListParentAssociations(
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _filterassettypes VARCHAR = NULL -- CSV
)
RETURNS TABLE (
    AssetCode VARCHAR,
    AssetTypeCode VARCHAR,
    Attributes JSON
)
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _filterassettypes = UPPER(_filterassettypes);

	IF ((_filterassettypes <> '') IS NOT TRUE) THEN
		_filterassettypes = (SELECT array_to_string(array_agg(code), ',') FROM public.assettype);
	END IF;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;

    RETURN QUERY
        SELECT
            pa.code AS AssetCode,
            pt.code AS AssetTypeCode,
            attr.attributes AS attributes
        FROM public.asset a
        JOIN public.assettype t ON t.id = a.assettypeid
        JOIN public.association ass ON ass.assetid = a.id
        JOIN public.asset pa ON pa.id = ass.parentassetid
        JOIN public.assettype pt ON pt.id = pa.assettypeid
		JOIN UNNEST(string_to_array(_filterassettypes, ',')) filt(assettype) ON TRIM(filt.assettype) = pt.code
        JOIN public.GetAttributes(pt.code, pa.code) attr ON attr.assetid = pa.id
        WHERE ass.assetid = _assetid
		ORDER BY t.code, a.code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RetrieveAssociations(
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
	_filterassettypes VARCHAR = NULL -- csv
)
RETURNS TABLE (
    AssetCode VARCHAR,
    AssetTypeCode VARCHAR,
    Attributes JSON
)
AS $$
DECLARE
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _filterassettypes = UPPER(_filterassettypes);

	IF ((_filterassettypes <> '') IS NOT TRUE) THEN
		_filterassettypes = (SELECT array_to_string(array_agg(code), ',') FROM public.assettype);
	END IF;

    RETURN QUERY
        WITH RECURSIVE assets AS (
            SELECT as1.assetid AS id
            FROM public.asset a1
            JOIN public.assettype at1 ON at1.id = a1.assettypeid
			JOIN public.association as1 ON as1.parentassetid = a1.id
            WHERE a1.code = _assetcode AND at1.code = _assettypecode
            UNION
            SELECT a2.id
            FROM public.asset a2
            JOIN public.assettype at2 ON at2.id = a2.assettypeid
            JOIN public.association as2 ON as2.assetid = a2.id
            JOIN assets ass2 ON ass2.id = as2.parentassetid
        )
        SELECT
            a.code AS AssetCode,
            t.code AS AssetTypeCode,
            attr.attributes AS attributes
        FROM assets
        JOIN public.asset a ON a.id = assets.id
        JOIN public.assettype t ON t.id = a.assettypeid
		JOIN UNNEST(string_to_array(_filterassettypes, ',')) filt(assettype) ON TRIM(filt.assettype) = t.code
        JOIN public.GetAttributes(t.code, a.code) attr ON attr.assetid = a.id
		ORDER BY t.code, a.code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION SyncAssetCollection(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcodelist VARCHAR
)
RETURNS TABLE (
    DeletedAssetCodeList VARCHAR,
    AddedAssetCodeList VARCHAR
)
AS $$
DECLARE
    _assettypeid BIGINT;
    _deletedcodes VARCHAR[];
    _addedcodes VARCHAR[];
BEGIN
     -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcodelist = UPPER(_assetcodelist);

	LOCK TABLE public.asset, public.assettype IN SHARE ROW EXCLUSIVE MODE;

    -- add AssetType if missing
    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NULL) THEN
        INSERT INTO public.assettype (code)
        VALUES (_assettypecode)
        RETURNING id INTO _assettypeid;
    END IF;

    -- Disassociate unreferences assets
	DELETE FROM public.association
	WHERE assetid IN
	(
		SELECT a.id
		FROM public.asset a
		LEFT JOIN UNNEST(string_to_array(_assetcodelist, ',')) src(assetcode) ON src.assetcode = a.code
		WHERE a.assettypeid = _assettypeid AND src.assetcode IS NULL
	)
	OR parentassetid IN
	(
		SELECT a.id
		FROM public.asset a
		LEFT JOIN UNNEST(string_to_array(_assetcodelist, ',')) src(assetcode) ON src.assetcode = a.code
		WHERE a.assettypeid = _assettypeid AND src.assetcode IS NULL
	);

	WITH del AS (
		DELETE FROM public.asset
		WHERE id IN
		(
			SELECT a.id
			FROM public.asset a
			LEFT JOIN UNNEST(string_to_array(_assetcodelist, ',')) src(assetcode) ON src.assetcode = a.code
			WHERE a.assettypeid = _assettypeid AND src.assetcode IS NULL
		)
		RETURNING code
	)
    SELECT array_agg(code) INTO _deletedcodes FROM del;

    -- Add missing assets
	WITH ins AS
	(
		INSERT INTO public.asset (code, assettypeid)
		SELECT src.assetcode AS code, _assettypeid AS assettypeid
		FROM UNNEST(string_to_array(_assetcodelist, ',')) src(assetcode)
		LEFT JOIN public.asset a ON a.code = src.assetcode AND a.assettypeid = _assettypeid
		WHERE a.code IS NULL
		RETURNING code
	)
	SELECT array_agg(code) INTO _addedcodes from ins;

    PERFORM public.AddChangeAudit(_operator, 'SYNC', 'asset', 'For: ' || _assettypecode);

	raise notice 'deleted: %', _deletedcodes;
	raise notice 'added: %', _addedcodes;

    RETURN QUERY
        SELECT
            array_to_string(_deletedcodes, ',')::VARCHAR AS DeletedAssetCodeList,
            array_to_string(_addedcodes, ',')::VARCHAR AS AddedAssetCodeList;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION SyncAssociations(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _associatedassettypecode VARCHAR, -- child
    _associatedassetcodelist VARCHAR -- child
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
    _associatedassetid BIGINT;
    _associatedassettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _associatedassettypecode = UPPER(_associatedassettypecode);
    _associatedassetcodelist = UPPER(_associatedassetcodelist);

    LOCK TABLE public.asset, public.assettype IN SHARE ROW EXCLUSIVE MODE;

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode;
    IF (_assettypeid IS NULL) THEN
        INSERT INTO public.assettype (code)
        VALUES (_assettypecode)
        RETURNING id INTO _assettypeid;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode;
    IF (_assetid IS NULL) THEN
        INSERT INTO public.asset (assettypeid, code)
        VALUES (_assettypeid, _assetcode)
        RETURNING id INTO _assetid;
    END IF;

    SELECT at.id INTO _associatedassettypeid
    FROM public.assettype at
    WHERE at.code = _associatedassettypecode;
    IF (_associatedassettypeid IS NULL) THEN
        INSERT INTO public.assettype (code)
        VALUES (_associatedassettypecode)
        RETURNING id INTO _associatedassettypeid;
    END IF;

    WITH source AS
    (
        SELECT assetcodes.assetcode AS assetcode, _associatedassettypeid AS assettypeid
        FROM UNNEST(string_to_array(_associatedassetcodelist, ',')) assetcodes(assetcode)
    )
    INSERT INTO public.asset (assettypeid, code)
        SELECT src.assettypeid, src.assetcode
        FROM source src
    ON CONFLICT (assettypeid, code) DO NOTHING;

    -- Clear first
    DELETE FROM public.association
    WHERE parentassetid = _assetid
        AND assetid IN (SELECT a.id FROM public.asset a WHERE a.assettypeid = _associatedassettypeid);

    -- Assign
    INSERT INTO public.association (assetid, parentassetid)
    SELECT a.id, _assetid
    FROM public.asset a
    JOIN UNNEST(string_to_array(_associatedassetcodelist, ',')) assetcodes(assetcode) ON assetcodes.assetcode = a.code
    WHERE a.assettypeid = _associatedassettypeid;

    PERFORM public.AddChangeAudit(_operator, 'SYNC', 'association', 'From: ' || _assetcode || '|' || _assettypecode || ' to ' || _associatedassetcodelist || '|' || _associatedassettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION UpdateAsset(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _updatedassettypecode VARCHAR,
    _updatedassetcode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
    _updatedassettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);
    _updatedassettypecode = UPPER(_updatedassettypecode);
    _updatedassetcode = UPPER(_updatedassetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT at.id INTO _updatedassettypeid
    FROM public.assettype at
    WHERE at.code = _updatedassettypecode
    FOR UPDATE;
    IF (_updatedassettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _updatedassettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    IF (EXISTS (SELECT NULL FROM public.asset a JOIN public.assettype at ON at.id = a.assettypeid WHERE a.code = _updatedassetcode AND at.code = _updatedassettypecode)) THEN
        RAISE EXCEPTION 'Updated Asset and AssetType already exists: %|%', _updatedassetcode, _updatedassettypecode;
    END IF;

    UPDATE public.asset
    SET code = _updatedassetcode, assettypeid = _updatedassettypeid
    WHERE id = _assetid;

    PERFORM public.AddChangeAudit(_operator, 'UPDATE', 'asset', 'From: ' || _assetcode || '|' || _assettypecode || ' to ' || _updatedassetcode || '|' || _updatedassettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION UpdateAssetType(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _updatedassettypecode VARCHAR
)
RETURNS VOID
AS $$
DECLARE
    _assettypeid BIGINT;
BEGIN
    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _updatedassettypecode = UPPER(_updatedassettypecode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    IF (EXISTS (SELECT NULL FROM public.assettype WHERE code = _updatedassettypecode)) THEN
        RAISE EXCEPTION 'Updated AssetType already exists: %', _updatedassettypecode;
    END IF;

    UPDATE public.assettype
    SET code = _updatedassettypecode
    WHERE id = _assettypeid;

    PERFORM public.AddChangeAudit(_operator, 'UPDATE', 'assettype', 'From: ' || _assettypecode || ' to ' || _updatedassettypecode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION UpdateAttributes(
    _operator VARCHAR,
    _assettypecode VARCHAR,
    _assetcode VARCHAR,
    _attributes JSON = NULL
)
RETURNS VOID
AS $$
DECLARE
    _assetid BIGINT;
    _assettypeid BIGINT;
BEGIN
    IF (_assetcode IS NULL OR _assetcode = '') THEN
        RAISE EXCEPTION 'Asset has no code';
    END IF;

    -- Normalise
    _assettypecode = UPPER(_assettypecode);
    _assetcode = UPPER(_assetcode);

    SELECT at.id INTO _assettypeid
    FROM public.assettype at
    WHERE at.code = _assettypecode
    FOR UPDATE;
    IF (_assettypeid IS NULL) THEN
        RAISE EXCEPTION 'AssetType is unknown: %', _assettypecode;
    END IF;

    SELECT a.id INTO _assetid
    FROM public.asset a
    WHERE a.assettypeid = _assettypeid AND a.code = _assetcode
    FOR UPDATE;
    IF (_assetid IS NULL) THEN
        RAISE EXCEPTION 'Asset is unknown: %', _assetcode;
    END IF;

    INSERT INTO public.attribute (assetid, key, value)
    SELECT
        _assetid AS assetid,
        UPPER(j.key) AS key,
        j.value AS value
    FROM json_to_recordset(_attributes) as j(
        key VARCHAR,
        value VARCHAR
    )
    ON CONFLICT (assetid, key) DO
    UPDATE
        SET value = excluded.value;

    PERFORM public.AddChangeAudit(_operator, 'UPDATE', 'attribute', _assetcode);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT TRANSACTION;
