/*=============================================================================
  Ria Financial Intelligence Agent
  Step 2: Table Definitions

  Execution Order: 2 of 9
  Description: Creates the RAW tables for cross-border money transfer fraud
               and compliance:
                 - Reference: corridors, agent locations, analysts
                 - Customers: senders, KYC/CDD profiles, beneficiaries,
                   funding sources, devices, app sessions
                 - Activity: transfers (with FATF Travel Rule fields),
                   ACH returns, chargebacks, refunds, Reg E disputes
                 - Fraud ops: alerts, cases, case events (FFIEC audit trail),
                   case notes, fraud losses
                 - Compliance: sanctions screening, SAR filings, CTR filings,
                   structuring reviews
                 - Customer 360: complaints, NPS surveys
                 - Documents: fraud typologies, policies
               All data is synthetic. PCI DSS: cards are stored as token,
               BIN and last 4 only. GLBA: no SSNs or full account numbers.
               Columns prefixed CONFIRMED_ / IS_ are investigation outcomes
               used as ML labels, never as model features.
               Every table and column carries a COMMENT for Cortex Analyst.
=============================================================================*/

USE DATABASE RIA_FINANCIAL_INTELLIGENCE;
USE SCHEMA RAW;
USE WAREHOUSE RIA_FINANCIAL_WH;

-- ============================================================================
-- REFERENCE
-- ============================================================================
CREATE OR REPLACE TABLE CORRIDORS (
    CORRIDOR_ID             VARCHAR(20)   NOT NULL COMMENT 'Corridor identifier, for example US-MX',
    CORRIDOR_NAME           VARCHAR(100)  NOT NULL COMMENT 'Corridor name, for example United States to Mexico',
    SEND_COUNTRY            VARCHAR(60)   NOT NULL COMMENT 'Country the money is sent from',
    PAYOUT_COUNTRY          VARCHAR(60)   NOT NULL COMMENT 'Country the money is paid out in',
    SEND_CURRENCY           VARCHAR(3)    NOT NULL COMMENT 'ISO 4217 send currency',
    PAYOUT_CURRENCY         VARCHAR(3)    NOT NULL COMMENT 'ISO 4217 payout currency',
    USD_TO_PAYOUT_RATE      NUMBER(18,6)  NOT NULL COMMENT 'Reference FX rate: payout currency units per US dollar',
    USD_TO_SEND_RATE        NUMBER(18,6)  NOT NULL COMMENT 'Reference FX rate: send currency units per US dollar',
    CORRIDOR_RISK_LEVEL     VARCHAR(10)   NOT NULL COMMENT 'AML corridor risk: Low, Medium or High',
    CORRIDOR_RISK_SCORE     NUMBER(5,2)   NOT NULL COMMENT 'AML corridor risk score 0-100',
    IS_HIGH_RISK_JURISDICTION BOOLEAN     NOT NULL COMMENT 'TRUE when the payout country is on the internal high-risk jurisdiction list',
    REGION                  VARCHAR(40)   NOT NULL COMMENT 'Payout region: Latin America, Asia Pacific, Africa, Europe, Middle East',
    CONSTRAINT PK_CORRIDORS PRIMARY KEY (CORRIDOR_ID)
) COMMENT = 'Send-to-payout country corridors with currencies, FX and AML risk';

CREATE OR REPLACE TABLE AGENT_LOCATIONS (
    AGENT_ID                VARCHAR(20)   NOT NULL COMMENT 'Agent location identifier (AG-00000 format)',
    AGENT_NAME              VARCHAR(120)  NOT NULL COMMENT 'Agent or branch trading name',
    AGENT_TYPE              VARCHAR(30)   NOT NULL COMMENT 'Ria Company Store, Retail Partner, Bank Partner or Payout Partner',
    ROLE                    VARCHAR(20)   NOT NULL COMMENT 'Send, Payout or Both',
    COUNTRY                 VARCHAR(60)   NOT NULL COMMENT 'Country of the location',
    CITY                    VARCHAR(80)   NOT NULL COMMENT 'City of the location',
    REGION                  VARCHAR(40)   NOT NULL COMMENT 'Region of the location',
    ONBOARDED_DATE          DATE          NOT NULL COMMENT 'Date the agent was onboarded',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Active, Under Review, Suspended or Terminated',
    DAILY_LIMIT_USD         NUMBER(12,2)  NOT NULL COMMENT 'Daily send limit in US dollars',
    LAST_AUDIT_DATE         DATE                   COMMENT 'Date of the last compliance audit',
    AUDIT_RATING            NUMBER(3,1)            COMMENT 'Last compliance audit rating 1.0 (poor) to 5.0 (strong)',
    TRAINING_COMPLETED      BOOLEAN       NOT NULL COMMENT 'TRUE when annual AML training is complete',
    CONFIRMED_COLLUSION     BOOLEAN       NOT NULL COMMENT 'Investigation outcome: TRUE when the agent was confirmed to be colluding in fraud or AML abuse. ML label',
    CONSTRAINT PK_AGENT_LOCATIONS PRIMARY KEY (AGENT_ID)
) COMMENT = 'Agent and branch network: company stores, retail and bank partners, payout partners';

CREATE OR REPLACE TABLE ANALYSTS (
    ANALYST_ID              VARCHAR(20)   NOT NULL COMMENT 'Analyst identifier (AN-000 format)',
    ANALYST_NAME            VARCHAR(100)  NOT NULL COMMENT 'Analyst name (synthetic)',
    QUEUE                   VARCHAR(40)   NOT NULL COMMENT 'Work queue: Fraud Operations, AML Investigations, Sanctions, Agent Oversight, Disputes',
    ROLE                    VARCHAR(40)   NOT NULL COMMENT 'Analyst, Senior Analyst, Team Lead or BSA Officer',
    HIRE_DATE               DATE          NOT NULL COMMENT 'Hire date',
    CONSTRAINT PK_ANALYSTS PRIMARY KEY (ANALYST_ID)
) COMMENT = 'Fraud, AML, sanctions and disputes analysts';

