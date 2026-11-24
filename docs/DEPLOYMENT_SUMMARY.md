<table width="100%"><tr>
<td align="left"><img src="../ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="../Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Deployment summary

Account `AWS161` | Database `RIA_FINANCIAL_INTELLIGENCE` | Warehouse `RIA_FINANCIAL_WH` | Built 2026-11-23

![Deployment flow](images/deployment_flow.svg?v=2)

## Deployed

| Step | Result |
|---|---|
| 1 | Database, 3 schemas, MEDIUM warehouse |
| 2 | 27 RAW tables |
| 3 | 2,699,095 synthetic rows: 1,219,785 transfers, 40,000 customers, 916,542 sessions, 20,602 alerts, 4,499 cases |
| 4 | 26 ANALYTICS views and 10 score tables |
| 5 | 10 semantic views |
| 6 | 6 Cortex Search services |
| 7 | 10 models trained, logged to the Model Registry, scored, and inventoried in `ML.MODEL_REGISTRY` |
| 8 | 13 agent functions |
| 9 | `RIA_FINANCIAL_AGENT` with 30 tools |

## Model registry

| # | Registry model | Owner | Status | Last validated | Next due | Past due | High / Medium tier cutoff |
|---|---|---|---|---|---|---|---|
| 1 | `RIA_TRANSACTION_FRAUD` | Fraud Data Science | Validated | 2026-07-26 | 2027-07-26 | no | 0.027 / 0.006 |
| 2 | `RIA_ACCOUNT_TAKEOVER` | Digital Fraud Analytics | Validated | 2026-05-07 | 2027-05-07 | no | 0.041 / 0.01 |
| 3 | `RIA_SYNTHETIC_IDENTITY` | Identity Risk Analytics | Conditionally Validated | 2025-10-09 | 2026-10-09 | YES | 0.006 / 0.001 |
| 4 | `RIA_MULE_BENEFICIARY` | AML Analytics | Validated | 2026-08-25 | 2027-08-25 | no | 0.007 / 0.0 |
| 5 | `RIA_STRUCTURING` | AML Analytics | Validated | 2025-11-08 | 2026-11-08 | YES | 0.002 / 0.0 |
| 6 | `RIA_AGENT_COLLUSION` | Agent Oversight Analytics | Pending Validation | never | 2026-10-24 | YES | 0.038 / 0.001 |
| 7 | `RIA_CHARGEBACK_RISK` | Card Risk Analytics | Validated | 2026-09-24 | 2027-09-24 | no | 0.401 / 0.042 |
| 8 | `RIA_SCAM_VICTIM` | Fraud Data Science | Pending Validation | never | 2026-12-23 | no | 0.266 / 0.04 |
| 9 | `RIA_FRAUD_RING_ANOMALY` | Financial Crimes Analytics | Validated | 2026-03-18 | 2027-03-18 | no | 0.99 / 0.95 |
| 10 | `RIA_SCREENING_TRIAGE` | Sanctions Analytics | Conditionally Validated | 2025-10-24 | 2026-10-24 | YES | 0.125 / 0.024 |

4 of 10 models are past their validation date. Validation dates are demonstration governance values.

## Verified outcomes

- Confirmed fraud rate 0.69% of transfers (8,390 transfers); send volume $576.8M from 2025-06-01 to 2026-11-22.
- FATF Travel Rule: 7,247 transfers of $3,000 or more, 0 missing originator or beneficiary data.
- Open alerts 2,591, of which 859 are open more than 30 days.
- SAR filings: 19 unfiled and due within 10 days, 3 overdue.
- Sanctions screening false-positive rate 95.6% of closed hits.
- Customers in the High composite model risk tier: 3,226. Fraud-ring clusters of 3 or more accounts: 39.
- Registry check: for every model the warehouse prediction matches the local prediction on a probe set.

## Agent test: 16/16

Run at 2026-11-23T18:27:44 with `python3 scripts/test_agent.py --connection AWS161`. A question passes when the expected tool is used, its result is non-empty (for the 10 model questions the counts and ranked lists must be populated), and the agent writes an answer.

| # | Result | Question | Tools used |
|---|---|---|---|
| 1 | PASS | Which transfers in the last 7 days have the highest fraud probability? | GetTransactionFraudScore |
| 2 | PASS | Which customer accounts show the highest account-takeover risk this week? | GetAccountTakeoverRisk |
| 3 | PASS | How many new sign-ups this month are likely synthetic identities? | GetSyntheticIdentityRisk |
| 4 | PASS | Which beneficiaries are most likely to be money mules, and how much have they received? | GetMuleBeneficiaries |
| 5 | PASS | Which senders look like they are structuring transfers just under $10,000? | GetStructuringAlerts |
| 6 | PASS | Which agent locations have the highest collusion risk score? | GetAgentCollusionRisk |
| 7 | PASS | What is the predicted chargeback exposure on card-funded transfers this month? | GetChargebackRisk |
| 8 | PASS | Which recent transfers look like the sender is a scam victim? | GetScamVictimAlerts |
| 9 | PASS | What are the largest suspected fraud rings and how many accounts does each link? | GetFraudRings |
| 10 | PASS | Which open sanctions screening hits are most likely true matches and should be worked first? | GetScreeningTriage |
| 11 | PASS | What is our fraud loss rate by corridor this quarter? | FraudLossAnalytics, system_execute_sql |
| 12 | PASS | How many alerts are open past 30 days, and which queue owns them? | CaseAnalytics, system_execute_sql |
| 13 | PASS | Are any SAR filings at risk of missing the 30-day deadline? | ComplianceAnalytics, system_execute_sql |
| 14 | PASS | Give me a Customer 360 brief for customer C000123. | GetCustomer360 |
| 15 | PASS | What is the sanctions screening false-positive rate by list source? | ScreeningAnalytics, system_execute_sql |
| 16 | PASS | Which models in the registry are past their validation date? | GetModelRegistry |

## Caveat

Model metrics come from synthetic data in which the generator creates both the features and the labels. They are not production performance. 5 models (#2, #3, #4, #5, #8) score above 0.985 ROC AUC. Each was checked for label leakage: no input column is derived from the label, and the best single feature on its own is far below the model score, so the high values reflect several independent synthetic signals stacking, not a leak. The notebook prints that evidence and `ML.MODEL_REGISTRY.METRIC_NOTE` records it. Several rounds of generator changes added label noise, decoys and overlap to bring the metrics down.

## Not done

- Committed and pushed to https://github.com/sfc-gh-sdickson/ria-financial (private) after this build.
- No Streamlit dashboard (not requested).
- No database grants beyond `USAGE` on the agent for `PUBLIC`. Other roles need grants before they can run the tools.
