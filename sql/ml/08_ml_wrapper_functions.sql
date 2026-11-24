/*=============================================================================
  Ria Financial Intelligence Agent
  Step 8: ML Wrapper Functions and Agent Functions

  Execution Order: 8 of 9
  Description: SQL functions the Cortex Agent calls as tools. Each one reads
               the batch model scores written by notebooks/07_ml_models.py
               (the ANALYTICS.*_SCORES tables), joins the facts an analyst
               needs, and returns one OBJECT or a capped ARRAY so responses
               stay small. Scores are model predictions trained on synthetic
               data and every model function says so in its output.
               Parameter names match the agent tool input_schema property
               names. String filters ignore case and treat NULL, empty,
               'NULL' and 'ALL' as no filter. Empty results return counts of
               zero and an empty array, never NULL.
=============================================================================*/

USE DATABASE RIA_FINANCIAL_INTELLIGENCE;
USE SCHEMA ANALYTICS;
USE WAREHOUSE RIA_FINANCIAL_WH;

-- ---------------------------------------------------------------------------
-- Overview
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_FRAUD_OVERVIEW()
RETURNS OBJECT
AS
$$
SELECT OBJECT_CONSTRUCT(
    'as_of', CURRENT_DATE()::VARCHAR,
    'transfers_30d', (SELECT COUNT(*) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS WHERE CREATED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'send_volume_30d_usd', (SELECT ROUND(COALESCE(SUM(SEND_AMOUNT_USD), 0), 0) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS WHERE CREATED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'confirmed_fraud_rate_pct_30d', (SELECT ROUND(100 * DIV0(COUNT_IF(IS_FRAUD), COUNT(*)), 3) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS WHERE CREATED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'net_fraud_loss_usd_90d', (SELECT ROUND(COALESCE(SUM(NET_LOSS_USD), 0), 0) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_LOSSES WHERE LOSS_DATE >= DATEADD(DAY, -90, CURRENT_DATE())),
    'recovered_usd_90d', (SELECT ROUND(COALESCE(SUM(RECOVERED_USD), 0), 0) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_LOSSES WHERE LOSS_DATE >= DATEADD(DAY, -90, CURRENT_DATE())),
    'open_alerts', (SELECT COUNT_IF(STATUS <> 'Closed') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_ALERTS),
    'open_alerts_over_30_days', (SELECT COUNT_IF(STATUS <> 'Closed' AND CREATED_AT < DATEADD(DAY, -30, CURRENT_TIMESTAMP())) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_ALERTS),
    'unassigned_open_alerts', (SELECT COUNT_IF(STATUS <> 'Closed' AND ASSIGNED_ANALYST_ID IS NULL) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_ALERTS),
    'open_alerts_by_queue', (SELECT COALESCE(OBJECT_AGG(QUEUE, N), OBJECT_CONSTRUCT()) FROM (SELECT QUEUE, COUNT(*) AS N FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_ALERTS WHERE STATUS <> 'Closed' GROUP BY QUEUE)),
    'open_cases', (SELECT COUNT_IF(STATUS <> 'Closed') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_CASES),
    'cases_pending_sar_decision', (SELECT COUNT_IF(STATUS = 'Pending SAR Decision') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_CASES),
    'chargebacks_30d', (SELECT COUNT(*) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.CHARGEBACKS WHERE RECEIVED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'chargeback_usd_30d', (SELECT ROUND(COALESCE(SUM(AMOUNT_USD), 0), 0) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.CHARGEBACKS WHERE RECEIVED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'unauthorized_ach_returns_30d', (SELECT COUNT_IF(IS_UNAUTHORIZED) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.ACH_RETURNS WHERE RETURNED_AT >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())),
    'open_screening_hits', (SELECT COUNT_IF(STATUS = 'Open') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.SANCTIONS_SCREENING),
    'sar_unfiled', (SELECT COUNT_IF(FILED_DATE IS NULL) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.SAR_FILINGS),
    'sar_at_risk_next_10_days', (SELECT COUNT_IF(FILED_DATE IS NULL AND DUE_DATE BETWEEN CURRENT_DATE() AND DATEADD(DAY, 10, CURRENT_DATE())) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.SAR_FILINGS),
    'sar_overdue', (SELECT COUNT_IF(FILED_DATE IS NULL AND DUE_DATE < CURRENT_DATE()) FROM RIA_FINANCIAL_INTELLIGENCE.RAW.SAR_FILINGS),
    'ctr_pending', (SELECT COUNT_IF(FILING_STATUS = 'Pending') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.CTR_FILINGS),
    'reg_e_disputes_open', (SELECT COUNT_IF(STATUS <> 'Resolved') FROM RIA_FINANCIAL_INTELLIGENCE.RAW.DISPUTES),
    'high_collusion_risk_agents', (SELECT COUNT_IF(RISK_TIER = 'High') FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_COLLUSION_SCORES),
    'models_past_validation_date', (SELECT COUNT_IF(NEXT_VALIDATION_DATE < CURRENT_DATE()) FROM RIA_FINANCIAL_INTELLIGENCE.ML.MODEL_REGISTRY),
    'note', 'Counts are from operational tables. Risk tiers elsewhere come from models trained on synthetic data.')
$$;

-- ---------------------------------------------------------------------------
-- Model 1: transaction fraud
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_TRANSACTION_FRAUD_SCORE(DAYS_BACK NUMBER, TRANSFER_ID_FILTER VARCHAR)
RETURNS OBJECT
AS
$$
WITH f AS (
    SELECT s.TRANSFER_ID, s.CUSTOMER_ID, s.CREATED_AT, s.FRAUD_PROB, s.RISK_TIER, t.CORRIDOR_ID, t.CHANNEL, t.FUNDING_TYPE, t.SEND_AMOUNT_USD, t.STATUS, t.IS_FRAUD
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.TRANSFER_FRAUD_SCORES s
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS t ON t.TRANSFER_ID = s.TRANSFER_ID
    WHERE IFF(TRANSFER_ID_FILTER IS NULL OR TRIM(TRANSFER_ID_FILTER) IN ('', 'NULL', 'ALL'),
              s.CREATED_AT >= DATEADD(DAY, -1 * COALESCE(DAYS_BACK, 7), CURRENT_TIMESTAMP()),
              s.TRANSFER_ID = UPPER(TRIM(TRANSFER_ID_FILTER)))
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_TRANSACTION_FRAUD (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'window_days', COALESCE(DAYS_BACK, 7),
    'scored_transfers', COUNT(*),
    'high_tier', COUNT_IF(RISK_TIER = 'High'), 'medium_tier', COUNT_IF(RISK_TIER = 'Medium'),
    'high_tier_volume_usd', ROUND(COALESCE(SUM(IFF(RISK_TIER = 'High', SEND_AMOUNT_USD, 0)), 0), 0),
    'top_transfers', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('transfer_id', TRANSFER_ID, 'customer_id', CUSTOMER_ID, 'created_at', CREATED_AT::VARCHAR,
            'fraud_probability', ROUND(FRAUD_PROB, 4), 'risk_tier', RISK_TIER, 'amount_usd', SEND_AMOUNT_USD, 'corridor', CORRIDOR_ID, 'channel', CHANNEL,
            'funding_type', FUNDING_TYPE, 'status', STATUS, 'confirmed_fraud', IS_FRAUD)) WITHIN GROUP (ORDER BY FRAUD_PROB DESC)
        FROM (SELECT * FROM f ORDER BY FRAUD_PROB DESC LIMIT 15)), ARRAY_CONSTRUCT()))
FROM f
$$;

-- ---------------------------------------------------------------------------
-- Model 2: account takeover
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_ACCOUNT_TAKEOVER_RISK(DAYS_BACK NUMBER)
RETURNS OBJECT
AS
$$
WITH w AS (
    SELECT s.CUSTOMER_ID, s.SESSION_ID, s.LOGIN_AT, s.ATO_PROB, s.RISK_TIER, ds.IP_COUNTRY, ds.IS_NEW_DEVICE, ds.FAILED_ATTEMPTS, ds.PASSWORD_RESET_24H, ds.BENEFICIARY_ADDED
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.ATO_SESSION_SCORES s
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.APP_SESSIONS ds ON ds.SESSION_ID = s.SESSION_ID
    WHERE s.LOGIN_AT >= DATEADD(DAY, -1 * COALESCE(DAYS_BACK, 7), CURRENT_TIMESTAMP())
),
c AS (
    SELECT CUSTOMER_ID, MAX(ATO_PROB) AS MAX_PROB, COUNT(*) AS SESSIONS, MAX_BY(RISK_TIER, ATO_PROB) AS TIER, MAX_BY(SESSION_ID, ATO_PROB) AS TOP_SESSION,
           MAX_BY(IP_COUNTRY, ATO_PROB) AS IP_COUNTRY, MAX_BY(IS_NEW_DEVICE, ATO_PROB) AS NEW_DEVICE, MAX_BY(FAILED_ATTEMPTS, ATO_PROB) AS FAILED,
           MAX_BY(PASSWORD_RESET_24H, ATO_PROB) AS PW_RESET, MAX_BY(BENEFICIARY_ADDED, ATO_PROB) AS BENE_ADDED, MAX(LOGIN_AT) AS LAST_LOGIN
    FROM w GROUP BY CUSTOMER_ID
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_ACCOUNT_TAKEOVER (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'window_days', COALESCE(DAYS_BACK, 7),
    'customers_scored', COUNT(*), 'high_tier_customers', COUNT_IF(TIER = 'High'), 'medium_tier_customers', COUNT_IF(TIER = 'Medium'),
    'top_customers', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('customer_id', CUSTOMER_ID, 'max_ato_probability', ROUND(MAX_PROB, 4), 'risk_tier', TIER,
            'sessions_in_window', SESSIONS, 'top_session', TOP_SESSION, 'ip_country', IP_COUNTRY, 'new_device', NEW_DEVICE, 'failed_attempts', FAILED,
            'password_reset_24h', PW_RESET, 'beneficiary_added', BENE_ADDED, 'last_login', LAST_LOGIN::VARCHAR)) WITHIN GROUP (ORDER BY MAX_PROB DESC)
        FROM (SELECT * FROM c ORDER BY MAX_PROB DESC LIMIT 15)), ARRAY_CONSTRUCT()))
