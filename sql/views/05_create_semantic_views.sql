/*=============================================================================
  Ria Financial Intelligence Agent
  Step 5: Semantic Views

  Execution Order: 5 of 9
  Description: Ten Cortex Analyst semantic views (RIA_*_SV), one per analytics
               tool in the agent routing table. Clause order is TABLES,
               RELATIONSHIPS, DIMENSIONS, METRICS. Every expression refers to
               a column that exists in the underlying ANALYTICS view.
               Model scores shown in these views are predictions trained on
               synthetic data.
=============================================================================*/

USE DATABASE RIA_FINANCIAL_INTELLIGENCE;
USE SCHEMA ANALYTICS;
USE WAREHOUSE RIA_FINANCIAL_WH;

CREATE OR REPLACE SEMANTIC VIEW RIA_TRANSFERS_SV
  TABLES (td AS ANALYTICS.TRANSFER_DETAIL PRIMARY KEY (TRANSFER_ID) COMMENT = 'One row per money transfer with corridor, channel, payout method, funding type, amounts and model fraud score')
  DIMENSIONS (
    td.transfer_id AS TRANSFER_ID COMMENT = 'Transfer identifier',
    td.customer_id AS CUSTOMER_ID COMMENT = 'Sender customer identifier',
    td.corridor_id AS CORRIDOR_ID COMMENT = 'Corridor code such as US-MX',
    td.corridor_name AS CORRIDOR_NAME WITH SYNONYMS ('corridor','route','send-to-payout route') COMMENT = 'Corridor name, for example United States to Mexico',
    td.send_country AS SEND_COUNTRY COMMENT = 'Country the money is sent from',
    td.payout_country AS PAYOUT_COUNTRY WITH SYNONYMS ('destination','destination country','receiving country') COMMENT = 'Country the money is paid out in',
    td.payout_region AS PAYOUT_REGION WITH SYNONYMS ('destination region') COMMENT = 'Latin America, Asia Pacific, Africa or Middle East',
    td.corridor_risk_level AS CORRIDOR_RISK_LEVEL COMMENT = 'AML corridor risk level: Low, Medium or High',
    td.is_high_risk_jurisdiction AS IS_HIGH_RISK_JURISDICTION COMMENT = 'TRUE when the payout country is on the high-risk jurisdiction list',
    td.channel AS CHANNEL WITH SYNONYMS ('send channel','origination channel') COMMENT = 'Retail Agent, Mobile App or Web',
    td.payout_method AS PAYOUT_METHOD WITH SYNONYMS ('delivery method','payout type') COMMENT = 'Cash Pickup, Bank Deposit, Mobile Wallet or Home Delivery',
    td.funding_type AS FUNDING_TYPE WITH SYNONYMS ('funding source','payment method','how it was paid for') COMMENT = 'Cash, Debit Card, Credit Card or Bank Account',
    td.purpose AS PURPOSE WITH SYNONYMS ('reason for sending') COMMENT = 'Declared purpose of the transfer',
    td.transfer_status AS STATUS COMMENT = 'Paid, Available for Pickup, On Hold, Blocked, Cancelled or Refunded',
    td.transfer_date AS TRANSFER_DATE WITH SYNONYMS ('date','day') COMMENT = 'Date of the transfer',
    td.transfer_week AS TRANSFER_WEEK COMMENT = 'Week start (Monday) of the transfer',
    td.transfer_month AS TRANSFER_MONTH WITH SYNONYMS ('month') COMMENT = 'Month of the transfer',
    td.transfer_quarter AS TRANSFER_QUARTER WITH SYNONYMS ('quarter') COMMENT = 'Quarter of the transfer',
    td.amount_band AS AMOUNT_BAND COMMENT = 'Under $500, $500-$2,999, $3,000-$9,999 or $10,000+',
    td.customer_segment AS CUSTOMER_SEGMENT COMMENT = 'Regular Remitter, Occasional Sender, High Value, Small Business or New',
    td.customer_risk_rating AS CUSTOMER_RISK_RATING COMMENT = 'KYC risk rating of the sender: Low, Medium or High',
    td.send_agent_id AS SEND_AGENT_ID COMMENT = 'Agent location where the transfer was sent',
    td.send_agent_name AS SEND_AGENT_NAME COMMENT = 'Agent location name',
    td.travel_rule_required AS TRAVEL_RULE_REQUIRED COMMENT = 'TRUE when amount is $3,000 or more and FATF Travel Rule data is required',
    td.travel_rule_complete AS TRAVEL_RULE_COMPLETE COMMENT = 'TRUE when originator and beneficiary details are present',
    td.confirmed_fraud AS CONFIRMED_FRAUD COMMENT = 'Investigation outcome: TRUE when confirmed fraudulent',
    td.fraud_type AS FRAUD_TYPE COMMENT = 'Confirmed fraud type',
    td.confirmed_scam_victim AS CONFIRMED_SCAM_VICTIM COMMENT = 'Investigation outcome: TRUE when the sender was a confirmed scam victim',
    td.fraud_risk_tier AS FRAUD_RISK_TIER WITH SYNONYMS ('fraud score tier') COMMENT = 'Model-predicted fraud risk tier: Low, Medium or High (scored for the last 180 days)')
  METRICS (
    td.transfer_count AS COUNT(TRANSFER_ID) WITH SYNONYMS ('number of transfers','transactions') COMMENT = 'Number of transfers',
    td.send_volume_usd AS SUM(SEND_AMOUNT_USD) WITH SYNONYMS ('volume','total sent','send volume') COMMENT = 'Total send amount in US dollars',
    td.avg_transfer_usd AS AVG(SEND_AMOUNT_USD) WITH SYNONYMS ('average transfer size','average ticket') COMMENT = 'Average send amount in US dollars',
    td.total_fees_usd AS SUM(FEE_USD) COMMENT = 'Fees charged in US dollars',
    td.total_fx_margin_usd AS SUM(FX_MARGIN_USD) COMMENT = 'FX margin revenue in US dollars',
    td.total_revenue_usd AS SUM(REVENUE_USD) WITH SYNONYMS ('revenue') COMMENT = 'Fees plus FX margin in US dollars',
    td.fraud_transfer_count AS COUNT_IF(CONFIRMED_FRAUD) COMMENT = 'Transfers confirmed fraudulent',
    td.fraud_rate_pct AS 100 * DIV0(COUNT_IF(CONFIRMED_FRAUD), COUNT(TRANSFER_ID)) WITH SYNONYMS ('fraud rate') COMMENT = 'Confirmed fraud transfers as a percent of transfers',
    td.scam_victim_transfer_count AS COUNT_IF(CONFIRMED_SCAM_VICTIM) COMMENT = 'Transfers confirmed as scam-victim sends',
    td.cancelled_transfer_count AS COUNT_IF(STATUS = 'Cancelled') COMMENT = 'Cancelled transfers',
    td.high_fraud_risk_transfer_count AS COUNT_IF(FRAUD_RISK_TIER = 'High') COMMENT = 'Scored transfers in the High model risk tier',
    td.avg_fraud_probability AS AVG(FRAUD_PROBABILITY) COMMENT = 'Average model fraud probability on scored transfers',
    td.travel_rule_gap_count AS COUNT_IF(TRAVEL_RULE_REQUIRED AND NOT TRAVEL_RULE_COMPLETE) COMMENT = 'Transfers of $3,000 or more missing Travel Rule data',
    td.distinct_customers AS COUNT(DISTINCT CUSTOMER_ID) COMMENT = 'Distinct sending customers')
  COMMENT = 'Transfer volume, revenue and fraud by corridor, channel, payout method and funding type';

