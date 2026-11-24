/*=============================================================================
  Ria Financial Intelligence Agent
  Step 3: Synthetic Data Generation

  Execution Order: 3 of 9
  Description: Generates correlated synthetic data for cross-border money
               transfer fraud and compliance. Each of 40,000 customers gets a
               hidden profile (NORMAL / SYN / ATO / CARD / RING / STRUCT / SCAM)
               that drives transfers, sessions, devices, funding sources,
               alerts, cases, losses and screening, so the ML models have real
               but noisy signal. Fraud is about 0.8 percent of transfers.
               Label columns (IS_FRAUD, CONFIRMED_*, IS_ACCOUNT_TAKEOVER and so
               on) are investigation outcomes used only as ML targets.
               Roughly 1.2 million transfers; allow about two minutes on a
               MEDIUM warehouse.
               Safe to re-run: every RAW table is truncated first. After a
               re-run, retrain and rescore with python3 notebooks/07_ml_models.py
               (scripts/deploy.py does this automatically when views exist).
               Run the whole file in ONE session (uses temporary tables).
=============================================================================*/

USE DATABASE RIA_FINANCIAL_INTELLIGENCE;
USE SCHEMA RAW;
USE WAREHOUSE RIA_FINANCIAL_WH;

TRUNCATE TABLE IF EXISTS CORRIDORS;
TRUNCATE TABLE IF EXISTS AGENT_LOCATIONS;
TRUNCATE TABLE IF EXISTS ANALYSTS;
TRUNCATE TABLE IF EXISTS CUSTOMERS;
TRUNCATE TABLE IF EXISTS KYC_PROFILES;
TRUNCATE TABLE IF EXISTS BENEFICIARIES;
TRUNCATE TABLE IF EXISTS FUNDING_SOURCES;
TRUNCATE TABLE IF EXISTS DEVICES;
TRUNCATE TABLE IF EXISTS APP_SESSIONS;
TRUNCATE TABLE IF EXISTS TRANSFERS;
TRUNCATE TABLE IF EXISTS ACH_RETURNS;
TRUNCATE TABLE IF EXISTS CHARGEBACKS;
TRUNCATE TABLE IF EXISTS REFUNDS;
TRUNCATE TABLE IF EXISTS DISPUTES;
TRUNCATE TABLE IF EXISTS FRAUD_ALERTS;
TRUNCATE TABLE IF EXISTS FRAUD_CASES;
TRUNCATE TABLE IF EXISTS CASE_EVENTS;
TRUNCATE TABLE IF EXISTS CASE_NOTES;
TRUNCATE TABLE IF EXISTS FRAUD_LOSSES;
TRUNCATE TABLE IF EXISTS SANCTIONS_SCREENING;
TRUNCATE TABLE IF EXISTS SAR_FILINGS;
TRUNCATE TABLE IF EXISTS CTR_FILINGS;
TRUNCATE TABLE IF EXISTS STRUCTURING_REVIEWS;
TRUNCATE TABLE IF EXISTS COMPLAINTS;
TRUNCATE TABLE IF EXISTS NPS_SURVEYS;
TRUNCATE TABLE IF EXISTS FRAUD_TYPOLOGIES;
TRUNCATE TABLE IF EXISTS POLICY_DOCUMENTS;

-- ============================================================================
-- CORRIDORS (20)
-- ============================================================================
INSERT INTO CORRIDORS
SELECT column1, column2, column3, column4, column5, column6, column7::NUMBER(18,6), column8::NUMBER(18,6),
       column9, column10::NUMBER(5,2), column11, column12
FROM VALUES
 ('US-MX','United States to Mexico','United States','Mexico','USD','MXN',17.2,1.0,'Medium',38.0,FALSE,'Latin America'),
 ('US-GT','United States to Guatemala','United States','Guatemala','USD','GTQ',7.75,1.0,'Medium',36.0,FALSE,'Latin America'),
 ('US-SV','United States to El Salvador','United States','El Salvador','USD','USD',1.0,1.0,'Medium',40.0,FALSE,'Latin America'),
 ('US-HN','United States to Honduras','United States','Honduras','USD','HNL',24.7,1.0,'Medium',44.0,FALSE,'Latin America'),
 ('US-DO','United States to Dominican Republic','United States','Dominican Republic','USD','DOP',59.0,1.0,'Medium',35.0,FALSE,'Latin America'),
 ('US-CO','United States to Colombia','United States','Colombia','USD','COP',4100.0,1.0,'Medium',42.0,FALSE,'Latin America'),
 ('US-JM','United States to Jamaica','United States','Jamaica','USD','JMD',156.0,1.0,'Medium',41.0,FALSE,'Latin America'),
 ('US-HT','United States to Haiti','United States','Haiti','USD','HTG',131.0,1.0,'High',71.0,TRUE,'Latin America'),
 ('US-PH','United States to Philippines','United States','Philippines','USD','PHP',56.5,1.0,'Low',28.0,FALSE,'Asia Pacific'),
 ('US-IN','United States to India','United States','India','USD','INR',83.2,1.0,'Low',30.0,FALSE,'Asia Pacific'),
 ('US-VN','United States to Vietnam','United States','Vietnam','USD','VND',24500.0,1.0,'Medium',39.0,FALSE,'Asia Pacific'),
 ('US-CN','United States to China','United States','China','USD','CNY',7.2,1.0,'Medium',52.0,FALSE,'Asia Pacific'),
 ('US-PK','United States to Pakistan','United States','Pakistan','USD','PKR',278.0,1.0,'High',66.0,TRUE,'Asia Pacific'),
 ('US-BD','United States to Bangladesh','United States','Bangladesh','USD','BDT',110.0,1.0,'Medium',48.0,FALSE,'Asia Pacific'),
 ('US-NG','United States to Nigeria','United States','Nigeria','USD','NGN',1550.0,1.0,'High',74.0,TRUE,'Africa'),
 ('US-GH','United States to Ghana','United States','Ghana','USD','GHS',12.5,1.0,'Medium',50.0,FALSE,'Africa'),
 ('US-EG','United States to Egypt','United States','Egypt','USD','EGP',48.0,1.0,'Medium',54.0,FALSE,'Middle East'),
 ('ES-CO','Spain to Colombia','Spain','Colombia','EUR','COP',4450.0,0.92,'Medium',42.0,FALSE,'Latin America'),
 ('GB-IN','United Kingdom to India','United Kingdom','India','GBP','INR',105.3,0.79,'Low',30.0,FALSE,'Asia Pacific'),
 ('CA-PH','Canada to Philippines','Canada','Philippines','CAD','PHP',41.5,1.36,'Low',28.0,FALSE,'Asia Pacific');

-- Corridor volume weights (sum = 100) drive each customer's preferred corridor
CREATE OR REPLACE TEMPORARY TABLE CORR_W AS
SELECT CORRIDOR_ID,
       (SUM(W) OVER (ORDER BY ORD) - W) / 100.0 AS LO,
       CASE WHEN ORD = 20 THEN 1.0001 ELSE SUM(W) OVER (ORDER BY ORD) / 100.0 END AS HI
FROM (SELECT column1 AS CORRIDOR_ID, column2 AS W, column3 AS ORD FROM VALUES
 ('US-MX',26,1),('US-GT',6,2),('US-SV',6,3),('US-HN',4,4),('US-DO',5,5),('US-CO',5,6),('US-JM',3,7),
 ('US-HT',2,8),('US-PH',8,9),('US-IN',12,10),('US-VN',3,11),('US-CN',2,12),('US-PK',3,13),('US-BD',2,14),
 ('US-NG',3,15),('US-GH',1,16),('US-EG',1,17),('ES-CO',3,18),('GB-IN',2,19),('CA-PH',3,20));

-- ============================================================================
-- ANALYSTS (120)
-- ============================================================================
INSERT INTO ANALYSTS
SELECT 'AN-' || LPAD(g.I::VARCHAR, 3, '0'),
    GET(ARRAY_CONSTRUCT('Alex','Priya','Marcus','Elena','Jamal','Sofia','Kenji','Amara','Daniel','Leila',
        'Victor','Hannah','Omar','Chen','Rosa','Tomas','Nadia','Ethan','Mei','Carlos'), MOD(g.I, 20))::VARCHAR
        || ' ' ||
    GET(ARRAY_CONSTRUCT('Rivera','Nguyen','Okafor','Petrov','Hassan','Moreau','Tanaka','Silva','Kowalski','Bennett',
        'Alvarez','Singh','Murphy','Fischer','Costa','Dubois','Khan','Larsen','Reyes','Walker'), MOD(g.I * 7, 20))::VARCHAR,
    GET(ARRAY_CONSTRUCT('Fraud Operations','Fraud Operations','AML Investigations','AML Investigations',
        'Sanctions','Agent Oversight','Disputes','Disputes'), MOD(g.I, 8))::VARCHAR,
    CASE WHEN MOD(g.I, 25) = 0 THEN 'BSA Officer' WHEN MOD(g.I, 9) = 0 THEN 'Team Lead'
         WHEN MOD(g.I, 3) = 0 THEN 'Senior Analyst' ELSE 'Analyst' END,
    DATEADD(DAY, -1 * UNIFORM(90, 3000, RANDOM()), CURRENT_DATE())
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS I FROM TABLE(GENERATOR(ROWCOUNT => 120))) g;

-- ============================================================================
-- AGENT LOCATIONS (1,200: 800 send-capable, 400 payout)
-- ============================================================================
INSERT INTO AGENT_LOCATIONS
SELECT 'AG-' || LPAD(s.I::VARCHAR, 5, '0'),
    s.CITY || ' ' || GET(ARRAY_CONSTRUCT('Express','Money Center','Plaza','Remit','Central','Express Mart','Travel','Corner'), MOD(s.I, 8))::VARCHAR
        || ' #' || s.I::VARCHAR,
    s.AGENT_TYPE, s.ROLE, s.COUNTRY, s.CITY, s.REGION,
    DATEADD(DAY, -1 * UNIFORM(200, 4500, RANDOM()), CURRENT_DATE()),
    CASE WHEN MOD(s.I * 13, 100) < 93 THEN 'Active' WHEN MOD(s.I * 13, 100) < 97 THEN 'Under Review'
         WHEN MOD(s.I * 13, 100) < 99 THEN 'Suspended' ELSE 'Terminated' END,
    CASE s.AGENT_TYPE WHEN 'Ria Company Store' THEN 60000 WHEN 'Bank Partner' THEN 120000 ELSE 25000 END,
    DATEADD(DAY, -1 * UNIFORM(10, 500, RANDOM()), CURRENT_DATE()),
    ROUND(IFF(s.COLLUDES, UNIFORM(1.5::FLOAT, 3.8::FLOAT, RANDOM()), UNIFORM(2.8::FLOAT, 5.0::FLOAT, RANDOM())), 1),
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < IFF(s.COLLUDES, 0.55, 0.92),
    s.COLLUDES
FROM (
    SELECT I,
        IFF(I <= 800, GET(ARRAY_CONSTRUCT('United States','United States','United States','United States','United States','United States',
              'United States','United States','United States','United States','United States','United States','United States',
              'United States','United States','United States','United States','Spain','United Kingdom','Canada'), MOD(I, 20))::VARCHAR,
            GET(ARRAY_CONSTRUCT('Mexico','Mexico','Mexico','Mexico','Mexico','Guatemala','El Salvador','Honduras','Dominican Republic',
              'Colombia','Jamaica','Haiti','Philippines','Philippines','India','India','Vietnam','China','Pakistan','Bangladesh',
              'Nigeria','Ghana','Egypt'), MOD(I, 23))::VARCHAR) AS COUNTRY,
        IFF(I <= 800, GET(ARRAY_CONSTRUCT('Houston','Los Angeles','Chicago','New York','Miami','Dallas','Phoenix','San Antonio','Atlanta',
              'Newark','San Diego','Denver','Charlotte','Las Vegas','Washington','Boston','Seattle','Madrid','London','Toronto'), MOD(I, 20))::VARCHAR,
            GET(ARRAY_CONSTRUCT('Guadalajara','Monterrey','Mexico City','Puebla','Tijuana','Guatemala City','San Salvador','Tegucigalpa',
              'Santo Domingo','Bogota','Kingston','Port-au-Prince','Manila','Cebu','Mumbai','Delhi','Ho Chi Minh City','Shanghai',
              'Karachi','Dhaka','Lagos','Accra','Cairo'), MOD(I, 23))::VARCHAR) AS CITY,
        IFF(I <= 800, IFF(MOD(I, 20) IN (17, 18), 'Europe', 'North America'),
            CASE WHEN MOD(I, 23) <= 11 THEN 'Latin America' WHEN MOD(I, 23) <= 19 THEN 'Asia Pacific'
                 WHEN MOD(I, 23) <= 21 THEN 'Africa' ELSE 'Middle East' END) AS REGION,
        CASE WHEN I > 800 THEN 'Payout Partner' WHEN MOD(I, 10) = 0 THEN 'Ria Company Store' WHEN MOD(I, 10) = 1 THEN 'Bank Partner'
             ELSE 'Retail Partner' END AS AGENT_TYPE,
        CASE WHEN I > 800 THEN 'Payout' WHEN MOD(I, 4) = 0 THEN 'Both' ELSE 'Send' END AS ROLE,
        (I <= 800 AND MOD(ABS(HASH(I, 'collusion')), 20) = 7) AS COLLUDES
    FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS I FROM TABLE(GENERATOR(ROWCOUNT => 1200)))
) s;

CREATE OR REPLACE TEMPORARY TABLE SEND_AGENTS AS
SELECT AGENT_ID, COUNTRY, CONFIRMED_COLLUSION,
       ROW_NUMBER() OVER (PARTITION BY COUNTRY ORDER BY AGENT_ID) AS RN,
       COUNT(*) OVER (PARTITION BY COUNTRY) AS CNT
FROM AGENT_LOCATIONS WHERE ROLE IN ('Send', 'Both');

CREATE OR REPLACE TEMPORARY TABLE COLLUSIVE_AGENTS AS
SELECT AGENT_ID, ROW_NUMBER() OVER (ORDER BY AGENT_ID) AS RN, COUNT(*) OVER () AS CNT
FROM AGENT_LOCATIONS WHERE CONFIRMED_COLLUSION AND COUNTRY = 'United States';

CREATE OR REPLACE TEMPORARY TABLE PAYOUT_AGENTS AS
SELECT AGENT_ID, COUNTRY, ROW_NUMBER() OVER (PARTITION BY COUNTRY ORDER BY AGENT_ID) AS RN,
       COUNT(*) OVER (PARTITION BY COUNTRY) AS CNT
FROM AGENT_LOCATIONS WHERE ROLE IN ('Payout', 'Both') AND COUNTRY NOT IN ('United States','Spain','United Kingdom','Canada');

-- ============================================================================
-- CUSTOMERS (40,000). Hidden PROFILE drives behavior so models have real signal.
--   SYN synthetic identity, ATO account-takeover victim, CARD card fraudster,
--   RING fraud-ring member, STRUCT structurer, SCAM scam victim, NORMAL.
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CUST_DRAW AS
SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_PROF, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_CORR,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_SEG,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_SIGN,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_SIGN2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_AGE,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_AGE2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_CH,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_AGT,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_AGT2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_HH,   UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_STAT,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_NOISE, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_AMT,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_CRED, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_BANK,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_DEV2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R_NAME
FROM TABLE(GENERATOR(ROWCOUNT => 40000));

CREATE OR REPLACE TEMPORARY TABLE CUST_STAGE AS
SELECT d.*,
    CASE WHEN R_PROF < 0.018 THEN 'SYN' WHEN R_PROF < 0.038 THEN 'ATO' WHEN R_PROF < 0.048 THEN 'CARD'
         WHEN R_PROF < 0.056 THEN 'RING' WHEN R_PROF < 0.065 THEN 'STRUCT' WHEN R_PROF < 0.078 THEN 'SCAM'
         ELSE 'NORMAL' END AS PROFILE
FROM CUST_DRAW d;

CREATE OR REPLACE TEMPORARY TABLE CUST_BASE AS
SELECT s.*,
    CASE WHEN PROFILE = 'SYN' THEN 10 + FLOOR(R_SIGN * 290)
         WHEN PROFILE = 'RING' THEN 10 + FLOOR(R_SIGN * 190)
         WHEN R_SIGN2 < 0.08 THEN 1 + FLOOR(R_SIGN * 60)
         ELSE 61 + FLOOR(R_SIGN * 1040) END AS SIGNUP_DAYS,
    c.CORRIDOR_ID AS PREF_CORRIDOR,
    CASE WHEN PROFILE = 'SCAM' AND R_AGE < 0.55 THEN 60 + FLOOR(R_AGE2 * 26)
         ELSE 18 + FLOOR(POW(R_AGE2, 0.9) * 55) END AS AGE_YEARS
FROM CUST_STAGE s
JOIN CORR_W c ON s.R_CORR >= c.LO AND s.R_CORR < c.HI;

CREATE OR REPLACE TEMPORARY TABLE CUST_LATENT AS
SELECT b.N AS CUST_NUM, 'C' || LPAD(b.N::VARCHAR, 6, '0') AS CUSTOMER_ID, b.PROFILE,
    CASE WHEN b.SIGNUP_DAYS < 90 THEN 'New'
         WHEN b.R_SEG < 0.55 THEN 'Regular Remitter' WHEN b.R_SEG < 0.80 THEN 'Occasional Sender'
         WHEN b.R_SEG < 0.88 THEN 'High Value' ELSE 'Small Business' END AS SEGMENT,
    b.SIGNUP_DAYS, b.PREF_CORRIDOR, b.AGE_YEARS,
    co.SEND_COUNTRY,
    CASE WHEN b.R_CH < 0.45 THEN 'Retail Agent' WHEN b.R_CH < 0.85 THEN 'Mobile App' ELSE 'Web' END AS SIGNUP_CHANNEL,
    -- Household partner: odd customers may share phone/device/IP with the previous customer
    (MOD(b.N, 2) = 1 AND b.PROFILE = 'NORMAL'
        AND LAG(b.R_HH) OVER (ORDER BY b.N) < 0.025 AND LAG(b.PROFILE) OVER (ORDER BY b.N) = 'NORMAL') AS IS_HH_PARTNER,
    IFF(b.PROFILE = 'RING', 1 + FLOOR(POW(b.R_HH, 1.35) * 40), NULL) AS RING_ID,
    b.R_AGE, b.R_NOISE, b.R_AMT, b.R_CRED, b.R_BANK, b.R_DEV2, b.R_STAT, b.R_NAME, b.R_AGT, b.R_AGT2
FROM CUST_BASE b
JOIN CORRIDORS co ON co.CORRIDOR_ID = b.PREF_CORRIDOR;

CREATE OR REPLACE TEMPORARY TABLE CUST_KEYS AS
SELECT l.*,
    -- Sharing keys: ring members share one key, household partners share the earlier customer's key
    CASE WHEN l.RING_ID IS NOT NULL THEN 1000000 + l.RING_ID WHEN l.IS_HH_PARTNER THEN l.CUST_NUM - 1 ELSE l.CUST_NUM END AS SHARE_KEY,
    IFF(l.PROFILE = 'STRUCT' AND l.R_AGT2 < 0.35 AND l.SEND_COUNTRY = 'United States' AND ca.AGENT_ID IS NOT NULL,
        ca.AGENT_ID, sa.AGENT_ID) AS HOME_AGENT_ID
FROM CUST_LATENT l
JOIN SEND_AGENTS sa ON sa.COUNTRY = l.SEND_COUNTRY AND sa.RN = 1 + FLOOR(l.R_AGT * sa.CNT)
LEFT JOIN COLLUSIVE_AGENTS ca ON ca.RN = 1 + MOD(l.CUST_NUM, ca.CNT);

INSERT INTO CUSTOMERS
SELECT k.CUSTOMER_ID,
    GET(ARRAY_CONSTRUCT('Maria','Jose','Juan','Ana','Luis','Carmen','Carlos','Rosa','Miguel','Laura','Pedro','Sofia','Jorge','Elena','Diego',
        'Priya','Rahul','Amit','Sunita','Anil','Grace','Joy','Mark','Liza','Ramon','Nguyen','Linh','Wei','Li','Chen',
        'Fatima','Ahmed','Hassan','Amina','Chidi','Ngozi','Kwame','Abena','Marie','Jean'), MOD(FLOOR(k.R_NAME * 4000)::INT, 40))::VARCHAR,
    GET(ARRAY_CONSTRUCT('Garcia','Martinez','Lopez','Hernandez','Gonzalez','Rodriguez','Perez','Sanchez','Ramirez','Torres',
        'Patel','Sharma','Singh','Kumar','Reddy','Santos','Reyes','Cruz','Bautista','Mendoza',
        'Tran','Pham','Wang','Zhang','Liu','Khan','Ali','Hussain','Okafor','Adeyemi',
        'Mensah','Boateng','Osei','Pierre','Joseph','Baptiste','Smith','Johnson','Brown','Davis'), MOD(FLOOR(k.R_NAME * 400000)::INT, 40))::VARCHAR,
    DATEADD(DAY, -1 * (k.AGE_YEARS * 365 + FLOOR(k.R_AGE * 360)), CURRENT_DATE()),
    'cust' || LPAD(k.CUST_NUM::VARCHAR, 6, '0') || '@example.com',
    '+1-' || (200 + MOD(FLOOR(k.SHARE_KEY / 10000), 700))::INT::VARCHAR || '-555-' || LPAD(MOD(k.SHARE_KEY, 10000)::INT::VARCHAR, 4, '0'),
    k.SEND_COUNTRY,
    GET(ARRAY_CONSTRUCT('Houston','Los Angeles','Chicago','New York','Miami','Dallas','Phoenix','San Antonio','Atlanta','Newark',
        'San Diego','Denver','Charlotte','Las Vegas','Washington','Boston','Seattle'), MOD(k.CUST_NUM, 17))::VARCHAR,
    pc.PAYOUT_COUNTRY,
    DATEADD(DAY, -1 * k.SIGNUP_DAYS, CURRENT_DATE()),
    k.SIGNUP_CHANNEL,
    k.HOME_AGENT_ID,
    k.PREF_CORRIDOR,
    k.SEGMENT,
    CASE WHEN k.R_CRED < 0.60 THEN 'None' WHEN k.R_CRED < 0.82 THEN 'Silver' WHEN k.R_CRED < 0.94 THEN 'Gold' ELSE 'Platinum' END,
    CASE WHEN k.PROFILE = 'SYN' AND k.R_STAT < 0.6 THEN 'Blocked' WHEN k.PROFILE IN ('ATO','CARD','RING') AND k.R_STAT < 0.25 THEN 'Blocked'
         WHEN k.R_STAT < 0.88 THEN 'Active' WHEN k.R_STAT < 0.95 THEN 'Dormant' WHEN k.R_STAT < 0.98 THEN 'Closed' ELSE 'Blocked' END,
    k.R_BANK < 0.55
