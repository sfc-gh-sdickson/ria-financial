import json

DB = "RIA_FINANCIAL_INTELLIGENCE"
WH = "RIA_FINANCIAL_WH"
AGENT = "SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT"

SYSTEM = (
    "You are the Ria Financial Assistant, an expert on cross-border money transfer fraud and the compliance work around it: senders and beneficiaries, "
    "transfers by corridor, channel and payout method, the agent and branch network, digital app sessions and devices, card and bank funding sources, "
    "fraud alerts and cases, chargebacks, refunds and ACH returns, AML and sanctions screening, SAR and CTR filings, KYC and customer due diligence, "
    "and the Customer 360 (lifetime value, transfer frequency, complaints, NPS, recency). You help fraud analysts, AML investigators, sanctions analysts, "
    "agent oversight teams, compliance officers and executives. Give data-driven answers with specific numbers. Currency is US dollars; transfers also carry "
    "send and payout currencies. All data is synthetic. Every fraud score, risk tier and probability comes from a machine learning model trained on "
    "synthetic data: say so whenever you quote one, and never present model metrics as production performance. Customer names are masked; refer to customers "
    "by customer ID. Never reveal or guess names, SSNs, full card numbers or full account numbers."
)

ORCH = (
    "FRAUD SNAPSHOT: Use GetFraudOverview for a broad snapshot of alerts, cases, losses, chargebacks, screening and filing deadlines. "
    "OPERATIONAL ANALYTICS: Use TransferAnalytics for transfer volume, revenue and fraud rate by corridor, channel, payout method and funding type. "
    "Use CaseAnalytics for alert and case backlog, aging, queues, analysts and dispositions. Use FraudLossAnalytics for fraud losses, recoveries, write-offs and loss rate by corridor and quarter. "
    "Use DisputeAnalytics for chargebacks, refunds, ACH returns and Reg E disputes. Use AgentNetworkAnalytics for agent and branch performance, audits and training. "
    "Use ScreeningAnalytics for sanctions screening volume, outcomes and false-positive rates. Use ComplianceAnalytics for SAR and CTR filings, days to file and deadline risk. "
    "Use KycAnalytics for KYC status, customer risk ratings, PEP and EDD. Use DigitalChannelAnalytics for app and web sessions, devices and logins. "
    "MODEL QUESTIONS: Use GetTransactionFraudScore for the transfers most likely to be fraud (pass days_back, and transfer_id_filter as an empty string unless the user names a transfer). "
    "Use GetAccountTakeoverRisk for customers with the highest account-takeover risk (days_back). Use GetSyntheticIdentityRisk for new sign-ups likely to be synthetic identities (days_back, 30 for this month). "
    "Use GetMuleBeneficiaries for likely money mules and how much they received (top_n). Use GetStructuringAlerts for senders structuring transfers just under thresholds (weeks_back). "
    "Use GetAgentCollusionRisk for agent locations with the highest collusion risk (top_n). Use GetChargebackRisk for predicted chargeback exposure on card-funded transfers (days_back, 30 for this month). "
    "Use GetScamVictimAlerts for recent transfers where the sender may be a scam victim (days_back). Use GetFraudRings for the largest suspected fraud rings and the accounts each links (top_n). "
    "Use GetScreeningTriage for open sanctions hits most likely to be true matches (top_n). Use GetModelRegistry for the model inventory, versions, owners and validation status, including models past their validation date. "
    "CUSTOMER BRIEFS: For one customer call GetCustomer360 with the customer ID, then add CaseNotesSearch or ComplaintSearch only if the user asks why. If GetCustomer360 returns nothing, say the customer ID was not found. "
    "Use Customer360Analytics to compare customers or segments on lifetime value, frequency, complaints, NPS and recency. "
    "DOCUMENTS: Use FraudTypologySearch for typology guides, red flags, playbooks and regulator advisories. Use CaseNotesSearch for investigator notes. Use SarNarrativeSearch for SAR narratives. "
    "Use PolicySearch for compliance and fraud policies and procedures. Use ComplaintSearch for customer complaints. Use CustomerFeedbackSearch for NPS comments. "
    "CHARTS: For a chart, graph or plot, query the matching Analyst tool, then call data_to_chart with the requested type: bar, line, pie, scatter or area."
)