CREATE OR REPLACE SEMANTIC VIEW RIA_FRAUD_LOSS_SV
  TABLES (fl AS ANALYTICS.FRAUD_LOSS_MONTHLY PRIMARY KEY (CORRIDOR_ID, TRANSFER_MONTH) COMMENT = 'Corridor by month volume, fraud and loss. Loss is attributed to the month of the transfer')
  DIMENSIONS (
    fl.corridor_id AS CORRIDOR_ID COMMENT = 'Corridor code',
    fl.corridor_name AS CORRIDOR_NAME WITH SYNONYMS ('corridor','route') COMMENT = 'Corridor name',
    fl.send_country AS SEND_COUNTRY COMMENT = 'Send country',
    fl.payout_country AS PAYOUT_COUNTRY WITH SYNONYMS ('destination country') COMMENT = 'Payout country',
    fl.payout_region AS PAYOUT_REGION COMMENT = 'Payout region',
    fl.corridor_risk_level AS CORRIDOR_RISK_LEVEL COMMENT = 'Corridor AML risk level',
    fl.transfer_month AS TRANSFER_MONTH WITH SYNONYMS ('month') COMMENT = 'Month of the transfers',
    fl.transfer_quarter AS TRANSFER_QUARTER WITH SYNONYMS ('quarter') COMMENT = 'Quarter of the transfers')
  METRICS (
    fl.transfer_count AS SUM(TRANSFER_COUNT) COMMENT = 'Number of transfers',
    fl.volume_usd AS SUM(VOLUME_USD) WITH SYNONYMS ('send volume') COMMENT = 'Send volume in US dollars',
    fl.fraud_transfer_count AS SUM(FRAUD_TRANSFER_COUNT) COMMENT = 'Transfers confirmed fraudulent',
    fl.fraud_volume_usd AS SUM(FRAUD_VOLUME_USD) COMMENT = 'Send amount of fraudulent transfers in US dollars',
    fl.gross_loss_usd AS SUM(GROSS_LOSS_USD) COMMENT = 'Gross fraud loss in US dollars',
    fl.recovered_usd AS SUM(RECOVERED_USD) WITH SYNONYMS ('recoveries') COMMENT = 'Recovered amount in US dollars',
    fl.write_off_usd AS SUM(WRITE_OFF_USD) WITH SYNONYMS ('write-offs') COMMENT = 'Written-off amount in US dollars',
    fl.net_loss_usd AS SUM(NET_LOSS_USD) WITH SYNONYMS ('net fraud loss','fraud loss') COMMENT = 'Net fraud loss (gross minus recovered) in US dollars',
    fl.loss_count AS SUM(LOSS_COUNT) COMMENT = 'Number of loss records',
    fl.loss_rate_pct AS 100 * DIV0(fl.net_loss_usd, fl.volume_usd) WITH SYNONYMS ('fraud loss rate','loss rate') COMMENT = 'Net loss as a percent of send volume',
    fl.loss_rate_bps AS 10000 * DIV0(fl.net_loss_usd, fl.volume_usd) COMMENT = 'Net loss in basis points of send volume',
    fl.recovery_rate_pct AS 100 * DIV0(fl.recovered_usd, fl.gross_loss_usd) COMMENT = 'Recovered as a percent of gross loss',
    fl.fraud_rate_pct AS 100 * DIV0(fl.fraud_transfer_count, fl.transfer_count) COMMENT = 'Fraud transfers as a percent of transfers')
  COMMENT = 'Fraud losses, recoveries and write-offs by corridor and month';