FROM CUST_KEYS k
JOIN CORRIDORS pc ON pc.CORRIDOR_ID = k.PREF_CORRIDOR;

-- ============================================================================
-- KYC PROFILES
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE KYC_DRAW AS
SELECT k.CUST_NUM, k.CUSTOMER_ID, k.PROFILE, k.SEGMENT, k.SIGNUP_DAYS, k.AGE_YEARS, k.IS_HH_PARTNER, k.RING_ID, k.SIGNUP_CHANNEL,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R10
FROM CUST_KEYS k;

INSERT INTO KYC_PROFILES
SELECT q.CUSTOMER_ID,
    CASE WHEN q.RISK = 'High' THEN 'Tier 3' WHEN q.R3 < 0.35 THEN 'Tier 1' ELSE 'Tier 2' END,
    q.RISK,
    q.PEP,
    (q.RISK = 'High' OR q.PEP),
    (q.RISK = 'High' OR q.PEP) AND q.R4 < 0.85,
    CASE WHEN q.R5 < 0.45 THEN 'Passport' WHEN q.R5 < 0.75 THEN 'National ID' WHEN q.R5 < 0.93 THEN 'Drivers License' ELSE 'Consular ID' END,
    CASE WHEN q.SIGNUP_DAYS < 10 AND q.R6 < 0.3 THEN 'Pending'
         WHEN q.PROFILE = 'SYN' THEN IFF(q.R6 < 0.82, 'Verified', 'Failed')
         WHEN q.R6 < 0.93 THEN 'Verified' WHEN q.R6 < 0.96 THEN 'Pending' WHEN q.R6 < 0.985 THEN 'Failed' ELSE 'Expired' END,
    CASE WHEN q.PROFILE = 'SYN' AND q.R7 < 0.55 THEN 1 + FLOOR(q.R7 / 0.55 * 5)
         WHEN q.R7 < 0.80 THEN 1 WHEN q.R7 < 0.94 THEN 2 WHEN q.R7 < 0.99 THEN 3 ELSE 4 END,
    DATEADD(HOUR, 2, DATEADD(DAY, -1 * q.SIGNUP_DAYS, CURRENT_DATE())::TIMESTAMP_NTZ),
    IFF(q.PROFILE = 'SYN' AND q.R8 < 0.50, FLOOR(q.R9 * 150), IFF(q.R8 < 0.05, FLOOR(q.R9 * 60), 30 + FLOOR(POW(q.R9, 0.6) * 4000))),
    q.R10 < CASE WHEN q.PROFILE = 'SYN' THEN 0.22 WHEN q.PROFILE = 'RING' THEN 0.15 ELSE 0.04 END,
    CASE WHEN q.PROFILE = 'SYN' AND q.R1 < 0.35 THEN 3 + FLOOR(q.R2 * 8)
         WHEN q.IS_HH_PARTNER THEN 1
         WHEN q.R1 < 0.88 THEN 0 WHEN q.R1 < 0.96 THEN 1 WHEN q.R1 < 0.99 THEN 2 ELSE 3 END,
    ROUND(IFF(q.PROFILE = 'SYN' AND q.R2 < 0.50, 0.1 + q.R3 * 3.9,
              GREATEST(0.5, LEAST(q.AGE_YEARS - 17, 1.5 + q.R4 * 33.5))), 1),
    GET(ARRAY_CONSTRUCT('Salary','Salary','Salary','Self-Employment','Savings','Business Income','Pension','Family Support','Remittance Income'),
        MOD(FLOOR(q.R5 * 900)::INT, 9))::VARCHAR,
    GET(ARRAY_CONSTRUCT('Construction Worker','Nurse','Driver','Restaurant Worker','Cleaner','Warehouse Associate','Teacher','Engineer',
        'Retail Associate','Caregiver','Business Owner','Student','Retired','Mechanic','Farm Worker'), MOD(FLOOR(q.R6 * 1500)::INT, 15))::VARCHAR,
    ROUND(CASE WHEN q.PROFILE = 'STRUCT' AND q.R9 < 0.6 THEN 2500 + q.R7 * 6000 WHEN q.SEGMENT = 'High Value' THEN 2000 + q.R7 * 6000 WHEN q.SEGMENT = 'Small Business' THEN 1500 + q.R7 * 4500
                         WHEN q.SEGMENT = 'Occasional Sender' THEN 100 + q.R7 * 300 WHEN q.SEGMENT = 'New' THEN 200 + q.R7 * 400
                         ELSE 300 + q.R7 * 500 END, 2),
    DATEADD(DAY, -1 * LEAST(q.SIGNUP_DAYS, 20 + FLOOR(q.R8 * 700)), CURRENT_DATE()),
    DATEADD(MONTH, CASE q.RISK WHEN 'High' THEN 12 WHEN 'Medium' THEN 24 ELSE 36 END,
            DATEADD(DAY, -1 * LEAST(q.SIGNUP_DAYS, 20 + FLOOR(q.R8 * 700)), CURRENT_DATE())),
    CASE WHEN q.SIGNUP_DAYS < 60 THEN NULL ELSE (q.PROFILE = 'SYN' AND MOD(ABS(HASH(q.CUSTOMER_ID, 11)), 100) < 88) END
FROM (
    SELECT d.*,
        CASE WHEN d.PROFILE = 'SYN' THEN CASE WHEN d.R1 < 0.55 THEN 'Low' WHEN d.R1 < 0.90 THEN 'Medium' ELSE 'High' END
             WHEN d.PROFILE IN ('RING','STRUCT') THEN CASE WHEN d.R1 < 0.45 THEN 'Low' WHEN d.R1 < 0.75 THEN 'Medium' ELSE 'High' END
             ELSE CASE WHEN d.R1 < 0.70 THEN 'Low' WHEN d.R1 < 0.95 THEN 'Medium' ELSE 'High' END END AS RISK,
        (d.R2 < IFF(d.SEGMENT = 'High Value', 0.012, 0.003)) AS PEP
    FROM KYC_DRAW d
) q;

-- ============================================================================
-- TRANSFER PLANNING (hidden customer profile drives behavior)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE NUMS AS
SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS K FROM TABLE(GENERATOR(ROWCOUNT => 320));

CREATE OR REPLACE TEMPORARY TABLE CORR_ORD AS
SELECT w.CORRIDOR_ID, ROW_NUMBER() OVER (ORDER BY w.LO) AS ORD, c.PAYOUT_COUNTRY, c.SEND_COUNTRY, c.SEND_CURRENCY, c.PAYOUT_CURRENCY,
       c.USD_TO_PAYOUT_RATE, c.USD_TO_SEND_RATE
FROM CORR_W w JOIN CORRIDORS c ON c.CORRIDOR_ID = w.CORRIDOR_ID;

CREATE OR REPLACE TEMPORARY TABLE CUST_PLAN AS
SELECT k.CUST_NUM, k.CUSTOMER_ID, k.PROFILE, k.SEGMENT, k.SIGNUP_DAYS, k.SEND_COUNTRY, k.PREF_CORRIDOR, k.SIGNUP_CHANNEL,
    k.HOME_AGENT_ID, k.AGE_YEARS, k.RING_ID, o.ORD AS PREF_ORD,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < CASE k.PROFILE WHEN 'CARD' THEN 0.7 WHEN 'SYN' THEN 0.6 ELSE 0.25 END AS HAS_CREDIT,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < CASE k.PROFILE WHEN 'SYN' THEN 0.7 ELSE 0.35 END AS HAS_BANK,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.07 AS HAS_DEV2,
    LEAST(540, k.SIGNUP_DAYS) AS ACTIVE_DAYS,
    CASE k.SEGMENT WHEN 'Regular Remitter' THEN 150 * EXP((k.R_AMT - 0.5) * 1.6)
                   WHEN 'Occasional Sender' THEN 120 * EXP((k.R_AMT - 0.5) * 1.6)
                   WHEN 'High Value' THEN 900 * EXP((k.R_AMT - 0.5) * 1.2)
                   WHEN 'Small Business' THEN 500 * EXP((k.R_AMT - 0.5) * 1.4)
                   ELSE 140 * EXP((k.R_AMT - 0.5) * 1.2) END AS BASE_AMT,
    CASE WHEN k.PROFILE = 'SYN' THEN 0
         ELSE LEAST(300, GREATEST(1, ROUND(
              CASE k.SEGMENT WHEN 'Regular Remitter' THEN 2.2 WHEN 'Occasional Sender' THEN 0.6 WHEN 'High Value' THEN 3.0
                             WHEN 'Small Business' THEN 6.0 ELSE 2.0 END
              * LEAST(540, k.SIGNUP_DAYS) / 30.0 * (0.4 + 1.2 * k.R_NOISE)))) END AS N_NORMAL,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS S1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS S2
FROM CUST_KEYS k
JOIN CORR_ORD o ON o.CORRIDOR_ID = k.PREF_CORRIDOR;

-- ---------------------------------------------------------------------------
-- NORMAL transfers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TP_NORMAL_RAW AS
SELECT p.CUST_NUM, n.K,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R10,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R12, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R13,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R14, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R15,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R16, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R17,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R18, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R19,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R20
FROM CUST_PLAN p JOIN NUMS n ON n.K <= p.N_NORMAL;

CREATE OR REPLACE TEMPORARY TABLE TP_NORMAL1 AS
SELECT r.*, p.SEGMENT, p.SEND_COUNTRY, p.HOME_AGENT_ID, p.PREF_ORD, p.HAS_CREDIT, p.HAS_BANK, p.ACTIVE_DAYS, p.S2,
    CASE p.SIGNUP_CHANNEL
      WHEN 'Retail Agent' THEN CASE WHEN r.R1 < 0.90 THEN 'Retail Agent' WHEN r.R1 < 0.95 THEN 'Mobile App' ELSE 'Web' END
      WHEN 'Mobile App'   THEN CASE WHEN r.R1 < 0.90 THEN 'Mobile App' WHEN r.R1 < 0.96 THEN 'Web' ELSE 'Retail Agent' END
      ELSE CASE WHEN r.R1 < 0.90 THEN 'Web' WHEN r.R1 < 0.95 THEN 'Mobile App' ELSE 'Retail Agent' END END AS CHANNEL,
    p.BASE_AMT * EXP((r.R3 - 0.5) * 0.9) * IFF(r.R4 < IFF(p.SEGMENT = 'New', 0.22, 0.03), 3 + 3 * r.R5, 1) AS AMT_RAW
FROM TP_NORMAL_RAW r JOIN CUST_PLAN p ON p.CUST_NUM = r.CUST_NUM;

CREATE OR REPLACE TEMPORARY TABLE CAND_NORMAL AS
SELECT t.CUST_NUM,
    DATEADD(SECOND, IFF(t.CHANNEL = 'Retail Agent', 9 + FLOOR(t.R9 * 10), IFF(t.R10 < 0.20, MOD(20 + FLOOR(t.R9 * 10), 24), 8 + FLOOR(t.R9 * 12))) * 3600
                    + FLOOR(t.R15 * 3599), DATEADD(DAY, -1 * (1 + FLOOR(t.R14 * t.ACTIVE_DAYS)), CURRENT_DATE())::TIMESTAMP_NTZ) AS CREATED_AT,
    t.CHANNEL, f.FUNDING_TYPE,
    CASE WHEN t.SEGMENT = 'High Value' AND t.R7 < 0.003 AND f.FUNDING_TYPE = 'Cash' THEN ROUND(10000 + 5000 * t.R8, 2)
         WHEN t.S2 < 0.06 AND t.SEGMENT IN ('High Value', 'Small Business') AND t.R6 < 0.4 THEN ROUND(2600 + 380 * t.R3, 2)
         WHEN t.R6 < 0.6 THEN LEAST(9500, GREATEST(20, ROUND(t.AMT_RAW / 10.0, 0) * 10))
         ELSE LEAST(9500, GREATEST(20, ROUND(t.AMT_RAW, 2))) END AS AMOUNT_USD,
    CASE WHEN t.R16 < 0.03 THEN 81600 + (t.PREF_ORD - 1) * 30 + 1 + FLOOR(t.R18 * 30)
         WHEN t.R16 < 0.10 THEN 82200 + (t.PREF_ORD - 1) * 400 + 1 + FLOOR(t.R18 * 400)
         ELSE (t.CUST_NUM - 1) * 2 + 1 + IFF(t.R17 < 0.35, 1, 0) END AS BENE_NUM,
    t.PREF_ORD AS BENE_CORR_ORD,
    'NORMAL' AS KIND,
    (t.R12 < 0.0012 AND f.FUNDING_TYPE <> 'Cash') AS IS_FRAUD,
    IFF(t.R12 < 0.0012 AND f.FUNDING_TYPE <> 'Cash', 'Unauthorized Claim', NULL) AS FRAUD_TYPE,
    FALSE AS IS_SCAM,
    IFF(t.CHANNEL <> 'Retail Agent' AND t.R13 < 0.03, 'RISKY', 'NORMAL') AS SESSION_KIND,
    IFF(t.CHANNEL = 'Retail Agent',
        IFF(t.SEND_COUNTRY = 'United States' AND t.R19 < 0.08,
            'AG-' || LPAD((1 + FLOOR(t.R20 * 800) - GREATEST(0, MOD(1 + FLOOR(t.R20 * 800), 20) - 16))::VARCHAR, 5, '0'),
            t.HOME_AGENT_ID), NULL) AS SEND_AGENT_ID
FROM TP_NORMAL1 t
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN t.CHANNEL = 'Retail Agent' THEN CASE WHEN t.R2 < 0.72 THEN 'Cash' WHEN t.R2 < 0.90 THEN 'Debit Card'
                                                  ELSE IFF(t.HAS_CREDIT, 'Credit Card', 'Debit Card') END
        ELSE CASE WHEN t.R2 < 0.46 THEN 'Debit Card' WHEN t.R2 < 0.68 THEN IFF(t.HAS_CREDIT, 'Credit Card', 'Debit Card')
                  ELSE IFF(t.HAS_BANK, 'Bank Account', 'Debit Card') END END AS FUNDING_TYPE
) f;

-- ---------------------------------------------------------------------------
-- SYNTHETIC IDENTITY bust-out
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE CAND_SYN AS
SELECT x.CUST_NUM,
    DATEADD(SECOND, IFF(x.R3 < 0.4, FLOOR(x.R2 * 6), 8 + FLOOR(x.R2 * 14)) * 3600 + FLOOR(x.R4 * 3599),
            DATEADD(DAY, -1 * GREATEST(1, x.SIGNUP_DAYS - LEAST(x.SIGNUP_DAYS - 1, FLOOR((x.K - 1) * 45.0 / x.NTX * (0.5 + x.R1)))),
                    CURRENT_DATE())::TIMESTAMP_NTZ) AS CREATED_AT,
    x.CHANNEL,
    CASE WHEN x.CHANNEL = 'Retail Agent' THEN IFF(x.R8 < 0.6, 'Cash', 'Debit Card')
         WHEN x.R8 < 0.4 THEN IFF(x.HAS_BANK, 'Bank Account', 'Debit Card') WHEN x.R8 < 0.75 THEN 'Debit Card'
         ELSE IFF(x.HAS_CREDIT, 'Credit Card', 'Debit Card') END AS FUNDING_TYPE,
    IFF(x.K <= 2 OR (x.SLEEPER AND x.K < x.NTX - 1), ROUND(60 + 340 * x.R5, 2), ROUND(300 + 2200 * POW(x.R5, 1.3), 2)) AS AMOUNT_USD,
    IFF(x.SEND_COUNTRY = 'United States' AND x.K > 2 AND x.R9 < 0.55, 80000 + 1 + FLOOR(POW(x.R10, 1.25) * 1200),
        (x.CUST_NUM - 1) * 2 + 1 + IFF(x.R10 < 0.5, 0, 1)) AS BENE_NUM,
    IFF(x.SEND_COUNTRY = 'United States' AND x.K > 2 AND x.R9 < 0.55,
        CASE WHEN MOD(80000 + 1 + FLOOR(POW(x.R10, 1.25) * 1200), 5) = 0 THEN 1 ELSE x.PREF_ORD END, x.PREF_ORD) AS BENE_CORR_ORD,
    'SYN' AS KIND,
    (x.K > 2 AND x.R6 < 0.8 AND (NOT x.SLEEPER OR x.K >= x.NTX - 1)) AS IS_FRAUD,
    IFF(x.K > 2 AND x.R6 < 0.8 AND (NOT x.SLEEPER OR x.K >= x.NTX - 1), 'Synthetic Identity', NULL) AS FRAUD_TYPE,
    FALSE AS IS_SCAM,
    IFF(x.K > 2 AND x.R6 < 0.8 AND (NOT x.SLEEPER OR x.K >= x.NTX - 1) AND x.CHANNEL <> 'Retail Agent', 'FRAUDSTER', 'NORMAL') AS SESSION_KIND,
    IFF(x.CHANNEL = 'Retail Agent', x.HOME_AGENT_ID, NULL) AS SEND_AGENT_ID
FROM (
    SELECT p.CUST_NUM, n.K, 3 + MOD(p.CUST_NUM * 7, 8) AS NTX, (MOD(p.CUST_NUM, 10) < 3) AS SLEEPER, p.SIGNUP_DAYS, p.PREF_ORD, p.HAS_CREDIT, p.HAS_BANK, p.SEND_COUNTRY, p.HOME_AGENT_ID,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R10,
        CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.55 THEN 'Mobile App' WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.67 THEN 'Web'
             ELSE 'Retail Agent' END AS CHANNEL
    FROM CUST_PLAN p JOIN NUMS n ON n.K <= 3 + MOD(p.CUST_NUM * 7, 8) WHERE p.PROFILE = 'SYN'
) x;

-- ---------------------------------------------------------------------------
-- ACCOUNT TAKEOVER: sessions (1-3 per victim), 75% followed by a transfer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE ATO_SESS AS
SELECT p.CUST_NUM, n.K AS J, p.PREF_ORD, p.HAS_CREDIT, p.HAS_BANK, p.SEND_COUNTRY,
    DATEADD(SECOND, IFF(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.55, FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * 6), 8 + FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * 14)) * 3600
            + FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * 3599),
            DATEADD(DAY, -1 * (1 + FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * p.ACTIVE_DAYS)), CURRENT_DATE())::TIMESTAMP_NTZ) AS LOGIN_AT,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.75 AS HAS_TRANSFER,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8
FROM CUST_PLAN p JOIN NUMS n ON n.K <= 1 + MOD(p.CUST_NUM, 3) WHERE p.PROFILE = 'ATO';

CREATE OR REPLACE TEMPORARY TABLE CAND_ATO AS
SELECT a.CUST_NUM,
    DATEADD(MINUTE, 5 + FLOOR(a.R8 * 35), a.LOGIN_AT) AS CREATED_AT,
    IFF(a.R3 < 0.55, 'Mobile App', 'Web') AS CHANNEL,
    CASE WHEN a.R4 < 0.60 THEN 'Debit Card' WHEN a.R4 < 0.85 THEN IFF(a.HAS_BANK, 'Bank Account', 'Debit Card')
         ELSE IFF(a.HAS_CREDIT, 'Credit Card', 'Debit Card') END AS FUNDING_TYPE,
    ROUND(200 + 2500 * POW(a.R5, 1.4), 2) AS AMOUNT_USD,
    IFF(a.SEND_COUNTRY = 'United States' AND a.R6 < 0.8, 80000 + 1 + FLOOR(POW(a.R7, 1.25) * 1200), (a.CUST_NUM - 1) * 2 + 2) AS BENE_NUM,
    IFF(a.SEND_COUNTRY = 'United States' AND a.R6 < 0.8,
        CASE WHEN MOD(80000 + 1 + FLOOR(POW(a.R7, 1.25) * 1200), 5) = 0 THEN 1 WHEN MOD(80000 + 1 + FLOOR(POW(a.R7, 1.25) * 1200), 7) = 0 THEN 15
             ELSE 1 + MOD((80000 + 1 + FLOOR(POW(a.R7, 1.25) * 1200)) * 7, 17) END, a.PREF_ORD) AS BENE_CORR_ORD,
    'ATO' AS KIND, TRUE AS IS_FRAUD, 'Account Takeover' AS FRAUD_TYPE, FALSE AS IS_SCAM, 'ATO' AS SESSION_KIND,
    CAST(NULL AS VARCHAR) AS SEND_AGENT_ID
FROM ATO_SESS a WHERE a.HAS_TRANSFER;