FROM c
$$;

-- ---------------------------------------------------------------------------
-- Model 3: synthetic identity
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_SYNTHETIC_IDENTITY_RISK(DAYS_BACK NUMBER)
RETURNS OBJECT
AS
$$
WITH n AS (
    SELECT s.CUSTOMER_ID, s.SIGNUP_DATE, s.SYNTHETIC_PROB, s.RISK_TIER, k.EMAIL_AGE_DAYS, k.PHONE_IS_VOIP, k.ADDRESS_SHARED_COUNT, k.ID_VERIFICATION_ATTEMPTS, k.ID_VERIFICATION_STATUS
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.SYNTHETIC_ID_SCORES s
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.KYC_PROFILES k ON k.CUSTOMER_ID = s.CUSTOMER_ID
    WHERE s.SIGNUP_DATE >= DATEADD(DAY, -1 * COALESCE(DAYS_BACK, 30), CURRENT_DATE())
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_SYNTHETIC_IDENTITY (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'window_days', COALESCE(DAYS_BACK, 30),
    'new_signups_scored', COUNT(*),
    'likely_synthetic_high_tier', COUNT_IF(RISK_TIER = 'High'),
    'possible_synthetic_medium_tier', COUNT_IF(RISK_TIER = 'Medium'),
    'expected_synthetic_count', ROUND(COALESCE(SUM(SYNTHETIC_PROB), 0), 1),
    'pct_signups_high_or_medium', ROUND(100 * DIV0(COUNT_IF(RISK_TIER IN ('High', 'Medium')), COUNT(*)), 1),
    'top_customers', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('customer_id', CUSTOMER_ID, 'signup_date', SIGNUP_DATE::VARCHAR, 'synthetic_probability', ROUND(SYNTHETIC_PROB, 4),
            'risk_tier', RISK_TIER, 'email_age_days', EMAIL_AGE_DAYS, 'voip_phone', PHONE_IS_VOIP, 'address_shared_with', ADDRESS_SHARED_COUNT,
            'id_attempts', ID_VERIFICATION_ATTEMPTS, 'id_status', ID_VERIFICATION_STATUS)) WITHIN GROUP (ORDER BY SYNTHETIC_PROB DESC)
        FROM (SELECT * FROM n ORDER BY SYNTHETIC_PROB DESC LIMIT 10)), ARRAY_CONSTRUCT()))