CREATE OR REPLACE SEMANTIC VIEW RIA_CASES_SV
  TABLES (
    al AS ANALYTICS.ALERT_DETAIL PRIMARY KEY (ALERT_ID) COMMENT = 'One row per fraud or AML alert',
    cs AS ANALYTICS.CASE_DETAIL PRIMARY KEY (CASE_ID) COMMENT = 'One row per investigation case')
  RELATIONSHIPS (alerts_to_cases AS al (CASE_ID) REFERENCES cs)
  DIMENSIONS (
    al.alert_id AS ALERT_ID COMMENT = 'Alert identifier',
    al.alert_type AS ALERT_TYPE COMMENT = 'Transaction Fraud, Account Takeover, Structuring, Money Mule, Scam Victim, Velocity, Agent Collusion or Card Fraud',
    al.detection_source AS DETECTION_SOURCE COMMENT = 'Rule, Model or Referral',
    al.severity AS SEVERITY COMMENT = 'Low, Medium, High or Critical',
    al.alert_queue AS QUEUE WITH SYNONYMS ('owning queue','queue','work queue') COMMENT = 'Queue that owns the alert',
    al.alert_status AS STATUS COMMENT = 'Open, In Review, Escalated or Closed',
    al.alert_disposition AS DISPOSITION COMMENT = 'True Positive, False Positive or Inconclusive (blank while open)',
    al.alert_age_bucket AS AGE_BUCKET WITH SYNONYMS ('aging bucket','aging') COMMENT = 'Age bucket: 0-7 days, 8-30 days, 31-60 days, 61-90 days or Over 90 days',
    al.alert_created_month AS CREATED_MONTH COMMENT = 'Month the alert was created',
    al.alert_created_date AS CREATED_DATE COMMENT = 'Date the alert was created',
    al.is_open_alert AS IS_OPEN COMMENT = 'TRUE when the alert is not closed',
    al.is_open_over_30_days AS IS_OPEN_OVER_30_DAYS COMMENT = 'TRUE when the alert has been open more than 30 days',
    al.is_unassigned AS IS_UNASSIGNED COMMENT = 'TRUE when no analyst is assigned',
    al.assigned_analyst_name AS ASSIGNED_ANALYST_NAME WITH SYNONYMS ('alert analyst') COMMENT = 'Analyst assigned to the alert',
    cs.case_id AS CASE_ID COMMENT = 'Case identifier',
    cs.case_type AS CASE_TYPE COMMENT = 'Fraud, Account Takeover, AML - Structuring, Money Mule, Scam, Agent Collusion, Fraud Ring or Card Fraud',
    cs.case_queue AS QUEUE COMMENT = 'Queue that owns the case',
    cs.case_priority AS PRIORITY COMMENT = 'P1 to P4',
    cs.case_status AS STATUS COMMENT = 'Open, Investigating, Pending SAR Decision or Closed',
    cs.case_disposition AS DISPOSITION COMMENT = 'Confirmed Fraud, Not Fraud, Referred to Law Enforcement or Insufficient Evidence',
    cs.case_opened_month AS OPENED_MONTH COMMENT = 'Month the case was opened',
    cs.case_is_open AS IS_OPEN COMMENT = 'TRUE when the case is not closed',
    cs.case_is_open_over_30_days AS IS_OPEN_OVER_30_DAYS COMMENT = 'TRUE when the case has been open more than 30 days',
    cs.sar_required AS SAR_REQUIRED COMMENT = 'TRUE when a SAR was decided to be required, blank when undecided',
    cs.case_analyst_name AS ASSIGNED_ANALYST_NAME COMMENT = 'Lead analyst on the case')
  METRICS (
    al.alert_count AS COUNT(al.ALERT_ID) COMMENT = 'Number of alerts',
    al.open_alert_count AS COUNT_IF(al.IS_OPEN) WITH SYNONYMS ('alert backlog') COMMENT = 'Alerts not yet closed',
    al.open_alerts_over_30_days AS COUNT_IF(al.IS_OPEN_OVER_30_DAYS) WITH SYNONYMS ('aged alerts') COMMENT = 'Alerts open more than 30 days',
    al.unassigned_alert_count AS COUNT_IF(al.IS_UNASSIGNED AND al.IS_OPEN) COMMENT = 'Open alerts with no analyst assigned',
    al.true_positive_count AS COUNT_IF(al.DISPOSITION = 'True Positive') COMMENT = 'Alerts closed as true positive',
    al.false_positive_count AS COUNT_IF(al.DISPOSITION = 'False Positive') COMMENT = 'Alerts closed as false positive',
    al.false_positive_rate_pct AS 100 * DIV0(COUNT_IF(al.DISPOSITION = 'False Positive'), COUNT_IF(al.DISPOSITION IS NOT NULL)) COMMENT = 'False positives as a percent of dispositioned alerts',
    al.avg_alert_age_days AS AVG(al.AGE_DAYS) COMMENT = 'Average alert age in days',
    al.avg_hours_to_assign AS AVG(al.HOURS_TO_ASSIGN) COMMENT = 'Average hours from alert creation to assignment',
    al.avg_hours_to_close AS AVG(al.HOURS_TO_CLOSE) COMMENT = 'Average hours from alert creation to closure',
    cs.case_count AS COUNT(cs.CASE_ID) COMMENT = 'Number of cases',
    cs.open_case_count AS COUNT_IF(cs.IS_OPEN) WITH SYNONYMS ('case backlog') COMMENT = 'Cases not yet closed',
    cs.open_cases_over_30_days AS COUNT_IF(cs.IS_OPEN_OVER_30_DAYS) COMMENT = 'Cases open more than 30 days',
    cs.avg_case_age_days AS AVG(cs.AGE_DAYS) COMMENT = 'Average case age in days',
    cs.total_exposure_usd AS SUM(cs.EXPOSURE_USD) COMMENT = 'Transfer value under investigation in US dollars',
    cs.total_case_net_loss_usd AS SUM(cs.NET_LOSS_USD) COMMENT = 'Net loss linked to cases in US dollars',
    cs.sar_required_case_count AS COUNT_IF(cs.SAR_REQUIRED) COMMENT = 'Cases where a SAR is required')
  COMMENT = 'Alert and case backlog, aging, queues and dispositions';