-- ============================================================================
-- CUSTOMERS
-- ============================================================================
CREATE OR REPLACE TABLE CUSTOMERS (
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer (sender) identifier (C000000 format)',
    FIRST_NAME              VARCHAR(60)   NOT NULL COMMENT 'First name (synthetic PII; masked in ANALYTICS views)',
    LAST_NAME               VARCHAR(60)   NOT NULL COMMENT 'Last name (synthetic PII; masked in ANALYTICS views)',
    DATE_OF_BIRTH           DATE          NOT NULL COMMENT 'Date of birth (synthetic PII; ANALYTICS views expose age only)',
    EMAIL                   VARCHAR(150)  NOT NULL COMMENT 'Email address (synthetic PII; masked in ANALYTICS views)',
    PHONE                   VARCHAR(30)   NOT NULL COMMENT 'Phone number (synthetic PII; ANALYTICS views expose last 4 only)',
    COUNTRY_OF_RESIDENCE    VARCHAR(60)   NOT NULL COMMENT 'Country of residence',
    CITY                    VARCHAR(80)   NOT NULL COMMENT 'City of residence',
    NATIONALITY             VARCHAR(60)   NOT NULL COMMENT 'Nationality',
    SIGNUP_DATE             DATE          NOT NULL COMMENT 'Date the customer registered',
    SIGNUP_CHANNEL          VARCHAR(20)   NOT NULL COMMENT 'Mobile App, Web or Retail Agent',
    HOME_AGENT_ID           VARCHAR(20)            COMMENT 'Agent location the customer usually visits',
    PREFERRED_CORRIDOR_ID   VARCHAR(20)   NOT NULL COMMENT 'Corridor the customer usually sends to',
    SEGMENT                 VARCHAR(30)   NOT NULL COMMENT 'Regular Remitter, Occasional Sender, High Value, Small Business or New',
    LOYALTY_TIER            VARCHAR(20)   NOT NULL COMMENT 'Ria loyalty tier: None, Silver, Gold, Platinum',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Active, Dormant, Closed or Blocked',
    MARKETING_OPT_IN        BOOLEAN       NOT NULL COMMENT 'TRUE when the customer opted in to marketing',
    CONSTRAINT PK_CUSTOMERS PRIMARY KEY (CUSTOMER_ID)
) COMMENT = 'Senders (customers). Synthetic PII, masked in ANALYTICS views';

CREATE OR REPLACE TABLE KYC_PROFILES (
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer identifier',
    KYC_TIER                VARCHAR(10)   NOT NULL COMMENT 'KYC tier: Tier 1 (basic), Tier 2 (verified), Tier 3 (enhanced)',
    RISK_RATING             VARCHAR(10)   NOT NULL COMMENT 'CDD customer risk rating: Low, Medium or High',
    PEP_FLAG                BOOLEAN       NOT NULL COMMENT 'TRUE when the customer is a politically exposed person',
    EDD_REQUIRED            BOOLEAN       NOT NULL COMMENT 'TRUE when enhanced due diligence is required',
    EDD_COMPLETED           BOOLEAN       NOT NULL COMMENT 'TRUE when required enhanced due diligence is complete',
    ID_DOCUMENT_TYPE        VARCHAR(30)   NOT NULL COMMENT 'Passport, National ID, Drivers License or Consular ID',
    ID_VERIFICATION_STATUS  VARCHAR(20)   NOT NULL COMMENT 'Verified, Pending, Failed or Expired',
    ID_VERIFICATION_ATTEMPTS INTEGER      NOT NULL COMMENT 'Number of ID verification attempts at onboarding',
    ID_VERIFIED_AT          TIMESTAMP_NTZ          COMMENT 'When the identity was verified',
    EMAIL_AGE_DAYS          INTEGER       NOT NULL COMMENT 'Age of the email address in days at signup (from email intelligence vendor)',
    PHONE_IS_VOIP           BOOLEAN       NOT NULL COMMENT 'TRUE when the phone number is a VoIP number',
    ADDRESS_SHARED_COUNT    INTEGER       NOT NULL COMMENT 'Number of other customers registered at the same address',
    CREDIT_HEADER_AGE_YEARS NUMBER(5,1)   NOT NULL COMMENT 'Age of the identity credit-header file in years (thin files are short)',
    SOURCE_OF_FUNDS         VARCHAR(40)   NOT NULL COMMENT 'Declared source of funds',
    OCCUPATION              VARCHAR(60)   NOT NULL COMMENT 'Declared occupation',
    EXPECTED_MONTHLY_USD    NUMBER(12,2)  NOT NULL COMMENT 'Declared expected monthly send amount in US dollars',
    LAST_REVIEW_DATE        DATE          NOT NULL COMMENT 'Date of the last CDD review',
    NEXT_REVIEW_DATE        DATE          NOT NULL COMMENT 'Date the next CDD review is due',
    CONFIRMED_SYNTHETIC_ID  BOOLEAN                COMMENT 'Investigation outcome: TRUE when confirmed synthetic identity, FALSE when confirmed genuine, NULL when signup is too recent to know. ML label',
    CONSTRAINT PK_KYC_PROFILES PRIMARY KEY (CUSTOMER_ID)
) COMMENT = 'KYC, CDD and EDD profile per customer';