-- ---------------------------------------------------------------------------
-- CARD-NOT-PRESENT fraudsters: bursts of card-funded transfers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE CAND_CARD AS
SELECT x.CUST_NUM,
    DATEADD(SECOND, IFF(x.R3 < 0.45, FLOOR(x.R2 * 6), 8 + FLOOR(x.R2 * 14)) * 3600 + FLOOR(x.R4 * 3599),
            DATEADD(DAY, -1 * GREATEST(1, LEAST(x.ACTIVE_DAYS, 2 + FLOOR(x.S1 * GREATEST(1, x.ACTIVE_DAYS - 2))) - FLOOR((x.K - 1) * 0.7 * x.R1)),
                    CURRENT_DATE())::TIMESTAMP_NTZ) AS CREATED_AT,
    x.CHANNEL,
    IFF(x.R5 < 0.7 AND x.HAS_CREDIT, 'Credit Card', 'Debit Card') AS FUNDING_TYPE,
    ROUND(150 + 1650 * x.R6, 2) AS AMOUNT_USD,
    IFF(x.SEND_COUNTRY = 'United States' AND x.R7 < 0.55, 80000 + 1 + FLOOR(POW(x.R8, 1.25) * 1200), (x.CUST_NUM - 1) * 2 + 1 + IFF(x.R8 < 0.5, 0, 1)) AS BENE_NUM,
    IFF(x.SEND_COUNTRY = 'United States' AND x.R7 < 0.55,
        CASE WHEN MOD(80000 + 1 + FLOOR(POW(x.R8, 1.25) * 1200), 5) = 0 THEN 1 WHEN MOD(80000 + 1 + FLOOR(POW(x.R8, 1.25) * 1200), 7) = 0 THEN 15
             ELSE 1 + MOD((80000 + 1 + FLOOR(POW(x.R8, 1.25) * 1200)) * 7, 17) END, x.PREF_ORD) AS BENE_CORR_ORD,
    'CARD' AS KIND, (x.R9 < 0.88) AS IS_FRAUD, IFF(x.R9 < 0.88, 'Card Not Present', NULL) AS FRAUD_TYPE, FALSE AS IS_SCAM,
    IFF(x.CHANNEL = 'Retail Agent', 'NORMAL', IFF(x.R9 < 0.88, 'FRAUDSTER', 'NORMAL')) AS SESSION_KIND,
    IFF(x.CHANNEL = 'Retail Agent', x.HOME_AGENT_ID, NULL) AS SEND_AGENT_ID
FROM (
    SELECT p.CUST_NUM, n.K, p.ACTIVE_DAYS, p.S1, p.PREF_ORD, p.HAS_CREDIT, p.SEND_COUNTRY, p.HOME_AGENT_ID,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9,
        CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.5 THEN 'Mobile App' WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.9 THEN 'Web'
             ELSE 'Retail Agent' END AS CHANNEL
    FROM CUST_PLAN p JOIN NUMS n ON n.K <= 4 + MOD(p.CUST_NUM * 5, 11) WHERE p.PROFILE = 'CARD'
) x;

-- ---------------------------------------------------------------------------
-- FRAUD RING members: shared beneficiaries, coordinated digital transfers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE CAND_RING AS
SELECT x.CUST_NUM,
    DATEADD(SECOND, IFF(x.R3 < 0.35, FLOOR(x.R2 * 6), 8 + FLOOR(x.R2 * 14)) * 3600 + FLOOR(x.R4 * 3599),
            DATEADD(DAY, -1 * (1 + FLOOR(x.R1 * x.ACTIVE_DAYS)), CURRENT_DATE())::TIMESTAMP_NTZ) AS CREATED_AT,
    x.CHANNEL,
    CASE WHEN x.R5 < 0.45 THEN 'Debit Card' WHEN x.R5 < 0.75 THEN IFF(x.HAS_BANK, 'Bank Account', 'Debit Card')
         ELSE IFF(x.HAS_CREDIT, 'Credit Card', 'Debit Card') END AS FUNDING_TYPE,
    ROUND(200 + 1000 * x.R6, 2) AS AMOUNT_USD,
    IFF(x.SEND_COUNTRY = 'United States' AND x.R7 < 0.7, 80000 + 1200 + (x.RING_ID - 1) * 3 + 1 + MOD(x.K, 3),
        (x.CUST_NUM - 1) * 2 + 1 + IFF(x.R8 < 0.5, 0, 1)) AS BENE_NUM,
    IFF(x.SEND_COUNTRY = 'United States' AND x.R7 < 0.7,
        CASE WHEN MOD(80000 + 1200 + (x.RING_ID - 1) * 3 + 1 + MOD(x.K, 3), 5) = 0 THEN 1
             WHEN MOD(80000 + 1200 + (x.RING_ID - 1) * 3 + 1 + MOD(x.K, 3), 7) = 0 THEN 15
             ELSE 1 + MOD((80000 + 1200 + (x.RING_ID - 1) * 3 + 1 + MOD(x.K, 3)) * 7, 17) END, x.PREF_ORD) AS BENE_CORR_ORD,
    'RING' AS KIND, (x.R9 < 0.6) AS IS_FRAUD, IFF(x.R9 < 0.6, 'Fraud Ring', NULL) AS FRAUD_TYPE, FALSE AS IS_SCAM,
    IFF(x.CHANNEL = 'Retail Agent', 'NORMAL', 'FRAUDSTER') AS SESSION_KIND,
    IFF(x.CHANNEL = 'Retail Agent', x.HOME_AGENT_ID, NULL) AS SEND_AGENT_ID
FROM (
    SELECT p.CUST_NUM, n.K, p.ACTIVE_DAYS, p.RING_ID, p.PREF_ORD, p.HAS_CREDIT, p.HAS_BANK, p.SEND_COUNTRY, p.HOME_AGENT_ID,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9,
        CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.55 THEN 'Mobile App' WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.85 THEN 'Web'
             ELSE 'Retail Agent' END AS CHANNEL
    FROM CUST_PLAN p JOIN NUMS n ON n.K <= 4 + MOD(p.CUST_NUM * 3, 9) WHERE p.PROFILE = 'RING'
) x;

-- ---------------------------------------------------------------------------
-- STRUCTURING: weeks of 3-6 cash transfers just under $3,000 or $10,000
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE STRUCT_WEEKS AS
SELECT p.CUST_NUM, n.K AS W, 2 + MOD(p.CUST_NUM + n.K, 4) AS M, p.ACTIVE_DAYS, p.SIGNUP_DAYS, p.PREF_ORD, p.HOME_AGENT_ID,
    DATE_TRUNC('WEEK', DATEADD(DAY, -1 * (8 + FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * GREATEST(1, p.ACTIVE_DAYS - 16))), CURRENT_DATE())) AS WEEK_START,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.5 AS JUST_UNDER_3K
FROM CUST_PLAN p JOIN NUMS n ON n.K <= 2 + MOD(p.CUST_NUM, 4) WHERE p.PROFILE = 'STRUCT';

CREATE OR REPLACE TEMPORARY TABLE CAND_STRUCT AS
SELECT x.CUST_NUM,
    DATEADD(SECOND, (9 + FLOOR(x.R2 * 10)) * 3600 + FLOOR(x.R3 * 3599),
        LEAST(DATEADD(DAY, -1, CURRENT_DATE()),
              GREATEST(DATEADD(DAY, -1 * x.SIGNUP_DAYS, CURRENT_DATE()), DATEADD(DAY, MOD(x.T + FLOOR(x.R1 * 3), 7), x.WEEK_START)))::TIMESTAMP_NTZ) AS CREATED_AT,
    'Retail Agent' AS CHANNEL,
    IFF(x.R4 < 0.85, 'Cash', 'Debit Card') AS FUNDING_TYPE,
    CASE WHEN MOD(ABS(HASH(x.CUST_NUM, x.W)), 100) < 35 THEN ROUND(1200 + 1200 * x.R5, 2)
         WHEN x.JUST_UNDER_3K THEN IFF(MOD(ABS(HASH(x.CUST_NUM, x.W, x.T)), 100) < 30, ROUND(1800 + 1190 * x.R5, 2), ROUND(2500 + 490 * x.R5, 2))
         ELSE ROUND(8500 + 1400 * x.R5, 2) END AS AMOUNT_USD,
    (x.CUST_NUM - 1) * 2 + 1 + MOD(x.T, 2) AS BENE_NUM,
    x.PREF_ORD AS BENE_CORR_ORD,
    'STRUCT' AS KIND, FALSE AS IS_FRAUD, CAST(NULL AS VARCHAR) AS FRAUD_TYPE, FALSE AS IS_SCAM, 'NORMAL' AS SESSION_KIND,
    x.HOME_AGENT_ID AS SEND_AGENT_ID
FROM (
    SELECT w.*, t.K AS T,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5
    FROM STRUCT_WEEKS w JOIN NUMS t ON t.K <= w.M
) x;

-- ---------------------------------------------------------------------------
-- SCAM victims (APP / romance / elder): repeated large sends to new payees
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE CAND_SCAM AS
SELECT x.CUST_NUM,
    DATEADD(SECOND, (9 + FLOOR(x.R2 * 12)) * 3600 + FLOOR(x.R3 * 3599),
            DATEADD(DAY, -1 * GREATEST(1, LEAST(x.ACTIVE_DAYS, 2 + FLOOR(x.S1 * GREATEST(1, x.ACTIVE_DAYS - 2))) - FLOOR((x.K - 1) * 7 * x.R1)),
                    CURRENT_DATE())::TIMESTAMP_NTZ) AS CREATED_AT,
    x.CHANNEL,
    CASE WHEN x.CHANNEL = 'Retail Agent' THEN IFF(x.R4 < 0.7, 'Cash', 'Debit Card')
         WHEN x.R4 < 0.4 THEN IFF(x.HAS_BANK, 'Bank Account', 'Debit Card') ELSE 'Debit Card' END AS FUNDING_TYPE,
    ROUND(200 + 2800 * POW(x.R5, 1.3), 2) AS AMOUNT_USD,
    IFF(x.SEND_COUNTRY = 'United States' AND x.S2 < 0.50, 80000 + 1 + FLOOR(POW(x.S1, 1.25) * 1200), (x.CUST_NUM - 1) * 2 + 2) AS BENE_NUM,
    IFF(x.SEND_COUNTRY = 'United States' AND x.S2 < 0.50,
        CASE WHEN MOD(80000 + 1 + FLOOR(POW(x.S1, 1.25) * 1200), 5) = 0 THEN 1 WHEN MOD(80000 + 1 + FLOOR(POW(x.S1, 1.25) * 1200), 7) = 0 THEN 15
             ELSE 1 + MOD((80000 + 1 + FLOOR(POW(x.S1, 1.25) * 1200)) * 7, 17) END, x.PREF_ORD) AS BENE_CORR_ORD,
    'SCAM' AS KIND, FALSE AS IS_FRAUD, CAST(NULL AS VARCHAR) AS FRAUD_TYPE, (x.R8 < 0.72) AS IS_SCAM, 'NORMAL' AS SESSION_KIND,
    IFF(x.CHANNEL = 'Retail Agent', x.HOME_AGENT_ID, NULL) AS SEND_AGENT_ID
FROM (
    SELECT p.CUST_NUM, n.K, p.ACTIVE_DAYS, p.S1, p.S2, p.PREF_ORD, p.HAS_BANK, p.SEND_COUNTRY, p.HOME_AGENT_ID,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8,
        CASE WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.45 THEN 'Retail Agent' WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.8 THEN 'Mobile App'
             ELSE 'Web' END AS CHANNEL
    FROM CUST_PLAN p JOIN NUMS n ON n.K <= 1 + MOD(p.CUST_NUM * 3, 4) WHERE p.PROFILE = 'SCAM'
) x;

-- ============================================================================
-- BENEFICIARIES: 80,000 customer-owned + 1,600 mule pool + 600 legitimate hub payees
-- ============================================================================
INSERT INTO BENEFICIARIES
SELECT 'B' || LPAD(g.N::VARCHAR, 7, '0'),
    'C' || LPAD(IFF(g.N <= 80000, FLOOR((g.N + 1) / 2), 1 + MOD(g.N * 17, 40000))::VARCHAR, 6, '0'),
    GET(ARRAY_CONSTRUCT('Maria','Jose','Juan','Ana','Luis','Carmen','Carlos','Rosa','Miguel','Laura','Pedro','Sofia','Jorge','Elena','Diego',
        'Priya','Rahul','Amit','Sunita','Anil','Grace','Joy','Mark','Liza','Ramon','Nguyen','Linh','Wei','Li','Chen',
        'Fatima','Ahmed','Hassan','Amina','Chidi','Ngozi','Kwame','Abena','Marie','Jean'), MOD(g.N * 7, 40)::INT)::VARCHAR,
    GET(ARRAY_CONSTRUCT('Garcia','Martinez','Lopez','Hernandez','Gonzalez','Rodriguez','Perez','Sanchez','Ramirez','Torres',
        'Patel','Sharma','Singh','Kumar','Reddy','Santos','Reyes','Cruz','Bautista','Mendoza',
        'Tran','Pham','Wang','Zhang','Liu','Khan','Ali','Hussain','Okafor','Adeyemi',
        'Mensah','Boateng','Osei','Pierre','Joseph','Baptiste','Smith','Johnson','Brown','Davis'), MOD(g.N * 11 + FLOOR(g.N / 40), 40)::INT)::VARCHAR,
    o.PAYOUT_COUNTRY,
    GET(ARRAY_CONSTRUCT('Guadalajara','Guatemala City','San Salvador','Tegucigalpa','Santo Domingo','Bogota','Kingston','Port-au-Prince','Manila','Mumbai',
        'Ho Chi Minh City','Shanghai','Karachi','Dhaka','Lagos','Accra','Cairo','Medellin','Delhi','Cebu'), (o.ORD - 1)::INT)::VARCHAR,
    CASE WHEN g.N BETWEEN 80001 AND 81600 THEN CASE WHEN MOD(g.N * 3, 100) < 30 THEN 'Other' WHEN MOD(g.N * 3, 100) < 60 THEN 'Friend'
                                                    WHEN MOD(g.N * 3, 100) < 80 THEN 'Family' WHEN MOD(g.N * 3, 100) < 95 THEN 'Business' ELSE 'Self' END
         WHEN g.N > 82200 THEN IFF(MOD(g.N * 3, 100) < 70, 'Family', 'Friend')
         WHEN g.N > 81600 THEN IFF(MOD(g.N * 3, 100) < 80, 'Business', 'Friend')
         ELSE CASE WHEN MOD(g.N * 3, 100) < 60 THEN 'Family' WHEN MOD(g.N * 3, 100) < 80 THEN 'Friend' WHEN MOD(g.N * 3, 100) < 88 THEN 'Business'
                   WHEN MOD(g.N * 3, 100) < 93 THEN 'Self' ELSE 'Other' END END,
    CASE WHEN g.N BETWEEN 80001 AND 81600 THEN CASE WHEN MOD(g.N * 13, 100) < 62 THEN 'Cash Pickup' WHEN MOD(g.N * 13, 100) < 85 THEN 'Mobile Wallet' ELSE 'Bank Deposit' END
         ELSE CASE WHEN MOD(g.N * 13, 100) < 52 THEN 'Cash Pickup' WHEN MOD(g.N * 13, 100) < 78 THEN 'Bank Deposit'
                   WHEN MOD(g.N * 13, 100) < 92 THEN 'Mobile Wallet' ELSE 'Home Delivery' END END,
    GET(ARRAY_CONSTRUCT('Banco Nacional','BDO Unibank','State Bank','First Citizens','Banco Popular','Ecobank','Access Bank','BAC Credomatic','Banrural','Metrobank'), MOD(g.N, 10)::INT)::VARCHAR,
    LPAD(MOD(g.N * 7919, 10000)::VARCHAR, 4, '0'),
    DATEADD(DAY, -1 * UNIFORM(1, 500, RANDOM()), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
    (g.N BETWEEN 80001 AND 81600 AND MOD(ABS(HASH(g.N)), 100) < 75)
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N FROM TABLE(GENERATOR(ROWCOUNT => 90200))) g
LEFT JOIN CUST_PLAN cp ON g.N <= 80000 AND cp.CUST_NUM = FLOOR((g.N + 1) / 2)
JOIN CORR_ORD o ON o.ORD = CASE WHEN g.N <= 80000 THEN cp.PREF_ORD
                                WHEN g.N <= 81600 THEN CASE WHEN MOD(g.N, 5) = 0 THEN 1 WHEN MOD(g.N, 7) = 0 THEN 15 ELSE 1 + MOD(g.N * 7, 17) END
                                WHEN g.N <= 82200 THEN 1 + FLOOR((g.N - 81601) / 30)
                                ELSE 1 + FLOOR((g.N - 82201) / 400) END;

UPDATE BENEFICIARIES SET BANK_NAME = NULL, ACCOUNT_LAST4 = NULL WHERE PREFERRED_PAYOUT_METHOD <> 'Bank Deposit';

-- ============================================================================
-- FUNDING SOURCES: PCI DSS token, BIN and last 4 only
-- ============================================================================
INSERT INTO FUNDING_SOURCES
SELECT 'FS' || LPAD(((p.CUST_NUM - 1) * 4 + t.T)::VARCHAR, 7, '0'), p.CUSTOMER_ID, t.TYPE,
    IFF(t.T IN (2, 3), 'tok_' || LPAD(TO_VARCHAR(ABS(HASH(p.CUST_NUM, t.T)) % 1000000000000), 12, '0'), NULL),
    IFF(t.T IN (2, 3), GET(ARRAY_CONSTRUCT('411111','424242','453201','510510','555544','520082','371449','378282','601100','601111','400555','541333'),
                           MOD(p.CUST_NUM + t.T, 12)::INT)::VARCHAR, NULL),
    IFF(t.T IN (2, 3), LPAD((ABS(HASH(p.CUST_NUM, t.T, 9)) % 10000)::VARCHAR, 4, '0'), NULL),
    IFF(t.T IN (2, 3), CASE WHEN MOD(p.CUST_NUM + t.T, 12) IN (0,1,2,10) THEN 'Visa' WHEN MOD(p.CUST_NUM + t.T, 12) IN (3,4,5,11) THEN 'Mastercard'
                            WHEN MOD(p.CUST_NUM + t.T, 12) IN (6,7) THEN 'Amex' ELSE 'Discover' END, NULL),
    IFF(t.T IN (2, 3), IFF(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < CASE p.PROFILE WHEN 'CARD' THEN 0.40 WHEN 'SYN' THEN 0.25 WHEN 'RING' THEN 0.20 ELSE 0.03 END,
                           GET(ARRAY_CONSTRUCT('Mexico','Nigeria','Brazil','Philippines','India','Turkey','Romania','Vietnam'), MOD(p.CUST_NUM, 8)::INT)::VARCHAR,
                           p.SEND_COUNTRY), NULL),
    IFF(t.T = 4, GET(ARRAY_CONSTRUCT('Chase','Bank of America','Wells Fargo','Citibank','US Bank','PNC','Capital One','TD Bank'), MOD(p.CUST_NUM, 8)::INT)::VARCHAR, NULL),
    IFF(t.T = 4, LPAD((ABS(HASH(p.CUST_NUM, 4, 7)) % 10000)::VARCHAR, 4, '0'), NULL),
    DATEADD(HOUR, 3, DATEADD(DAY, -1 * p.SIGNUP_DAYS, CURRENT_DATE())::TIMESTAMP_NTZ),
    IFF(p.PROFILE IN ('SYN','CARD') AND t.T IN (2, 3) AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.3, 'Removed', 'Active')
FROM CUST_PLAN p
JOIN (SELECT column1 AS T, column2 AS TYPE FROM VALUES (1,'Cash'),(2,'Debit Card'),(3,'Credit Card'),(4,'Bank Account')) t
  ON (t.T IN (1, 2) OR (t.T = 3 AND p.HAS_CREDIT) OR (t.T = 4 AND p.HAS_BANK));

-- ============================================================================
-- TRANSFERS: assemble all behaviors, apply agent-collusion pattern, derive fields
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CAND_ALL AS
SELECT * FROM CAND_NORMAL
UNION ALL BY NAME SELECT * FROM CAND_SYN
UNION ALL BY NAME SELECT * FROM CAND_ATO
UNION ALL BY NAME SELECT * FROM CAND_CARD
UNION ALL BY NAME SELECT * FROM CAND_RING
UNION ALL BY NAME SELECT * FROM CAND_STRUCT
UNION ALL BY NAME SELECT * FROM CAND_SCAM;

CREATE OR REPLACE TEMPORARY TABLE CAND_DRAW AS
SELECT c.*, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RC, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RA,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RS, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RS2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RP, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RM,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RF, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RT,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS RX
FROM CAND_ALL c;

CREATE OR REPLACE TEMPORARY TABLE CAND_FINAL AS
SELECT d.CUST_NUM, d.CREATED_AT, d.CHANNEL, d.FUNDING_TYPE, d.BENE_NUM, d.BENE_CORR_ORD, d.KIND, (d.IS_FRAUD AND MOD(ABS(HASH(d.CUST_NUM, d.CREATED_AT)), 100) < 93) AS IS_FRAUD,
    IFF(d.IS_FRAUD AND MOD(ABS(HASH(d.CUST_NUM, d.CREATED_AT)), 100) < 93, d.FRAUD_TYPE, NULL) AS FRAUD_TYPE, d.IS_SCAM,
    d.SESSION_KIND, d.SEND_AGENT_ID, d.RS, d.RS2, d.RP, d.RM, d.RF, d.RT, d.RX, d.AGENT_INTENSITY,
    IFF(d.AGENT_INTENSITY > 0 AND d.KIND = 'NORMAL' AND d.RC < d.AGENT_INTENSITY, ROUND(2500 + 490 * d.RA, 2), d.AMOUNT_USD) AS AMOUNT_USD,
    d.COLL AS AGENT_COLLUDES,
    ROW_NUMBER() OVER (ORDER BY d.CREATED_AT, d.CUST_NUM, d.BENE_NUM, d.AMOUNT_USD) AS RN,
    IFF(d.RM < 0.9,
        IFF(d.BENE_NUM BETWEEN 80001 AND 81600,
            CASE WHEN MOD(d.BENE_NUM * 13, 100) < 62 THEN 'Cash Pickup' WHEN MOD(d.BENE_NUM * 13, 100) < 85 THEN 'Mobile Wallet' ELSE 'Bank Deposit' END,
            CASE WHEN MOD(d.BENE_NUM * 13, 100) < 52 THEN 'Cash Pickup' WHEN MOD(d.BENE_NUM * 13, 100) < 78 THEN 'Bank Deposit'
                 WHEN MOD(d.BENE_NUM * 13, 100) < 92 THEN 'Mobile Wallet' ELSE 'Home Delivery' END),
        'Cash Pickup') AS PAYOUT_METHOD
FROM (
    SELECT c.*, COALESCE(a.CONFIRMED_COLLUSION, FALSE) AS COLL,
        -- Heterogeneous agent behavior: colluding agents vary in intensity and some honest, cash-heavy agents look similar
        CASE WHEN a.CONFIRMED_COLLUSION THEN 0.02 + 0.12 * (MOD(ABS(HASH(c.SEND_AGENT_ID, 7)), 100) / 100.0)
             WHEN a.AGENT_ID IS NOT NULL AND MOD(ABS(HASH(c.SEND_AGENT_ID)), 5) = 0 THEN 0.02 + 0.13 * (MOD(ABS(HASH(c.SEND_AGENT_ID, 7)), 100) / 100.0)
             ELSE 0 END AS AGENT_INTENSITY
    FROM CAND_DRAW c
    LEFT JOIN AGENT_LOCATIONS a ON a.AGENT_ID = c.SEND_AGENT_ID
) d;