FROM n
$$;

-- ---------------------------------------------------------------------------
-- Model 4: money mule beneficiaries
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_MULE_BENEFICIARIES(TOP_N NUMBER)
RETURNS OBJECT
AS
$$
WITH r AS (
    SELECT t.BENEFICIARY_ID, COUNT(*) AS TRANSFERS_RECEIVED, COUNT(DISTINCT t.CUSTOMER_ID) AS DISTINCT_SENDERS, SUM(t.SEND_AMOUNT_USD) AS TOTAL_RECEIVED_USD,
           MIN(t.CREATED_AT) AS FIRST_RECEIVED, MAX(t.CREATED_AT) AS LAST_RECEIVED
    FROM RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS t GROUP BY t.BENEFICIARY_ID
),
m AS (
    SELECT s.BENEFICIARY_ID, s.MULE_PROB, s.RISK_TIER, b.COUNTRY, b.RELATIONSHIP, b.PREFERRED_PAYOUT_METHOD, r.TRANSFERS_RECEIVED, r.DISTINCT_SENDERS, r.TOTAL_RECEIVED_USD,
           r.FIRST_RECEIVED, r.LAST_RECEIVED
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.MULE_SCORES s
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.BENEFICIARIES b ON b.BENEFICIARY_ID = s.BENEFICIARY_ID
    JOIN r ON r.BENEFICIARY_ID = s.BENEFICIARY_ID
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_MULE_BENEFICIARY (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'beneficiaries_scored', COUNT(*), 'high_tier_beneficiaries', COUNT_IF(RISK_TIER = 'High'), 'medium_tier_beneficiaries', COUNT_IF(RISK_TIER = 'Medium'),
    'high_tier_total_received_usd', ROUND(COALESCE(SUM(IFF(RISK_TIER = 'High', TOTAL_RECEIVED_USD, 0)), 0), 0),
    'top_beneficiaries', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('beneficiary_id', BENEFICIARY_ID, 'mule_probability', ROUND(MULE_PROB, 4), 'risk_tier', RISK_TIER,
            'country', COUNTRY, 'declared_relationship', RELATIONSHIP, 'payout_method', PREFERRED_PAYOUT_METHOD, 'transfers_received', TRANSFERS_RECEIVED,
            'distinct_senders', DISTINCT_SENDERS, 'total_received_usd', ROUND(TOTAL_RECEIVED_USD, 0), 'first_received', FIRST_RECEIVED::VARCHAR,
            'last_received', LAST_RECEIVED::VARCHAR)) WITHIN GROUP (ORDER BY MULE_PROB DESC)
        FROM (SELECT * FROM m QUALIFY ROW_NUMBER() OVER (ORDER BY MULE_PROB DESC) <= LEAST(GREATEST(COALESCE(TOP_N, 10), 1), 25))), ARRAY_CONSTRUCT()))