CREATE OR REPLACE TABLE BENEFICIARIES (
    BENEFICIARY_ID          VARCHAR(20)   NOT NULL COMMENT 'Beneficiary identifier (B0000000 format)',
    CREATED_BY_CUSTOMER_ID  VARCHAR(20)   NOT NULL COMMENT 'Customer who first added the beneficiary',
    FIRST_NAME              VARCHAR(60)   NOT NULL COMMENT 'Beneficiary first name (synthetic PII; masked in ANALYTICS views)',
    LAST_NAME               VARCHAR(60)   NOT NULL COMMENT 'Beneficiary last name (synthetic PII; masked in ANALYTICS views)',
    COUNTRY                 VARCHAR(60)   NOT NULL COMMENT 'Beneficiary country',
    CITY                    VARCHAR(80)   NOT NULL COMMENT 'Beneficiary city',
    RELATIONSHIP            VARCHAR(30)   NOT NULL COMMENT 'Declared relationship to sender: Family, Friend, Business, Self, Other',
    PREFERRED_PAYOUT_METHOD VARCHAR(30)   NOT NULL COMMENT 'Cash Pickup, Bank Deposit, Mobile Wallet or Home Delivery',
    BANK_NAME               VARCHAR(80)            COMMENT 'Receiving bank for bank deposit',
    ACCOUNT_LAST4           VARCHAR(4)             COMMENT 'Last 4 digits of the receiving account (GLBA: no full account numbers)',
    CREATED_AT              TIMESTAMP_NTZ NOT NULL COMMENT 'When the beneficiary was added',
    CONFIRMED_MULE          BOOLEAN       NOT NULL COMMENT 'Investigation outcome: TRUE when confirmed money mule. ML label',
    CONSTRAINT PK_BENEFICIARIES PRIMARY KEY (BENEFICIARY_ID)
) COMMENT = 'Transfer recipients (beneficiaries)';

CREATE OR REPLACE TABLE FUNDING_SOURCES (
    FUNDING_SOURCE_ID       VARCHAR(20)   NOT NULL COMMENT 'Funding source identifier (FS0000000 format)',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer who owns the funding source',
    SOURCE_TYPE             VARCHAR(20)   NOT NULL COMMENT 'Debit Card, Credit Card, Bank Account or Cash',
    CARD_TOKEN              VARCHAR(40)            COMMENT 'PCI DSS network token for the card (never the PAN)',
    CARD_BIN                VARCHAR(6)             COMMENT 'Card bank identification number (first 6 digits)',
    CARD_LAST4              VARCHAR(4)             COMMENT 'Last 4 digits of the card',
    CARD_NETWORK            VARCHAR(20)            COMMENT 'Visa, Mastercard, Amex or Discover',
    ISSUER_COUNTRY          VARCHAR(60)            COMMENT 'Card issuer country',
    BANK_NAME               VARCHAR(80)            COMMENT 'Bank name for ACH-funded transfers',
    ACCOUNT_LAST4           VARCHAR(4)             COMMENT 'Last 4 digits of the bank account (GLBA: no full account numbers)',
    ADDED_AT                TIMESTAMP_NTZ NOT NULL COMMENT 'When the funding source was added',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Active, Expired or Removed',
    CONSTRAINT PK_FUNDING_SOURCES PRIMARY KEY (FUNDING_SOURCE_ID)
) COMMENT = 'Cards, bank accounts and cash funding sources. PCI DSS: token, BIN and last 4 only';

CREATE OR REPLACE TABLE DEVICES (
    DEVICE_ID               VARCHAR(20)   NOT NULL COMMENT 'Device identifier (D0000000 format)',
    DEVICE_FINGERPRINT      VARCHAR(64)   NOT NULL COMMENT 'Hashed device fingerprint',
    OS                      VARCHAR(20)   NOT NULL COMMENT 'iOS, Android, Windows or macOS',
    APP_VERSION             VARCHAR(20)   NOT NULL COMMENT 'Ria app version',
    IS_EMULATOR             BOOLEAN       NOT NULL COMMENT 'TRUE when the device is an emulator',
    IS_ROOTED               BOOLEAN       NOT NULL COMMENT 'TRUE when the device is rooted or jailbroken',
    FIRST_SEEN_AT           TIMESTAMP_NTZ NOT NULL COMMENT 'First time the device was seen',
    CONSTRAINT PK_DEVICES PRIMARY KEY (DEVICE_ID)
) COMMENT = 'Devices seen in digital sessions';

CREATE OR REPLACE TABLE APP_SESSIONS (
    SESSION_ID              VARCHAR(20)   NOT NULL COMMENT 'Session identifier (S00000000 format)',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer who logged in',
    DEVICE_ID               VARCHAR(20)   NOT NULL COMMENT 'Device used',
    IP_ADDRESS              VARCHAR(40)   NOT NULL COMMENT 'Synthetic IP address from the RFC 2544 benchmarking range 198.18.0.0/15',
    IP_COUNTRY              VARCHAR(60)   NOT NULL COMMENT 'Country the IP geolocates to',
    CHANNEL                 VARCHAR(20)   NOT NULL COMMENT 'Mobile App or Web',
    LOGIN_AT                TIMESTAMP_NTZ NOT NULL COMMENT 'Login timestamp',
    LOGIN_METHOD            VARCHAR(20)   NOT NULL COMMENT 'Password, Biometric or OTP',
    LOGIN_SUCCESS           BOOLEAN       NOT NULL COMMENT 'TRUE when the login succeeded',
    FAILED_ATTEMPTS         INTEGER       NOT NULL COMMENT 'Failed login attempts before this session',
    IS_NEW_DEVICE           BOOLEAN       NOT NULL COMMENT 'TRUE when the device had not been seen for this customer',
    IS_VPN                  BOOLEAN       NOT NULL COMMENT 'TRUE when the IP is a known VPN or proxy',
    PASSWORD_RESET_24H      BOOLEAN       NOT NULL COMMENT 'TRUE when the password was reset in the prior 24 hours',
    GEO_DISTANCE_KM         NUMBER(10,1)  NOT NULL COMMENT 'Distance from the customer''s usual login location in kilometers',
    SESSION_DURATION_SEC    INTEGER       NOT NULL COMMENT 'Session length in seconds',
    ACTIONS_COUNT           INTEGER       NOT NULL COMMENT 'Number of in-app actions in the session',
    BENEFICIARY_ADDED       BOOLEAN       NOT NULL COMMENT 'TRUE when a beneficiary was added in the session',
    PROFILE_CHANGED         BOOLEAN       NOT NULL COMMENT 'TRUE when email, phone or password was changed in the session',
    IS_ACCOUNT_TAKEOVER     BOOLEAN       NOT NULL COMMENT 'Investigation outcome: TRUE when the session was confirmed account takeover. ML label',
    CONSTRAINT PK_APP_SESSIONS PRIMARY KEY (SESSION_ID)
) COMMENT = 'Mobile app and web login sessions';