RESPONSE = (
    "Be concise and specific. Use tables for lists of transfers, customers, beneficiaries, agents or cases. Say when a number comes from a machine learning model and that it was trained on synthetic data. "
    "Quote the model risk tier together with the probability. End every fraud brief and every customer brief with one or two recommended next actions. "
    "A customer brief must include the KYC risk rating, the latest model scores and tiers, open alerts and open cases, and the 90-day transfer volume. "
    "SAR information is confidential: mention SAR status only when the user asks about compliance filings. Never present synthetic-data model metrics such as AUC as production performance."
)

SAMPLES = [
    "Which transfers in the last 7 days have the highest fraud probability?",
    "Which customer accounts show the highest account-takeover risk this week?",
    "How many new sign-ups this month are likely synthetic identities?",
    "Which beneficiaries are most likely to be money mules, and how much have they received?",
    "Which senders look like they are structuring transfers just under $10,000?",
    "Which agent locations have the highest collusion risk score?",
    "What is the predicted chargeback exposure on card-funded transfers this month?",
    "Which recent transfers look like the sender is a scam victim?",
    "What are the largest suspected fraud rings and how many accounts does each link?",
    "Which open sanctions screening hits are most likely true matches and should be worked first?",
    "What is our fraud loss rate by corridor this quarter?",
    "How many alerts are open past 30 days, and which queue owns them?",
    "Are any SAR filings at risk of missing the 30-day deadline?",
    "Give me a Customer 360 brief for customer C000123.",
    "What is the sanctions screening false-positive rate by list source?",
    "Which models in the registry are past their validation date?",
]

ANALYST = [
    ("TransferAnalytics", "RIA_TRANSFERS_SV", "Query transfer volume, revenue, fees, fraud rate and travel-rule gaps by corridor, send or payout country, channel, payout method, funding type, purpose, amount band and time."),
    ("CaseAnalytics", "RIA_CASES_SV", "Query fraud and AML alerts and cases: open backlog, items open over 30 days, aging buckets, owning queue, analyst, severity, dispositions, false-positive rate and exposure."),
    ("FraudLossAnalytics", "RIA_FRAUD_LOSS_SV", "Query fraud losses, recoveries, write-offs, net loss and loss rate by corridor, region, month and quarter."),
    ("DisputeAnalytics", "RIA_DISPUTES_SV", "Query card chargebacks, ACH returns with NACHA codes, refunds and Reg E disputes: counts, amounts, reasons, status, days elapsed and on-time rates."),
    ("AgentNetworkAnalytics", "RIA_AGENT_NETWORK_SV", "Query agent and branch locations: type, country, status, audit rating, AML training, 90-day send and payout volume, near-threshold share, cancellation rate and collusion risk tier."),
    ("ScreeningAnalytics", "RIA_SCREENING_SV", "Query sanctions screening hits by list source (SDN, EU, UN, UK HMT), status, disposition, true-match and false-positive rates, and time to disposition."),
    ("ComplianceAnalytics", "RIA_COMPLIANCE_SV", "Query SAR and CTR filings: status, days to file, filings at risk of missing the deadline, overdue filings and on-time rate."),
    ("KycAnalytics", "RIA_KYC_SV", "Query KYC, CDD and EDD status: customer risk ratings, PEP counts, outstanding EDD, overdue reviews, ID verification status and synthetic identity risk tiers."),
    ("DigitalChannelAnalytics", "RIA_DIGITAL_SV", "Query app and web login sessions: channel, device operating system, new devices, VPN use, failed logins, foreign IPs, emulator and rooted devices, and account takeover risk tiers."),
    ("Customer360Analytics", "RIA_CUSTOMER_360_SV", "Query one row per customer: lifetime value, transfer frequency, 90-day volume, complaints, NPS, rule-based recency status and composite model risk tier."),
]

