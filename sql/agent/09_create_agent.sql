/*=============================================================================
  Ria Financial Intelligence Agent
  Step 9: Cortex Agent

  Execution Order: 9 of 9
  Description: Creates RIA_FINANCIAL_AGENT, which answers fraud, AML, KYC and
               Customer 360 questions using 10 Cortex Analyst semantic views,
               6 Cortex Search services, the 10 model wrapper functions plus
               the overview, model registry and customer brief functions.
=============================================================================*/

USE WAREHOUSE RIA_FINANCIAL_WH;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;

CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT
  COMMENT = 'Ria Financial Intelligence Agent: cross-border transfer fraud, AML and sanctions compliance, KYC, 10 fraud models and Customer 360. All data is synthetic'
  PROFILE = '{"display_name": "Ria Financial Assistant", "color": "blue"}'
  FROM SPECIFICATION
  $$
{
  "models": {
    "orchestration": "auto"
  },
  "instructions": {
    "system": "You are the Ria Financial Assistant, an expert on cross-border money transfer fraud and the compliance work around it: senders and beneficiaries, transfers by corridor, channel and payout method, the agent and branch network, digital app sessions and devices, card and bank funding sources, fraud alerts and cases, chargebacks, refunds and ACH returns, AML and sanctions screening, SAR and CTR filings, KYC and customer due diligence, and the Customer 360 (lifetime value, transfer frequency, complaints, NPS, recency). You help fraud analysts, AML investigators, sanctions analysts, agent oversight teams, compliance officers and executives. Give data-driven answers with specific numbers. Currency is US dollars; transfers also carry send and payout currencies. All data is synthetic. Every fraud score, risk tier and probability comes from a machine learning model trained on synthetic data: say so whenever you quote one, and never present model metrics as production performance. Customer names are masked; refer to customers by customer ID. Never reveal or guess names, SSNs, full card numbers or full account numbers.",
    "orchestration": "FRAUD SNAPSHOT: Use GetFraudOverview for a broad snapshot of alerts, cases, losses, chargebacks, screening and filing deadlines. OPERATIONAL ANALYTICS: Use TransferAnalytics for transfer volume, revenue and fraud rate by corridor, channel, payout method and funding type. Use CaseAnalytics for alert and case backlog, aging, queues, analysts and dispositions. Use FraudLossAnalytics for fraud losses, recoveries, write-offs and loss rate by corridor and quarter. Use DisputeAnalytics for chargebacks, refunds, ACH returns and Reg E disputes. Use AgentNetworkAnalytics for agent and branch performance, audits and training. Use ScreeningAnalytics for sanctions screening volume, outcomes and false-positive rates. Use ComplianceAnalytics for SAR and CTR filings, days to file and deadline risk. Use KycAnalytics for KYC status, customer risk ratings, PEP and EDD. Use DigitalChannelAnalytics for app and web sessions, devices and logins. MODEL QUESTIONS: Use GetTransactionFraudScore for the transfers most likely to be fraud (pass days_back, and transfer_id_filter as an empty string unless the user names a transfer). Use GetAccountTakeoverRisk for customers with the highest account-takeover risk (days_back). Use GetSyntheticIdentityRisk for new sign-ups likely to be synthetic identities (days_back, 30 for this month). Use GetMuleBeneficiaries for likely money mules and how much they received (top_n). Use GetStructuringAlerts for senders structuring transfers just under thresholds (weeks_back). Use GetAgentCollusionRisk for agent locations with the highest collusion risk (top_n). Use GetChargebackRisk for predicted chargeback exposure on card-funded transfers (days_back, 30 for this month). Use GetScamVictimAlerts for recent transfers where the sender may be a scam victim (days_back). Use GetFraudRings for the largest suspected fraud rings and the accounts each links (top_n). Use GetScreeningTriage for open sanctions hits most likely to be true matches (top_n). Use GetModelRegistry for the model inventory, versions, owners and validation status, including models past their validation date. CUSTOMER BRIEFS: For one customer call GetCustomer360 with the customer ID, then add CaseNotesSearch or ComplaintSearch only if the user asks why. If GetCustomer360 returns nothing, say the customer ID was not found. Use Customer360Analytics to compare customers or segments on lifetime value, frequency, complaints, NPS and recency. DOCUMENTS: Use FraudTypologySearch for typology guides, red flags, playbooks and regulator advisories. Use CaseNotesSearch for investigator notes. Use SarNarrativeSearch for SAR narratives. Use PolicySearch for compliance and fraud policies and procedures. Use ComplaintSearch for customer complaints. Use CustomerFeedbackSearch for NPS comments. CHARTS: For a chart, graph or plot, query the matching Analyst tool, then call data_to_chart with the requested type: bar, line, pie, scatter or area.",
    "response": "Be concise and specific. Use tables for lists of transfers, customers, beneficiaries, agents or cases. Say when a number comes from a machine learning model and that it was trained on synthetic data. Quote the model risk tier together with the probability. End every fraud brief and every customer brief with one or two recommended next actions. A customer brief must include the KYC risk rating, the latest model scores and tiers, open alerts and open cases, and the 90-day transfer volume. SAR information is confidential: mention SAR status only when the user asks about compliance filings. Never present synthetic-data model metrics such as AUC as production performance.",
    "sample_questions": [
      {
        "question": "Which transfers in the last 7 days have the highest fraud probability?"
      },
      {
        "question": "Which customer accounts show the highest account-takeover risk this week?"
      },
      {
        "question": "How many new sign-ups this month are likely synthetic identities?"
      },
      {
        "question": "Which beneficiaries are most likely to be money mules, and how much have they received?"
      },
      {
        "question": "Which senders look like they are structuring transfers just under $10,000?"
      },
      {
        "question": "Which agent locations have the highest collusion risk score?"
      },
      {
        "question": "What is the predicted chargeback exposure on card-funded transfers this month?"
      },
      {
        "question": "Which recent transfers look like the sender is a scam victim?"
      },
      {
        "question": "What are the largest suspected fraud rings and how many accounts does each link?"
      },
      {
        "question": "Which open sanctions screening hits are most likely true matches and should be worked first?"
      },
      {
        "question": "What is our fraud loss rate by corridor this quarter?"
      },
      {
        "question": "How many alerts are open past 30 days, and which queue owns them?"
      },
      {
        "question": "Are any SAR filings at risk of missing the 30-day deadline?"
      },
      {
        "question": "Give me a Customer 360 brief for customer C000123."
      },
      {
        "question": "What is the sanctions screening false-positive rate by list source?"
      },
      {
        "question": "Which models in the registry are past their validation date?"
      }
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "TransferAnalytics",
        "description": "Query transfer volume, revenue, fees, fraud rate and travel-rule gaps by corridor, send or payout country, channel, payout method, funding type, purpose, amount band and time."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "CaseAnalytics",
        "description": "Query fraud and AML alerts and cases: open backlog, items open over 30 days, aging buckets, owning queue, analyst, severity, dispositions, false-positive rate and exposure."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "FraudLossAnalytics",
        "description": "Query fraud losses, recoveries, write-offs, net loss and loss rate by corridor, region, month and quarter."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "DisputeAnalytics",
        "description": "Query card chargebacks, ACH returns with NACHA codes, refunds and Reg E disputes: counts, amounts, reasons, status, days elapsed and on-time rates."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "AgentNetworkAnalytics",
        "description": "Query agent and branch locations: type, country, status, audit rating, AML training, 90-day send and payout volume, near-threshold share, cancellation rate and collusion risk tier."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "ScreeningAnalytics",
        "description": "Query sanctions screening hits by list source (SDN, EU, UN, UK HMT), status, disposition, true-match and false-positive rates, and time to disposition."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "ComplianceAnalytics",
        "description": "Query SAR and CTR filings: status, days to file, filings at risk of missing the deadline, overdue filings and on-time rate."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "KycAnalytics",
        "description": "Query KYC, CDD and EDD status: customer risk ratings, PEP counts, outstanding EDD, overdue reviews, ID verification status and synthetic identity risk tiers."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "DigitalChannelAnalytics",
        "description": "Query app and web login sessions: channel, device operating system, new devices, VPN use, failed logins, foreign IPs, emulator and rooted devices, and account takeover risk tiers."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "Customer360Analytics",
        "description": "Query one row per customer: lifetime value, transfer frequency, 90-day volume, complaints, NPS, rule-based recency status and composite model risk tier."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "FraudTypologySearch",
        "description": "Search fraud and AML typology guides, red flags, investigation playbooks and regulator advisories."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "CaseNotesSearch",
        "description": "Search investigator case notes by case type, priority and status."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "SarNarrativeSearch",
        "description": "Search synthetic SAR narratives by suspicious activity type and filing status."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "PolicySearch",
        "description": "Search compliance and fraud policies and procedures by policy area and regulation."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "ComplaintSearch",
        "description": "Search customer complaints, including CFPB escalations, by category and channel."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "CustomerFeedbackSearch",
        "description": "Search NPS survey comments by promoter, passive or detractor."
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetFraudOverview",
        "description": "Returns a fraud and compliance snapshot: 30-day volume and confirmed fraud rate, 90-day net loss and recoveries, open alerts and cases, open alerts over 30 days by queue, chargebacks, open sanctions hits, SAR deadlines and models past validation.",
        "input_schema": {
          "type": "object",
          "properties": {}
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetTransactionFraudScore",
        "description": "Model 1. Returns the 15 transfers with the highest model fraud probability in the window, plus tier counts. Probabilities are model predictions trained on synthetic data.",
        "input_schema": {
          "type": "object",
          "properties": {
            "days_back": {
              "type": "number",
              "description": "Look-back window in days, for example 7"
            },
            "transfer_id_filter": {
              "type": "string",
              "description": "A specific transfer ID such as T000123456, or an empty string to rank all transfers in the window"
            }
          },
          "required": [
            "days_back",
            "transfer_id_filter"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetAccountTakeoverRisk",
        "description": "Model 2. Returns the 15 customers with the highest account-takeover probability across login sessions in the window, with device and login signals.",
        "input_schema": {
          "type": "object",
          "properties": {
            "days_back": {
              "type": "number",
              "description": "Look-back window in days, for example 7 for this week"
            }
          },
          "required": [
            "days_back"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetSyntheticIdentityRisk",
        "description": "Model 3. Returns how many new sign-ups in the window are likely synthetic identities (High and Medium tier counts, expected count) and the 10 highest-risk customers.",
        "input_schema": {
          "type": "object",
          "properties": {
            "days_back": {
              "type": "number",
              "description": "Sign-up window in days, for example 30 for this month"
            }
          },
          "required": [
            "days_back"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetMuleBeneficiaries",
        "description": "Model 4. Returns the beneficiaries most likely to be money mules with transfers received, distinct senders and total received in US dollars.",
        "input_schema": {
          "type": "object",
          "properties": {
            "top_n": {
              "type": "number",
              "description": "How many beneficiaries to return, 1 to 25, for example 10"
            }
          },
          "required": [
            "top_n"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetStructuringAlerts",
        "description": "Model 5. Returns customer-weeks most likely to be structuring (sends just under the $3,000 Travel Rule or $10,000 CTR thresholds) with weekly totals and counts.",
        "input_schema": {
          "type": "object",
          "properties": {
            "weeks_back": {
              "type": "number",
              "description": "Look-back window in weeks, for example 4"
            }
          },
          "required": [
            "weeks_back"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetAgentCollusionRisk",
        "description": "Model 6. Returns agent locations with the highest collusion probability with audit rating, training status, cancellation rate and share of sends just under thresholds.",
        "input_schema": {
          "type": "object",
          "properties": {
            "top_n": {
              "type": "number",
              "description": "How many locations to return, 1 to 25, for example 10"
            }
          },
          "required": [
            "top_n"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetChargebackRisk",
        "description": "Model 7. Returns predicted chargeback exposure in US dollars on card-funded transfers in the window, with tier counts, exposure by funding type and the 10 transfers with the largest expected chargeback.",
        "input_schema": {
          "type": "object",
          "properties": {
            "days_back": {
              "type": "number",
              "description": "Look-back window in days, for example 30 for this month"
            }
          },
          "required": [
            "days_back"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetScamVictimAlerts",
        "description": "Model 8. Returns recent transfers where the sender looks like a scam victim (APP, romance or elder fraud) with amount, corridor, purpose and sender age band.",
        "input_schema": {
          "type": "object",
          "properties": {
            "days_back": {
              "type": "number",
              "description": "Look-back window in days, for example 14"
            }
          },
          "required": [
            "days_back"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetFraudRings",
        "description": "Model 9. Returns the largest suspected fraud rings: clusters of accounts sharing a phone number, with accounts linked, anomaly score, volume and open cases.",
        "input_schema": {
          "type": "object",
          "properties": {
            "top_n": {
              "type": "number",
              "description": "How many clusters to return, 1 to 20, for example 10"
            }
          },
          "required": [
            "top_n"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetScreeningTriage",
        "description": "Model 10. Returns open sanctions screening hits ordered by true-match probability so likely true matches are worked first. Never auto-clear a hit from a model score.",
        "input_schema": {
          "type": "object",
          "properties": {
            "top_n": {
              "type": "number",
              "description": "How many hits to return, 1 to 25, for example 10"
            }
          },
          "required": [
            "top_n"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetModelRegistry",
        "description": "Returns the SR 11-7 model inventory for all 10 models: version, owner, training date, ROC and PR AUC on synthetic data, validation status and dates, and which models are past their validation date.",
        "input_schema": {
          "type": "object",
          "properties": {}
        }
      }
    },
    {
      "tool_spec": {
        "type": "generic",
        "name": "GetCustomer360",
        "description": "Returns the Customer 360 brief for one customer ID: KYC risk rating, lifetime value, 90-day volume, open alerts and cases, complaints, NPS, rule-based recency, and the latest model scores and tiers.",
        "input_schema": {
          "type": "object",
          "properties": {
            "customer_id_filter": {
              "type": "string",
              "description": "Customer ID such as C000123"
            }
          },
          "required": [
            "customer_id_filter"
          ]
        }
      }
    },
    {
      "tool_spec": {
        "type": "data_to_chart",
        "name": "data_to_chart",
        "description": "Creates bar, line, pie, scatter and area charts from query results."
      }
    }
  ],
  "tool_resources": {
    "TransferAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_TRANSFERS_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "CaseAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_CASES_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "FraudLossAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_FRAUD_LOSS_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "DisputeAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_DISPUTES_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "AgentNetworkAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_AGENT_NETWORK_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "ScreeningAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_SCREENING_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "ComplianceAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_COMPLIANCE_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "KycAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_KYC_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "DigitalChannelAnalytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_DIGITAL_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "Customer360Analytics": {
      "semantic_view": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_CUSTOMER_360_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "FraudTypologySearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_TYPOLOGY_SEARCH",
      "max_results": 8,
      "columns": [
        "TITLE",
        "CONTENT",
        "TYPOLOGY",
        "CATEGORY"
      ]
    },
    "CaseNotesSearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_CASE_NOTES_SEARCH",
      "max_results": 8,
      "columns": [
        "NOTE_TEXT",
        "CASE_ID",
        "CASE_TYPE",
        "PRIORITY",
        "CASE_STATUS"
      ]
    },
    "SarNarrativeSearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_SAR_NARRATIVE_SEARCH",
      "max_results": 8,
      "columns": [
        "NARRATIVE",
        "SAR_ID",
        "SUSPICIOUS_ACTIVITY_TYPE",
        "FILING_STATUS"
      ]
    },
    "PolicySearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_POLICY_SEARCH",
      "max_results": 8,
      "columns": [
        "TITLE",
        "CONTENT",
        "POLICY_AREA",
        "REGULATION"
      ]
    },
    "ComplaintSearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_COMPLAINT_SEARCH",
      "max_results": 8,
      "columns": [
        "COMPLAINT_TEXT",
        "CATEGORY",
        "CHANNEL",
        "STATUS",
        "CFPB_ESCALATED"
      ]
    },
    "CustomerFeedbackSearch": {
      "search_service": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.RIA_FEEDBACK_SEARCH",
      "max_results": 8,
      "columns": [
        "COMMENT_TEXT",
        "NPS_CATEGORY",
        "NPS_SCORE"
      ]
    },
    "GetFraudOverview": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_FRAUD_OVERVIEW",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetTransactionFraudScore": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_TRANSACTION_FRAUD_SCORE",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetAccountTakeoverRisk": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_ACCOUNT_TAKEOVER_RISK",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetSyntheticIdentityRisk": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_SYNTHETIC_IDENTITY_RISK",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetMuleBeneficiaries": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_MULE_BENEFICIARIES",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetStructuringAlerts": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_STRUCTURING_ALERTS",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetAgentCollusionRisk": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_AGENT_COLLUSION_RISK",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetChargebackRisk": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_CHARGEBACK_RISK",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetScamVictimAlerts": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_SCAM_VICTIM_ALERTS",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetFraudRings": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_FRAUD_RINGS",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetScreeningTriage": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_SCREENING_TRIAGE",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetModelRegistry": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_MODEL_REGISTRY",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    },
    "GetCustomer360": {
      "type": "function",
      "identifier": "RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.AGENT_GET_CUSTOMER_360",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIA_FINANCIAL_WH"
      }
    }
  }
}
  $$;

GRANT USAGE ON AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT TO ROLE PUBLIC;