FROM m
$$;

-- ---------------------------------------------------------------------------
-- Model 5: structuring
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_STRUCTURING_ALERTS(WEEKS_BACK NUMBER)
RETURNS OBJECT
AS
$$
WITH s AS (
    SELECT CUSTOMER_ID, WEEK_START, STRUCTURING_PROB, RISK_TIER
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.STRUCTURING_SCORES
    WHERE WEEK_START >= DATEADD(WEEK, -1 * COALESCE(WEEKS_BACK, 4), CURRENT_DATE())
),
w AS (
    SELECT t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE AS WEEK_START, COUNT(*) AS TRANSFERS, SUM(t.SEND_AMOUNT_USD) AS WEEK_TOTAL_USD, MAX(t.SEND_AMOUNT_USD) AS MAX_TRANSFER_USD,
           COUNT_IF(t.SEND_AMOUNT_USD BETWEEN 2500 AND 2999.99) AS NEAR_3K_COUNT, COUNT_IF(t.SEND_AMOUNT_USD BETWEEN 8500 AND 9999.99) AS NEAR_10K_COUNT,
           AVG(IFF(t.FUNDING_TYPE = 'Cash', 1, 0)) AS CASH_SHARE
    FROM RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS t
    WHERE t.CREATED_AT >= DATEADD(WEEK, -1 * (COALESCE(WEEKS_BACK, 4) + 1), CURRENT_DATE()) AND t.STATUS <> 'Cancelled'
    GROUP BY t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE
),
j AS (
    SELECT s.CUSTOMER_ID, s.WEEK_START, s.STRUCTURING_PROB, s.RISK_TIER, w.TRANSFERS, w.WEEK_TOTAL_USD, w.MAX_TRANSFER_USD, w.NEAR_3K_COUNT, w.NEAR_10K_COUNT, w.CASH_SHARE
    FROM s JOIN w ON w.CUSTOMER_ID = s.CUSTOMER_ID AND w.WEEK_START = s.WEEK_START
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_STRUCTURING (XGBoost). Probabilities are model predictions trained on synthetic data. CTR threshold is $10,000; Travel Rule threshold is $3,000.',
    'window_weeks', COALESCE(WEEKS_BACK, 4),
    'customer_weeks_scored', COUNT(*), 'high_tier_customer_weeks', COUNT_IF(RISK_TIER = 'High'), 'medium_tier_customer_weeks', COUNT_IF(RISK_TIER = 'Medium'),
    'distinct_high_tier_customers', COUNT(DISTINCT IFF(RISK_TIER = 'High', CUSTOMER_ID, NULL)),
    'top_customer_weeks', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('customer_id', CUSTOMER_ID, 'week_start', WEEK_START::VARCHAR, 'structuring_probability', ROUND(STRUCTURING_PROB, 4),
            'risk_tier', RISK_TIER, 'transfers', TRANSFERS, 'week_total_usd', ROUND(WEEK_TOTAL_USD, 0), 'largest_transfer_usd', MAX_TRANSFER_USD,
            'transfers_just_under_3k', NEAR_3K_COUNT, 'transfers_just_under_10k', NEAR_10K_COUNT, 'cash_share', ROUND(CASH_SHARE, 2))) WITHIN GROUP (ORDER BY STRUCTURING_PROB DESC)
        FROM (SELECT * FROM j ORDER BY STRUCTURING_PROB DESC LIMIT 15)), ARRAY_CONSTRUCT()))
FROM j
$$;

