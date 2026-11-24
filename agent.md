<table width="100%"><tr>
<td align="left"><img src="ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Ria Financial agent

`SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT`

Display name: Ria Financial Assistant. Color: blue. Orchestration model: `auto`.

## What it is for

Cross-border money transfer and payments fraud, and the compliance work around it: senders and beneficiaries, transfers (corridors, channels, payout methods), agent and branch network, digital sessions and devices, cards and bank funding sources, fraud alerts and cases, chargebacks and refunds, AML and sanctions screening, SAR filings, KYC and CDD, and Customer 360.

Currency is US dollars, with send and payout currencies kept for each transfer. Every fraud score, risk tier and probability comes from a model prediction trained on synthetic data. The agent is instructed to say so when it quotes a number from a model.

## The 10 models and their tools

| # | Model | Algorithm | Target | ROC AUC | PR AUC | Positives | Agent tool |
|---|---|---|---|---|---|---|---|
| 1 | Transaction fraud score | XGBoost | IS_FRAUD per transfer | 0.961 | 0.758 | 0.69% | `GetTransactionFraudScore` |
| 2 | Account takeover (ATO) | XGBoost | ATO event per login session | 0.996 | 0.796 | 0.18% | `GetAccountTakeoverRisk` |
| 3 | Synthetic identity detection | XGBoost | Synthetic-ID flag per new customer | 0.993 | 0.816 | 1.46% | `GetSyntheticIdentityRisk` |
| 4 | Money mule / beneficiary risk | XGBoost | Mule flag per beneficiary | 0.997 | 0.751 | 1.14% | `GetMuleBeneficiaries` |
| 5 | Structuring / AML pattern | XGBoost | Structuring flag per customer-week | 0.990 | 0.889 | 9.57% | `GetStructuringAlerts` |
| 6 | Agent/branch collusion | XGBoost | Collusion flag per agent location | 0.980 | 0.833 | 5.25% | `GetAgentCollusionRisk` |
| 7 | Card-funded / CNP fraud and chargeback | XGBoost | Chargeback within 90 days per card-funded transfer | 0.774 | 0.160 | 0.53% | `GetChargebackRisk` |
| 8 | Scam victim (APP / elder fraud) | XGBoost | Confirmed scam-victim flag per transfer | 0.986 | 0.308 | 0.08% | `GetScamVictimAlerts` |
| 9 | Fraud ring / network anomaly | Isolation forest (sklearn Pipeline) | Anomaly score per customer and phone cluster | 0.979 | 0.196 | 0.69% | `GetFraudRings` |
| 10 | Sanctions screening false-positive triage | XGBoost | True match vs false positive per screening hit | 0.908 | 0.520 | 4.36% | `GetScreeningTriage` |

## How it routes

Defined in `sql/agent/09_create_agent.sql`.

| Question shape | Tool |
|---|---|
| Fraud snapshot (alerts, losses, cases) | `GetFraudOverview` |
| Transfer volume by corridor, channel, payout method | `TransferAnalytics` |
| Alert and case backlog, aging, dispositions | `CaseAnalytics` |
| Fraud losses, recoveries, write-offs | `FraudLossAnalytics` |
| Chargebacks, refunds, ACH returns, Reg E disputes | `DisputeAnalytics` |
| Agent and branch network performance | `AgentNetworkAnalytics` |
| Sanctions screening volume and outcomes | `ScreeningAnalytics` |
| SAR and CTR filings, days to file | `ComplianceAnalytics` |
| KYC status, customer risk ratings, PEP and EDD | `KycAnalytics` |
| Digital sessions, devices, logins | `DigitalChannelAnalytics` |
| The 10 model questions | The model's tool (see table above) |
| Model inventory, versions, validation status | `GetModelRegistry` |
| A named customer's brief | `GetCustomer360`, then a search tool if the user asks why |
| Customer value, frequency, complaints, NPS, recency | `Customer360Analytics` |
| Typology docs, case notes, SAR narratives, policies, complaints, NPS comments | The matching `*Search` tool |

A fraud or customer brief ends with one or two next actions. It includes the KYC risk rating, the latest model scores, open alerts or cases and the 90-day transfer volume.

## Sample questions in the spec

| # | Question | Tool | Model |
|---|---|---|---|
| 1 | Which transfers in the last 7 days have the highest fraud probability? | `GetTransactionFraudScore` | Transaction fraud |
| 2 | Which customer accounts show the highest account-takeover risk this week? | `GetAccountTakeoverRisk` | Account takeover |
| 3 | How many new sign-ups this month are likely synthetic identities? | `GetSyntheticIdentityRisk` | Synthetic identity |
| 4 | Which beneficiaries are most likely to be money mules, and how much have they received? | `GetMuleBeneficiaries` | Money mule |
| 5 | Which senders look like they are structuring transfers just under $10,000? | `GetStructuringAlerts` | Structuring |
| 6 | Which agent locations have the highest collusion risk score? | `GetAgentCollusionRisk` | Agent collusion |
| 7 | What is the predicted chargeback exposure on card-funded transfers this month? | `GetChargebackRisk` | Chargeback risk |
| 8 | Which recent transfers look like the sender is a scam victim? | `GetScamVictimAlerts` | Scam victim |
| 9 | What are the largest suspected fraud rings and how many accounts does each link? | `GetFraudRings` | Fraud ring |
| 10 | Which open sanctions screening hits are most likely true matches and should be worked first? | `GetScreeningTriage` | Screening triage |
| 11 | What is our fraud loss rate by corridor this quarter? | `FraudLossAnalytics` | - |
| 12 | How many alerts are open past 30 days, and which queue owns them? | `CaseAnalytics` | - |
| 13 | Are any SAR filings at risk of missing the 30-day deadline? | `ComplianceAnalytics` | - |
| 14 | Give me a Customer 360 brief for customer C000123. | `GetCustomer360` | - |
| 15 | What is the sanctions screening false-positive rate by list source? | `ScreeningAnalytics` | - |
| 16 | Which models in the registry are past their validation date? | `GetModelRegistry` | - |

## Verification

`scripts/test_agent.py` calls `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` against all 16 sample questions. Last run: 16/16. Each model question must return populated scores.

## Known failure

Rerunning `sql/data/03_generate_synthetic_data.sql` changes every ID, so the score tables no longer match the data. `scripts/deploy.py` reruns `notebooks/07_ml_models.py` automatically. If you run the SQL by hand, run `python3 notebooks/07_ml_models.py` afterwards.