INSERT INTO TRANSFERS
SELECT 'T' || LPAD(f.RN::VARCHAR, 9, '0'),
    p.CUSTOMER_ID,
    'B' || LPAD(f.BENE_NUM::VARCHAR, 7, '0'),
    o.CORRIDOR_ID,
    f.CHANNEL,
    f.SEND_AGENT_ID,
    IFF(f.PAYOUT_METHOD = 'Cash Pickup', pa.AGENT_ID, NULL),
    f.PAYOUT_METHOD,
    'FS' || LPAD(((f.CUST_NUM - 1) * 4 + CASE f.FUNDING_TYPE WHEN 'Cash' THEN 1 WHEN 'Debit Card' THEN 2 WHEN 'Credit Card' THEN 3 ELSE 4 END)::VARCHAR, 7, '0'),
    f.FUNDING_TYPE,
    IFF(f.CHANNEL <> 'Retail Agent', 'S' || LPAD(f.RN::VARCHAR, 8, '0'), NULL),
    f.CREATED_AT,
    f.AMOUNT_USD,
    o.SEND_CURRENCY,
    ROUND(f.AMOUNT_USD * o.USD_TO_SEND_RATE, 2),
    o.PAYOUT_CURRENCY,
    ROUND(f.AMOUNT_USD * o.USD_TO_PAYOUT_RATE * (1 - (0.008 + 0.017 * f.RF)), 2),
    ROUND(o.USD_TO_PAYOUT_RATE * (1 - (0.008 + 0.017 * f.RF)), 6),
    ROUND(LEAST(60, IFF(f.CHANNEL = 'Retail Agent', 3.0 + 0.012 * f.AMOUNT_USD, 1.5 + 0.007 * f.AMOUNT_USD)), 2),
    ROUND(f.AMOUNT_USD * (0.008 + 0.017 * f.RF), 2),
    CASE WHEN f.KIND = 'SCAM' THEN CASE WHEN f.RP < 0.35 THEN 'Family Support' WHEN f.RP < 0.60 THEN 'Investment' WHEN f.RP < 0.80 THEN 'Gift' ELSE 'Other' END
         WHEN f.KIND = 'STRUCT' THEN IFF(f.RP < 0.7, 'Family Support', 'Business')
         ELSE CASE WHEN f.RP < 0.55 THEN 'Family Support' WHEN f.RP < 0.67 THEN 'Bills' WHEN f.RP < 0.73 THEN 'Education' WHEN f.RP < 0.78 THEN 'Medical'
                   WHEN f.RP < 0.84 THEN 'Savings' WHEN f.RP < 0.90 THEN 'Gift' WHEN f.RP < 0.95 THEN 'Business' WHEN f.RP < 0.97 THEN 'Investment' ELSE 'Other' END END,
    CASE WHEN f.IS_FRAUD THEN CASE WHEN f.RS < 0.70 THEN 'Paid' WHEN f.RS < 0.82 THEN 'Blocked' WHEN f.RS < 0.92 THEN 'Refunded' ELSE 'Cancelled' END
         WHEN f.AGENT_INTENSITY > 0 AND f.RS < f.AGENT_INTENSITY * 0.25 THEN 'Cancelled'
         WHEN f.RS < 0.013 THEN 'Cancelled'
         WHEN f.RS < 0.023 THEN 'Refunded'
         WHEN f.RS < 0.0245 AND f.CREATED_AT >= DATEADD(DAY, -10, CURRENT_TIMESTAMP()) THEN 'On Hold'
         WHEN f.CREATED_AT >= DATEADD(DAY, -3, CURRENT_TIMESTAMP()) AND f.PAYOUT_METHOD = 'Cash Pickup' AND f.RS2 < 0.5 THEN 'Available for Pickup'
         ELSE 'Paid' END,
    NULL, NULL, NULL,
    f.AMOUNT_USD >= 3000,
    NULL, NULL, NULL, NULL, NULL,
    f.IS_FRAUD, f.FRAUD_TYPE, f.IS_SCAM
FROM CAND_FINAL f
JOIN CUST_PLAN p ON p.CUST_NUM = f.CUST_NUM
JOIN CORR_ORD o ON o.ORD = f.BENE_CORR_ORD
LEFT JOIN PAYOUT_AGENTS pa ON pa.COUNTRY = o.PAYOUT_COUNTRY AND pa.RN = 1 + MOD(f.RN * 7, pa.CNT);

-- Timestamps for paid / cancelled transfers
UPDATE TRANSFERS t SET
    PAID_AT = IFF(t.STATUS = 'Paid',
        LEAST(DATEADD(MINUTE, CASE t.PAYOUT_METHOD WHEN 'Mobile Wallet' THEN 2 + MOD(ABS(HASH(t.TRANSFER_ID)), 28)
                                                  WHEN 'Bank Deposit' THEN 60 + MOD(ABS(HASH(t.TRANSFER_ID)), 1380)
                                                  WHEN 'Cash Pickup' THEN 10 + MOD(ABS(HASH(t.TRANSFER_ID)), 2800)
                                                  ELSE 1440 + MOD(ABS(HASH(t.TRANSFER_ID)), 2880) END, t.CREATED_AT),
              CURRENT_TIMESTAMP()::TIMESTAMP_NTZ), NULL),
    CANCELLED_AT = IFF(t.STATUS IN ('Cancelled', 'Refunded'),
        DATEADD(MINUTE, IFF(MOD(ABS(HASH(t.TRANSFER_ID, 5)), 100) < 55, 1 + MOD(ABS(HASH(t.TRANSFER_ID, 6)), 28), 120 + MOD(ABS(HASH(t.TRANSFER_ID, 7)), 2800)), t.CREATED_AT), NULL),
    CANCELLED_WITHIN_WINDOW = IFF(t.STATUS IN ('Cancelled', 'Refunded'), MOD(ABS(HASH(t.TRANSFER_ID, 5)), 100) < 55, NULL);

-- FATF Travel Rule: originator and beneficiary details on every transfer of $3,000 or more
UPDATE TRANSFERS t SET
    ORIGINATOR_NAME = c.FIRST_NAME || ' ' || c.LAST_NAME,
    ORIGINATOR_ADDRESS = c.CITY || ', ' || c.COUNTRY_OF_RESIDENCE,
    ORIGINATOR_ACCOUNT_REF = t.FUNDING_SOURCE_ID,
    BENEFICIARY_NAME = b.FIRST_NAME || ' ' || b.LAST_NAME,
    BENEFICIARY_ADDRESS = b.CITY || ', ' || b.COUNTRY
FROM CUSTOMERS c, BENEFICIARIES b
WHERE t.TRAVEL_RULE_REQUIRED AND c.CUSTOMER_ID = t.CUSTOMER_ID AND b.BENEFICIARY_ID = t.BENEFICIARY_ID;

-- Beneficiaries: creation time follows first use; the first sender is the creator; drop unused rows
UPDATE BENEFICIARIES b SET
    CREATED_AT = DATEADD(MINUTE, -1 * (5 + MOD(ABS(HASH(b.BENEFICIARY_ID)), 4000)), m.FIRST_TS),
    CREATED_BY_CUSTOMER_ID = m.FIRST_CUSTOMER
FROM (SELECT BENEFICIARY_ID, MIN(CREATED_AT) AS FIRST_TS, MIN_BY(CUSTOMER_ID, CREATED_AT) AS FIRST_CUSTOMER
      FROM TRANSFERS GROUP BY BENEFICIARY_ID) m
WHERE m.BENEFICIARY_ID = b.BENEFICIARY_ID;

DELETE FROM BENEFICIARIES WHERE BENEFICIARY_ID NOT IN (SELECT DISTINCT BENEFICIARY_ID FROM TRANSFERS);

-- Stolen / synthetic-identity cards and accounts are added just before first use
UPDATE FUNDING_SOURCES fs SET ADDED_AT = GREATEST(c.SIGNUP_TS, DATEADD(HOUR, -1 * (1 + MOD(ABS(HASH(fs.FUNDING_SOURCE_ID)), 48)), u.FIRST_USE))
FROM (SELECT FUNDING_SOURCE_ID, MIN(CREATED_AT) AS FIRST_USE FROM TRANSFERS GROUP BY FUNDING_SOURCE_ID) u,
     (SELECT CUSTOMER_ID, SIGNUP_DATE::TIMESTAMP_NTZ AS SIGNUP_TS FROM CUSTOMERS) c,
     (SELECT CUSTOMER_ID, PROFILE FROM CUST_PLAN) pr
WHERE u.FUNDING_SOURCE_ID = fs.FUNDING_SOURCE_ID AND c.CUSTOMER_ID = fs.CUSTOMER_ID AND pr.CUSTOMER_ID = fs.CUSTOMER_ID
  AND pr.PROFILE IN ('CARD', 'SYN', 'RING') AND fs.SOURCE_TYPE <> 'Cash';

UPDATE CUSTOMERS c SET LOYALTY_TIER = CASE WHEN a.N >= 60 THEN 'Platinum' WHEN a.N >= 30 THEN 'Gold' WHEN a.N >= 12 THEN 'Silver' ELSE 'None' END
FROM (SELECT CUSTOMER_ID, COUNT(*) AS N FROM TRANSFERS GROUP BY CUSTOMER_ID) a WHERE a.CUSTOMER_ID = c.CUSTOMER_ID;

-- Ring members share one phone number (already keyed in CUSTOMERS.PHONE via SHARE_KEY)

-- ============================================================================
-- APP SESSIONS and DEVICES
--   Sessions: one per digital transfer, plus ATO attempts without a transfer,
--   plus ordinary extra logins (some credential-stuffing noise).
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE SESS_SRC AS
SELECT 'S' || LPAD(f.RN::VARCHAR, 8, '0') AS SESSION_ID, f.CUST_NUM,
       DATEADD(MINUTE, -1 * (2 + MOD(ABS(HASH(f.RN)), 28)), f.CREATED_AT) AS LOGIN_AT,
       f.CHANNEL, f.SESSION_KIND AS KIND, TRUE AS SUCCESS_FORCED
FROM CAND_FINAL f WHERE f.CHANNEL <> 'Retail Agent'
UNION ALL
SELECT 'S' || LPAD((5500000 + ROW_NUMBER() OVER (ORDER BY a.CUST_NUM, a.J))::VARCHAR, 8, '0'), a.CUST_NUM, a.LOGIN_AT,
       IFF(a.R3 < 0.55, 'Mobile App', 'Web'), 'ATO', CAST(NULL AS BOOLEAN)
FROM ATO_SESS a WHERE NOT a.HAS_TRANSFER
UNION ALL
SELECT 'S' || LPAD((5000000 + ROW_NUMBER() OVER (ORDER BY x.CUST_NUM, x.K))::VARCHAR, 8, '0'), x.CUST_NUM,
       DATEADD(SECOND, IFF(x.R3 < 0.2, MOD(20 + FLOOR(x.R2 * 10), 24), 8 + FLOOR(x.R2 * 12))::INT * 3600 + FLOOR(x.R4 * 3599),
               DATEADD(DAY, -1 * (1 + FLOOR(x.R1 * x.ACTIVE_DAYS)), CURRENT_DATE())::TIMESTAMP_NTZ),
       IFF(x.SIGNUP_CHANNEL = 'Mobile App', IFF(x.R5 < 0.9, 'Mobile App', 'Web'), IFF(x.R5 < 0.9, 'Web', 'Mobile App')),
       CASE WHEN x.R6 < 0.015 THEN 'STUFF' WHEN x.R6 < 0.027 THEN 'RISKY' ELSE 'NORMAL' END, CAST(NULL AS BOOLEAN)
FROM (
    SELECT p.CUST_NUM, n.K, p.ACTIVE_DAYS, p.SIGNUP_CHANNEL,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6
    FROM CUST_PLAN p JOIN NUMS n ON n.K <= ROUND(p.N_NORMAL * 0.32)
    WHERE p.PROFILE <> 'SYN' AND p.SIGNUP_CHANNEL <> 'Retail Agent'
) x;

CREATE OR REPLACE TEMPORARY TABLE SESS_DRAW AS
SELECT s.*, k.SHARE_KEY, k.SEND_COUNTRY, p.HAS_DEV2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D1,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D2,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D3,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D4,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D5,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D7,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D8,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D9,  UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D10,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D11, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D12,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D13, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D14,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS D15
FROM SESS_SRC s
JOIN CUST_KEYS k ON k.CUST_NUM = s.CUST_NUM
JOIN CUST_PLAN p ON p.CUST_NUM = s.CUST_NUM;

-- EK: feature profile. A stealthy 15% of ATO sessions look like normal logins on device, geography and VPN.
CREATE OR REPLACE TEMPORARY TABLE SESS_1 AS
SELECT d.*,
    CASE WHEN d.KIND = 'ATO' AND d.D15 < 0.55 THEN 'NORMAL' WHEN d.KIND = 'STUFF' THEN 'NORMAL' ELSE d.KIND END AS EK
FROM SESS_DRAW d;

CREATE OR REPLACE TEMPORARY TABLE SESS_2 AS
SELECT s.*,
    CASE s.EK WHEN 'NORMAL' THEN s.D1 < 0.04 WHEN 'RISKY' THEN s.D1 < 0.90 WHEN 'ATO' THEN s.D1 < 0.80 ELSE s.D1 < 0.60 END AS IS_NEW_DEVICE,
    CASE s.EK WHEN 'NORMAL' THEN s.D4 < 0.04 WHEN 'RISKY' THEN s.D4 < 0.10 WHEN 'ATO' THEN s.D4 < 0.40 ELSE s.D4 < 0.30 END AS IS_VPN
FROM SESS_1 s;

CREATE OR REPLACE TEMPORARY TABLE SESS_STAGE AS
SELECT s.SESSION_ID, s.CUST_NUM, s.LOGIN_AT, s.CHANNEL, s.KIND, s.IS_NEW_DEVICE, s.IS_VPN,
    CASE WHEN s.KIND = 'ATO' AND s.IS_NEW_DEVICE THEN IFF(s.D2 < 0.5, 9000000 + 1 + FLOOR(s.D2 * 600), 7000000 + MOD(ABS(HASH(s.SESSION_ID)), 900000))
         WHEN s.KIND = 'NORMAL' AND s.D3 > 0.985 THEN 8000000 + MOD(ABS(HASH(s.SESSION_ID)), 250)
         WHEN s.KIND = 'ATO' THEN s.SHARE_KEY
         WHEN s.KIND = 'RISKY' THEN 4000000 + s.CUST_NUM
         WHEN s.KIND = 'FRAUDSTER' AND s.IS_NEW_DEVICE THEN 3000000 + s.CUST_NUM
         WHEN s.IS_NEW_DEVICE THEN 2000000 + s.CUST_NUM
         WHEN s.HAS_DEV2 AND s.D3 < 0.25 THEN 2000000 + s.CUST_NUM
         ELSE s.SHARE_KEY END AS DEVICE_KEY,
    CASE WHEN s.KIND = 'ATO' AND s.IS_NEW_DEVICE THEN IFF(s.D13 < 0.5, 100000 + 1 + FLOOR(s.D13 * 240), 120000 + MOD(ABS(HASH(s.SESSION_ID)), 8000))
         WHEN s.KIND = 'NORMAL' AND s.D3 > 0.985 THEN 110000 + MOD(ABS(HASH(s.SESSION_ID, 1)), 2000)
         WHEN s.IS_VPN THEN 110000 + MOD(ABS(HASH(s.SESSION_ID)), 2000)
         WHEN s.KIND = 'FRAUDSTER' AND s.IS_NEW_DEVICE THEN 112000 + MOD(s.CUST_NUM, 8000)
         WHEN s.KIND = 'RISKY' THEN 120000 + MOD(ABS(HASH(s.SESSION_ID)), 8000)
         WHEN s.SHARE_KEY >= 1000000 THEN 90000 + (s.SHARE_KEY - 1000000)
         ELSE s.SHARE_KEY END AS IP_KEY,
    CASE WHEN (s.KIND = 'ATO' AND s.IS_NEW_DEVICE AND s.D14 < 0.7) OR (s.IS_VPN) OR s.KIND = 'RISKY'
              OR (s.KIND = 'FRAUDSTER' AND s.IS_NEW_DEVICE AND s.D14 < 0.35)
         THEN GET(ARRAY_CONSTRUCT('Nigeria','Romania','Russia','Brazil','Vietnam','Ukraine','Indonesia','Netherlands','Turkey','India'),
                  MOD(ABS(HASH(s.SESSION_ID)), 10)::INT)::VARCHAR
         ELSE s.SEND_COUNTRY END AS IP_COUNTRY,
    CASE WHEN s.KIND = 'ATO' AND s.D10 < 0.55 THEN 'Password' WHEN s.KIND = 'ATO' AND s.D10 < 0.75 THEN 'OTP' WHEN s.KIND = 'ATO' THEN IFF(s.CHANNEL = 'Web', 'Password', 'Biometric')
         WHEN s.KIND = 'FRAUDSTER' THEN IFF(s.D10 < 0.75, 'Password', 'OTP')
         WHEN s.D10 < 0.40 THEN IFF(s.CHANNEL = 'Web', 'Password', 'Biometric') WHEN s.D10 < 0.85 THEN 'Password' ELSE 'OTP' END AS LOGIN_METHOD,
    COALESCE(s.SUCCESS_FORCED, CASE s.KIND WHEN 'STUFF' THEN s.D11 < 0.30 WHEN 'ATO' THEN s.D11 < 0.70 ELSE TRUE END) AS LOGIN_SUCCESS,
    CASE WHEN s.KIND = 'STUFF' THEN 3 + FLOOR(s.D8 * 7)
         WHEN s.EK = 'NORMAL' THEN CASE WHEN s.D7 < 0.90 THEN 0 WHEN s.D7 < 0.97 THEN 1 WHEN s.D7 < 0.995 THEN 2 ELSE 3 + FLOOR(s.D8 * 3) END
         WHEN s.EK = 'RISKY' THEN FLOOR(s.D7 * 3)
         WHEN s.EK = 'ATO' THEN IFF(s.D7 < 0.5, FLOOR(s.D8 * 2), 2 + FLOOR(s.D8 * 6))
         ELSE IFF(s.D7 < 0.8, 0, FLOOR(s.D8 * 3)) END AS FAILED_ATTEMPTS,
    CASE s.EK WHEN 'NORMAL' THEN s.D9 < 0.008 WHEN 'RISKY' THEN s.D9 < 0.03 WHEN 'ATO' THEN s.D9 < 0.25 ELSE s.D9 < 0.04 END AS PASSWORD_RESET_24H,
    ROUND(CASE s.EK WHEN 'NORMAL' THEN IFF(s.D5 < 0.95, s.D6 * 25, 25 + s.D6 * 375)
                    WHEN 'RISKY' THEN 800 + s.D6 * 8200
                    WHEN 'ATO' THEN IFF(s.D5 < 0.70, 500 + s.D6 * 8500, s.D6 * 25)
                    ELSE IFF(s.D5 < 0.25, 300 + s.D6 * 5000, s.D6 * 30) END, 1) AS GEO_DISTANCE_KM,
    CASE s.KIND WHEN 'ATO' THEN 40 + FLOOR(s.D12 * 320) WHEN 'FRAUDSTER' THEN 50 + FLOOR(s.D12 * 300) ELSE 40 + FLOOR(s.D12 * 560) END AS SESSION_DURATION_SEC,
    CASE s.KIND WHEN 'ATO' THEN 3 + FLOOR(s.D12 * 24) WHEN 'FRAUDSTER' THEN 4 + FLOOR(s.D12 * 24) WHEN 'STUFF' THEN 1 ELSE 3 + FLOOR(s.D12 * 36) END AS ACTIONS_COUNT,
    CASE s.KIND WHEN 'ATO' THEN s.D3 < 0.45 WHEN 'FRAUDSTER' THEN s.D3 < 0.45 WHEN 'RISKY' THEN s.D3 < 0.25 WHEN 'STUFF' THEN FALSE ELSE s.D3 < 0.14 END AS BENEFICIARY_ADDED,
    CASE s.KIND WHEN 'ATO' THEN s.D11 < 0.20 WHEN 'FRAUDSTER' THEN s.D11 < 0.08 WHEN 'RISKY' THEN s.D11 < 0.10 WHEN 'STUFF' THEN FALSE ELSE s.D11 < 0.045 END AS PROFILE_CHANGED
FROM SESS_2 s;

INSERT INTO APP_SESSIONS
SELECT s.SESSION_ID, c.CUSTOMER_ID, 'D' || LPAD(s.DEVICE_KEY::INT::VARCHAR, 7, '0'),
    '198.' || (18 + FLOOR(s.IP_KEY / 65536))::INT::VARCHAR || '.' || MOD(FLOOR(s.IP_KEY / 256), 256)::INT::VARCHAR || '.' || MOD(s.IP_KEY, 256)::INT::VARCHAR,
    s.IP_COUNTRY, IFF(s.CHANNEL = 'Web', 'Web', 'Mobile App'), s.LOGIN_AT, s.LOGIN_METHOD, s.LOGIN_SUCCESS,
    s.FAILED_ATTEMPTS::INT, s.IS_NEW_DEVICE, s.IS_VPN, s.PASSWORD_RESET_24H, s.GEO_DISTANCE_KM,
    s.SESSION_DURATION_SEC::INT, s.ACTIONS_COUNT::INT, s.BENEFICIARY_ADDED, s.PROFILE_CHANGED,
    (s.KIND = 'ATO')
FROM SESS_STAGE s JOIN CUST_PLAN c ON c.CUST_NUM = s.CUST_NUM;