-- ---------------------------------------------------------------------------
-- Model 6: agent collusion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_AGENT_COLLUSION_RISK(TOP_N NUMBER)
RETURNS OBJECT
AS
$$
WITH a AS (
    SELECT n.AGENT_ID, n.AGENT_NAME, n.AGENT_TYPE, n.COUNTRY, n.CITY, n.STATUS, n.AUDIT_RATING, n.TRAINING_COMPLETED, n.DAYS_SINCE_AUDIT, n.SEND_TRANSFERS_90D,
           n.SEND_VOLUME_90D_USD, n.NEAR_THRESHOLD_SHARE_PCT, n.CANCELLATION_RATE_PCT, n.COLLUSION_PROBABILITY, n.COLLUSION_RISK_TIER, n.CONFIRMED_COLLUSION
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_NETWORK n WHERE n.COLLUSION_PROBABILITY IS NOT NULL
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_AGENT_COLLUSION (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'locations_scored', COUNT(*), 'high_tier_locations', COUNT_IF(COLLUSION_RISK_TIER = 'High'), 'medium_tier_locations', COUNT_IF(COLLUSION_RISK_TIER = 'Medium'),
    'top_locations', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('agent_id', AGENT_ID, 'agent_name', AGENT_NAME, 'agent_type', AGENT_TYPE, 'country', COUNTRY, 'city', CITY,
            'agent_status', STATUS, 'collusion_probability', ROUND(COLLUSION_PROBABILITY, 4), 'risk_tier', COLLUSION_RISK_TIER, 'audit_rating', AUDIT_RATING,
            'aml_training_complete', TRAINING_COMPLETED, 'days_since_audit', DAYS_SINCE_AUDIT, 'send_transfers_90d', SEND_TRANSFERS_90D,
            'send_volume_90d_usd', ROUND(SEND_VOLUME_90D_USD, 0), 'pct_sends_just_under_thresholds', ROUND(NEAR_THRESHOLD_SHARE_PCT, 1),
            'cancellation_rate_pct', ROUND(CANCELLATION_RATE_PCT, 1), 'confirmed_collusion', CONFIRMED_COLLUSION)) WITHIN GROUP (ORDER BY COLLUSION_PROBABILITY DESC)
        FROM (SELECT * FROM a QUALIFY ROW_NUMBER() OVER (ORDER BY COLLUSION_PROBABILITY DESC) <= LEAST(GREATEST(COALESCE(TOP_N, 10), 1), 25))), ARRAY_CONSTRUCT()))
FROM a
$$;

-- ---------------------------------------------------------------------------
-- Model 7: chargeback risk
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_CHARGEBACK_RISK(DAYS_BACK NUMBER)
RETURNS OBJECT
AS
$$
WITH c AS (
    SELECT s.TRANSFER_ID, s.CUSTOMER_ID, s.CREATED_AT, s.AMOUNT_USD, s.CHARGEBACK_PROB, s.EXPECTED_CHARGEBACK_USD, s.RISK_TIER, t.FUNDING_TYPE, t.CORRIDOR_ID, t.CHANNEL
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.CHARGEBACK_SCORES s
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS t ON t.TRANSFER_ID = s.TRANSFER_ID
    WHERE s.CREATED_AT >= DATEADD(DAY, -1 * COALESCE(DAYS_BACK, 30), CURRENT_TIMESTAMP())
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_CHARGEBACK_RISK (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'window_days', COALESCE(DAYS_BACK, 30),
    'card_funded_transfers_scored', COUNT(*), 'card_volume_usd', ROUND(COALESCE(SUM(AMOUNT_USD), 0), 0),
    'predicted_chargeback_exposure_usd', ROUND(COALESCE(SUM(EXPECTED_CHARGEBACK_USD), 0), 0),
    'expected_chargeback_count', ROUND(COALESCE(SUM(CHARGEBACK_PROB), 0), 1),
    'high_tier_transfers', COUNT_IF(RISK_TIER = 'High'), 'high_tier_exposure_usd', ROUND(COALESCE(SUM(IFF(RISK_TIER = 'High', EXPECTED_CHARGEBACK_USD, 0)), 0), 0),
    'exposure_by_funding_type', COALESCE((SELECT OBJECT_AGG(FUNDING_TYPE, ROUND(E, 0)) FROM (SELECT FUNDING_TYPE, SUM(EXPECTED_CHARGEBACK_USD) AS E FROM c GROUP BY FUNDING_TYPE)), OBJECT_CONSTRUCT()),
    'top_transfers', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('transfer_id', TRANSFER_ID, 'customer_id', CUSTOMER_ID, 'created_at', CREATED_AT::VARCHAR, 'amount_usd', AMOUNT_USD,
            'chargeback_probability', ROUND(CHARGEBACK_PROB, 4), 'expected_chargeback_usd', ROUND(EXPECTED_CHARGEBACK_USD, 2), 'risk_tier', RISK_TIER, 'funding_type', FUNDING_TYPE,
            'corridor', CORRIDOR_ID, 'channel', CHANNEL)) WITHIN GROUP (ORDER BY EXPECTED_CHARGEBACK_USD DESC)
        FROM (SELECT * FROM c ORDER BY EXPECTED_CHARGEBACK_USD DESC LIMIT 10)), ARRAY_CONSTRUCT()))
FROM c
$$;

