# Ria Financial agent: build prompt

`SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT`

Display name: Ria Financial Assistant. Color: blue. Orchestration model: `auto`.

Database `RIA_FINANCIAL_INTELLIGENCE`. Warehouse `RIA_FINANCIAL_WH`. Schemas `RAW`, `ANALYTICS`, `ML`.

Follow the Rocket Lab build as the working template: same file layout, naming patterns, build order, and verification. Do not deviate from it except where this file says to.

## What it is for

Cross-border money transfer and payments fraud, and the compliance work around it. Coverage: senders and beneficiaries, transfers (corridors, channels, payout methods), agent and branch network, digital app sessions and devices, cards and bank funding sources, fraud alerts and cases, chargebacks and refunds, AML/sanctions screening, SAR filings, KYC and customer due diligence, plus Customer 360 (lifetime value, transfer frequency, complaints, NPS, churn).

Currency is US dollars, with send and payout currencies kept for each transfer. Every fraud score, risk tier and probability comes from a model prediction trained on synthetic data. The agent must say so when it quotes a number from a model.

## Financial Services standards to reflect

Use these to design the data model, the alert and case fields, and the agent's answer rules. All data is synthetic. Do not generate real PII.

| Standard | What it means for the build |
|---|---|
| BSA/AML (FinCEN) | CTR threshold $10,000. Structuring detection below $10,000. SAR filing deadline 30 days from detection. `SAR_FILINGS` table with filing status and days to file |
| OFAC / global sanctions | Name screening results with match score, list source (SDN, EU, UN, UK HMT) and disposition (cleared, escalated, blocked) |
| FATF Travel Rule | Originator and beneficiary fields on every transfer of $3,000 or more |
| KYC / CDD / EDD | Customer risk rating (low, medium, high), PEP flag, EDD-required flag, ID verification status |
| PCI DSS | No full card numbers. Store a token, BIN and last 4 only |
| GLBA / privacy | Mask PII in views the agent can see. No SSNs or full account numbers |
| Reg E / CFPB remittance rule | Error and dispute tracking, cancellation window, refund timeliness |
| NACHA | ACH return codes (R01, R02, R10, and so on) on bank-funded transfers |
| SR 11-7 / OCC 2011-12 model risk | `ML.MODEL_REGISTRY` with model owner, version, training date, metrics, validation status and intended use, for all 10 models |
| FFIEC | Alert-to-case-to-disposition audit trail, with analyst and timestamps |

## ML models: 10 fraud models

Build all 10. Each model needs a training section in `notebooks/07_ml_models.py`, a row in `ML.MODEL_REGISTRY`, a score table or scored view, a wrapper procedure or function, an agent tool, and at least one sample question in the agent spec. Do not declare the build finished with fewer than 10.

| # | Model | Type | Target | Agent tool | Sample question (minimum one) |
|---|---|---|---|---|---|
| 1 | Transaction fraud score | Classification | `IS_FRAUD` per transfer | `GetTransactionFraudScore` | Which transfers in the last 7 days have the highest fraud probability? |
| 2 | Account takeover (ATO) | Classification | ATO event per login session | `GetAccountTakeoverRisk` | Which customer accounts show the highest account-takeover risk this week? |
| 3 | Synthetic identity detection | Classification | Synthetic-ID flag per new customer | `GetSyntheticIdentityRisk` | How many new sign-ups this month are likely synthetic identities? |
| 4 | Money mule / beneficiary risk | Classification | Mule flag per beneficiary | `GetMuleBeneficiaries` | Which beneficiaries are most likely to be money mules, and how much have they received? |
| 5 | Structuring / AML pattern | Classification | Structuring flag per customer-week | `GetStructuringAlerts` | Which senders look like they are structuring transfers just under $10,000? |
| 6 | Agent/branch collusion | Classification | Collusion flag per agent location | `GetAgentCollusionRisk` | Which agent locations have the highest collusion risk score? |
| 7 | Card-funded / CNP fraud and chargeback | Classification | Chargeback within 90 days | `GetChargebackRisk` | What is the predicted chargeback exposure on card-funded transfers this month? |
| 8 | Scam victim (APP / elder fraud) | Classification | Confirmed scam-victim flag per transfer | `GetScamVictimAlerts` | Which recent transfers look like the sender is a scam victim? |
| 9 | Fraud ring / network anomaly | Unsupervised (isolation forest or clustering on shared device, IP, phone, beneficiary) | Anomaly score per customer cluster | `GetFraudRings` | What are the largest suspected fraud rings and how many accounts does each link? |
| 10 | Sanctions screening false-positive triage | Classification | True match vs false positive per screening hit | `GetScreeningTriage` | Which open sanctions screening hits are most likely true matches and should be worked first? |

Rules for the models:

- Feature column names and data types in each wrapper must match the notebook training data exactly, case included.
- Handle NULLs with `COALESCE` before scoring. Handle empty result sets cleanly.
- Procedure parameter names must match the agent tool `input_schema` property names exactly (for example `TRANSFER_ID`, not `TRANSFER_ID_INPUT`).
- Run each training query on its own and confirm it returns rows before training.
- Label rates must be realistic. Fraud around 0.5–3% of transfers, not 50%. Use class weights or resampling, and report PR AUC as well as ROC AUC.
- Use grouped CV by customer so a customer can't leak across folds.
- Rerunning data generation (step 3) must not leave the score tables empty. Either rerun `python3 notebooks/07_ml_models.py` automatically or document it as a known failure, as Rocket Lab did.

## How it routes

Defined in `sql/agent/09_create_agent.sql`.

| Question shape | Tool |
|---|---|
| Fraud snapshot (alerts, losses, cases) | `GetFraudOverview` |
| Transfer volume by corridor, channel, payout method | `TransferAnalytics` |
| Alert and case backlog, aging, dispositions | `CaseAnalytics` |
| Fraud losses, recoveries, write-offs | `FraudLossAnalytics` |
| Chargebacks, refunds, ACH returns | `DisputeAnalytics` |
| Agent and branch network performance | `AgentNetworkAnalytics` |
| Sanctions screening volume and outcomes | `ScreeningAnalytics` |
| SAR and CTR filings, days to file | `ComplianceAnalytics` |
| KYC status, customer risk ratings, PEP/EDD | `KycAnalytics` |
| Digital sessions, devices, logins | `DigitalChannelAnalytics` |
| The 10 model questions | The model's tool from the ML table above |
| Model inventory, versions, validation status | `GetModelRegistry` |
| A named customer's brief | `GetCustomer360`, then a search tool if the user asks why |
| Customer value, churn, complaints | `Customer360Analytics` |
| Fraud typology docs, case notes, SAR narratives, policies, complaints | The matching `*Search` tool |

A fraud or customer brief must end with one or two next actions. It must include customer risk rating, the latest model scores, open alerts or cases, and 90-day transfer volume.

## Sample questions in the spec

Include the 10 model sample questions above, plus:

- What is our fraud loss rate by corridor this quarter?
- How many alerts are open past 30 days, and which queue owns them?
- Are any SAR filings at risk of missing the 30-day deadline?
- Give me a Customer 360 brief for customer C000123.
- What is the sanctions screening false-positive rate by list source?
- Which models in the registry are past their validation date?

Every sample question must use only metrics and dimensions that the semantic views actually expose. Check each one against the deployed semantic view before adding it.

## Build order

1. `sql/setup/01_database_and_schema.sql`
2. `sql/setup/02_create_tables.sql`: RAW tables. Extract the column list into a reference file before writing any other SQL.
3. `sql/data/03_generate_synthetic_data.sql`
4. `sql/views/04_create_views.sql`, including `CUSTOMER_360` and `FRAUD_360`
5. `sql/views/05_create_semantic_views.sql`: `RIA_*_SV`
6. `sql/search/06_create_cortex_search.sql`: `RIA_*_SEARCH`
7. `notebooks/07_ml_models.py`: all 10 models plus `MODEL_REGISTRY`
8. `sql/ml/08_ml_wrapper_functions.sql`
9. `sql/agent/09_create_agent.sql`
10. `scripts/test_agent.py`, then docs (README, AGENT_SETUP, questions, ARTIFACTS_GUIDE, DEPLOYMENT_SUMMARY, agent.md, BUILD_LOG) and SVG diagrams that pass `scripts/check_svg.py`

## Rules carried over from GENERATION_FAILURES_AND_LESSONS.md

- Snowflake SQL is not generic SQL. Verify every function against the Snowflake reference.
- `UNIFORM(min, max, RANDOM())`: min and max must be constants.
- `SEQ4()` only inside `TABLE(GENERATOR(...))`. Use `ROW_NUMBER()` everywhere else.
- `GENERATOR(ROWCOUNT => n)`: n must be a constant.
- Semantic views: clause order is TABLES → RELATIONSHIPS → FACTS → DIMENSIONS → METRICS. Syntax is `table.semantic_name AS physical_column`, with the semantic name on the left. Every expression must exist in the table DDL. Synonyms must be globally unique.
- Cortex Search: turn on change tracking on source tables, set the `ON` text column, and list `ATTRIBUTES` correctly.
- Status and category fields must show varied distributions. Run `GROUP BY` checks after step 3.
- Use pandas methods on pandas DataFrames and Snowpark methods on Snowpark DataFrames.
- Don't change working code you weren't asked to change.
- Never declare a step complete without running its verification.

## Verification

`scripts/test_agent.py` calls `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` against all sample questions: the 10 model questions plus the 6 general ones. Target is 16/16. Each model question must return scores that aren't empty.

Log every step in `BUILD_LOG.md` using the Rocket Lab table format (Date, Step, Result), with a Verified outcomes section and a Caveat section.

## Caveat

Model metrics come from synthetic data in which the generator creates both the features and the labels. Do not quote them as production performance. Near-perfect AUCs are a sign of label leakage, so investigate them rather than report them.