INSERT INTO DEVICES
SELECT 'D' || LPAD(d.DEVICE_KEY::INT::VARCHAR, 7, '0'),
    SHA2('ria-device-' || d.DEVICE_KEY::VARCHAR, 256),
    CASE WHEN d.R1 < 0.40 THEN 'iOS' WHEN d.R1 < 0.85 THEN 'Android' WHEN d.R1 < 0.95 THEN 'Windows' ELSE 'macOS' END,
    GET(ARRAY_CONSTRUCT('7.8.1','7.9.0','8.0.2','8.1.0','8.2.1','8.3.0'), MOD(ABS(HASH(d.DEVICE_KEY)), 6)::INT)::VARCHAR,
    d.R2 < CASE WHEN d.DEVICE_KEY >= 9000000 OR d.DEVICE_KEY BETWEEN 7000000 AND 7999999 THEN 0.25 WHEN d.DEVICE_KEY BETWEEN 1000001 AND 1000040 THEN 0.12 ELSE 0.004 END,
    d.R3 < CASE WHEN d.DEVICE_KEY >= 9000000 OR d.DEVICE_KEY BETWEEN 7000000 AND 7999999 THEN 0.20 WHEN d.DEVICE_KEY BETWEEN 1000001 AND 1000040 THEN 0.10 ELSE 0.01 END,
    d.FIRST_SEEN
FROM (SELECT DEVICE_KEY, MIN(LOGIN_AT) AS FIRST_SEEN,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
      FROM SESS_STAGE GROUP BY DEVICE_KEY) d;

-- ============================================================================
-- HELPERS
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE T_KIND AS
SELECT 'T' || LPAD(RN::VARCHAR, 9, '0') AS TRANSFER_ID, CUST_NUM, KIND, AGENT_COLLUDES, SESSION_KIND FROM CAND_FINAL;

CREATE OR REPLACE TEMPORARY TABLE ANALYST_POOL AS
SELECT ANALYST_ID, QUEUE, ROW_NUMBER() OVER (PARTITION BY QUEUE ORDER BY ANALYST_ID) AS RN,
       COUNT(*) OVER (PARTITION BY QUEUE) AS CNT
FROM ANALYSTS;

-- ============================================================================
-- CHARGEBACKS on card-funded transfers (fraud-driven plus friendly fraud)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CB_DRAW AS
SELECT t.TRANSFER_ID, t.FUNDING_SOURCE_ID, t.FUNDING_TYPE, t.SEND_AMOUNT_USD, t.CREATED_AT, t.IS_FRAUD, k.KIND, (t.CHANNEL <> 'Retail Agent') AS IS_DIGITAL,
    (fs.ISSUER_COUNTRY <> c.COUNTRY_OF_RESIDENCE) AS FOREIGN_ISSUER,
    DATEDIFF(DAY, c.SIGNUP_DATE, t.CREATED_AT::DATE) AS TENURE_D,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
FROM TRANSFERS t
JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID
JOIN FUNDING_SOURCES fs ON fs.FUNDING_SOURCE_ID = t.FUNDING_SOURCE_ID
JOIN CUSTOMERS c ON c.CUSTOMER_ID = t.CUSTOMER_ID
WHERE t.FUNDING_TYPE IN ('Debit Card', 'Credit Card') AND t.STATUS = 'Paid';

CREATE OR REPLACE TEMPORARY TABLE CB_CAND AS
SELECT d.*,
    CASE WHEN d.R3 < 0.06 THEN 91 + FLOOR(d.R2 * 30) WHEN d.IS_FRAUD THEN 5 + FLOOR(d.R2 * 40) ELSE 20 + FLOOR(d.R2 * 65) END AS DAYS_FROM_TRANSFER
FROM CB_DRAW d
WHERE d.R1 < 1.0 / (1.0 + EXP(-1 * (-6.4
        + CASE WHEN d.IS_FRAUD THEN CASE d.KIND WHEN 'CARD' THEN 4.4 WHEN 'SYN' THEN 3.9 WHEN 'ATO' THEN 3.5 WHEN 'RING' THEN 3.1 ELSE 3.0 END ELSE 0 END
        + IFF(d.FUNDING_TYPE = 'Credit Card', 0.7, 0) + IFF(d.FOREIGN_ISSUER, 1.0, 0) + IFF(d.IS_DIGITAL, 0.5, 0)
        + 0.6 * LN(GREATEST(d.SEND_AMOUNT_USD, 20) / 150.0) + IFF(d.TENURE_D < 30, 0.6, 0) - IFF(d.TENURE_D > 365, 0.7, 0))));

INSERT INTO CHARGEBACKS
SELECT 'CB' || LPAD(ROW_NUMBER() OVER (ORDER BY c.CREATED_AT, c.TRANSFER_ID)::VARCHAR, 7, '0'),
    c.TRANSFER_ID, c.FUNDING_SOURCE_ID,
    CASE WHEN c.IS_FRAUD OR c.R3 < 0.35 THEN '10.4' WHEN c.R3 < 0.65 THEN '13.1' WHEN c.R3 < 0.80 THEN '12.6' ELSE '4837' END,
    CASE WHEN c.IS_FRAUD OR c.R3 < 0.35 THEN 'Fraud - Card Not Present' WHEN c.R3 < 0.65 THEN 'Not Received'
         WHEN c.R3 < 0.80 THEN 'Duplicate' ELSE 'Not Recognized' END,
    c.SEND_AMOUNT_USD,
    DATEADD(DAY, c.DAYS_FROM_TRANSFER, c.CREATED_AT),
    c.DAYS_FROM_TRANSFER,
    CASE WHEN DATEDIFF(DAY, DATEADD(DAY, c.DAYS_FROM_TRANSFER, c.CREATED_AT), CURRENT_TIMESTAMP()) < 20 THEN 'Open'
         WHEN DATEDIFF(DAY, DATEADD(DAY, c.DAYS_FROM_TRANSFER, c.CREATED_AT), CURRENT_TIMESTAMP()) < 60
              THEN CASE WHEN c.R2 < 0.30 THEN 'Open' WHEN c.R2 < 0.60 THEN 'Represented' WHEN c.R2 < 0.75 THEN 'Won' ELSE 'Lost' END
         ELSE CASE WHEN c.R2 < 0.25 THEN 'Won' WHEN c.R2 < 0.85 THEN 'Lost' ELSE 'Represented' END END
FROM CB_CAND c
WHERE DATEADD(DAY, c.DAYS_FROM_TRANSFER, c.CREATED_AT) <= CURRENT_TIMESTAMP();

-- ============================================================================
-- NACHA ACH RETURNS on bank-funded transfers
-- ============================================================================
INSERT INTO ACH_RETURNS
SELECT 'ACH' || LPAD(ROW_NUMBER() OVER (ORDER BY x.CREATED_AT, x.TRANSFER_ID)::VARCHAR, 7, '0'),
    x.TRANSFER_ID, x.CODE,
    CASE x.CODE WHEN 'R01' THEN 'Insufficient Funds' WHEN 'R02' THEN 'Account Closed' WHEN 'R03' THEN 'No Account / Unable to Locate Account'
                WHEN 'R04' THEN 'Invalid Account Number' WHEN 'R05' THEN 'Unauthorized Debit to Consumer Account'
                WHEN 'R07' THEN 'Authorization Revoked by Customer' WHEN 'R08' THEN 'Payment Stopped'
                WHEN 'R09' THEN 'Uncollected Funds' WHEN 'R10' THEN 'Customer Advises Not Authorized' ELSE 'Account Frozen' END,
    x.RETURNED_AT, x.SEND_AMOUNT_USD, x.CODE IN ('R05', 'R07', 'R10')
FROM (
    SELECT d.TRANSFER_ID, d.CREATED_AT, d.SEND_AMOUNT_USD,
        CASE WHEN d.IS_FRAUD THEN CASE WHEN d.R2 < 0.55 THEN 'R10' WHEN d.R2 < 0.80 THEN 'R05' ELSE 'R07' END
             ELSE CASE WHEN d.R2 < 0.45 THEN 'R01' WHEN d.R2 < 0.55 THEN 'R09' WHEN d.R2 < 0.67 THEN 'R02' WHEN d.R2 < 0.75 THEN 'R03'
                       WHEN d.R2 < 0.82 THEN 'R04' WHEN d.R2 < 0.90 THEN 'R08' WHEN d.R2 < 0.95 THEN 'R16' ELSE 'R10' END END AS CODE,
        DATEADD(DAY, IFF(d.IS_FRAUD OR d.R2 > 0.95, 3 + FLOOR(d.R3 * 52), 2 + FLOOR(d.R3 * 4)), d.CREATED_AT) AS RETURNED_AT
    FROM (
        SELECT t.TRANSFER_ID, t.CREATED_AT, t.SEND_AMOUNT_USD, t.IS_FRAUD,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
        FROM TRANSFERS t WHERE t.FUNDING_TYPE = 'Bank Account' AND t.STATUS = 'Paid'
    ) d
    WHERE d.R1 < IFF(d.IS_FRAUD, 0.45, 0.02)
) x
WHERE x.RETURNED_AT <= CURRENT_TIMESTAMP();

-- ============================================================================
-- REFUNDS (Reg E remittance rule timeliness)
-- ============================================================================
INSERT INTO REFUNDS
SELECT 'RF' || LPAD(ROW_NUMBER() OVER (ORDER BY x.REQUESTED_AT, x.TRANSFER_ID)::VARCHAR, 7, '0'),
    x.TRANSFER_ID, x.REASON,
    IFF(x.CANCELLED_WITHIN_WINDOW, x.SEND_AMOUNT_USD + x.FEE_USD, x.SEND_AMOUNT_USD),
    x.REQUESTED_AT,
    IFF(DATEADD(DAY, x.DAYS, x.REQUESTED_AT) <= CURRENT_TIMESTAMP(), DATEADD(DAY, x.DAYS, x.REQUESTED_AT), NULL),
    IFF(DATEADD(DAY, x.DAYS, x.REQUESTED_AT) <= CURRENT_TIMESTAMP(), x.DAYS, NULL),
    IFF(DATEADD(DAY, x.DAYS, x.REQUESTED_AT) <= CURRENT_TIMESTAMP(), x.DAYS <= 3, NULL)
FROM (
    SELECT d.TRANSFER_ID, d.SEND_AMOUNT_USD, d.FEE_USD, COALESCE(d.CANCELLED_WITHIN_WINDOW, FALSE) AS CANCELLED_WITHIN_WINDOW,
        LEAST(COALESCE(d.CANCELLED_AT, DATEADD(HOUR, 2 + 24 * FLOOR(d.R3 * 3), d.CREATED_AT)), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS REQUESTED_AT,
        CASE WHEN d.IS_FRAUD THEN 'Fraud' WHEN d.STATUS = 'Blocked' THEN 'Compliance Block'
             WHEN d.CANCELLED_WITHIN_WINDOW THEN 'Customer Cancellation'
             WHEN d.R1 < 0.35 THEN 'Not Picked Up' WHEN d.R1 < 0.85 THEN 'Customer Cancellation' ELSE 'Error Resolution' END AS REASON,
        CASE WHEN d.R2 < 0.60 THEN FLOOR(d.R3 * 2) WHEN d.R2 < 0.92 THEN 2 + FLOOR(d.R3 * 2) ELSE 4 + FLOOR(d.R3 * 4) END AS DAYS
    FROM (
        SELECT t.*, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
        FROM TRANSFERS t WHERE t.STATUS IN ('Cancelled', 'Refunded', 'Blocked')
    ) d
) x;

-- ============================================================================
-- DISPUTES (Reg E error notices)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE DISP_DRAW AS
SELECT t.TRANSFER_ID, t.CUSTOMER_ID, t.CREATED_AT, t.IS_FRAUD, t.PAYOUT_METHOD,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5
FROM TRANSFERS t WHERE t.STATUS = 'Paid';

CREATE OR REPLACE TEMPORARY TABLE DISP_CAND AS
SELECT d.*,
    LEAST(DATEADD(DAY, IFF(d.IS_FRAUD, 3 + FLOOR(d.R2 * 47), 1 + FLOOR(d.R2 * 59)), d.CREATED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS OPENED_AT,
    CASE WHEN d.IS_FRAUD AND d.R3 < 0.7 THEN 'Unauthorized'
         WHEN d.PAYOUT_METHOD = 'Home Delivery' AND d.R3 < 0.5 THEN 'Late Delivery'
         WHEN d.R3 < 0.30 THEN 'Not Received' WHEN d.R3 < 0.45 THEN 'Incorrect Amount' WHEN d.R3 < 0.60 THEN 'Wrong Beneficiary'
         WHEN d.R3 < 0.92 THEN 'Late Delivery' ELSE 'Unauthorized' END AS ERROR_TYPE,
    IFF(d.R4 < 0.04, 91 + FLOOR(d.R5 * 30), 2 + FLOOR(POW(d.R5, 1.7) * 50)) AS DAYS_TO_RESOLVE
FROM DISP_DRAW d
WHERE d.R1 < IFF(d.IS_FRAUD, 0.35, IFF(d.PAYOUT_METHOD = 'Home Delivery', 0.008, 0.0045));

INSERT INTO DISPUTES
SELECT 'DP' || LPAD(ROW_NUMBER() OVER (ORDER BY c.OPENED_AT, c.TRANSFER_ID)::VARCHAR, 7, '0'),
    c.TRANSFER_ID, c.CUSTOMER_ID, c.ERROR_TYPE, c.OPENED_AT,
    IFF(DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT) <= CURRENT_TIMESTAMP(), DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT), NULL),
    IFF(DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT) <= CURRENT_TIMESTAMP(), c.DAYS_TO_RESOLVE, NULL),
    IFF(DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT) <= CURRENT_TIMESTAMP(), c.DAYS_TO_RESOLVE <= 90, NULL),
    CASE WHEN DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT) <= CURRENT_TIMESTAMP() THEN 'Resolved'
         WHEN DATEDIFF(DAY, c.OPENED_AT, CURRENT_TIMESTAMP()) < 10 THEN 'Open' ELSE 'Investigating' END,
    IFF(DATEADD(DAY, c.DAYS_TO_RESOLVE, c.OPENED_AT) <= CURRENT_TIMESTAMP(),
        CASE WHEN c.ERROR_TYPE = 'Unauthorized' AND c.R4 < 0.85 THEN 'Error Confirmed - Refunded'
             WHEN c.R5 < 0.40 THEN 'Error Confirmed - Refunded' WHEN c.R5 < 0.52 THEN 'Error Confirmed - Resent' ELSE 'No Error Found' END, NULL),
    ap.ANALYST_ID
FROM DISP_CAND c
JOIN ANALYST_POOL ap ON ap.QUEUE = 'Disputes' AND ap.RN = 1 + MOD(ABS(HASH(c.TRANSFER_ID)), ap.CNT);

-- ============================================================================
-- FRAUD ALERTS: detections on fraud (true positives), noisy rule/model false
-- positives, structuring weeks, mules, scams and agent collusion
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE ALERT_SRC AS
-- (a) detected fraud transfers (85% caught in real time)
SELECT d.CUSTOMER_ID, d.TRANSFER_ID, CAST(NULL AS VARCHAR) AS AGENT_ID,
    CASE d.KIND WHEN 'ATO' THEN 'Account Takeover' WHEN 'CARD' THEN 'Card Fraud'
                WHEN 'RING' THEN IFF(d.R2 < 0.2, 'Velocity', 'Transaction Fraud')
                WHEN 'SYN' THEN IFF(d.FUNDING_TYPE IN ('Debit Card', 'Credit Card') AND d.R2 < 0.4, 'Card Fraud', 'Transaction Fraud')
                ELSE 'Card Fraud' END AS ALERT_TYPE,
    d.KIND, d.CREATED_AT AS BASE_TS, 'FRAUD' AS TRUTH, d.SEND_AMOUNT_USD AS AMOUNT
FROM (SELECT t.CUSTOMER_ID, t.TRANSFER_ID, t.FUNDING_TYPE, t.CREATED_AT, t.SEND_AMOUNT_USD, k.KIND,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2
      FROM TRANSFERS t JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID WHERE t.IS_FRAUD) d
WHERE d.R1 < 0.85
UNION ALL
-- (b) false-positive rule and model alerts on legitimate transfers
SELECT d.CUSTOMER_ID, d.TRANSFER_ID, NULL,
    CASE WHEN d.R2 < 0.5 THEN 'Transaction Fraud' WHEN d.R2 < 0.8 THEN 'Velocity' ELSE 'Card Fraud' END,
    'NORMAL', d.CREATED_AT, 'NONE', d.SEND_AMOUNT_USD
FROM (SELECT t.CUSTOMER_ID, t.TRANSFER_ID, t.CREATED_AT, t.SEND_AMOUNT_USD,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2
      FROM TRANSFERS t JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID
      WHERE NOT t.IS_FRAUD AND NOT t.IS_SCAM_VICTIM AND k.KIND <> 'STRUCT') d
WHERE d.R1 < 0.004 + 0.03 * LEAST(d.SEND_AMOUNT_USD, 3000) / 3000
UNION ALL
-- (c) scam-victim detections
SELECT d.CUSTOMER_ID, d.TRANSFER_ID, NULL, 'Scam Victim', 'SCAM', d.CREATED_AT, 'FRAUD', d.SEND_AMOUNT_USD
FROM (SELECT t.CUSTOMER_ID, t.TRANSFER_ID, t.CREATED_AT, t.SEND_AMOUNT_USD, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1
      FROM TRANSFERS t WHERE t.IS_SCAM_VICTIM) d
WHERE d.R1 < 0.75
UNION ALL
-- (d) structuring customer-weeks (confirmed pattern) and false-positive structuring weeks
SELECT w.CUSTOMER_ID, w.TOP_TRANSFER, NULL, 'Structuring', IFF(w.STRUCT_N >= 2, 'STRUCT', 'NORMAL'),
       LEAST(DATEADD(DAY, 8, w.WEEK_START::TIMESTAMP_NTZ), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ),
       IFF(w.STRUCT_N >= 2, 'FRAUD', 'NONE'), w.WEEK_TOTAL
FROM (SELECT t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE AS WEEK_START, MAX_BY(t.TRANSFER_ID, t.SEND_AMOUNT_USD) AS TOP_TRANSFER,
             SUM(t.SEND_AMOUNT_USD) AS WEEK_TOTAL, COUNT(*) AS N, COUNT_IF(k.KIND = 'STRUCT') AS STRUCT_N,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1
      FROM TRANSFERS t JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID
      WHERE t.STATUS <> 'Cancelled' GROUP BY t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE
      HAVING COUNT(*) >= 2 AND SUM(t.SEND_AMOUNT_USD) >= 3000) w
WHERE (w.STRUCT_N >= 2 AND w.R1 < 0.80) OR (w.STRUCT_N = 0 AND w.R1 < 0.03)
UNION ALL
-- (e) money-mule beneficiaries flagged
SELECT b.CREATED_BY_CUSTOMER_ID, a.LAST_T, NULL, 'Money Mule', 'MULE', LEAST(DATEADD(DAY, 1, a.LAST_TS), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ), 'FRAUD', a.AMT
FROM (SELECT BENEFICIARY_ID, MAX_BY(TRANSFER_ID, CREATED_AT) AS LAST_T, MAX(CREATED_AT) AS LAST_TS, COUNT(*) AS N, SUM(SEND_AMOUNT_USD) AS AMT,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1
      FROM TRANSFERS GROUP BY BENEFICIARY_ID) a
JOIN BENEFICIARIES b ON b.BENEFICIARY_ID = a.BENEFICIARY_ID
WHERE b.CONFIRMED_MULE AND a.N >= 2 AND a.R1 < 0.70
UNION ALL
-- (f) agent collusion alerts
SELECT cu.CUSTOMER_ID, NULL, ag.AGENT_ID, 'Agent Collusion', 'AGENT',
       DATEADD(DAY, -1 * (3 + FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * 500)), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ, 'FRAUD',
       ROUND(5000 + UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * 20000, 2)
FROM AGENT_LOCATIONS ag
JOIN NUMS n ON n.K <= 3 + MOD(ABS(HASH(ag.AGENT_ID)), 4)
JOIN (SELECT SEND_AGENT_ID, MIN(CUSTOMER_ID) AS CUSTOMER_ID FROM TRANSFERS WHERE SEND_AGENT_ID IS NOT NULL GROUP BY 1) cu ON cu.SEND_AGENT_ID = ag.AGENT_ID
WHERE ag.CONFIRMED_COLLUSION;

CREATE OR REPLACE TEMPORARY TABLE ALERT_DRAW AS
SELECT s.*,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS Q7
FROM ALERT_SRC s;