CREATE OR REPLACE SEMANTIC VIEW RIA_DISPUTES_SV
  TABLES (da AS ANALYTICS.DISPUTE_ACTIVITY PRIMARY KEY (ITEM_ID) COMMENT = 'Chargebacks, ACH returns, refunds and Reg E disputes in one row-per-item view')
  DIMENSIONS (
    da.item_type AS ITEM_TYPE WITH SYNONYMS ('dispute type','type of item') COMMENT = 'Chargeback, ACH Return, Refund or Reg E Dispute',
    da.item_id AS ITEM_ID COMMENT = 'Item identifier',
    da.corridor_name AS CORRIDOR_NAME COMMENT = 'Corridor name',
    da.funding_type AS FUNDING_TYPE COMMENT = 'Funding type of the underlying transfer',
    da.channel AS CHANNEL COMMENT = 'Send channel of the underlying transfer',
    da.reason AS REASON WITH SYNONYMS ('reason','return reason','error type') COMMENT = 'Chargeback reason, ACH return reason, refund reason or Reg E error type',
    da.reason_code AS REASON_CODE WITH SYNONYMS ('return code','NACHA code') COMMENT = 'Card network reason code or NACHA return code such as R01, R10',
    da.item_status AS STATUS COMMENT = 'Open, Represented, Won, Lost, Returned, Refunded, Pending, Investigating or Resolved',
    da.event_date AS EVENT_DATE COMMENT = 'Date the item was received or opened',
    da.event_month AS EVENT_MONTH WITH SYNONYMS ('month') COMMENT = 'Month the item was received or opened',
    da.is_unauthorized AS IS_UNAUTHORIZED COMMENT = 'TRUE for fraud chargebacks, unauthorized ACH returns, fraud refunds and unauthorized error notices',
    da.within_timeline AS WITHIN_TIMELINE COMMENT = 'Reg E: refund within 3 business days or dispute resolved within 90 days',
    da.dispute_outcome AS OUTCOME COMMENT = 'Reg E dispute outcome')
  METRICS (
    da.item_count AS COUNT(ITEM_ID) COMMENT = 'Number of items',
    da.total_amount_usd AS SUM(AMOUNT_USD) COMMENT = 'Total amount in US dollars',
    da.avg_amount_usd AS AVG(AMOUNT_USD) COMMENT = 'Average amount in US dollars',
    da.avg_days_elapsed AS AVG(DAYS_ELAPSED) COMMENT = 'Average days from transfer to chargeback, to refund, or to dispute resolution',
    da.unauthorized_count AS COUNT_IF(IS_UNAUTHORIZED) COMMENT = 'Items flagged as unauthorized',
    da.late_count AS COUNT_IF(WITHIN_TIMELINE = FALSE) COMMENT = 'Items that missed the Reg E timeline',
    da.on_time_rate_pct AS 100 * DIV0(COUNT_IF(WITHIN_TIMELINE), COUNT_IF(WITHIN_TIMELINE IS NOT NULL)) COMMENT = 'Percent of timed items within the Reg E timeline',
    da.open_item_count AS COUNT_IF(STATUS IN ('Open', 'Investigating', 'Pending')) COMMENT = 'Items still open or pending')
  COMMENT = 'Chargebacks, ACH returns, refunds and Reg E disputes';