-- ---------------------------------------------------------------------------
-- Model 8: scam victim
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_SCAM_VICTIM_ALERTS(DAYS_BACK NUMBER)
RETURNS OBJECT
AS
$$
WITH s AS (
    SELECT sc.TRANSFER_ID, sc.CUSTOMER_ID, sc.CREATED_AT, sc.SCAM_PROB, sc.RISK_TIER, t.SEND_AMOUNT_USD, t.CORRIDOR_ID, t.PURPOSE, t.FUNDING_TYPE, t.CHANNEL, p.AGE_BAND
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.SCAM_SCORES sc
    JOIN RIA_FINANCIAL_INTELLIGENCE.RAW.TRANSFERS t ON t.TRANSFER_ID = sc.TRANSFER_ID
    JOIN RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.CUSTOMER_PROFILE p ON p.CUSTOMER_ID = sc.CUSTOMER_ID
    WHERE sc.CREATED_AT >= DATEADD(DAY, -1 * COALESCE(DAYS_BACK, 14), CURRENT_TIMESTAMP())
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_SCAM_VICTIM (XGBoost). Probabilities are model predictions trained on synthetic data.',
    'window_days', COALESCE(DAYS_BACK, 14),
    'transfers_scored', COUNT(*), 'high_tier_transfers', COUNT_IF(RISK_TIER = 'High'), 'medium_tier_transfers', COUNT_IF(RISK_TIER = 'Medium'),
    'high_tier_volume_usd', ROUND(COALESCE(SUM(IFF(RISK_TIER = 'High', SEND_AMOUNT_USD, 0)), 0), 0),
    'top_transfers', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('transfer_id', TRANSFER_ID, 'customer_id', CUSTOMER_ID, 'created_at', CREATED_AT::VARCHAR,
            'scam_probability', ROUND(SCAM_PROB, 4), 'risk_tier', RISK_TIER, 'amount_usd', SEND_AMOUNT_USD, 'corridor', CORRIDOR_ID, 'purpose', PURPOSE,
            'funding_type', FUNDING_TYPE, 'channel', CHANNEL, 'sender_age_band', AGE_BAND)) WITHIN GROUP (ORDER BY SCAM_PROB DESC)
        FROM (SELECT * FROM s ORDER BY SCAM_PROB DESC LIMIT 15)), ARRAY_CONSTRUCT()))
FROM s
$$;

-- ---------------------------------------------------------------------------
-- Model 9: fraud rings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_FRAUD_RINGS(TOP_N NUMBER)
RETURNS OBJECT
AS
$$
WITH r AS (SELECT * FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.FRAUD_RING_CLUSTERS)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_FRAUD_RING_ANOMALY (isolation forest, unsupervised). Scores are model predictions trained on synthetic data. Clusters are accounts sharing a phone number.',
    'clusters_of_3_or_more_accounts', COUNT(*), 'accounts_in_those_clusters', COALESCE(SUM(ACCOUNTS_LINKED), 0),
    'clusters_in_high_tier', COUNT_IF(CLUSTER_RISK_TIER = 'High'),
    'top_clusters', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('cluster_id', CLUSTER_ID, 'accounts_linked', ACCOUNTS_LINKED, 'cluster_anomaly_score', ROUND(CLUSTER_ANOMALY_SCORE, 3),
            'risk_tier', CLUSTER_RISK_TIER, 'volume_90d_usd', ROUND(VOLUME_90D_USD, 0), 'volume_all_time_usd', ROUND(VOLUME_ALL_USD, 0), 'open_cases', OPEN_CASES,
            'fraud_ring_cases', RING_CASES, 'sample_member_customer_ids', LEFT(MEMBER_CUSTOMER_IDS, 110))) WITHIN GROUP (ORDER BY ACCOUNTS_LINKED DESC, CLUSTER_ANOMALY_SCORE DESC)
        FROM (SELECT * FROM r QUALIFY ROW_NUMBER() OVER (ORDER BY ACCOUNTS_LINKED DESC, CLUSTER_ANOMALY_SCORE DESC) <= LEAST(GREATEST(COALESCE(TOP_N, 10), 1), 20))), ARRAY_CONSTRUCT()))
FROM r
$$;