-- ============================================================================
-- TRANSFERS
-- ============================================================================
CREATE OR REPLACE TABLE TRANSFERS (
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Transfer identifier (T000000000 format)',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Sender customer identifier',
    BENEFICIARY_ID          VARCHAR(20)   NOT NULL COMMENT 'Beneficiary identifier',
    CORRIDOR_ID             VARCHAR(20)   NOT NULL COMMENT 'Corridor identifier',
    CHANNEL                 VARCHAR(20)   NOT NULL COMMENT 'Send channel: Retail Agent, Mobile App or Web',
    SEND_AGENT_ID           VARCHAR(20)            COMMENT 'Agent location where the transfer was sent (Retail Agent channel)',
    PAYOUT_AGENT_ID         VARCHAR(20)            COMMENT 'Agent location that paid out (cash pickup)',
    PAYOUT_METHOD           VARCHAR(30)   NOT NULL COMMENT 'Cash Pickup, Bank Deposit, Mobile Wallet or Home Delivery',
    FUNDING_SOURCE_ID       VARCHAR(20)   NOT NULL COMMENT 'Funding source identifier',
    FUNDING_TYPE            VARCHAR(20)   NOT NULL COMMENT 'Cash, Debit Card, Credit Card or Bank Account',
    SESSION_ID              VARCHAR(20)            COMMENT 'Digital session the transfer was created in',
    CREATED_AT              TIMESTAMP_NTZ NOT NULL COMMENT 'When the transfer was created',
    SEND_AMOUNT_USD         NUMBER(12,2)  NOT NULL COMMENT 'Send amount in US dollars',
    SEND_CURRENCY           VARCHAR(3)    NOT NULL COMMENT 'ISO 4217 send currency',
    SEND_AMOUNT_LOCAL       NUMBER(16,2)  NOT NULL COMMENT 'Send amount in the send currency',
    PAYOUT_CURRENCY         VARCHAR(3)    NOT NULL COMMENT 'ISO 4217 payout currency',
    PAYOUT_AMOUNT_LOCAL     NUMBER(18,2)  NOT NULL COMMENT 'Payout amount in the payout currency',
    FX_RATE                 NUMBER(18,6)  NOT NULL COMMENT 'Applied FX rate: payout currency units per US dollar',
    FEE_USD                 NUMBER(10,2)  NOT NULL COMMENT 'Fee charged in US dollars',
    FX_MARGIN_USD           NUMBER(10,2)  NOT NULL COMMENT 'FX margin revenue in US dollars',
    PURPOSE                 VARCHAR(40)   NOT NULL COMMENT 'Declared purpose: Family Support, Bills, Education, Medical, Savings, Gift, Business, Investment, Other',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Paid, Available for Pickup, On Hold, Blocked, Cancelled or Refunded',
    PAID_AT                 TIMESTAMP_NTZ          COMMENT 'When the beneficiary was paid',
    CANCELLED_AT            TIMESTAMP_NTZ          COMMENT 'When the transfer was cancelled',
    CANCELLED_WITHIN_WINDOW BOOLEAN                COMMENT 'Reg E remittance rule: TRUE when cancelled within the 30-minute cancellation window',
    TRAVEL_RULE_REQUIRED    BOOLEAN       NOT NULL COMMENT 'FATF Travel Rule: TRUE when the send amount is $3,000 or more',
    ORIGINATOR_NAME         VARCHAR(120)           COMMENT 'Travel Rule originator name (populated when amount >= $3,000; synthetic PII)',
    ORIGINATOR_ADDRESS      VARCHAR(200)           COMMENT 'Travel Rule originator address (synthetic PII)',
    ORIGINATOR_ACCOUNT_REF  VARCHAR(40)            COMMENT 'Travel Rule originator account reference (funding source id)',
    BENEFICIARY_NAME        VARCHAR(120)           COMMENT 'Travel Rule beneficiary name (synthetic PII)',
    BENEFICIARY_ADDRESS     VARCHAR(200)           COMMENT 'Travel Rule beneficiary address (synthetic PII)',
    IS_FRAUD                BOOLEAN       NOT NULL COMMENT 'Investigation outcome: TRUE when confirmed fraudulent (unauthorized, takeover, card, ring or synthetic identity). ML label',
    FRAUD_TYPE              VARCHAR(40)            COMMENT 'Confirmed fraud type when IS_FRAUD',
    IS_SCAM_VICTIM          BOOLEAN       NOT NULL COMMENT 'Investigation outcome: TRUE when the sender was confirmed to be a scam victim (APP, romance, elder, impersonation). ML label',
    CONSTRAINT PK_TRANSFERS PRIMARY KEY (TRANSFER_ID)
) COMMENT = 'Money transfers with corridor, channel, payout method, amounts, FX and FATF Travel Rule fields';

