BEGIN TRANSACTION;

INSERT INTO fix.Entity (Code, Type, Name)
	VALUES ('${MarketOperator}', 'OR', '${MarketOperatorName}')
	ON CONFLICT DO NOTHING;

WITH Accounts AS (VALUES
	 ('${MarketOperator}', 'Zenith',  'client:Zenith${AuthSuffix}$Service',  'Zenith Data Services',        'FP')
	,('${MarketOperator}', 'Prodigy', 'client:Prodigy${AuthSuffix}$Control', 'Prodigy Market Control Tool', 'PI')
	,('${MarketOperator}', 'Foundry', 'client:Foundry${AuthSuffix}$Service', 'Foundry Registry Services',   'F')
	,('${MarketOperator}', 'OMS',     'client:OMS${AuthSuffix}$Service',     'Order Management Services',   'F')
), NewAccounts AS (
	INSERT INTO fix.Account (EntityID, Name, ExternalID, Description, Permissions)
		SELECT	EN.EntityID, AC.Name, AC.ExternalID, AC.Description, AC.Permissions
		FROM	Accounts AS AC (EntityCode, Name, ExternalID, Description, Permissions)
				JOIN fix.Entity EN ON AC.EntityCode = EN.Code
		ON CONFLICT DO NOTHING
		RETURNING AccountID, EntityID
)
INSERT INTO fix.AccountEntity (AccountID, EntityID)
	SELECT	AccountID, EntityID
	FROM	NewAccounts AS NA (AccountID, EntityID)
	ON CONFLICT DO NOTHING;

WITH Sessions AS (VALUES
	 ('${MarketOperator}', 'Zenith',  'FIXT.1.1', 'XOSP', '${MarketOperator}/ZMD',   NULL, 'FIX50SP2', TRUE,  '{}')
	,('${MarketOperator}', 'OMS',     'FIXT.1.1', 'XOSP', '${MarketOperator}/OMS',   NULL, 'FIX50SP2', FALSE, '{"Settings":{"SnapshotOnRestore":"True"}}')
	,('${MarketOperator}', 'Foundry', 'FIXT.1.1', 'XOSP', '${MarketOperator}/FNDRY', NULL, 'FIX50SP2', FALSE, '{}')
)
INSERT INTO fix.Session (BeginString, Sender, Target, Qualifiers, ApplVerID, AccountID, IsTransient, Data)
	SELECT	SE.BeginString, SE.Sender, SE.Target, SE.Qualifiers, SE.ApplVerID, AC.AccountID, SE.IsTransient, DECODE(SE.Data, 'escape')
	FROM	Sessions AS SE (EntityCode, AccountName, BeginString, Sender, Target, Qualifiers, ApplVerID, IsTransient, Data)
			JOIN fix.Entity EN ON EN.Code = SE.EntityCode
			JOIN fix.Account AC ON EN.EntityID = AC.EntityID AND AC.Name = SE.AccountName
	ON CONFLICT DO NOTHING;
				
WITH SessionEntities AS (VALUES
	 ('${MarketOperator}', 'Zenith',  FALSE)
	,('${MarketOperator}', 'Foundry', FALSE)
	,('${MarketOperator}', 'OMS',     TRUE)
)
INSERT INTO fix.SessionEntity (SessionID, EntityID, CanTrade)
	SELECT	SE.SessionID, EN.EntityID, AE.CanTrade
	FROM	SessionEntities AS AE (EntityCode, AccountName, CanTrade)
			JOIN fix.Entity EN ON EN.Code = AE.EntityCode
			JOIN fix.Account AC ON EN.EntityID = AC.EntityID AND AC.Name = AE.AccountName
			JOIN fix.Session SE ON AC.AccountID = SE.AccountID
	ON CONFLICT DO NOTHING;

--WITH SessionMarkets AS (VALUES
--	 ('${MarketOperator}', 'Zenith',  '${MarketCode}', FALSE)
--	,('${MarketOperator}', 'Foundry', '${MarketCode}', FALSE)
--	,('${MarketOperator}', 'OMS',     '${MarketCode}', TRUE)
--)
--INSERT INTO fix.SessionMarket (SessionID, MarketCode, CanTrade)
--	SELECT	SE.SessionID, AE.Market, AE.CanTrade
--	FROM	SessionMarkets AS AE (EntityCode, AccountName, Market, CanTrade)
--			JOIN fix.Entity EN ON EN.Code = AE.EntityCode
--			JOIN fix.Account AC ON EN.EntityID = AC.EntityID AND AC.Name = AE.AccountName
--			JOIN fix.Session SE ON AC.AccountID = SE.AccountID
--	ON CONFLICT DO NOTHING;

COMMIT;