CREATE OR REPLACE SEMANTIC VIEW RIA_AGENT_NETWORK_SV
  TABLES (an AS ANALYTICS.AGENT_NETWORK PRIMARY KEY (AGENT_ID) COMMENT = 'One row per agent or branch location with 90-day activity and collusion score')
  DIMENSIONS (
    an.agent_id AS AGENT_ID COMMENT = 'Agent location identifier',
    an.agent_name AS AGENT_NAME WITH SYNONYMS ('location','branch','store') COMMENT = 'Agent location name',
    an.agent_type AS AGENT_TYPE COMMENT = 'Ria Company Store, Retail Partner, Bank Partner or Payout Partner',
    an.agent_role AS ROLE COMMENT = 'Send, Payout or Both',
    an.country AS COUNTRY COMMENT = 'Country of the location',
    an.city AS CITY COMMENT = 'City of the location',
    an.region AS REGION COMMENT = 'Region of the location',
    an.agent_status AS STATUS COMMENT = 'Active, Under Review, Suspended or Terminated',
    an.training_completed AS TRAINING_COMPLETED COMMENT = 'TRUE when annual AML training is complete',
    an.confirmed_collusion AS CONFIRMED_COLLUSION COMMENT = 'Investigation outcome: TRUE when collusion was confirmed',
    an.collusion_risk_tier AS COLLUSION_RISK_TIER COMMENT = 'Model-predicted collusion risk tier: Low, Medium or High')
  METRICS (
    an.agent_count AS COUNT(AGENT_ID) COMMENT = 'Number of agent locations',
    an.avg_audit_rating AS AVG(AUDIT_RATING) COMMENT = 'Average compliance audit rating 1 to 5',
    an.avg_days_since_audit AS AVG(DAYS_SINCE_AUDIT) COMMENT = 'Average days since last audit',
    an.send_transfers_90d AS SUM(SEND_TRANSFERS_90D) COMMENT = 'Transfers sent in the last 90 days',
    an.send_volume_90d_usd AS SUM(SEND_VOLUME_90D_USD) COMMENT = 'Send volume in the last 90 days in US dollars',
    an.payout_volume_90d_usd AS SUM(PAYOUT_VOLUME_90D_USD) COMMENT = 'Payout volume in the last 90 days in US dollars',
    an.avg_near_threshold_share_pct AS AVG(NEAR_THRESHOLD_SHARE_PCT) COMMENT = 'Average percent of sends just under $3,000 or $10,000',
    an.avg_cancellation_rate_pct AS AVG(CANCELLATION_RATE_PCT) COMMENT = 'Average cancellation rate percent',
    an.avg_collusion_probability AS AVG(COLLUSION_PROBABILITY) COMMENT = 'Average model collusion probability',
    an.max_collusion_probability AS MAX(COLLUSION_PROBABILITY) COMMENT = 'Highest model collusion probability',
    an.high_collusion_risk_count AS COUNT_IF(COLLUSION_RISK_TIER = 'High') COMMENT = 'Locations in the High collusion risk tier',
    an.training_overdue_count AS COUNT_IF(NOT TRAINING_COMPLETED) COMMENT = 'Locations with overdue AML training',
    an.confirmed_collusion_count AS COUNT_IF(CONFIRMED_COLLUSION) COMMENT = 'Locations with confirmed collusion')
  COMMENT = 'Agent and branch network performance, audits and collusion risk';

CREATE OR REPLACE SEMANTIC VIEW RIA_SCREENING_SV
  TABLES (sd AS ANALYTICS.SCREENING_DETAIL PRIMARY KEY (SCREENING_ID) COMMENT = 'One row per sanctions screening hit')
  DIMENSIONS (
    sd.screening_id AS SCREENING_ID COMMENT = 'Screening hit identifier',
    sd.list_source AS LIST_SOURCE WITH SYNONYMS ('sanctions list','list') COMMENT = 'SDN (OFAC), EU, UN or UK HMT',
    sd.screened_party AS SCREENED_PARTY COMMENT = 'Sender or Beneficiary',
    sd.hit_status AS STATUS COMMENT = 'Open or Closed',
    sd.disposition AS DISPOSITION COMMENT = 'Pending, Cleared, Escalated or Blocked',
    sd.matched_entry_country AS MATCHED_ENTRY_COUNTRY COMMENT = 'Country of the matched list entry',
    sd.corridor_name AS CORRIDOR_NAME COMMENT = 'Corridor of the screened transfer',
    sd.payout_country AS PAYOUT_COUNTRY COMMENT = 'Payout country of the screened transfer',
    sd.customer_risk_rating AS CUSTOMER_RISK_RATING COMMENT = 'KYC risk rating of the sender',
    sd.screened_date AS SCREENED_DATE COMMENT = 'Date of the hit',
    sd.screened_month AS SCREENED_MONTH WITH SYNONYMS ('month') COMMENT = 'Month of the hit',
    sd.is_open AS IS_OPEN COMMENT = 'TRUE when the hit is still open',
    sd.is_true_match AS IS_TRUE_MATCH COMMENT = 'Investigation outcome: TRUE true match, FALSE false positive, blank while open',
    sd.triage_tier AS TRIAGE_TIER COMMENT = 'Model-predicted true-match tier: Low, Medium or High')
  METRICS (
    sd.hit_count AS COUNT(SCREENING_ID) WITH SYNONYMS ('screening hits','hits') COMMENT = 'Number of screening hits',
    sd.open_hit_count AS COUNT_IF(IS_OPEN) COMMENT = 'Open hits',
    sd.closed_hit_count AS COUNT_IF(NOT IS_OPEN) COMMENT = 'Closed hits',
    sd.true_match_count AS COUNT_IF(IS_TRUE_MATCH) COMMENT = 'Closed hits confirmed as true matches',
    sd.false_positive_count AS COUNT_IF(IS_TRUE_MATCH = FALSE) COMMENT = 'Closed hits cleared as false positives',
    sd.false_positive_rate_pct AS 100 * DIV0(COUNT_IF(IS_TRUE_MATCH = FALSE), COUNT_IF(IS_TRUE_MATCH IS NOT NULL)) WITH SYNONYMS ('false positive rate') COMMENT = 'False positives as a percent of closed hits',
    sd.blocked_count AS COUNT_IF(DISPOSITION = 'Blocked') COMMENT = 'Hits that led to a block',
    sd.avg_match_score AS AVG(MATCH_SCORE) COMMENT = 'Average screening engine match score',
    sd.avg_hours_to_disposition AS AVG(HOURS_TO_DISPOSITION) COMMENT = 'Average hours from hit to disposition',
    sd.total_amount_usd AS SUM(SEND_AMOUNT_USD) COMMENT = 'Value of screened transfers in US dollars',
    sd.avg_true_match_probability AS AVG(TRUE_MATCH_PROBABILITY) COMMENT = 'Average model true-match probability')
  COMMENT = 'OFAC and global sanctions screening volume and outcomes';