CREATE OR REPLACE TABLE ACH_RETURNS (
    RETURN_ID               VARCHAR(20)   NOT NULL COMMENT 'ACH return identifier',
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Bank-funded transfer that was returned',
    RETURN_CODE             VARCHAR(4)    NOT NULL COMMENT 'NACHA return code, for example R01, R02, R03, R10, R29',
    RETURN_REASON           VARCHAR(100)  NOT NULL COMMENT 'NACHA return reason',
    RETURNED_AT             TIMESTAMP_NTZ NOT NULL COMMENT 'When the return was received',
    AMOUNT_USD              NUMBER(12,2)  NOT NULL COMMENT 'Returned amount in US dollars',
    IS_UNAUTHORIZED         BOOLEAN       NOT NULL COMMENT 'TRUE for unauthorized return codes (R05, R07, R10, R29)',
    CONSTRAINT PK_ACH_RETURNS PRIMARY KEY (RETURN_ID)
) COMMENT = 'NACHA ACH returns on bank-funded transfers';

CREATE OR REPLACE TABLE CHARGEBACKS (
    CHARGEBACK_ID           VARCHAR(20)   NOT NULL COMMENT 'Chargeback identifier',
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Card-funded transfer charged back',
    FUNDING_SOURCE_ID       VARCHAR(20)   NOT NULL COMMENT 'Card funding source',
    REASON_CODE             VARCHAR(10)   NOT NULL COMMENT 'Card network reason code, for example 10.4 or 4837',
    REASON                  VARCHAR(80)   NOT NULL COMMENT 'Chargeback reason: Fraud - Card Not Present, Not Recognized, Not Received, Duplicate',
    AMOUNT_USD              NUMBER(12,2)  NOT NULL COMMENT 'Chargeback amount in US dollars',
    RECEIVED_AT             TIMESTAMP_NTZ NOT NULL COMMENT 'When the chargeback was received',
    DAYS_FROM_TRANSFER      INTEGER       NOT NULL COMMENT 'Days between the transfer and the chargeback',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Open, Represented, Won or Lost',
    CONSTRAINT PK_CHARGEBACKS PRIMARY KEY (CHARGEBACK_ID)
) COMMENT = 'Card chargebacks on card-funded transfers';

CREATE OR REPLACE TABLE REFUNDS (
    REFUND_ID               VARCHAR(20)   NOT NULL COMMENT 'Refund identifier',
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Refunded transfer',
    REASON                  VARCHAR(60)   NOT NULL COMMENT 'Customer Cancellation, Not Picked Up, Compliance Block, Error Resolution, Fraud',
    AMOUNT_USD              NUMBER(12,2)  NOT NULL COMMENT 'Refund amount in US dollars',
    REQUESTED_AT            TIMESTAMP_NTZ NOT NULL COMMENT 'When the refund was requested',
    REFUNDED_AT             TIMESTAMP_NTZ          COMMENT 'When the refund was paid',
    DAYS_TO_REFUND          INTEGER                COMMENT 'Business days from request to refund',
    WITHIN_REG_E_TIMELINE   BOOLEAN                COMMENT 'Reg E remittance rule: TRUE when refunded within 3 business days of a valid cancellation',
    CONSTRAINT PK_REFUNDS PRIMARY KEY (REFUND_ID)
) COMMENT = 'Refunds with Reg E timeliness';

CREATE OR REPLACE TABLE DISPUTES (
    DISPUTE_ID              VARCHAR(20)   NOT NULL COMMENT 'Dispute identifier',
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Disputed transfer',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer who raised the error notice',
    ERROR_TYPE              VARCHAR(60)   NOT NULL COMMENT 'Reg E error type: Incorrect Amount, Not Received, Wrong Beneficiary, Late Delivery, Unauthorized',
    OPENED_AT               TIMESTAMP_NTZ NOT NULL COMMENT 'When the error notice was received',
    RESOLVED_AT             TIMESTAMP_NTZ          COMMENT 'When the dispute was resolved',
    DAYS_TO_RESOLVE         INTEGER                COMMENT 'Days to resolve',
    WITHIN_90_DAYS          BOOLEAN                COMMENT 'Reg E remittance rule: TRUE when resolved within 90 days',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Open, Investigating or Resolved',
    OUTCOME                 VARCHAR(40)            COMMENT 'Error Confirmed - Refunded, Error Confirmed - Resent, No Error Found',
    ASSIGNED_ANALYST_ID     VARCHAR(20)            COMMENT 'Disputes analyst',
    CONSTRAINT PK_DISPUTES PRIMARY KEY (DISPUTE_ID)
) COMMENT = 'Reg E / CFPB remittance rule error notices and disputes';