SEARCH = [
    ("FraudTypologySearch", "RIA_TYPOLOGY_SEARCH", "Search fraud and AML typology guides, red flags, investigation playbooks and regulator advisories.", ["TITLE", "CONTENT", "TYPOLOGY", "CATEGORY"]),
    ("CaseNotesSearch", "RIA_CASE_NOTES_SEARCH", "Search investigator case notes by case type, priority and status.", ["NOTE_TEXT", "CASE_ID", "CASE_TYPE", "PRIORITY", "CASE_STATUS"]),
    ("SarNarrativeSearch", "RIA_SAR_NARRATIVE_SEARCH", "Search synthetic SAR narratives by suspicious activity type and filing status.", ["NARRATIVE", "SAR_ID", "SUSPICIOUS_ACTIVITY_TYPE", "FILING_STATUS"]),
    ("PolicySearch", "RIA_POLICY_SEARCH", "Search compliance and fraud policies and procedures by policy area and regulation.", ["TITLE", "CONTENT", "POLICY_AREA", "REGULATION"]),
    ("ComplaintSearch", "RIA_COMPLAINT_SEARCH", "Search customer complaints, including CFPB escalations, by category and channel.", ["COMPLAINT_TEXT", "CATEGORY", "CHANNEL", "STATUS", "CFPB_ESCALATED"]),
    ("CustomerFeedbackSearch", "RIA_FEEDBACK_SEARCH", "Search NPS survey comments by promoter, passive or detractor.", ["COMMENT_TEXT", "NPS_CATEGORY", "NPS_SCORE"]),
]


def num(desc):
    return {"type": "number", "description": desc}


FUNCS = [
    ("GetFraudOverview", "AGENT_GET_FRAUD_OVERVIEW", "Returns a fraud and compliance snapshot: 30-day volume and confirmed fraud rate, 90-day net loss and recoveries, open alerts and cases, open alerts over 30 days by queue, chargebacks, open sanctions hits, SAR deadlines and models past validation.", None),
    ("GetTransactionFraudScore", "AGENT_GET_TRANSACTION_FRAUD_SCORE", "Model 1. Returns the 15 transfers with the highest model fraud probability in the window, plus tier counts. Probabilities are model predictions trained on synthetic data.",
     {"days_back": num("Look-back window in days, for example 7"), "transfer_id_filter": {"type": "string", "description": "A specific transfer ID such as T000123456, or an empty string to rank all transfers in the window"}}),
    ("GetAccountTakeoverRisk", "AGENT_GET_ACCOUNT_TAKEOVER_RISK", "Model 2. Returns the 15 customers with the highest account-takeover probability across login sessions in the window, with device and login signals.",
     {"days_back": num("Look-back window in days, for example 7 for this week")}),
    ("GetSyntheticIdentityRisk", "AGENT_GET_SYNTHETIC_IDENTITY_RISK", "Model 3. Returns how many new sign-ups in the window are likely synthetic identities (High and Medium tier counts, expected count) and the 10 highest-risk customers.",
     {"days_back": num("Sign-up window in days, for example 30 for this month")}),
    ("GetMuleBeneficiaries", "AGENT_GET_MULE_BENEFICIARIES", "Model 4. Returns the beneficiaries most likely to be money mules with transfers received, distinct senders and total received in US dollars.",
     {"top_n": num("How many beneficiaries to return, 1 to 25, for example 10")}),
    ("GetStructuringAlerts", "AGENT_GET_STRUCTURING_ALERTS", "Model 5. Returns customer-weeks most likely to be structuring (sends just under the $3,000 Travel Rule or $10,000 CTR thresholds) with weekly totals and counts.",
     {"weeks_back": num("Look-back window in weeks, for example 4")}),
    ("GetAgentCollusionRisk", "AGENT_GET_AGENT_COLLUSION_RISK", "Model 6. Returns agent locations with the highest collusion probability with audit rating, training status, cancellation rate and share of sends just under thresholds.",
     {"top_n": num("How many locations to return, 1 to 25, for example 10")}),
    ("GetChargebackRisk", "AGENT_GET_CHARGEBACK_RISK", "Model 7. Returns predicted chargeback exposure in US dollars on card-funded transfers in the window, with tier counts, exposure by funding type and the 10 transfers with the largest expected chargeback.",
     {"days_back": num("Look-back window in days, for example 30 for this month")}),
    ("GetScamVictimAlerts", "AGENT_GET_SCAM_VICTIM_ALERTS", "Model 8. Returns recent transfers where the sender looks like a scam victim (APP, romance or elder fraud) with amount, corridor, purpose and sender age band.",
     {"days_back": num("Look-back window in days, for example 14")}),
    ("GetFraudRings", "AGENT_GET_FRAUD_RINGS", "Model 9. Returns the largest suspected fraud rings: clusters of accounts sharing a phone number, with accounts linked, anomaly score, volume and open cases.",
     {"top_n": num("How many clusters to return, 1 to 20, for example 10")}),
    ("GetScreeningTriage", "AGENT_GET_SCREENING_TRIAGE", "Model 10. Returns open sanctions screening hits ordered by true-match probability so likely true matches are worked first. Never auto-clear a hit from a model score.",
     {"top_n": num("How many hits to return, 1 to 25, for example 10")}),
    ("GetModelRegistry", "AGENT_GET_MODEL_REGISTRY", "Returns the SR 11-7 model inventory for all 10 models: version, owner, training date, ROC and PR AUC on synthetic data, validation status and dates, and which models are past their validation date.", None),
    ("GetCustomer360", "AGENT_GET_CUSTOMER_360", "Returns the Customer 360 brief for one customer ID: KYC risk rating, lifetime value, 90-day volume, open alerts and cases, complaints, NPS, rule-based recency, and the latest model scores and tiers.",
     {"customer_id_filter": {"type": "string", "description": "Customer ID such as C000123"}}),
]