CREATE OR REPLACE SEMANTIC VIEW RIA_COMPLIANCE_SV
  TABLES (cf AS ANALYTICS.COMPLIANCE_FILINGS PRIMARY KEY (FILING_TYPE, FILING_ID) COMMENT = 'SAR and CTR filings with deadline tracking')
  DIMENSIONS (
    cf.filing_type AS FILING_TYPE COMMENT = 'SAR or CTR',
    cf.filing_id AS FILING_ID COMMENT = 'Filing identifier',
    cf.activity_type AS ACTIVITY_TYPE COMMENT = 'SAR suspicious activity type, or Cash over $10,000 for CTRs',
    cf.filing_status AS FILING_STATUS COMMENT = 'Draft, In Review, Filed, Filed Late or Pending',
    cf.trigger_date AS TRIGGER_DATE COMMENT = 'SAR detection date or CTR business date',
    cf.trigger_month AS TRIGGER_MONTH WITH SYNONYMS ('month') COMMENT = 'Month of the trigger date',
    cf.due_date AS DUE_DATE COMMENT = 'Filing deadline',
    cf.is_filed AS IS_FILED COMMENT = 'TRUE when filed',
    cf.is_overdue AS IS_OVERDUE COMMENT = 'TRUE when unfiled and past the deadline',
    cf.is_at_risk AS IS_AT_RISK COMMENT = 'TRUE when unfiled and due within the next 10 days',
    cf.filed_on_time AS FILED_ON_TIME COMMENT = 'TRUE when filed on or before the deadline')
  METRICS (
    cf.filing_count AS COUNT(FILING_ID) COMMENT = 'Number of filings',
    cf.filed_count AS COUNT_IF(IS_FILED) COMMENT = 'Filed filings',
    cf.unfiled_count AS COUNT_IF(NOT IS_FILED) COMMENT = 'Filings not yet filed',
    cf.overdue_filing_count AS COUNT_IF(IS_OVERDUE) WITH SYNONYMS ('overdue filings','missed deadlines') COMMENT = 'Unfiled filings past the deadline',
    cf.at_risk_filing_count AS COUNT_IF(IS_AT_RISK) WITH SYNONYMS ('filings at risk','at risk of missing deadline') COMMENT = 'Unfiled filings due within 10 days',
    cf.late_filing_count AS COUNT_IF(FILING_STATUS = 'Filed Late') COMMENT = 'Filings filed after the deadline',
    cf.on_time_rate_pct AS 100 * DIV0(COUNT_IF(FILED_ON_TIME), COUNT_IF(IS_FILED)) COMMENT = 'Percent of filed filings that met the deadline',
    cf.avg_days_to_file AS AVG(DAYS_TO_FILE) COMMENT = 'Average days from trigger to filing',
    cf.max_days_to_file AS MAX(DAYS_TO_FILE) COMMENT = 'Longest days from trigger to filing',
    cf.min_days_until_due AS MIN(DAYS_UNTIL_DUE) COMMENT = 'Fewest days until the next unfiled deadline',
    cf.total_amount_usd AS SUM(AMOUNT_USD) COMMENT = 'Reported amount in US dollars')
  COMMENT = 'BSA SAR and CTR filings, days to file and deadline risk';