-- ============================================================================
-- FRAUD OPERATIONS
-- ============================================================================
CREATE OR REPLACE TABLE FRAUD_ALERTS (
    ALERT_ID                VARCHAR(20)   NOT NULL COMMENT 'Alert identifier (AL00000000 format)',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer the alert is about',
    TRANSFER_ID             VARCHAR(20)            COMMENT 'Transfer that triggered the alert, when transaction-level',
    AGENT_ID                VARCHAR(20)            COMMENT 'Agent location the alert is about, when agent-level',
    ALERT_TYPE              VARCHAR(40)   NOT NULL COMMENT 'Transaction Fraud, Account Takeover, Structuring, Money Mule, Scam Victim, Velocity, Agent Collusion, Card Fraud',
    DETECTION_SOURCE        VARCHAR(20)   NOT NULL COMMENT 'Rule, Model or Referral',
    RULE_CODE               VARCHAR(20)            COMMENT 'Detection rule code',
    ALERT_SCORE             NUMBER(5,1)   NOT NULL COMMENT 'Detection score 0-100 at alert time',
    SEVERITY                VARCHAR(10)   NOT NULL COMMENT 'Low, Medium, High or Critical',
    QUEUE                   VARCHAR(40)   NOT NULL COMMENT 'Owning queue: Fraud Operations, AML Investigations, Sanctions, Agent Oversight, Disputes',
    CREATED_AT              TIMESTAMP_NTZ NOT NULL COMMENT 'When the alert was created',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Open, In Review, Escalated or Closed',
    ASSIGNED_ANALYST_ID     VARCHAR(20)            COMMENT 'Assigned analyst',
    ASSIGNED_AT             TIMESTAMP_NTZ          COMMENT 'When the alert was assigned',
    DISPOSITION             VARCHAR(30)            COMMENT 'True Positive, False Positive or Inconclusive (NULL while open)',
    CLOSED_AT               TIMESTAMP_NTZ          COMMENT 'When the alert was closed',
    CASE_ID                 VARCHAR(20)            COMMENT 'Case the alert was escalated into',
    CONSTRAINT PK_FRAUD_ALERTS PRIMARY KEY (ALERT_ID)
) COMMENT = 'Fraud and AML alerts from rules, models and referrals';

CREATE OR REPLACE TABLE FRAUD_CASES (
    CASE_ID                 VARCHAR(20)   NOT NULL COMMENT 'Case identifier (CS0000000 format)',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Subject customer',
    CASE_TYPE               VARCHAR(40)   NOT NULL COMMENT 'Fraud, Account Takeover, AML - Structuring, Money Mule, Scam, Agent Collusion, Fraud Ring, Card Fraud',
    QUEUE                   VARCHAR(40)   NOT NULL COMMENT 'Owning queue',
    PRIORITY                VARCHAR(10)   NOT NULL COMMENT 'P1, P2, P3 or P4',
    OPENED_AT               TIMESTAMP_NTZ NOT NULL COMMENT 'When the case was opened',
    STATUS                  VARCHAR(30)   NOT NULL COMMENT 'Open, Investigating, Pending SAR Decision or Closed',
    ASSIGNED_ANALYST_ID     VARCHAR(20)   NOT NULL COMMENT 'Lead analyst',
    DISPOSITION             VARCHAR(40)            COMMENT 'Confirmed Fraud, Not Fraud, Referred to Law Enforcement, Insufficient Evidence (NULL while open)',
    CLOSED_AT               TIMESTAMP_NTZ          COMMENT 'When the case was closed',
    EXPOSURE_USD            NUMBER(14,2)  NOT NULL COMMENT 'Transfer value under investigation in US dollars',
    SAR_REQUIRED            BOOLEAN                COMMENT 'TRUE when a SAR was decided to be required',
    CONSTRAINT PK_FRAUD_CASES PRIMARY KEY (CASE_ID)
) COMMENT = 'Fraud and AML investigation cases';

CREATE OR REPLACE TABLE CASE_EVENTS (
    EVENT_ID                VARCHAR(24)   NOT NULL COMMENT 'Event identifier',
    CASE_ID                 VARCHAR(20)            COMMENT 'Case the event belongs to',
    ALERT_ID                VARCHAR(20)            COMMENT 'Alert the event belongs to',
    EVENT_TYPE              VARCHAR(40)   NOT NULL COMMENT 'Alert Created, Alert Assigned, Alert Closed, Escalated to Case, Case Opened, Note Added, SAR Decision, Case Closed',
    ANALYST_ID              VARCHAR(20)            COMMENT 'Analyst who performed the action (NULL for system events)',
    EVENT_AT                TIMESTAMP_NTZ NOT NULL COMMENT 'Event timestamp',
    DETAIL                  VARCHAR(300)           COMMENT 'Event detail',
    CONSTRAINT PK_CASE_EVENTS PRIMARY KEY (EVENT_ID)
) COMMENT = 'FFIEC alert-to-case-to-disposition audit trail';

CREATE OR REPLACE TABLE CASE_NOTES (
    NOTE_ID                 VARCHAR(20)   NOT NULL COMMENT 'Note identifier',
    CASE_ID                 VARCHAR(20)   NOT NULL COMMENT 'Case',
    ANALYST_ID              VARCHAR(20)   NOT NULL COMMENT 'Author analyst',
    CREATED_AT              TIMESTAMP_NTZ NOT NULL COMMENT 'When the note was written',
    NOTE_TEXT               VARCHAR(4000) NOT NULL COMMENT 'Investigator note text (synthetic)',
    CONSTRAINT PK_CASE_NOTES PRIMARY KEY (NOTE_ID)
) COMMENT = 'Investigator case notes';

CREATE OR REPLACE TABLE FRAUD_LOSSES (
    LOSS_ID                 VARCHAR(20)   NOT NULL COMMENT 'Loss identifier',
    TRANSFER_ID             VARCHAR(20)   NOT NULL COMMENT 'Transfer the loss relates to',
    CASE_ID                 VARCHAR(20)            COMMENT 'Case',
    LOSS_TYPE               VARCHAR(40)   NOT NULL COMMENT 'Unauthorized Transfer, Account Takeover, Card Chargeback, ACH Return, Agent Fraud, Scam Reimbursement, Synthetic Identity',
    LOSS_DATE               DATE          NOT NULL COMMENT 'Date the loss was booked',
    GROSS_LOSS_USD          NUMBER(12,2)  NOT NULL COMMENT 'Gross loss in US dollars',
    RECOVERED_USD           NUMBER(12,2)  NOT NULL COMMENT 'Amount recovered in US dollars',
    WRITE_OFF_USD           NUMBER(12,2)  NOT NULL COMMENT 'Amount written off in US dollars',
    NET_LOSS_USD            NUMBER(12,2)  NOT NULL COMMENT 'Net loss (gross minus recovered) in US dollars',
    RECOVERY_METHOD         VARCHAR(40)            COMMENT 'Payout Recall, Agent Clawback, Chargeback Representment, Customer Repayment, None',
    CONSTRAINT PK_FRAUD_LOSSES PRIMARY KEY (LOSS_ID)
) COMMENT = 'Fraud losses, recoveries and write-offs';