-- ---------------------------------------------------------------------------
-- Model 10: sanctions screening triage
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_SCREENING_TRIAGE(TOP_N NUMBER)
RETURNS OBJECT
AS
$$
WITH h AS (
    SELECT sd.SCREENING_ID, sd.TRANSFER_ID, sd.CUSTOMER_ID, sd.SCREENED_PARTY, sd.LIST_SOURCE, sd.MATCH_SCORE, sd.NAME_SIMILARITY, sd.DOB_MATCH, sd.COUNTRY_MATCH,
           sd.SECONDARY_ID_MATCH, sd.SEND_AMOUNT_USD, sd.PAYOUT_COUNTRY, sd.SCREENED_AT, sd.TRUE_MATCH_PROBABILITY, sd.TRIAGE_TIER,
           DATEDIFF(HOUR, sd.SCREENED_AT, CURRENT_TIMESTAMP()) AS HOURS_OPEN
    FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.SCREENING_DETAIL sd WHERE sd.IS_OPEN AND sd.TRUE_MATCH_PROBABILITY IS NOT NULL
)
SELECT OBJECT_CONSTRUCT(
    'model', 'RIA_SCREENING_TRIAGE (XGBoost). Probabilities are model predictions trained on synthetic data. A hit must never be auto-cleared from a model score.',
    'open_hits', COUNT(*), 'high_tier_open_hits', COUNT_IF(TRIAGE_TIER = 'High'), 'medium_tier_open_hits', COUNT_IF(TRIAGE_TIER = 'Medium'),
    'open_value_usd', ROUND(COALESCE(SUM(SEND_AMOUNT_USD), 0), 0),
    'work_first', COALESCE((SELECT ARRAY_AGG(OBJECT_CONSTRUCT('screening_id', SCREENING_ID, 'transfer_id', TRANSFER_ID, 'customer_id', CUSTOMER_ID, 'screened_party', SCREENED_PARTY,
            'list_source', LIST_SOURCE, 'true_match_probability', ROUND(TRUE_MATCH_PROBABILITY, 4), 'triage_tier', TRIAGE_TIER, 'match_score', MATCH_SCORE,
            'name_similarity', NAME_SIMILARITY, 'dob_match', DOB_MATCH, 'country_match', COUNTRY_MATCH, 'secondary_id_match', SECONDARY_ID_MATCH,
            'amount_usd', SEND_AMOUNT_USD, 'payout_country', PAYOUT_COUNTRY, 'hours_open', HOURS_OPEN)) WITHIN GROUP (ORDER BY TRUE_MATCH_PROBABILITY DESC)
        FROM (SELECT * FROM h QUALIFY ROW_NUMBER() OVER (ORDER BY TRUE_MATCH_PROBABILITY DESC) <= LEAST(GREATEST(COALESCE(TOP_N, 10), 1), 25))), ARRAY_CONSTRUCT()))
FROM h
$$;

-- ---------------------------------------------------------------------------
-- Model registry (SR 11-7 inventory)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_MODEL_REGISTRY()
RETURNS OBJECT
AS
$$
SELECT OBJECT_CONSTRUCT(
    'models', COUNT(*),
    'past_validation_date', COUNT_IF(NEXT_VALIDATION_DATE < CURRENT_DATE()),
    'pending_validation', COUNT_IF(VALIDATION_STATUS = 'Pending Validation'),
    'note', 'All 10 models are trained on synthetic data. Metrics are not production performance. Validation dates are demonstration governance values.',
    'inventory', COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('model_id', MODEL_ID, 'model_name', MODEL_NAME, 'algorithm', ALGORITHM, 'target', TARGET, 'version', VERSION,
            'owner', MODEL_OWNER, 'training_date', TRAINING_DATE::VARCHAR, 'training_rows', TRAINING_ROWS, 'positive_rate_pct', ROUND(100 * POSITIVE_RATE, 2),
            'roc_auc', ROUND(ROC_AUC, 3), 'pr_auc', ROUND(PR_AUC, 3), 'validation_status', VALIDATION_STATUS, 'last_validation_date', LAST_VALIDATION_DATE::VARCHAR,
            'next_validation_date', NEXT_VALIDATION_DATE::VARCHAR, 'past_validation_date', NEXT_VALIDATION_DATE < CURRENT_DATE(),
            'days_past_due', GREATEST(0, DATEDIFF(DAY, NEXT_VALIDATION_DATE, CURRENT_DATE())), 'intended_use', INTENDED_USE, 'agent_tool', AGENT_TOOL))
        WITHIN GROUP (ORDER BY MODEL_ID), ARRAY_CONSTRUCT()))
FROM RIA_FINANCIAL_INTELLIGENCE.ML.MODEL_REGISTRY
$$;

