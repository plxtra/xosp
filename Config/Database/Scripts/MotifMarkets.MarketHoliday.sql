BEGIN TRANSACTION;
CREATE TABLE public.Holidays (
    MarketId bigint NOT NULL,
    Holiday date NOT NULL,
    CONSTRAINT Holidays_pkey PRIMARY KEY (MarketId, Holiday)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

-- Sequences
CREATE SEQUENCE public.Markets_MarketId_seq;

-- Table
CREATE TABLE public.Markets (
    Id bigint NOT NULL DEFAULT nextval('Markets_MarketId_seq'::regclass),
    Market varchar NOT NULL COLLATE pg_catalog.default,
    CONSTRAINT Markets_pkey PRIMARY KEY (Id)
)
WITH (
    OIDS = FALSE)
TABLESPACE pg_default;

ALTER TABLE ONLY public.Holidays
	ADD CONSTRAINT holidays_marketid_fkey FOREIGN KEY (MarketId)
	REFERENCES public.Markets (Id);

CREATE OR REPLACE FUNCTION AddHoliday (_market varchar, _holiday date)
    RETURNS VOID
    AS $$
DECLARE
    _marketId bigint;
    _count int;
BEGIN
    SELECT
        m.Id INTO _marketId
    FROM
        public.Markets m
    WHERE
        UPPER(m.Market) = UPPER(_market);
    IF (_marketId IS NULL) THEN
        INSERT INTO public.Markets (Market)
            VALUES (UPPER(_market))
        RETURNING
            Id INTO _marketId;
    END IF;
    SELECT
        COUNT(*) INTO _count
    FROM
        public.Holidays h
    WHERE
        h.MarketId = _marketId
        AND h.Holiday = _holiday;
    IF (_Count = 0) THEN
        INSERT INTO public.Holidays (MarketId, Holiday)
            VALUES (_marketId, _holiday);
    END IF;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AllHolidaysForDate (_holiday date)
    RETURNS TABLE (
        Market varchar
    )
    AS $$
DECLARE
BEGIN
    RETURN QUERY
    SELECT
        m.Market
    FROM
        public.Holidays h
        JOIN public.Markets m ON m.Id = h.MarketId
    WHERE
        h.Holiday = _holiday
    ORDER BY
        m.Market;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION AllHolidaysForMarket (_market varchar)
    RETURNS TABLE (
        Holiday date
    )
    AS $$
DECLARE
BEGIN
    RETURN QUERY
    SELECT
        h.Holiday
    FROM
        public.Holidays h
        JOIN public.Markets m ON m.Id = h.MarketId
    WHERE
        UPPER(m.Market) = UPPER(_market)
    ORDER BY
        h.Holiday;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION IsHoliday (_market varchar, _holiday date)
    RETURNS BOOLEAN
    AS $$
DECLARE
    _count int;
BEGIN
    SELECT
        COUNT(*) INTO _count
    FROM
        public.Holidays h
        JOIN public.Markets m ON m.Id = h.MarketId
    WHERE
        UPPER(m.Market) = UPPER(_market)
        AND h.Holiday = _holiday;
    RETURN (_count > 0);
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RetrieveAllHolidaysForDateRange (_fromDate date = NULL, _toDate date = NULL)
    RETURNS TABLE (
        Holiday date,
        Market varchar
    )
    AS $$
DECLARE
BEGIN
    IF (_fromDate IS NULL) THEN
        _fromDate = date_trunc('year', now());
    END IF;
    IF (_toDate IS NULL) THEN
        _toDate = date_trunc('year', now()) + interval '1 year' - interval '1 day';
    END IF;
    RETURN QUERY
    SELECT
        h.Holiday,
        m.Market
    FROM
        public.Holidays h
        JOIN public.Markets m ON m.Id = h.MarketId
    WHERE
        h.Holiday >= _fromDate
        AND h.Holiday <= _toDate
    ORDER BY
        h.Holiday,
        m.Market;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION RetrieveAllMarkets ()
    RETURNS TABLE (
        Market varchar
    )
    AS $$
DECLARE
BEGIN
    RETURN QUERY
    SELECT
        m. Market
    FROM
        public.Markets m
    ORDER BY
        m.Market;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

COMMIT TRANSACTION;