CREATE OR REPLACE SEMANTIC VIEW RIA_KYC_SV
  TABLES (kd AS ANALYTICS.KYC_DETAIL PRIMARY KEY (CUSTOMER_ID) COMMENT = 'One row per customer with KYC, CDD and EDD status and synthetic-identity model score')
  DIMENSIONS (
    kd.customer_id AS CUSTOMER_ID COMMENT = 'Customer identifier',
    kd.risk_rating AS RISK_RATING WITH SYNONYMS ('customer risk rating','CDD risk') COMMENT = 'Low, Medium or High',
    kd.kyc_tier AS KYC_TIER COMMENT = 'Tier 1, Tier 2 or Tier 3',
    kd.pep_flag AS PEP_FLAG WITH SYNONYMS ('politically exposed') COMMENT = 'TRUE for politically exposed persons',
    kd.edd_required AS EDD_REQUIRED COMMENT = 'TRUE when enhanced due diligence is required',
    kd.edd_completed AS EDD_COMPLETED COMMENT = 'TRUE when enhanced due diligence is complete',
    kd.edd_outstanding AS EDD_OUTSTANDING COMMENT = 'TRUE when EDD is required but not complete',
    kd.id_verification_status AS ID_VERIFICATION_STATUS COMMENT = 'Verified, Pending, Failed or Expired',
    kd.id_document_type AS ID_DOCUMENT_TYPE COMMENT = 'Passport, National ID, Drivers License or Consular ID',
    kd.review_overdue AS REVIEW_OVERDUE COMMENT = 'TRUE when the periodic CDD review is overdue',
    kd.source_of_funds AS SOURCE_OF_FUNDS COMMENT = 'Declared source of funds',
    kd.occupation AS OCCUPATION COMMENT = 'Declared occupation',
    kd.segment AS SEGMENT COMMENT = 'Customer segment',
    kd.country_of_residence AS COUNTRY_OF_RESIDENCE COMMENT = 'Country of residence',
    kd.signup_channel AS SIGNUP_CHANNEL COMMENT = 'Mobile App, Web or Retail Agent',
    kd.signup_month AS SIGNUP_MONTH WITH SYNONYMS ('registration month','sign-up month') COMMENT = 'Month the customer registered',
    kd.age_band AS AGE_BAND COMMENT = 'Age band',
    kd.customer_status AS CUSTOMER_STATUS COMMENT = 'Active, Dormant, Closed or Blocked',
    kd.phone_is_voip AS PHONE_IS_VOIP COMMENT = 'TRUE when the phone is a VoIP number',
    kd.synthetic_id_risk_tier AS SYNTHETIC_ID_RISK_TIER COMMENT = 'Model-predicted synthetic identity risk tier: Low, Medium or High')
  METRICS (
    kd.customer_count AS COUNT(CUSTOMER_ID) COMMENT = 'Number of customers',
    kd.pep_count AS COUNT_IF(PEP_FLAG) COMMENT = 'Politically exposed customers',
    kd.edd_outstanding_count AS COUNT_IF(EDD_OUTSTANDING) COMMENT = 'Customers with EDD required but not complete',
    kd.reviews_overdue_count AS COUNT_IF(REVIEW_OVERDUE) COMMENT = 'Customers with an overdue CDD review',
    kd.avg_days_review_overdue AS AVG(DAYS_REVIEW_OVERDUE) COMMENT = 'Average days a review is overdue',
    kd.failed_verification_count AS COUNT_IF(ID_VERIFICATION_STATUS = 'Failed') COMMENT = 'Customers whose ID verification failed',
    kd.high_risk_customer_count AS COUNT_IF(RISK_RATING = 'High') COMMENT = 'Customers rated High risk',
    kd.avg_id_attempts AS AVG(ID_VERIFICATION_ATTEMPTS) COMMENT = 'Average ID verification attempts',
    kd.avg_expected_monthly_usd AS AVG(EXPECTED_MONTHLY_USD) COMMENT = 'Average declared monthly volume in US dollars',
    kd.avg_synthetic_id_probability AS AVG(SYNTHETIC_ID_PROBABILITY) COMMENT = 'Average model synthetic-identity probability',
    kd.high_synthetic_id_risk_count AS COUNT_IF(SYNTHETIC_ID_RISK_TIER = 'High') COMMENT = 'Customers in the High synthetic identity risk tier')
  COMMENT = 'KYC, CDD and EDD status, customer risk ratings and PEP counts';

CREATE OR REPLACE SEMANTIC VIEW RIA_DIGITAL_SV
  TABLES (ds AS ANALYTICS.DIGITAL_SESSION_DETAIL PRIMARY KEY (SESSION_ID) COMMENT = 'One row per app or web login session with device details and account-takeover model score')
  DIMENSIONS (
    ds.session_id AS SESSION_ID COMMENT = 'Session identifier',
    ds.channel AS CHANNEL COMMENT = 'Mobile App or Web',
    ds.device_os AS OS COMMENT = 'iOS, Android, Windows or macOS',
    ds.login_method AS LOGIN_METHOD COMMENT = 'Password, Biometric or OTP',
    ds.login_success AS LOGIN_SUCCESS COMMENT = 'TRUE when the login succeeded',
    ds.ip_country AS IP_COUNTRY COMMENT = 'Country the IP geolocates to',
    ds.is_foreign_ip AS IS_FOREIGN_IP COMMENT = 'TRUE when the IP country differs from the customer country',
    ds.is_new_device AS IS_NEW_DEVICE COMMENT = 'TRUE when the device was new for the customer',
    ds.is_vpn AS IS_VPN COMMENT = 'TRUE when the IP is a VPN or proxy',
    ds.is_emulator AS IS_EMULATOR COMMENT = 'TRUE when the device is an emulator',
    ds.is_rooted AS IS_ROOTED COMMENT = 'TRUE when the device is rooted or jailbroken',
    ds.password_reset_24h AS PASSWORD_RESET_24H COMMENT = 'TRUE when the password was reset in the prior 24 hours',
    ds.beneficiary_added AS BENEFICIARY_ADDED COMMENT = 'TRUE when a beneficiary was added in the session',
    ds.profile_changed AS PROFILE_CHANGED COMMENT = 'TRUE when email, phone or password changed in the session',
    ds.login_date AS LOGIN_DATE COMMENT = 'Date of the login',
    ds.login_month AS LOGIN_MONTH WITH SYNONYMS ('month') COMMENT = 'Month of the login',
    ds.confirmed_account_takeover AS CONFIRMED_ACCOUNT_TAKEOVER COMMENT = 'Investigation outcome: TRUE when confirmed account takeover',
    ds.ato_risk_tier AS ATO_RISK_TIER COMMENT = 'Model-predicted account takeover risk tier: Low, Medium or High (scored for the last 180 days)')
  METRICS (
    ds.session_count AS COUNT(SESSION_ID) WITH SYNONYMS ('logins') COMMENT = 'Number of sessions',
    ds.distinct_customers AS COUNT(DISTINCT CUSTOMER_ID) COMMENT = 'Distinct customers',
    ds.failed_login_count AS COUNT_IF(NOT LOGIN_SUCCESS) COMMENT = 'Failed logins',
    ds.avg_failed_attempts AS AVG(FAILED_ATTEMPTS) COMMENT = 'Average failed attempts before a session',
    ds.new_device_session_count AS COUNT_IF(IS_NEW_DEVICE) COMMENT = 'Sessions on a new device',
    ds.vpn_session_count AS COUNT_IF(IS_VPN) COMMENT = 'Sessions through a VPN or proxy',
    ds.avg_geo_distance_km AS AVG(GEO_DISTANCE_KM) COMMENT = 'Average distance from the usual login location in kilometers',
    ds.avg_session_duration_sec AS AVG(SESSION_DURATION_SEC) COMMENT = 'Average session length in seconds',
    ds.confirmed_takeover_count AS COUNT_IF(CONFIRMED_ACCOUNT_TAKEOVER) COMMENT = 'Sessions confirmed as account takeover',
    ds.high_ato_risk_session_count AS COUNT_IF(ATO_RISK_TIER = 'High') COMMENT = 'Scored sessions in the High takeover risk tier',
    ds.avg_ato_probability AS AVG(ATO_PROBABILITY) COMMENT = 'Average model account-takeover probability on scored sessions')
  COMMENT = 'Digital sessions, devices, logins and account takeover';