tools, resources = [], {}
for name, sv, desc in ANALYST:
    tools.append({"tool_spec": {"type": "cortex_analyst_text_to_sql", "name": name, "description": desc}})
    resources[name] = {"semantic_view": f"{DB}.ANALYTICS.{sv}", "execution_environment": {"type": "warehouse", "warehouse": WH}}
for name, svc, desc, cols in SEARCH:
    tools.append({"tool_spec": {"type": "cortex_search", "name": name, "description": desc}})
    resources[name] = {"search_service": f"{DB}.ANALYTICS.{svc}", "max_results": 8, "columns": cols}
for name, fn, desc, props in FUNCS:
    spec = {"type": "generic", "name": name, "description": desc}
    if props:
        spec["input_schema"] = {"type": "object", "properties": props, "required": list(props)}
    else:
        spec["input_schema"] = {"type": "object", "properties": {}}
    tools.append({"tool_spec": spec})
    resources[name] = {"type": "function", "identifier": f"{DB}.ANALYTICS.{fn}", "execution_environment": {"type": "warehouse", "warehouse": WH}}
tools.append({"tool_spec": {"type": "data_to_chart", "name": "data_to_chart", "description": "Creates bar, line, pie, scatter and area charts from query results."}})

spec = {
    "models": {"orchestration": "auto"},
    "instructions": {"system": SYSTEM, "orchestration": ORCH, "response": RESPONSE, "sample_questions": [{"question": q} for q in SAMPLES]},
    "tools": tools,
    "tool_resources": resources,
}
js = json.dumps(spec, indent=2)
assert "$$" not in js
sql = f"""/*=============================================================================
  Ria Financial Intelligence Agent
  Step 9: Cortex Agent

  Execution Order: 9 of 9
  Description: Creates RIA_FINANCIAL_AGENT, which answers fraud, AML, KYC and
               Customer 360 questions using 10 Cortex Analyst semantic views,
               6 Cortex Search services, the 10 model wrapper functions plus
               the overview, model registry and customer brief functions.
=============================================================================*/

USE WAREHOUSE {WH};

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;

CREATE OR REPLACE AGENT {AGENT}
  COMMENT = 'Ria Financial Intelligence Agent: cross-border transfer fraud, AML and sanctions compliance, KYC, 10 fraud models and Customer 360. All data is synthetic'
  PROFILE = '{{"display_name": "Ria Financial Assistant", "color": "blue"}}'
  FROM SPECIFICATION
  $$
{js}
  $$;

GRANT USAGE ON AGENT {AGENT} TO ROLE PUBLIC;
"""
open("/Users/sdickson/Ria Financial/sql/agent/09_create_agent.sql", "w").write(sql)
print("tools:", len(tools), "analyst", len(ANALYST), "search", len(SEARCH), "functions", len(FUNCS), "samples", len(SAMPLES))
print("model tools:", [f[0] for f in FUNCS if f[0].startswith("Get") and f[0] not in ("GetFraudOverview", "GetModelRegistry", "GetCustomer360")])