CREATE OR REPLACE TEMPORARY TABLE ALERT_1 AS
SELECT d.*,
    CASE WHEN d.Q1 < 0.40 THEN 'Model' WHEN d.Q1 < 0.90 THEN 'Rule' ELSE 'Referral' END AS DETECTION_SOURCE,
    LEAST(DATEADD(MINUTE, CASE WHEN d.ALERT_TYPE IN ('Structuring', 'Money Mule', 'Agent Collusion') THEN 0
                               WHEN d.Q1 < 0.40 THEN 1 + FLOOR(d.Q2 * 30) WHEN d.Q1 < 0.90 THEN 1 + FLOOR(d.Q2 * 120)
                               ELSE 1440 + FLOOR(d.Q2 * 13000) END, d.BASE_TS), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS CREATED_AT,
    IFF(d.TRUTH = 'FRAUD', 55 + 43 * POW(d.Q3, 0.7), 35 + 50 * d.Q3) AS SCORE
FROM ALERT_DRAW d;

CREATE OR REPLACE TEMPORARY TABLE ALERT_2 AS
SELECT a.*, DATEDIFF(DAY, a.CREATED_AT, CURRENT_TIMESTAMP()) AS AGE_D,
    CASE WHEN a.SCORE >= 90 OR a.AMOUNT >= 5000 THEN 'Critical' WHEN a.SCORE >= 75 THEN 'High' WHEN a.SCORE >= 55 THEN 'Medium' ELSE 'Low' END AS SEVERITY,
    CASE WHEN a.ALERT_TYPE IN ('Structuring', 'Money Mule') THEN 'AML Investigations' WHEN a.ALERT_TYPE = 'Agent Collusion' THEN 'Agent Oversight'
         ELSE 'Fraud Operations' END AS QUEUE
FROM ALERT_1 a;

CREATE OR REPLACE TEMPORARY TABLE ALERT_3 AS
SELECT a.*,
    CASE WHEN a.AGE_D < 7  THEN CASE WHEN a.Q4 < 0.55 THEN 'Open' WHEN a.Q4 < 0.80 THEN 'In Review' WHEN a.Q4 < 0.85 THEN 'Escalated' ELSE 'Closed' END
         WHEN a.AGE_D < 30 THEN CASE WHEN a.Q4 < 0.20 THEN 'Open' WHEN a.Q4 < 0.40 THEN 'In Review' WHEN a.Q4 < 0.48 THEN 'Escalated' ELSE 'Closed' END
         WHEN a.AGE_D < 90 THEN CASE WHEN a.Q4 < 0.06 THEN 'Open' WHEN a.Q4 < 0.12 THEN 'In Review' WHEN a.Q4 < 0.17 THEN 'Escalated' ELSE 'Closed' END
         ELSE CASE WHEN a.Q4 < 0.008 THEN 'Open' WHEN a.Q4 < 0.013 THEN 'In Review' WHEN a.Q4 < 0.018 THEN 'Escalated' ELSE 'Closed' END END AS STATUS,
    CASE WHEN a.TRUTH = 'FRAUD' THEN CASE WHEN a.Q5 < 0.80 THEN 'True Positive' WHEN a.Q5 < 0.95 THEN 'False Positive' ELSE 'Inconclusive' END
         ELSE CASE WHEN a.Q5 < 0.92 THEN 'False Positive' WHEN a.Q5 < 0.95 THEN 'True Positive' ELSE 'Inconclusive' END END AS DISP_DRAW
FROM ALERT_2 a;

CREATE OR REPLACE TEMPORARY TABLE ALERT_4 AS
SELECT a.*,
    IFF(a.STATUS = 'Closed', a.DISP_DRAW, NULL) AS DISPOSITION,
    (a.STATUS = 'Escalated' OR (a.STATUS = 'Closed' AND a.DISP_DRAW = 'True Positive' AND a.Q6 < 0.9)) AS HAS_CASE,
    CASE WHEN a.KIND = 'RING' THEN 'Fraud Ring'
         ELSE CASE a.ALERT_TYPE WHEN 'Account Takeover' THEN 'Account Takeover' WHEN 'Card Fraud' THEN 'Card Fraud' WHEN 'Structuring' THEN 'AML - Structuring'
                                WHEN 'Money Mule' THEN 'Money Mule' WHEN 'Scam Victim' THEN 'Scam' WHEN 'Agent Collusion' THEN 'Agent Collusion'
                                ELSE 'Fraud' END END AS CASE_TYPE,
    (a.STATUS <> 'Open' OR a.Q7 < 0.40) AS IS_ASSIGNED
FROM ALERT_3 a;

CREATE OR REPLACE TEMPORARY TABLE ALERT_5 AS
SELECT a.*,
    ROW_NUMBER() OVER (ORDER BY a.CREATED_AT, a.CUSTOMER_ID, a.ALERT_TYPE, a.AMOUNT) AS RN,
    IFF(a.HAS_CASE, a.CUSTOMER_ID || '|' || a.CASE_TYPE || '|' || FLOOR(DATEDIFF(DAY, '2025-01-01'::DATE, a.CREATED_AT::DATE) / 45), NULL) AS CASE_KEY
FROM ALERT_4 a;

CREATE OR REPLACE TEMPORARY TABLE ALERT_6 AS
SELECT a.*, IFF(a.CASE_KEY IS NULL, NULL, 'CS' || LPAD(DENSE_RANK() OVER (ORDER BY a.CASE_KEY)::VARCHAR, 7, '0')) AS CASE_ID,
    ap.ANALYST_ID AS ANALYST_ID_RES,
    IFF(a.IS_ASSIGNED, LEAST(DATEADD(MINUTE, 5 + FLOOR(a.Q2 * 2880), a.CREATED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ), NULL) AS ASSIGNED_AT_RES
FROM ALERT_5 a
LEFT JOIN ANALYST_POOL ap ON ap.QUEUE = a.QUEUE AND ap.RN = 1 + MOD(ABS(HASH(a.RN)), ap.CNT) AND a.IS_ASSIGNED;

INSERT INTO FRAUD_ALERTS
SELECT 'AL' || LPAD(a.RN::VARCHAR, 8, '0'), a.CUSTOMER_ID, a.TRANSFER_ID, a.AGENT_ID, a.ALERT_TYPE, a.DETECTION_SOURCE,
    CASE a.ALERT_TYPE WHEN 'Account Takeover' THEN 'ATO-' || (101 + MOD(a.RN, 6)) WHEN 'Card Fraud' THEN 'CNP-' || (201 + MOD(a.RN, 5))
         WHEN 'Structuring' THEN 'AML-STR-' || (1 + MOD(a.RN, 4)) WHEN 'Money Mule' THEN 'MULE-' || (1 + MOD(a.RN, 4))
         WHEN 'Scam Victim' THEN 'SCAM-' || (1 + MOD(a.RN, 5)) WHEN 'Agent Collusion' THEN 'AGT-' || (1 + MOD(a.RN, 3))
         WHEN 'Velocity' THEN 'VEL-' || (1 + MOD(a.RN, 5)) ELSE 'TXN-' || (301 + MOD(a.RN, 8)) END,
    ROUND(a.SCORE, 1), a.SEVERITY, a.QUEUE, a.CREATED_AT, a.STATUS, a.ANALYST_ID_RES, a.ASSIGNED_AT_RES, a.DISPOSITION,
    IFF(a.STATUS = 'Closed', LEAST(DATEADD(MINUTE, 60 + FLOOR(a.Q3 * 4000), COALESCE(a.ASSIGNED_AT_RES, a.CREATED_AT)), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ), NULL),
    a.CASE_ID
FROM ALERT_6 a;

-- ============================================================================
-- FRAUD CASES (built from escalated and true-positive alerts)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CASE_AGG AS
SELECT a.CASE_ID, MIN(a.CUSTOMER_ID) AS CUSTOMER_ID, MIN(a.CASE_TYPE) AS CASE_TYPE, MIN(a.QUEUE) AS QUEUE,
    LEAST(DATEADD(HOUR, 1 + FLOOR(MIN(a.Q2) * 24), MIN(a.CREATED_AT)), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS OPENED_AT,
    SUM(a.AMOUNT) AS EXPOSURE, COUNT(*) AS ALERT_COUNT, COUNT_IF(a.TRUTH = 'FRAUD') AS FRAUD_ALERTS,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS C1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS C2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS C3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS C4
FROM ALERT_6 a WHERE a.CASE_ID IS NOT NULL GROUP BY a.CASE_ID;

CREATE OR REPLACE TEMPORARY TABLE CASE_2 AS
SELECT c.*, DATEDIFF(DAY, c.OPENED_AT, CURRENT_TIMESTAMP()) AS AGE_D,
    LEAST(DATEADD(DAY, 3 + FLOOR(c.C2 * 57), c.OPENED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS CLOSE_TS,
    CASE WHEN DATEDIFF(DAY, c.OPENED_AT, CURRENT_TIMESTAMP()) < 14 THEN CASE WHEN c.C1 < 0.40 THEN 'Open' WHEN c.C1 < 0.80 THEN 'Investigating' WHEN c.C1 < 0.85 THEN 'Pending SAR Decision' ELSE 'Closed' END
         WHEN DATEDIFF(DAY, c.OPENED_AT, CURRENT_TIMESTAMP()) < 45 THEN CASE WHEN c.C1 < 0.10 THEN 'Open' WHEN c.C1 < 0.40 THEN 'Investigating' WHEN c.C1 < 0.50 THEN 'Pending SAR Decision' ELSE 'Closed' END
         WHEN DATEDIFF(DAY, c.OPENED_AT, CURRENT_TIMESTAMP()) < 120 THEN CASE WHEN c.C1 < 0.03 THEN 'Open' WHEN c.C1 < 0.11 THEN 'Investigating' WHEN c.C1 < 0.16 THEN 'Pending SAR Decision' ELSE 'Closed' END
         ELSE CASE WHEN c.C1 < 0.015 THEN 'Investigating' ELSE 'Closed' END END AS STATUS_DRAW,
    (c.CASE_TYPE IN ('AML - Structuring', 'Money Mule', 'Scam', 'Agent Collusion', 'Fraud Ring')) AS IS_AML_TYPE
FROM CASE_AGG c;

CREATE OR REPLACE TEMPORARY TABLE CASE_3 AS
SELECT c.*,
    CASE WHEN c.STATUS_DRAW = 'Closed' THEN 'Closed' ELSE c.STATUS_DRAW END AS STATUS,
    CASE WHEN c.STATUS_DRAW <> 'Closed' THEN NULL
         WHEN c.FRAUD_ALERTS > 0 THEN CASE WHEN c.C3 < 0.78 THEN 'Confirmed Fraud' WHEN c.C3 < 0.86 THEN 'Referred to Law Enforcement' ELSE 'Insufficient Evidence' END
         ELSE CASE WHEN c.C3 < 0.85 THEN 'Not Fraud' ELSE 'Insufficient Evidence' END END AS DISPOSITION
FROM CASE_2 c;

INSERT INTO FRAUD_CASES
SELECT c.CASE_ID, c.CUSTOMER_ID, c.CASE_TYPE, c.QUEUE,
    CASE WHEN c.EXPOSURE >= 10000 THEN 'P1' WHEN c.EXPOSURE >= 3000 THEN 'P2' WHEN c.EXPOSURE >= 1000 THEN 'P3' ELSE 'P4' END,
    c.OPENED_AT, c.STATUS, ap.ANALYST_ID, c.DISPOSITION, IFF(c.STATUS = 'Closed', c.CLOSE_TS, NULL),
    ROUND(c.EXPOSURE, 2),
    CASE WHEN c.STATUS = 'Pending SAR Decision' THEN NULL
         WHEN c.STATUS = 'Closed' THEN CASE WHEN c.DISPOSITION IN ('Confirmed Fraud', 'Referred to Law Enforcement')
                                            THEN c.C4 < IFF(c.IS_AML_TYPE, 0.65, 0.12) ELSE FALSE END
         WHEN c.STATUS = 'Investigating' AND c.IS_AML_TYPE AND c.C4 < 0.25 THEN TRUE
         ELSE NULL END
FROM CASE_3 c
JOIN ANALYST_POOL ap ON ap.QUEUE = c.QUEUE AND ap.RN = 1 + MOD(ABS(HASH(c.CASE_ID)), ap.CNT);

-- ============================================================================
-- CASE NOTES
-- ============================================================================
INSERT INTO CASE_NOTES
SELECT 'NT' || LPAD(ROW_NUMBER() OVER (ORDER BY x.CREATED_AT, x.CASE_ID, x.K)::VARCHAR, 8, '0'),
    x.CASE_ID, x.ANALYST_ID, x.CREATED_AT,
    CASE x.K
      WHEN 1 THEN CASE x.CASE_TYPE
         WHEN 'Account Takeover' THEN 'Initial review: login from an unrecognized device with failed attempts and a password reset in the prior 24 hours, followed by a new beneficiary and a transfer of about $' || x.EXPO || '. Customer contacted; account restricted pending verification.'
         WHEN 'Card Fraud' THEN 'Initial review: card-funded transfers in a short burst from a newly added card, issuer country differs from the customer. Exposure about $' || x.EXPO || '. Card token suspended and chargeback exposure flagged to disputes.'
         WHEN 'AML - Structuring' THEN 'Initial review: repeated cash sends just under reporting thresholds across the week totalling about $' || x.EXPO || '. Same agent location each day. Pulled prior four weeks for comparison.'
         WHEN 'Money Mule' THEN 'Initial review: beneficiary received transfers from several unrelated senders in a short window and cashed out within hours. Total received about $' || x.EXPO || '. Linked senders listed for outreach.'
         WHEN 'Scam' THEN 'Initial review: sender made repeated larger-than-usual transfers to a newly added beneficiary after contact from an unknown party. Total about $' || x.EXPO || '. Customer reached by phone; scam typology confirmed in conversation.'
         WHEN 'Agent Collusion' THEN 'Initial review: agent location shows elevated transfers just under the Travel Rule threshold, high cancellation rate and repeat customers with identical beneficiaries. Exposure estimated at $' || x.EXPO || '. Compliance audit requested.'
         WHEN 'Fraud Ring' THEN 'Initial review: multiple accounts share a phone number and device, onboarded within weeks of each other, sending to a small set of common beneficiaries. Combined exposure about $' || x.EXPO || '.'
         ELSE 'Initial review: transfers from a recently opened account with failed ID verification attempts and rapidly increasing amounts. Exposure about $' || x.EXPO || '. Identity documents requested.' END
      WHEN 2 THEN CASE x.CASE_TYPE
         WHEN 'Account Takeover' THEN 'Investigation: device fingerprint seen on other victim accounts. IP resolves to a hosting provider. Beneficiary added during the session was also used by earlier victims. Recall requested at payout.'
         WHEN 'Card Fraud' THEN 'Investigation: BIN and issuer mismatch confirmed with the card network. Same device used to fund transfers from several cards. Chargebacks expected within 45 days.'
         WHEN 'AML - Structuring' THEN 'Investigation: customer declared lower expected monthly volume at onboarding. Transfers split across days to stay beneath the $10,000 reporting level. Source of funds questionnaire sent.'
         WHEN 'Money Mule' THEN 'Investigation: beneficiary relationship declared as Other for most senders. Payouts at two agent locations within the same hour. Related beneficiaries share the same bank account last four.'
         WHEN 'Scam' THEN 'Investigation: sender is over 60 and reports being told to keep the transfers secret. Payout method cash pickup in a high-risk corridor. Elder fraud referral prepared.'
         WHEN 'Agent Collusion' THEN 'Investigation: agent training overdue and last audit rating below threshold. Counter staff IDs recorded on the suspicious transfers. Agent limits reduced while review continues.'
         WHEN 'Fraud Ring' THEN 'Investigation: link analysis connects accounts through shared device, IP and beneficiary. Largest cluster identified; remaining accounts monitored for onboarding of replacements.'
         ELSE 'Investigation: ID verification retried multiple times, email created days before signup, address shared with other accounts. Synthetic identity indicators match the typology guide.' END
      ELSE CASE WHEN x.STATUS = 'Closed' THEN
              CASE x.DISPOSITION WHEN 'Confirmed Fraud' THEN 'Conclusion: activity confirmed fraudulent. Accounts blocked, losses recorded, beneficiary and device added to watch lists.'
                                 WHEN 'Referred to Law Enforcement' THEN 'Conclusion: confirmed fraud with evidence package referred to law enforcement. Accounts blocked and records preserved.'
                                 WHEN 'Not Fraud' THEN 'Conclusion: customer confirmed the activity as genuine. Alert thresholds reviewed; no further action.'
                                 ELSE 'Conclusion: evidence insufficient to establish fraud. Case closed with monitoring flag applied.' END
            ELSE 'Update: awaiting customer response and payout confirmation from the partner. Next review scheduled in 3 days.' END END
FROM (
    SELECT c.CASE_ID, c.CASE_TYPE, c.STATUS, c.DISPOSITION, n.K, fc.ASSIGNED_ANALYST_ID AS ANALYST_ID, ROUND(c.EXPOSURE, 0)::INT AS EXPO,
        LEAST(DATEADD(DAY, n.K - 1, DATEADD(HOUR, 2, c.OPENED_AT)), COALESCE(IFF(c.STATUS = 'Closed', c.CLOSE_TS, NULL), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ)) AS CREATED_AT
    FROM CASE_3 c
    JOIN FRAUD_CASES fc ON fc.CASE_ID = c.CASE_ID
    JOIN NUMS n ON n.K <= IFF(c.STATUS = 'Closed', 3, 1 + MOD(ABS(HASH(c.CASE_ID)), 2))
) x;

-- ============================================================================
-- CASE EVENTS: FFIEC alert-to-case-to-disposition audit trail
-- ============================================================================
INSERT INTO CASE_EVENTS
SELECT 'EV' || LPAD(ROW_NUMBER() OVER (ORDER BY e.EVENT_AT, e.ALERT_ID, e.CASE_ID, e.EVENT_TYPE)::VARCHAR, 9, '0'),
    e.CASE_ID, e.ALERT_ID, e.EVENT_TYPE, e.ANALYST_ID, e.EVENT_AT, e.DETAIL
FROM (
    SELECT fa.CASE_ID, fa.ALERT_ID, 'Alert Created' AS EVENT_TYPE, CAST(NULL AS VARCHAR) AS ANALYST_ID, fa.CREATED_AT AS EVENT_AT,
           'Alert created by ' || fa.DETECTION_SOURCE || ' (' || fa.RULE_CODE || '), score ' || fa.ALERT_SCORE::VARCHAR AS DETAIL
    FROM FRAUD_ALERTS fa
    UNION ALL
    SELECT fa.CASE_ID, fa.ALERT_ID, 'Alert Assigned', fa.ASSIGNED_ANALYST_ID, fa.ASSIGNED_AT, 'Assigned to ' || fa.QUEUE || ' queue'
    FROM FRAUD_ALERTS fa WHERE fa.ASSIGNED_AT IS NOT NULL
    UNION ALL
    SELECT fa.CASE_ID, fa.ALERT_ID, 'Alert Closed', fa.ASSIGNED_ANALYST_ID, fa.CLOSED_AT, 'Disposition: ' || fa.DISPOSITION
    FROM FRAUD_ALERTS fa WHERE fa.CLOSED_AT IS NOT NULL
    UNION ALL
    SELECT fa.CASE_ID, fa.ALERT_ID, 'Escalated to Case', fa.ASSIGNED_ANALYST_ID,
           COALESCE(fa.CLOSED_AT, LEAST(DATEADD(HOUR, 3, COALESCE(fa.ASSIGNED_AT, fa.CREATED_AT)), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ)),
           'Escalated to case ' || fa.CASE_ID
    FROM FRAUD_ALERTS fa WHERE fa.CASE_ID IS NOT NULL
    UNION ALL
    SELECT fc.CASE_ID, NULL, 'Case Opened', fc.ASSIGNED_ANALYST_ID, fc.OPENED_AT, 'Case opened: ' || fc.CASE_TYPE || ', priority ' || fc.PRIORITY
    FROM FRAUD_CASES fc
    UNION ALL
    SELECT cn.CASE_ID, NULL, 'Note Added', cn.ANALYST_ID, cn.CREATED_AT, 'Investigator note added'
    FROM CASE_NOTES cn
    UNION ALL
    SELECT fc.CASE_ID, NULL, 'SAR Decision', fc.ASSIGNED_ANALYST_ID, COALESCE(fc.CLOSED_AT, LEAST(DATEADD(DAY, 10, fc.OPENED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ)),
           IFF(fc.SAR_REQUIRED, 'SAR required', 'SAR not required')
    FROM FRAUD_CASES fc WHERE fc.SAR_REQUIRED IS NOT NULL
    UNION ALL
    SELECT fc.CASE_ID, NULL, 'Case Closed', fc.ASSIGNED_ANALYST_ID, fc.CLOSED_AT, 'Disposition: ' || fc.DISPOSITION
    FROM FRAUD_CASES fc WHERE fc.CLOSED_AT IS NOT NULL
) e;

-- ============================================================================
-- FRAUD LOSSES, RECOVERIES AND WRITE-OFFS
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE LOSS_SRC AS
SELECT t.TRANSFER_ID, t.CREATED_AT, t.SEND_AMOUNT_USD,
    CASE WHEN k.AGENT_COLLUDES AND t.SEND_AMOUNT_USD BETWEEN 2500 AND 2990 AND NOT t.IS_FRAUD THEN 'Agent Fraud'
         WHEN t.IS_SCAM_VICTIM THEN 'Scam Reimbursement'
         WHEN k.KIND = 'ATO' THEN 'Account Takeover' WHEN k.KIND = 'SYN' THEN 'Synthetic Identity'
         WHEN t.FUNDING_TYPE IN ('Debit Card', 'Credit Card') THEN 'Card Chargeback'
         WHEN t.FUNDING_TYPE = 'Bank Account' THEN 'ACH Return' ELSE 'Unauthorized Transfer' END AS LOSS_TYPE,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS L1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS L2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS L3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS L4
FROM TRANSFERS t JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID
WHERE t.STATUS = 'Paid' AND (t.IS_FRAUD OR t.IS_SCAM_VICTIM OR (k.AGENT_COLLUDES AND t.SEND_AMOUNT_USD BETWEEN 2500 AND 2990));

CREATE OR REPLACE TEMPORARY TABLE LOSS_1 AS
SELECT s.*,
    LEAST(DATEADD(DAY, 1 + FLOOR(s.L1 * 44), s.CREATED_AT)::DATE, DATEADD(DAY, -1, CURRENT_DATE())) AS LOSS_DATE,
    CASE s.LOSS_TYPE WHEN 'Scam Reimbursement' THEN IFF(s.L4 < 0.25, 1, 0) WHEN 'Agent Fraud' THEN IFF(s.L4 < 0.06, 1, 0) ELSE 1 END AS KEEP_ROW,
    CASE s.LOSS_TYPE WHEN 'Account Takeover' THEN 0.30 WHEN 'Card Chargeback' THEN 0.35 WHEN 'ACH Return' THEN 0.25 WHEN 'Agent Fraud' THEN 0.55
                     WHEN 'Scam Reimbursement' THEN 0.10 WHEN 'Synthetic Identity' THEN 0.08 ELSE 0.15 END AS P_RECOVER,
    CASE s.LOSS_TYPE WHEN 'Account Takeover' THEN 'Payout Recall' WHEN 'Card Chargeback' THEN 'Chargeback Representment'
                     WHEN 'ACH Return' THEN 'Customer Repayment' WHEN 'Agent Fraud' THEN 'Agent Clawback' ELSE 'Payout Recall' END AS METHOD
FROM LOSS_SRC s;

INSERT INTO FRAUD_LOSSES
SELECT 'LS' || LPAD(ROW_NUMBER() OVER (ORDER BY l.LOSS_DATE, l.TRANSFER_ID)::VARCHAR, 7, '0'),
    l.TRANSFER_ID, fa.CASE_ID, l.LOSS_TYPE, l.LOSS_DATE,
    l.SEND_AMOUNT_USD,
    ROUND(IFF(l.L2 < l.P_RECOVER, l.SEND_AMOUNT_USD * (0.2 + 0.8 * l.L3), 0), 2),
    IFF(DATEDIFF(DAY, l.LOSS_DATE, CURRENT_DATE()) > 90 AND l.L3 < 0.5,
        ROUND(l.SEND_AMOUNT_USD - IFF(l.L2 < l.P_RECOVER, l.SEND_AMOUNT_USD * (0.2 + 0.8 * l.L3), 0), 2), 0),
    ROUND(l.SEND_AMOUNT_USD - IFF(l.L2 < l.P_RECOVER, l.SEND_AMOUNT_USD * (0.2 + 0.8 * l.L3), 0), 2),
    IFF(l.L2 < l.P_RECOVER, l.METHOD, 'None')
FROM LOSS_1 l
LEFT JOIN (SELECT TRANSFER_ID, MIN(CASE_ID) AS CASE_ID FROM FRAUD_ALERTS WHERE TRANSFER_ID IS NOT NULL GROUP BY TRANSFER_ID) fa ON fa.TRANSFER_ID = l.TRANSFER_ID
WHERE l.KEEP_ROW = 1;

-- ============================================================================
-- SANCTIONS SCREENING HITS (OFAC SDN, EU, UN, UK HMT)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE SCR_DRAW AS
SELECT t.TRANSFER_ID, t.CUSTOMER_ID, t.BENEFICIARY_ID, t.CREATED_AT, co.CORRIDOR_RISK_SCORE,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R5, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R6,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R7, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R8, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R9,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R10
FROM TRANSFERS t JOIN CORRIDORS co ON co.CORRIDOR_ID = t.CORRIDOR_ID;

CREATE OR REPLACE TEMPORARY TABLE SCR_1 AS
SELECT d.*, (d.R2 < 0.015 + 0.08 * d.CORRIDOR_RISK_SCORE / 100.0) AS IS_TRUE, (d.R3 < 0.25) AS HARD_FP, (MOD(ABS(HASH(d.TRANSFER_ID, 5)), 100) < 30) AS WEAK_TRUE
FROM SCR_DRAW d WHERE d.R1 < 0.0050;

CREATE OR REPLACE TEMPORARY TABLE SCR_2 AS
SELECT s.*,
    ROUND(CASE WHEN s.IS_TRUE AND NOT s.WEAK_TRUE THEN 0.72 + 0.27 * POW(s.R4, 0.7) WHEN s.HARD_FP OR s.IS_TRUE THEN 0.78 + 0.18 * s.R4 ELSE 0.52 + 0.44 * s.R4 END, 3) AS NAME_SIM,
    CASE WHEN s.IS_TRUE AND NOT s.WEAK_TRUE THEN s.R5 < 0.60 WHEN s.HARD_FP OR s.IS_TRUE THEN s.R5 < 0.35 ELSE s.R5 < 0.10 END AS DOB_MATCH,
    CASE WHEN s.IS_TRUE AND NOT s.WEAK_TRUE THEN s.R6 < 0.55 WHEN s.HARD_FP OR s.IS_TRUE THEN s.R6 < 0.35 ELSE s.R6 < 0.20 END AS COUNTRY_MATCH,
    CASE WHEN s.IS_TRUE AND NOT s.WEAK_TRUE THEN s.R7 < 0.30 WHEN s.HARD_FP OR s.IS_TRUE THEN s.R7 < 0.15 ELSE s.R7 < 0.04 END AS SECONDARY_MATCH,
    DATEDIFF(DAY, s.CREATED_AT, CURRENT_TIMESTAMP()) AS AGE_D
FROM SCR_1 s;

CREATE OR REPLACE TEMPORARY TABLE SCR_3 AS
SELECT s.*, ROW_NUMBER() OVER (ORDER BY s.CREATED_AT, s.TRANSFER_ID) AS RN,
    CASE WHEN s.AGE_D < 3 THEN s.R8 < 0.85 WHEN s.AGE_D < 14 THEN s.R8 < 0.40 ELSE s.R8 < 0.02 END AS IS_OPEN
FROM SCR_2 s;

INSERT INTO SANCTIONS_SCREENING
SELECT 'SC' || LPAD(s.RN::VARCHAR, 8, '0'), s.TRANSFER_ID, s.CUSTOMER_ID,
    IFF(s.R9 >= 0.45, s.BENEFICIARY_ID, NULL), IFF(s.R9 < 0.45, 'Sender', 'Beneficiary'),
    CASE WHEN s.R10 < 0.55 THEN 'SDN' WHEN s.R10 < 0.70 THEN 'EU' WHEN s.R10 < 0.85 THEN 'UN' ELSE 'UK HMT' END,
    GET(ARRAY_CONSTRUCT('Abdul Rahman Haddad','Viktor Orlov','Hassan Al-Mansour','Dmitri Volkov','Ali Reza Karimi','Omar Farouk','Sergei Petrenko',
        'Mohammad Jafari','Ivan Sokolov','Yusuf Al-Rashid','Nikolai Baranov','Khalid Mahmoud','Pavel Morozov','Rashid Hamadi','Andrei Kuznetsov',
        'Global Trade Partners LLC','Orion Maritime Services','Sahel Exchange House','Baltic Metals Trading','Gulf Horizon Logistics'),
        MOD(ABS(HASH(s.RN)), 20)::INT)::VARCHAR,
    GET(ARRAY_CONSTRUCT('Iran','Russia','Syria','North Korea','Venezuela','Belarus','Myanmar','Cuba','Libya','Yemen','Sudan','Lebanon'),
        MOD(ABS(HASH(s.RN, 3)), 12)::INT)::VARCHAR,
    ROUND(CASE WHEN s.IS_TRUE AND NOT s.WEAK_TRUE THEN 70 + 30 * s.R5 WHEN s.HARD_FP OR s.IS_TRUE THEN 72 + 20 * s.R6 ELSE 50 + 40 * s.R6 END, 1),
    s.NAME_SIM, s.DOB_MATCH, s.COUNTRY_MATCH, s.SECONDARY_MATCH, s.CREATED_AT,
    IFF(s.IS_OPEN, 'Open', 'Closed'),
    CASE WHEN s.IS_OPEN THEN 'Pending' WHEN s.IS_TRUE THEN IFF(s.R7 < 0.85, 'Blocked', 'Escalated') ELSE 'Cleared' END,
    ap.ANALYST_ID,
    IFF(s.IS_OPEN, NULL, LEAST(DATEADD(HOUR, IFF(s.IS_TRUE, 4 + FLOOR(s.R4 * 200), 1 + FLOOR(s.R4 * 72)), s.CREATED_AT), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ)),
    IFF(s.IS_OPEN, NULL, s.IS_TRUE)
FROM SCR_3 s
LEFT JOIN ANALYST_POOL ap ON ap.QUEUE = 'Sanctions' AND ap.RN = 1 + MOD(ABS(HASH(s.RN)), ap.CNT) AND (NOT s.IS_OPEN OR s.R6 < 0.7);

-- Holds and blocks on the underlying transfers
UPDATE TRANSFERS t SET STATUS = 'Blocked', PAID_AT = NULL
FROM SANCTIONS_SCREENING s WHERE s.TRANSFER_ID = t.TRANSFER_ID AND s.IS_TRUE_MATCH AND s.DISPOSITION = 'Blocked';

UPDATE TRANSFERS t SET STATUS = 'On Hold', PAID_AT = NULL
FROM SANCTIONS_SCREENING s WHERE s.TRANSFER_ID = t.TRANSFER_ID AND s.STATUS = 'Open'
  AND t.STATUS IN ('Paid', 'Available for Pickup') AND t.CREATED_AT >= DATEADD(DAY, -14, CURRENT_TIMESTAMP());

-- ============================================================================
-- SAR FILINGS (30-day BSA deadline from detection)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE SAR_DRAW AS
SELECT fc.CASE_ID, fc.CUSTOMER_ID, fc.CASE_TYPE, fc.EXPOSURE_USD, fc.OPENED_AT,
    DATEDIFF(YEAR, c.DATE_OF_BIRTH, CURRENT_DATE()) AS AGE_Y, co.PAYOUT_COUNTRY,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
FROM FRAUD_CASES fc
JOIN CUSTOMERS c ON c.CUSTOMER_ID = fc.CUSTOMER_ID
JOIN CORRIDORS co ON co.CORRIDOR_ID = c.PREFERRED_CORRIDOR_ID
WHERE fc.SAR_REQUIRED;

CREATE OR REPLACE TEMPORARY TABLE SAR_1 AS
SELECT d.*,
    LEAST(DATEADD(DAY, FLOOR(d.R1 * 6), d.OPENED_AT::DATE), DATEADD(DAY, -1, CURRENT_DATE())) AS DETECTION_DATE
FROM SAR_DRAW d;

CREATE OR REPLACE TEMPORARY TABLE SAR_2 AS
SELECT s.*, DATEDIFF(DAY, s.DETECTION_DATE, CURRENT_DATE()) AS AGE_D,
    CASE WHEN DATEDIFF(DAY, s.DETECTION_DATE, CURRENT_DATE()) > 45 THEN CASE WHEN s.R2 < 0.92 THEN 'Filed' ELSE 'Filed Late' END
         WHEN DATEDIFF(DAY, s.DETECTION_DATE, CURRENT_DATE()) > 30 THEN CASE WHEN s.R2 < 0.85 THEN 'Filed' WHEN s.R2 < 0.95 THEN 'Filed Late' WHEN s.R2 < 0.98 THEN 'In Review' ELSE 'Draft' END
         ELSE CASE WHEN s.R2 < 0.35 THEN 'Filed' WHEN s.R2 < 0.65 THEN 'In Review' ELSE 'Draft' END END AS FILING_STATUS,
    CASE s.CASE_TYPE WHEN 'AML - Structuring' THEN 'Structuring' WHEN 'Money Mule' THEN 'Money Mule'
         WHEN 'Scam' THEN IFF(s.AGE_Y >= 60, 'Elder Financial Exploitation', 'Fraud') WHEN 'Agent Collusion' THEN 'Agent Complicity'
         WHEN 'Fraud Ring' THEN IFF(s.R3 < 0.5, 'Identity Theft', 'Fraud') WHEN 'Account Takeover' THEN 'Identity Theft' ELSE 'Fraud' END AS ACTIVITY
FROM SAR_1 s;

INSERT INTO SAR_FILINGS
SELECT 'SAR' || LPAD(ROW_NUMBER() OVER (ORDER BY s.DETECTION_DATE, s.CASE_ID)::VARCHAR, 6, '0'),
    s.CASE_ID, s.CUSTOMER_ID, s.ACTIVITY, s.DETECTION_DATE, DATEADD(DAY, 30, s.DETECTION_DATE),
    CASE s.FILING_STATUS WHEN 'Filed' THEN DATEADD(DAY, LEAST(s.AGE_D, 3 + FLOOR(s.R3 * 26)), s.DETECTION_DATE)
                         WHEN 'Filed Late' THEN LEAST(DATEADD(DAY, 31 + FLOOR(s.R3 * 14), s.DETECTION_DATE), DATEADD(DAY, -1, CURRENT_DATE()))
                         ELSE NULL END,
    s.FILING_STATUS,
    CASE s.FILING_STATUS WHEN 'Filed' THEN LEAST(s.AGE_D, 3 + FLOOR(s.R3 * 26))
                         WHEN 'Filed Late' THEN LEAST(s.AGE_D - 1, 31 + FLOOR(s.R3 * 14)) ELSE NULL END,
    s.EXPOSURE_USD,
    ap.ANALYST_ID,
    'Subject customer ' || s.CUSTOMER_ID || ' was referred from case ' || s.CASE_ID || ' on ' || s.DETECTION_DATE::VARCHAR || '. '
    || CASE s.ACTIVITY
         WHEN 'Structuring' THEN 'Over several weeks the subject sent multiple cash remittances to ' || s.PAYOUT_COUNTRY || ' in amounts just below the $10,000 reporting level, often on consecutive days at the same agent location, totalling about $'
         WHEN 'Money Mule' THEN 'The subject received or relayed funds from multiple unrelated senders and cashed out quickly in ' || s.PAYOUT_COUNTRY || ', consistent with money mule activity, totalling about $'
         WHEN 'Elder Financial Exploitation' THEN 'The subject, an older adult, made repeated larger-than-usual remittances to a newly added beneficiary after contact from an unknown party, consistent with elder financial exploitation, totalling about $'
         WHEN 'Agent Complicity' THEN 'Transactions processed at an agent location showed patterns consistent with staff complicity, including amounts just under the Travel Rule threshold and repeat beneficiaries, totalling about $'
         WHEN 'Identity Theft' THEN 'The account was accessed from an unrecognized device and used to add a beneficiary and send funds without the customer''s knowledge, consistent with identity theft, totalling about $'
         ELSE 'The subject sent transfers that investigators concluded were fraudulent or unauthorized, totalling about $' END
    || ROUND(s.EXPOSURE_USD, 0)::VARCHAR || '. Supporting alerts, device and beneficiary links, and investigator notes are attached to the case file. This narrative is synthetic.'
FROM SAR_2 s
JOIN ANALYST_POOL ap ON ap.QUEUE = 'AML Investigations' AND ap.RN = 1 + MOD(ABS(HASH(s.CASE_ID)), ap.CNT);

-- ============================================================================
-- CTR FILINGS: daily cash over $10,000
-- ============================================================================
INSERT INTO CTR_FILINGS
SELECT 'CTR' || LPAD(ROW_NUMBER() OVER (ORDER BY x.BUSINESS_DATE, x.CUSTOMER_ID)::VARCHAR, 6, '0'),
    x.CUSTOMER_ID, x.BUSINESS_DATE, x.TOTAL_CASH, x.N, DATEADD(DAY, 15, x.BUSINESS_DATE),
    CASE WHEN DATEDIFF(DAY, x.BUSINESS_DATE, CURRENT_DATE()) <= 14 AND x.R1 < 0.5 THEN NULL
         WHEN x.R1 < 0.95 THEN DATEADD(DAY, 1 + FLOOR(x.R2 * 13), x.BUSINESS_DATE) ELSE LEAST(DATEADD(DAY, 16 + FLOOR(x.R2 * 6), x.BUSINESS_DATE), DATEADD(DAY, -1, CURRENT_DATE())) END,
    CASE WHEN DATEDIFF(DAY, x.BUSINESS_DATE, CURRENT_DATE()) <= 14 AND x.R1 < 0.5 THEN 'Pending'
         WHEN x.R1 < 0.95 THEN 'Filed' ELSE 'Filed Late' END
FROM (SELECT t.CUSTOMER_ID, t.CREATED_AT::DATE AS BUSINESS_DATE, SUM(t.SEND_AMOUNT_USD) AS TOTAL_CASH, COUNT(*) AS N,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2
      FROM TRANSFERS t WHERE t.FUNDING_TYPE = 'Cash' AND t.STATUS NOT IN ('Cancelled', 'Refunded', 'Blocked')
      GROUP BY t.CUSTOMER_ID, t.CREATED_AT::DATE HAVING SUM(t.SEND_AMOUNT_USD) > 10000) x;

-- ============================================================================
-- STRUCTURING REVIEWS: look-back reviews of customer-weeks with $3,000+ sent
-- ============================================================================
INSERT INTO STRUCTURING_REVIEWS
SELECT 'SR' || LPAD(ROW_NUMBER() OVER (ORDER BY w.WEEK_START, w.CUSTOMER_ID)::VARCHAR, 7, '0'),
    w.CUSTOMER_ID, w.WEEK_START,
    LEAST(DATEADD(DAY, 9 + FLOOR(w.R3 * 16), w.WEEK_START)::TIMESTAMP_NTZ, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ),
    ap.ANALYST_ID,
    (w.STRUCT_N >= 2 AND w.R2 < 0.90)
FROM (SELECT t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE AS WEEK_START, COUNT_IF(k.KIND = 'STRUCT') AS STRUCT_N,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3
      FROM TRANSFERS t JOIN T_KIND k ON k.TRANSFER_ID = t.TRANSFER_ID
      WHERE t.STATUS <> 'Cancelled'
      GROUP BY t.CUSTOMER_ID, DATE_TRUNC('WEEK', t.CREATED_AT)::DATE
      HAVING COUNT(*) >= 2 AND SUM(t.SEND_AMOUNT_USD) >= 3000) w
JOIN ANALYST_POOL ap ON ap.QUEUE = 'AML Investigations' AND ap.RN = 1 + MOD(ABS(HASH(w.CUSTOMER_ID, w.WEEK_START)), ap.CNT)
WHERE DATEADD(DAY, 14, w.WEEK_START) <= CURRENT_DATE()
  AND ((w.STRUCT_N >= 2 AND w.R1 < 0.92) OR (w.STRUCT_N = 0 AND w.R1 < 0.35));

-- ============================================================================
-- COMPLAINTS (Customer 360)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CMP_SRC AS
SELECT d.TRANSFER_ID, d.CUSTOMER_ID, d.OPENED_AT AS BASE_TS,
    CASE d.ERROR_TYPE WHEN 'Late Delivery' THEN 'Delay' WHEN 'Not Received' THEN IFF(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.6, 'Delay', 'Customer Service')
                      WHEN 'Incorrect Amount' THEN IFF(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.5, 'FX Rate', 'Fees')
                      WHEN 'Unauthorized' THEN 'Fraud' ELSE 'Customer Service' END AS CATEGORY
FROM DISPUTES d WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.35
UNION ALL
SELECT x.TRANSFER_ID, x.CUSTOMER_ID, x.CREATED_AT,
    CASE WHEN x.R2 < 0.25 THEN 'Fees' WHEN x.R2 < 0.50 THEN 'FX Rate' WHEN x.R2 < 0.70 THEN 'Delay' WHEN x.R2 < 0.90 THEN 'Customer Service' ELSE 'Refund' END
FROM (SELECT t.TRANSFER_ID, t.CUSTOMER_ID, t.CREATED_AT, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2
      FROM TRANSFERS t WHERE t.STATUS = 'Paid') x WHERE x.R1 < 0.004
UNION ALL
SELECT t.TRANSFER_ID, t.CUSTOMER_ID, t.CREATED_AT, 'Account Locked'
FROM TRANSFERS t WHERE t.STATUS IN ('Blocked', 'On Hold') AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.20
UNION ALL
SELECT t.TRANSFER_ID, t.CUSTOMER_ID, t.CREATED_AT, 'Refund'
FROM TRANSFERS t WHERE t.STATUS = 'Refunded' AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.15;

CREATE OR REPLACE TEMPORARY TABLE CMP_1 AS
SELECT s.*, ROW_NUMBER() OVER (ORDER BY s.BASE_TS, s.TRANSFER_ID, s.CATEGORY) AS RN,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3,
    UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4
FROM CMP_SRC s;

CREATE OR REPLACE TEMPORARY TABLE CMP_2 AS
SELECT s.*, LEAST(DATEADD(HOUR, 2 + FLOOR(s.R1 * 240), s.BASE_TS), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) AS SUBMITTED_AT,
    (s.R2 < 0.04) AS CFPB
FROM CMP_1 s;

INSERT INTO COMPLAINTS
SELECT 'CM' || LPAD(s.RN::VARCHAR, 7, '0'), s.CUSTOMER_ID, s.TRANSFER_ID,
    IFF(s.CFPB, 'CFPB Portal', CASE WHEN s.R3 < 0.35 THEN 'Phone' WHEN s.R3 < 0.60 THEN 'App' WHEN s.R3 < 0.80 THEN 'Email' ELSE 'Agent' END),
    s.CATEGORY, s.SUBMITTED_AT,
    IFF(DATEADD(DAY, 3 + FLOOR(s.R4 * 27), s.SUBMITTED_AT) <= CURRENT_TIMESTAMP(), DATEADD(DAY, 3 + FLOOR(s.R4 * 27), s.SUBMITTED_AT), NULL),
    CASE WHEN DATEADD(DAY, 3 + FLOOR(s.R4 * 27), s.SUBMITTED_AT) <= CURRENT_TIMESTAMP() THEN 'Resolved'
         WHEN DATEDIFF(DAY, s.SUBMITTED_AT, CURRENT_TIMESTAMP()) < 3 THEN 'Open' ELSE 'In Progress' END,
    s.CFPB,
    CASE s.CATEGORY
      WHEN 'Delay' THEN GET(ARRAY_CONSTRUCT('My transfer of $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || ' to ' || co.PAYOUT_COUNTRY || ' was supposed to arrive in minutes and my family still has not received it after two days.',
          'The money was sent on ' || t.CREATED_AT::DATE::VARCHAR || ' and the app still shows it as processing. My relative needed the funds for rent.',
          'Pickup was delayed for several days with no explanation. The agent in ' || co.PAYOUT_COUNTRY || ' said they had no record of the transfer.',
          'Delivery to the bank account took far longer than the estimate I was shown. Nobody called me back about the delay.',
          'The payout was held and I was never told why. I had to visit the store twice to get an answer.'), MOD(s.RN, 5)::INT)::VARCHAR
      WHEN 'Fees' THEN GET(ARRAY_CONSTRUCT('The fee charged on my $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || ' transfer was higher than the fee quoted on the screen.',
          'I was charged a fee I did not expect. The total shown at checkout did not match my card statement.',
          'Fees are too high compared with other providers for sending to ' || co.PAYOUT_COUNTRY || '.',
          'I was charged twice for the same transfer fee and need one of them refunded.',
          'The agent charged me a service fee that is not listed on your website.'), MOD(s.RN, 5)::INT)::VARCHAR
      WHEN 'FX Rate' THEN GET(ARRAY_CONSTRUCT('The exchange rate I received was much worse than the rate displayed when I started the transfer.',
          'My family received fewer ' || co.PAYOUT_CURRENCY || ' than promised. The rate seems to have changed after I paid.',
          'The rate for ' || co.PAYOUT_COUNTRY || ' is lower than the market rate I see online. Please explain the margin.',
          'I sent $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || ' and the payout amount was not what the receipt showed.',
          'The exchange rate on my receipt does not match the rate in the app confirmation.'), MOD(s.RN, 5)::INT)::VARCHAR
      WHEN 'Fraud' THEN GET(ARRAY_CONSTRUCT('I did not authorize this transfer of $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || '. Someone must have accessed my account and I want my money back.',
          'I received a notification for a transfer I never made. My card was charged and the beneficiary is a person I do not know.',
          'My account was used to send money to someone I have never heard of. I changed my password but the transfer already went through.',
          'A transfer was made from my account while I was asleep. Please block the account and investigate.',
          'I was contacted by someone pretending to be from your company and later saw a transfer I did not approve.'), MOD(s.RN, 5)::INT)::VARCHAR
      WHEN 'Account Locked' THEN GET(ARRAY_CONSTRUCT('My account was locked after a transfer and I cannot send money to my family. Support keeps asking for the same documents.',
          'The transfer of $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || ' is on hold and nobody can tell me when it will be released.',
          'I uploaded my ID three times and the account is still restricted. This is urgent because my mother needs the money.',
          'My transfer was blocked for compliance review but I was not given a reason or a timeline.',
          'The app says my account is under review. I have been a customer for years and never had this problem.'), MOD(s.RN, 5)::INT)::VARCHAR
      WHEN 'Refund' THEN GET(ARRAY_CONSTRUCT('I cancelled my transfer right away but the refund has not appeared on my card after a week.',
          'The beneficiary never picked up the money and I am still waiting for the refund of $' || ROUND(t.SEND_AMOUNT_USD, 0)::INT::VARCHAR || '.',
          'I was told the refund takes three days. It has been longer and the status in the app has not changed.',
          'The refund amount did not include the fee I paid even though I cancelled immediately.',
          'I asked for a refund because the receiver details were wrong, and the agent said it was not possible.'), MOD(s.RN, 5)::INT)::VARCHAR
      ELSE GET(ARRAY_CONSTRUCT('Customer service was unhelpful and I was transferred between agents several times.',
          'The store employee was rude and could not answer basic questions about my transfer.',
          'I have called the support line four times and nobody has followed up on my case.',
          'The app crashed during my transfer and I do not know whether it went through.',
          'I could not reach anyone by phone to correct the beneficiary name on my transfer.'), MOD(s.RN, 5)::INT)::VARCHAR END
FROM CMP_2 s
JOIN TRANSFERS t ON t.TRANSFER_ID = s.TRANSFER_ID
JOIN CORRIDORS co ON co.CORRIDOR_ID = t.CORRIDOR_ID;

-- ============================================================================
-- NPS SURVEYS
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE CMP_CNT AS SELECT CUSTOMER_ID, COUNT(*) AS N FROM COMPLAINTS GROUP BY CUSTOMER_ID;

INSERT INTO NPS_SURVEYS
SELECT 'NP' || LPAD(ROW_NUMBER() OVER (ORDER BY x.SURVEY_DATE, x.CUSTOMER_ID)::VARCHAR, 7, '0'),
    x.CUSTOMER_ID, x.SURVEY_DATE, x.SCORE,
    CASE WHEN x.SCORE >= 9 THEN 'Promoter' WHEN x.SCORE >= 7 THEN 'Passive' ELSE 'Detractor' END,
    IFF(x.R4 < 0.25, NULL,
        CASE WHEN x.SCORE >= 9 THEN GET(ARRAY_CONSTRUCT('Fast and reliable, my family always gets the money the same day.','Easy to use app and the rate is fair.',
                'Great experience at the store, the agent was friendly and quick.','I recommend Ria to everyone I know who sends money home.',
                'Transfers always arrive when promised and support is helpful.','Simple, safe and trusted for years.'), MOD(ABS(HASH(x.CUSTOMER_ID, x.SURVEY_DATE)), 6)::INT)::VARCHAR
             WHEN x.SCORE >= 7 THEN GET(ARRAY_CONSTRUCT('Good service overall, but fees could be lower.','Works fine, I just wish there were more promotions.',
                'Reliable but the app could be easier to navigate.','Okay experience. Rates are acceptable but not the best.',
                'Pickup is easy, though the lines at the store can be long.'), MOD(ABS(HASH(x.CUSTOMER_ID, x.SURVEY_DATE)), 5)::INT)::VARCHAR
             ELSE GET(ARRAY_CONSTRUCT('My transfer was delayed and nobody explained why.','Fees and exchange rate margin are too high.',
                'My account was locked for review and support was not helpful.','I had to submit my ID several times and it still was not accepted.',
                'The refund took too long to arrive.','Customer service kept transferring me and never solved the problem.',
                'The app crashed during my transfer.','The amount received was lower than I expected because of the exchange rate.'),
                MOD(ABS(HASH(x.CUSTOMER_ID, x.SURVEY_DATE)), 8)::INT)::VARCHAR END)
FROM (
    SELECT a.CUSTOMER_ID,
        DATEADD(DAY, -1 * (1 + FLOOR(a.R3 * LEAST(365, a.ACTIVE_D))), CURRENT_DATE()) AS SURVEY_DATE,
        LEAST(10, GREATEST(0, ROUND(10 * POW(a.R2, IFF(a.COMPLAINTS > 0, 0.7, 0.25)))))::INT AS SCORE, a.R4
    FROM (
        SELECT c.CUSTOMER_ID, n.K, DATEDIFF(DAY, c.SIGNUP_DATE, CURRENT_DATE()) AS ACTIVE_D,
            COALESCE(cc.N, 0) AS COMPLAINTS,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R1, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R2,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R3, UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS R4
        FROM CUSTOMERS c JOIN NUMS n ON n.K <= 1 + MOD(ABS(HASH(c.CUSTOMER_ID)), 2)
        LEFT JOIN CMP_CNT cc ON cc.CUSTOMER_ID = c.CUSTOMER_ID
    ) a
    WHERE a.R1 < 0.35
) x;

-- ============================================================================
-- FRAUD TYPOLOGIES (10 typologies x guide / red flags / playbook) + regulator advisories
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE TYP AS
SELECT column1 AS TYPOLOGY, column2 AS GUIDE, column3 AS FLAGS, column4 AS PLAYBOOK FROM VALUES
('Account Takeover',
 'Account takeover occurs when a criminal gains control of a genuine customer account using stolen credentials, SIM swap, phishing or malware, then changes security details, adds a new beneficiary and drains funds through remittance transfers. Losses are typically paid out as cash or mobile wallet within minutes, so detection has to happen before payout.',
 'Login from a new device or a hosting-provider IP in a different country than usual. Several failed logins followed by a success. Password or phone change shortly before a transfer. New beneficiary added in the same session followed by a transfer near the available limit. Very short sessions with few in-app actions. Device fingerprint seen on several unrelated accounts.',
 '1) Place the account in restricted mode and hold unpaid transfers. 2) Attempt payout recall through the partner. 3) Contact the customer through a previously verified channel. 4) Pull device, IP and beneficiary links to find other victims. 5) Reset credentials and remove unrecognized devices. 6) Record the loss and decide on a SAR if the pattern warrants it.'),
('Money Mule',
 'Money mules receive and move funds on behalf of criminals, knowingly or unwittingly, often after recruitment through fake job offers or romance scams. In remittance, mule beneficiaries collect funds from many unrelated senders and cash out quickly, often across several agent locations.',
 'Beneficiary receives from many unrelated senders in a short window. Relationship declared as Other or Friend for most senders. Payouts at multiple agent locations within hours. Many first-time senders. Payout amounts just under identification thresholds. Beneficiary details shared with other flagged beneficiaries.',
 '1) Block further payouts to the beneficiary. 2) List all senders and contact those who may be scam victims. 3) Link the beneficiary to bank accounts, phones and agent locations. 4) Decide whether the mule is complicit or a recruited victim. 5) File a SAR describing the flow of funds. 6) Add identifiers to the watch list.'),
('Structuring',
 'Structuring is breaking up cash transactions to evade reporting or identification thresholds, such as the 10,000 dollar Currency Transaction Report level or the 3,000 dollar Travel Rule threshold. It is illegal under the Bank Secrecy Act even when the funds are legitimate.',
 'Repeated cash sends just below 3,000 or 10,000 dollars. Several transfers on consecutive days to the same or related beneficiaries. Use of multiple agent locations or family members to split amounts. Customer reluctance to provide identification when a threshold is approached. Weekly totals far above declared expected monthly volume.',
 '1) Aggregate cash across agents for the week and the prior four weeks. 2) Compare with declared source of funds and expected volume. 3) Review the agent location for complicity. 4) Send a source of funds questionnaire. 5) Decide on a SAR within 30 days of detection. 6) Consider enhanced due diligence and activity limits.'),
('Romance Scam',
 'In romance scams a criminal builds a relationship online and persuades the victim to send money for emergencies, travel or investments. Victims send repeated transfers to new beneficiaries, often overseas, and are coached to avoid questions from staff.',
 'First-ever transfers to a new beneficiary in a high-risk corridor. Amounts escalate over days. Sender mentions an online friend, a medical emergency or a customs fee. Declared purpose changes between Gift, Family Support and Other. Sender appears anxious or secretive at the counter.',
 '1) Pause the transfer and speak with the customer in private. 2) Use the scam script and explain the common signs. 3) If the customer proceeds, document the warnings given. 4) Flag the beneficiary for mule review. 5) Report to the fraud team and file a SAR when exploitation is suspected. 6) Offer fraud hotline resources.'),
('Elder Fraud',
 'Elder financial exploitation targets older adults through impersonation of relatives, officials or technicians. Transfers are urgent, secret and larger than the customer history. FinCEN advises financial institutions to file SARs that identify elder financial exploitation.',
 'Customer aged 60 or over sending much more than usual. Cash-funded transfers to a new payee. A third party accompanies the customer and answers for them. Customer is confused about the purpose. Sudden interest in gift cards, crypto or investment opportunities.',
 '1) Delay if policy permits and contact a trusted contact on file. 2) Use plain-language prompts to confirm the purpose. 3) Escalate to the senior analyst for same-day review. 4) File a SAR using the elder financial exploitation key term. 5) Notify adult protective services where required.'),
('Synthetic Identity',
 'Synthetic identities combine real and fabricated data, such as a valid number with a made-up name, to create a customer who passes basic checks. They build trust with small transfers, then bust out with large card or bank funded transfers and disappear.',
 'Email created days before signup. VoIP phone number. Thin credit header file. Address shared with many unrelated customers. Multiple ID verification attempts. First transfers small and clean, followed by rapid growth in amounts and new beneficiaries.',
 '1) Restrict the account and hold outstanding transfers. 2) Request additional identity documents and liveness checks. 3) Check shared address, device and phone across the customer base. 4) Review chargebacks and ACH returns tied to the account. 5) Record the loss as Synthetic Identity and share indicators with the fraud team.'),
('Agent Collusion',
 'Agent collusion occurs when staff at an agent location knowingly process suspicious transactions, split amounts to avoid reporting, create fake customers or share customer data. It is detected through patterns across the location rather than from a single transaction.',
 'High share of transfers just under thresholds. High cancellation or reversal rate. Repeat customers with identical beneficiaries. Transactions outside business hours. Low audit rating or overdue AML training. Sudden volume increases without marketing activity.',
 '1) Compare the location with peers on threshold-adjacent volume and cancellations. 2) Review counter staff identifiers on flagged transfers. 3) Schedule an unannounced audit. 4) Reduce limits while the review continues. 5) Suspend or terminate the agent under the agent oversight policy. 6) File a SAR describing agent complicity.'),
('Card Fraud',
 'Card-not-present fraud uses stolen card details to fund transfers. The cardholder disputes the payment weeks later, leaving the company with chargeback losses. Fraudsters test cards with small amounts, then send larger transfers in short bursts.',
 'New account funded with a card issued in another country. Several cards used from one device. Card added moments before first use. Transfers in quick succession to the same beneficiary. Failed authorizations followed by success with a different card. Late-night activity.',
 '1) Suspend the card token and hold unpaid transfers. 2) Request additional verification such as 3-D Secure. 3) Check device and IP links to other accounts. 4) Prepare chargeback representment with device evidence where the cardholder is genuine. 5) Update rules for issuer country and card age.'),
('Fraud Ring',
 'A fraud ring is a group of accounts controlled or coordinated by the same actors. Links appear through shared devices, IP addresses, phone numbers and beneficiaries. Rings often onboard accounts in waves and rotate beneficiaries once one is blocked.',
 'Many accounts sharing a device, IP address or phone number. Accounts created within a short window with similar profiles. Common beneficiaries across unrelated customers. Synchronized login and transfer times. Replacement accounts appearing after one is blocked.',
 '1) Build the link graph from device, IP, phone and beneficiary. 2) Size the cluster and total exposure. 3) Block the shared identifiers and monitor for replacements. 4) Open one coordinated case rather than separate cases. 5) Share indicators with partners and file a SAR for the cluster.'),
('Sanctions Evasion',
 'Sanctions evasion attempts to move value to or for sanctioned persons or jurisdictions through name variations, third-party senders, intermediaries or structuring. Strict liability applies, so true matches must be blocked and reported to OFAC.',
 'Close name match on the SDN, EU, UN or UK HMT lists with a matching date of birth or country. Transfers routed through intermediaries in neighboring countries. Frequent small changes in beneficiary spelling. Business names that resemble listed entities.',
 '1) Do not release the transfer while the hit is open. 2) Compare name, date of birth, country and secondary identifiers. 3) Document the rationale for clearing false positives. 4) Block and report true matches to OFAC within required timelines. 5) Review related transfers and customers for further exposure.');

INSERT INTO FRAUD_TYPOLOGIES
SELECT 'FT-' || LPAD(ROW_NUMBER() OVER (ORDER BY x.TYPOLOGY, x.ORD)::VARCHAR, 3, '0'),
    x.TYPOLOGY || ' - ' || x.CATEGORY, x.TYPOLOGY, x.CATEGORY,
    DATEADD(DAY, -1 * (20 + MOD(ABS(HASH(x.TYPOLOGY, x.ORD)), 400)), CURRENT_DATE()), x.CONTENT
FROM (
    SELECT TYPOLOGY, 1 AS ORD, 'Typology Guide' AS CATEGORY, GUIDE AS CONTENT FROM TYP
    UNION ALL SELECT TYPOLOGY, 2, 'Red Flags', FLAGS FROM TYP
    UNION ALL SELECT TYPOLOGY, 3, 'Investigation Playbook', PLAYBOOK FROM TYP
) x;

INSERT INTO FRAUD_TYPOLOGIES
SELECT 'FT-' || LPAD((30 + ROW_NUMBER() OVER (ORDER BY column1))::VARCHAR, 3, '0'), column1, column2, 'Regulator Advisory',
    DATEADD(DAY, -1 * column4, CURRENT_DATE()), column3
FROM VALUES
('Regulator Advisory: Structuring and the 10,000 dollar reporting threshold', 'Structuring',
 'Summary of regulator guidance (synthetic summary for demonstration). Financial institutions are reminded that structuring transactions to evade Currency Transaction Report requirements is a federal crime regardless of the source of funds. Red flags include repeated cash transactions just under 10,000 dollars, use of multiple locations on the same day, and customers who change the amount after learning of the reporting requirement. Institutions should aggregate cash across locations and file SARs within 30 calendar days of initial detection.', 120),
('Regulator Advisory: Elder financial exploitation', 'Elder Fraud',
 'Summary of regulator guidance (synthetic summary for demonstration). Institutions are encouraged to train staff to recognize exploitation of older adults, to use the elder financial exploitation key term in SAR narratives, and to share information with adult protective services where permitted. Red flags include sudden large transfers by older customers, urgent secrecy, and unusual third-party involvement.', 200),
('Regulator Advisory: OFAC sanctions compliance for money services businesses', 'Sanctions Evasion',
 'Summary of regulator guidance (synthetic summary for demonstration). Money services businesses are expected to screen senders and beneficiaries against OFAC lists, to maintain a risk-based approach to name matching, and to block and report property of designated persons. Tuning of screening thresholds must be documented and periodically validated, and false positive rationales must be retained.', 90),
('Regulator Advisory: Remittance Transfer Rule reminders', 'Account Takeover',
 'Summary of regulator guidance (synthetic summary for demonstration). Providers must give senders a 30-minute cancellation window after payment, resolve errors reported within 180 days, complete investigations within 90 days and refund eligible amounts promptly. Providers should log error notices, outcomes and timelines to demonstrate compliance, including for unauthorized transfers resulting from account takeover.', 150);

-- ============================================================================
-- POLICY DOCUMENTS (9 areas x policy + procedure)
-- ============================================================================
CREATE OR REPLACE TEMPORARY TABLE POL AS
SELECT column1 AS AREA, column2 AS REG, column3 AS OWNER_NAME, column4 AS POLICY_TEXT, column5 AS PROC_TEXT FROM VALUES
('BSA/AML', 'Bank Secrecy Act (31 USC 5311) and FinCEN MSB rules', 'Chief Compliance Officer',
 'The company maintains a risk-based anti-money laundering program with a designated BSA Officer, written procedures, ongoing training and independent testing. Currency Transaction Reports are filed for cash over 10,000 dollars in a business day. Suspicious Activity Reports are filed within 30 calendar days of initial detection of suspicious activity. Structuring below 10,000 dollars is monitored weekly. Records are retained for five years.',
 'Alerts are triaged within 2 business days. Cases with suspected structuring, mule or elder exploitation require a SAR decision within 20 days of case opening. The BSA Officer approves all SARs. Unfiled SARs within 5 days of the deadline are escalated to the BSA Officer daily until filed.'),
('Sanctions', 'OFAC regulations (31 CFR Chapter V)', 'Head of Sanctions Compliance',
 'All senders and beneficiaries are screened against the OFAC SDN list and the EU, UN and UK HMT lists at onboarding and on every transfer. True matches must be blocked and reported. False positive dispositions must be documented with the identifiers compared. Screening thresholds are validated annually.',
 'Open hits are worked in match score order. Analysts compare name, date of birth, country and secondary identifiers. Transfers remain on hold while a hit is open. Blocked property is reported to OFAC within 10 business days.'),
('KYC', 'FinCEN Customer Due Diligence Rule (31 CFR 1010.230)', 'Head of Customer Risk',
 'Customers are risk rated Low, Medium or High at onboarding and reviewed at least every 36, 24 and 12 months respectively. Politically exposed persons and High-risk customers require enhanced due diligence including source of funds. Identity verification must be Verified before limits are raised. Customers with failed verification may not transact.',
 'Reviewers confirm identity documents, declared occupation, source of funds and expected monthly volume. Overdue reviews are reported weekly. Enhanced due diligence must be completed within 30 days of the trigger.'),
('Fraud', 'FFIEC authentication and fraud risk guidance', 'Head of Fraud Operations',
 'Fraud is managed through rules, machine learning models and analyst review. Every alert is assigned to an analyst, dispositioned as True Positive, False Positive or Inconclusive, and linked to a case when escalated. The alert-to-case-to-disposition audit trail must record the analyst and timestamp of every action.',
 'Critical alerts must be assigned within 1 hour and High alerts within 4 hours. Alerts open beyond 30 days are reported to the fraud operations lead weekly. Confirmed fraud losses and recoveries are booked within 5 business days.'),
('Privacy', 'Gramm-Leach-Bliley Act (GLBA)', 'Chief Privacy Officer',
 'Nonpublic personal information is collected only for lawful purposes and protected with access controls and masking. Analytical views used by agents and dashboards must mask names, email addresses and phone numbers and must never expose Social Security numbers or full account numbers.',
 'Access to unmasked customer data requires a documented business need and manager approval. Access is reviewed quarterly. Privacy incidents are reported within 24 hours.'),
('Remittance Transfer Rule', 'Regulation E Subpart B, 12 CFR 1005.30-1005.36 (CFPB)', 'Head of Consumer Compliance',
 'Senders receive pre-payment and receipt disclosures, may cancel within 30 minutes of payment, and are refunded promptly. Errors reported within 180 days must be investigated and resolved within 90 days. Error notices, investigations and outcomes are logged.',
 'Cancellation requests inside the window are refunded in full within 3 business days. Disputes are assigned to the Disputes queue on receipt and tracked to resolution. Disputes at risk of exceeding 90 days are escalated weekly.'),
('Model Risk', 'Federal Reserve SR 11-7 / OCC 2011-12', 'Head of Model Risk',
 'Every fraud and compliance model has a named owner, documented intended use, validation status and version, and is recorded in the model registry. Models are validated before use and at least annually. Model outputs presented to users must be identified as model predictions.',
 'Validation covers conceptual soundness, performance on out-of-sample data, and ongoing monitoring. Models past their validation date are reported to the model risk committee monthly. Synthetic-data performance must not be quoted as production performance.'),
('Agent Oversight', 'FinCEN MSB agent guidance and internal agent program', 'Head of Agent Compliance',
 'Agents are onboarded with due diligence, trained in AML annually, and audited at least every 12 months. Agents with low audit ratings, overdue training or suspicious patterns are placed under review, have limits reduced, and may be suspended or terminated.',
 'Agent Oversight analysts review threshold-adjacent volume, cancellation rates and repeat beneficiary patterns monthly. Locations scoring in the top decile on collusion risk receive an unannounced audit within 30 days.'),
('Card Security', 'PCI DSS', 'Chief Information Security Officer',
 'Full card numbers are never stored in analytical systems. Only a network token, the BIN and the last four digits are retained. Card data access is logged and reviewed. Cards used in confirmed fraud are suspended.',
 'Chargebacks are tracked to representment within network deadlines. Cards with repeated chargebacks are blocked. Quarterly scans confirm no full card numbers appear in analytics tables.');

INSERT INTO POLICY_DOCUMENTS
SELECT 'PD-' || LPAD(ROW_NUMBER() OVER (ORDER BY x.AREA, x.ORD)::VARCHAR, 3, '0'),
    x.AREA || IFF(x.ORD = 1, ' Policy', ' Procedure'), x.AREA, x.REG,
    IFF(x.ORD = 1, '3.2', '2.4'), DATEADD(DAY, -1 * (60 + MOD(ABS(HASH(x.AREA, x.ORD)), 600)), CURRENT_DATE()), x.OWNER_NAME, x.CONTENT
FROM (
    SELECT AREA, REG, OWNER_NAME, 1 AS ORD, POLICY_TEXT AS CONTENT FROM POL
    UNION ALL SELECT AREA, REG, OWNER_NAME, 2, PROC_TEXT FROM POL
) x;