CREATE OR REPLACE SEMANTIC VIEW RIA_CUSTOMER_360_SV
  TABLES (c3 AS ANALYTICS.CUSTOMER_360 PRIMARY KEY (CUSTOMER_ID) COMMENT = 'One row per customer: value, frequency, complaints, NPS, recency, KYC and model scores')
  DIMENSIONS (
    c3.customer_id AS CUSTOMER_ID COMMENT = 'Customer identifier',
    c3.segment AS SEGMENT COMMENT = 'Regular Remitter, Occasional Sender, High Value, Small Business or New',
    c3.loyalty_tier AS LOYALTY_TIER COMMENT = 'None, Silver, Gold or Platinum',
    c3.country_of_residence AS COUNTRY_OF_RESIDENCE COMMENT = 'Country of residence',
    c3.signup_channel AS SIGNUP_CHANNEL COMMENT = 'Mobile App, Web or Retail Agent',
    c3.preferred_corridor_name AS PREFERRED_CORRIDOR_NAME WITH SYNONYMS ('home corridor') COMMENT = 'Corridor the customer usually sends to',
    c3.kyc_risk_rating AS KYC_RISK_RATING COMMENT = 'Low, Medium or High',
    c3.customer_status AS CUSTOMER_STATUS COMMENT = 'Active, Dormant, Closed or Blocked',
    c3.age_band AS AGE_BAND COMMENT = 'Age band',
    c3.recency_status AS RECENCY_STATUS WITH SYNONYMS ('churn status','churn') COMMENT = 'Rule-based churn indicator, not a model: Active (sent in 45 days), At Risk (46-90 days), Lapsed (over 90 days) or No transfers',
    c3.latest_nps_category AS LATEST_NPS_CATEGORY COMMENT = 'Promoter, Passive or Detractor from the latest survey',
    c3.composite_model_risk_tier AS COMPOSITE_MODEL_RISK_TIER COMMENT = 'Highest tier across the customer-level fraud models: Low, Medium, High or Not scored',
    c3.pep_flag AS PEP_FLAG COMMENT = 'TRUE for politically exposed persons')
  METRICS (
    c3.customer_count AS COUNT(CUSTOMER_ID) COMMENT = 'Number of customers',
    c3.total_lifetime_value_usd AS SUM(LIFETIME_VALUE_USD) WITH SYNONYMS ('customer lifetime value','LTV') COMMENT = 'Fees plus FX margin on paid transfers in US dollars',
    c3.avg_lifetime_value_usd AS AVG(LIFETIME_VALUE_USD) COMMENT = 'Average lifetime value per customer in US dollars',
    c3.total_volume_90d_usd AS SUM(VOLUME_90D_USD) COMMENT = 'Send volume in the last 90 days in US dollars',
    c3.avg_transfers_per_month AS AVG(TRANSFERS_PER_MONTH) WITH SYNONYMS ('transfer frequency') COMMENT = 'Average transfers per month since signup',
    c3.avg_days_since_last_transfer AS AVG(DAYS_SINCE_LAST_TRANSFER) COMMENT = 'Average days since the last transfer',
    c3.total_complaints AS SUM(COMPLAINTS_TOTAL) COMMENT = 'Complaints filed',
    c3.open_complaints AS SUM(OPEN_COMPLAINTS) COMMENT = 'Complaints still open',
    c3.avg_nps AS AVG(LATEST_NPS) COMMENT = 'Average latest NPS score 0 to 10',
    c3.detractor_count AS COUNT_IF(LATEST_NPS_CATEGORY = 'Detractor') COMMENT = 'Customers whose latest NPS is a detractor',
    c3.at_risk_customer_count AS COUNT_IF(RECENCY_STATUS = 'At Risk') COMMENT = 'Customers not seen for 46 to 90 days',
    c3.lapsed_customer_count AS COUNT_IF(RECENCY_STATUS = 'Lapsed') COMMENT = 'Customers not seen for over 90 days',
    c3.lapsed_rate_pct AS 100 * DIV0(COUNT_IF(RECENCY_STATUS = 'Lapsed'), COUNT(CUSTOMER_ID)) COMMENT = 'Lapsed customers as a percent of customers',
    c3.customers_with_open_cases AS COUNT_IF(OPEN_CASES > 0) COMMENT = 'Customers with an open fraud or AML case',
    c3.high_model_risk_customer_count AS COUNT_IF(COMPOSITE_MODEL_RISK_TIER = 'High') COMMENT = 'Customers in the High model risk tier')
  COMMENT = 'Customer value, transfer frequency, complaints, NPS and recency';