-- ============================================================================
-- COMPLIANCE
-- ============================================================================
CREATE OR REPLACE TABLE SANCTIONS_SCREENING (
    SCREENING_ID            VARCHAR(20)   NOT NULL COMMENT 'Screening hit identifier (SC00000000 format)',
    TRANSFER_ID             VARCHAR(20)            COMMENT 'Transfer screened',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Sender customer',
    BENEFICIARY_ID          VARCHAR(20)            COMMENT 'Beneficiary, when the beneficiary was the party screened',
    SCREENED_PARTY          VARCHAR(20)   NOT NULL COMMENT 'Sender or Beneficiary',
    LIST_SOURCE             VARCHAR(20)   NOT NULL COMMENT 'Sanctions list: SDN (OFAC), EU, UN or UK HMT',
    MATCHED_ENTRY_NAME      VARCHAR(120)  NOT NULL COMMENT 'Name on the sanctions list that matched (synthetic)',
    MATCHED_ENTRY_COUNTRY   VARCHAR(60)   NOT NULL COMMENT 'Country on the matched list entry',
    MATCH_SCORE             NUMBER(5,1)   NOT NULL COMMENT 'Screening engine match score 0-100',
    NAME_SIMILARITY         NUMBER(5,3)   NOT NULL COMMENT 'Name similarity 0-1',
    DOB_MATCH               BOOLEAN       NOT NULL COMMENT 'TRUE when the date of birth matches the list entry',
    COUNTRY_MATCH           BOOLEAN       NOT NULL COMMENT 'TRUE when the country matches the list entry',
    SECONDARY_ID_MATCH      BOOLEAN       NOT NULL COMMENT 'TRUE when a secondary identifier (passport, address) matches',
    SCREENED_AT             TIMESTAMP_NTZ NOT NULL COMMENT 'When the hit was generated',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Open or Closed',
    DISPOSITION             VARCHAR(20)   NOT NULL COMMENT 'Pending, Cleared, Escalated or Blocked',
    ANALYST_ID              VARCHAR(20)            COMMENT 'Sanctions analyst',
    DISPOSITIONED_AT        TIMESTAMP_NTZ          COMMENT 'When the hit was dispositioned',
    IS_TRUE_MATCH           BOOLEAN                COMMENT 'Investigation outcome: TRUE true match, FALSE false positive, NULL while open. ML label',
    CONSTRAINT PK_SANCTIONS_SCREENING PRIMARY KEY (SCREENING_ID)
) COMMENT = 'OFAC and global sanctions name-screening hits';

CREATE OR REPLACE TABLE SAR_FILINGS (
    SAR_ID                  VARCHAR(20)   NOT NULL COMMENT 'SAR identifier',
    CASE_ID                 VARCHAR(20)   NOT NULL COMMENT 'Case the SAR came from',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Subject customer',
    SUSPICIOUS_ACTIVITY_TYPE VARCHAR(60)  NOT NULL COMMENT 'Structuring, Fraud, Money Mule, Elder Financial Exploitation, Identity Theft, Agent Complicity, Sanctions Evasion',
    DETECTION_DATE          DATE          NOT NULL COMMENT 'Date suspicious activity was detected (BSA 30-day clock starts)',
    DUE_DATE                DATE          NOT NULL COMMENT 'Filing deadline: detection date plus 30 days',
    FILED_DATE              DATE                   COMMENT 'Date filed with FinCEN',
    FILING_STATUS           VARCHAR(20)   NOT NULL COMMENT 'Draft, In Review, Filed or Filed Late',
    DAYS_TO_FILE            INTEGER                COMMENT 'Days from detection to filing',
    AMOUNT_USD              NUMBER(14,2)  NOT NULL COMMENT 'Suspicious amount in US dollars',
    PREPARER_ANALYST_ID     VARCHAR(20)   NOT NULL COMMENT 'Preparing analyst',
    NARRATIVE               VARCHAR(6000) NOT NULL COMMENT 'SAR narrative (synthetic)',
    CONSTRAINT PK_SAR_FILINGS PRIMARY KEY (SAR_ID)
) COMMENT = 'BSA Suspicious Activity Report filings with 30-day deadline tracking';

CREATE OR REPLACE TABLE CTR_FILINGS (
    CTR_ID                  VARCHAR(20)   NOT NULL COMMENT 'CTR identifier',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer',
    BUSINESS_DATE           DATE          NOT NULL COMMENT 'Business day aggregated',
    TOTAL_CASH_USD          NUMBER(14,2)  NOT NULL COMMENT 'Total cash-funded transfers that day in US dollars (over $10,000)',
    TRANSFER_COUNT          INTEGER       NOT NULL COMMENT 'Cash-funded transfers that day',
    DUE_DATE                DATE          NOT NULL COMMENT 'CTR due date: business date plus 15 days',
    FILED_DATE              DATE                   COMMENT 'Date filed with FinCEN',
    FILING_STATUS           VARCHAR(20)   NOT NULL COMMENT 'Pending, Filed or Filed Late',
    CONSTRAINT PK_CTR_FILINGS PRIMARY KEY (CTR_ID)
) COMMENT = 'BSA Currency Transaction Reports for daily cash over $10,000';