-- ---------------------------------------------------------------------------
-- Customer 360 brief for one customer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION AGENT_GET_CUSTOMER_360(CUSTOMER_ID_FILTER VARCHAR)
RETURNS OBJECT
AS
$$
SELECT OBJECT_CONSTRUCT(
    'customer_id', c.CUSTOMER_ID, 'customer_masked', c.CUSTOMER_NAME_MASKED, 'age_band', c.AGE_BAND, 'country', c.COUNTRY_OF_RESIDENCE, 'segment', c.SEGMENT,
    'loyalty_tier', c.LOYALTY_TIER, 'customer_status', c.CUSTOMER_STATUS, 'signup_date', c.SIGNUP_DATE::VARCHAR, 'tenure_days', c.TENURE_DAYS,
    'preferred_corridor', c.PREFERRED_CORRIDOR_NAME,
    'kyc_risk_rating', c.KYC_RISK_RATING, 'pep', c.PEP_FLAG, 'edd_required', c.EDD_REQUIRED, 'edd_completed', c.EDD_COMPLETED,
    'id_verification_status', c.ID_VERIFICATION_STATUS, 'next_kyc_review', c.NEXT_REVIEW_DATE::VARCHAR,
    'lifetime_transfers', c.LIFETIME_TRANSFERS, 'lifetime_value_usd', ROUND(c.LIFETIME_VALUE_USD, 2), 'transfers_90d', c.TRANSFERS_90D, 'volume_90d_usd', ROUND(c.VOLUME_90D_USD, 0),
    'avg_transfer_usd', ROUND(c.AVG_TRANSFER_USD, 2), 'transfers_per_month', c.TRANSFERS_PER_MONTH, 'days_since_last_transfer', c.DAYS_SINCE_LAST_TRANSFER,
    'recency_status_rule_based', c.RECENCY_STATUS,
    'open_alerts', c.OPEN_ALERTS, 'open_cases', c.OPEN_CASES, 'total_cases', c.TOTAL_CASES,
    'complaints_total', c.COMPLAINTS_TOTAL, 'complaints_90d', c.COMPLAINTS_90D, 'open_complaints', c.OPEN_COMPLAINTS,
    'latest_nps', c.LATEST_NPS, 'avg_nps', c.AVG_NPS, 'latest_nps_category', c.LATEST_NPS_CATEGORY,
    'model_scores', OBJECT_CONSTRUCT('note', 'Model predictions trained on synthetic data',
        'synthetic_identity_probability', ROUND(m.SYNTHETIC_ID_PROBABILITY, 4), 'synthetic_identity_tier', m.SYNTHETIC_ID_TIER,
        'account_takeover_max_probability_30d', ROUND(m.ATO_MAX_PROBABILITY_30D, 4), 'account_takeover_tier_30d', m.ATO_TIER_30D,
        'transaction_fraud_max_probability_90d', ROUND(m.TRANSFER_FRAUD_MAX_PROBABILITY_90D, 4), 'transaction_fraud_tier_90d', m.TRANSFER_FRAUD_TIER_90D,
        'structuring_max_probability_8w', ROUND(m.STRUCTURING_MAX_PROBABILITY_8W, 4), 'structuring_tier_8w', m.STRUCTURING_TIER_8W,
        'ring_anomaly_score', ROUND(m.RING_ANOMALY_SCORE, 3), 'ring_cluster_id', m.RING_CLUSTER_ID, 'ring_cluster_size', m.RING_CLUSTER_SIZE, 'ring_tier', m.RING_TIER,
        'composite_model_risk_tier', m.COMPOSITE_MODEL_RISK_TIER),
    'fraud_history', OBJECT_CONSTRUCT('confirmed_fraud_transfers', f.CONFIRMED_FRAUD_TRANSFERS, 'confirmed_fraud_usd', ROUND(f.CONFIRMED_FRAUD_USD, 0),
        'net_loss_usd', ROUND(f.NET_LOSS_USD, 0), 'chargebacks', f.CHARGEBACKS, 'ach_returns', f.ACH_RETURNS, 'screening_hits', f.SCREENING_HITS,
        'open_screening_hits', f.OPEN_SCREENING_HITS),
    'open_alerts_detail', (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('alert_id', ALERT_ID, 'type', ALERT_TYPE, 'severity', SEVERITY, 'status', STATUS, 'queue', QUEUE,
            'created_at', CREATED_AT::VARCHAR)) WITHIN GROUP (ORDER BY CREATED_AT DESC), ARRAY_CONSTRUCT())
        FROM (SELECT * FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_ALERTS WHERE CUSTOMER_ID = UPPER(TRIM(CUSTOMER_ID_FILTER)) AND STATUS <> 'Closed' ORDER BY CREATED_AT DESC LIMIT 5)),
    'open_cases_detail', (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('case_id', CASE_ID, 'type', CASE_TYPE, 'priority', PRIORITY, 'status', STATUS, 'exposure_usd', EXPOSURE_USD,
            'opened_at', OPENED_AT::VARCHAR)) WITHIN GROUP (ORDER BY OPENED_AT DESC), ARRAY_CONSTRUCT())
        FROM (SELECT * FROM RIA_FINANCIAL_INTELLIGENCE.RAW.FRAUD_CASES WHERE CUSTOMER_ID = UPPER(TRIM(CUSTOMER_ID_FILTER)) AND STATUS <> 'Closed' ORDER BY OPENED_AT DESC LIMIT 5))
)
FROM RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.CUSTOMER_360 c
JOIN RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.FRAUD_360 f ON f.CUSTOMER_ID = c.CUSTOMER_ID
JOIN RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.CUSTOMER_MODEL_SCORES m ON m.CUSTOMER_ID = c.CUSTOMER_ID
WHERE c.CUSTOMER_ID = UPPER(TRIM(CUSTOMER_ID_FILTER))
$$;