CREATE OR REPLACE TABLE STRUCTURING_REVIEWS (
    REVIEW_ID               VARCHAR(20)   NOT NULL COMMENT 'Review identifier',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer reviewed',
    WEEK_START              DATE          NOT NULL COMMENT 'Monday of the customer-week reviewed',
    REVIEWED_AT             TIMESTAMP_NTZ NOT NULL COMMENT 'When the review was completed',
    ANALYST_ID              VARCHAR(20)   NOT NULL COMMENT 'Reviewing analyst',
    CONFIRMED_STRUCTURING   BOOLEAN       NOT NULL COMMENT 'Review outcome: TRUE when the customer-week was confirmed structuring. ML label',
    CONSTRAINT PK_STRUCTURING_REVIEWS PRIMARY KEY (REVIEW_ID)
) COMMENT = 'AML look-back reviews of customer-weeks with $3,000 or more sent';

-- ============================================================================
-- CUSTOMER 360
-- ============================================================================
CREATE OR REPLACE TABLE COMPLAINTS (
    COMPLAINT_ID            VARCHAR(20)   NOT NULL COMMENT 'Complaint identifier',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer',
    TRANSFER_ID             VARCHAR(20)            COMMENT 'Related transfer',
    CHANNEL                 VARCHAR(20)   NOT NULL COMMENT 'Phone, Email, App, Agent or CFPB Portal',
    CATEGORY                VARCHAR(40)   NOT NULL COMMENT 'Delay, Fees, FX Rate, Fraud, Account Locked, Customer Service, Refund',
    SUBMITTED_AT            TIMESTAMP_NTZ NOT NULL COMMENT 'When the complaint was submitted',
    RESOLVED_AT             TIMESTAMP_NTZ          COMMENT 'When the complaint was resolved',
    STATUS                  VARCHAR(20)   NOT NULL COMMENT 'Open, In Progress or Resolved',
    CFPB_ESCALATED          BOOLEAN       NOT NULL COMMENT 'TRUE when the complaint came through or was escalated to the CFPB',
    COMPLAINT_TEXT          VARCHAR(3000) NOT NULL COMMENT 'Complaint text (synthetic)',
    CONSTRAINT PK_COMPLAINTS PRIMARY KEY (COMPLAINT_ID)
) COMMENT = 'Customer complaints including CFPB escalations';

CREATE OR REPLACE TABLE NPS_SURVEYS (
    SURVEY_ID               VARCHAR(20)   NOT NULL COMMENT 'Survey response identifier',
    CUSTOMER_ID             VARCHAR(20)   NOT NULL COMMENT 'Customer',
    SURVEY_DATE             DATE          NOT NULL COMMENT 'Response date',
    NPS_SCORE               INTEGER       NOT NULL COMMENT 'Likelihood to recommend 0-10',
    NPS_CATEGORY            VARCHAR(20)   NOT NULL COMMENT 'Promoter, Passive or Detractor',
    COMMENT_TEXT            VARCHAR(1000)          COMMENT 'Verbatim comment (synthetic)',
    CONSTRAINT PK_NPS_SURVEYS PRIMARY KEY (SURVEY_ID)
) COMMENT = 'Net Promoter Score survey responses';

-- ============================================================================
-- DOCUMENTS
-- ============================================================================
CREATE OR REPLACE TABLE FRAUD_TYPOLOGIES (
    DOC_ID                  VARCHAR(20)   NOT NULL COMMENT 'Document identifier',
    TITLE                   VARCHAR(200)  NOT NULL COMMENT 'Document title',
    TYPOLOGY                VARCHAR(60)   NOT NULL COMMENT 'Typology: Account Takeover, Money Mule, Structuring, Romance Scam, Elder Fraud, Synthetic Identity, Agent Collusion, Card Fraud, Fraud Ring, Sanctions Evasion',
    CATEGORY                VARCHAR(40)   NOT NULL COMMENT 'Typology Guide, Red Flags, Investigation Playbook or Regulator Advisory',
    UPDATED_AT              DATE          NOT NULL COMMENT 'Last update',
    CONTENT                 VARCHAR(8000) NOT NULL COMMENT 'Document text',
    CONSTRAINT PK_FRAUD_TYPOLOGIES PRIMARY KEY (DOC_ID)
) COMMENT = 'Fraud and AML typology guides, red flags and playbooks';

CREATE OR REPLACE TABLE POLICY_DOCUMENTS (
    DOC_ID                  VARCHAR(20)   NOT NULL COMMENT 'Policy identifier',
    TITLE                   VARCHAR(200)  NOT NULL COMMENT 'Policy title',
    POLICY_AREA             VARCHAR(60)   NOT NULL COMMENT 'BSA/AML, Sanctions, KYC, Fraud, Privacy, Remittance Transfer Rule, Model Risk, Agent Oversight, Card Security',
    REGULATION              VARCHAR(80)   NOT NULL COMMENT 'Governing regulation or standard',
    VERSION                 VARCHAR(10)   NOT NULL COMMENT 'Policy version',
    EFFECTIVE_DATE          DATE          NOT NULL COMMENT 'Effective date',
    OWNER                   VARCHAR(80)   NOT NULL COMMENT 'Policy owner',
    CONTENT                 VARCHAR(8000) NOT NULL COMMENT 'Policy text',
    CONSTRAINT PK_POLICY_DOCUMENTS PRIMARY KEY (DOC_ID)
) COMMENT = 'Compliance and fraud policies and procedures';
