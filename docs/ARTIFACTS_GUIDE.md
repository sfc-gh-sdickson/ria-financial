<table width="100%"><tr>
<td align="left"><img src="../ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="../Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Artifacts guide

Every object created in Snowflake and every file in the repository.

## Snowflake objects

| Object | Name |
|---|---|
| Database | `RIA_FINANCIAL_INTELLIGENCE` (schemas RAW, ANALYTICS, ML) |
| Warehouse | `RIA_FINANCIAL_WH` (MEDIUM, auto-suspend 300s) |
| Agent | `SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT` |
| Semantic views (10) | `RIA_AGENT_NETWORK_SV`, `RIA_CASES_SV`, `RIA_COMPLIANCE_SV`, `RIA_CUSTOMER_360_SV`, `RIA_DIGITAL_SV`, `RIA_DISPUTES_SV`, `RIA_FRAUD_LOSS_SV`, `RIA_KYC_SV`, `RIA_SCREENING_SV`, `RIA_TRANSFERS_SV` |
| Cortex Search services (6) | `RIA_CASE_NOTES_SEARCH`, `RIA_COMPLAINT_SEARCH`, `RIA_FEEDBACK_SEARCH`, `RIA_POLICY_SEARCH`, `RIA_SAR_NARRATIVE_SEARCH`, `RIA_TYPOLOGY_SEARCH` |
| Registered models (10) | `RIA_TRANSACTION_FRAUD`, `RIA_ACCOUNT_TAKEOVER`, `RIA_SYNTHETIC_IDENTITY`, `RIA_MULE_BENEFICIARY`, `RIA_STRUCTURING`, `RIA_AGENT_COLLUSION`, `RIA_CHARGEBACK_RISK`, `RIA_SCAM_VICTIM`, `RIA_FRAUD_RING_ANOMALY`, `RIA_SCREENING_TRIAGE` in `RIA_FINANCIAL_INTELLIGENCE.ML` |
| Model inventory | `RIA_FINANCIAL_INTELLIGENCE.ML.MODEL_REGISTRY` |

### RAW tables (27, 2,699,095 rows)

| Table | Rows |
|---|---|
| `ACH_RETURNS` | 1,660 |
| `AGENT_LOCATIONS` | 1,200 |
| `ANALYSTS` | 120 |
| `APP_SESSIONS` | 916,542 |
| `BENEFICIARIES` | 86,146 |
| `CASE_EVENTS` | 89,177 |
| `CASE_NOTES` | 12,322 |
| `CHARGEBACKS` | 3,923 |
| `COMPLAINTS` | 9,582 |
| `CORRIDORS` | 20 |
| `CTR_FILINGS` | 332 |
| `CUSTOMERS` | 40,000 |
| `DEVICES` | 65,660 |
| `DISPUTES` | 7,713 |
| `FRAUD_ALERTS` | 20,602 |
| `FRAUD_CASES` | 4,499 |
| `FRAUD_LOSSES` | 6,312 |
| `FRAUD_TYPOLOGIES` | 34 |
| `FUNDING_SOURCES` | 104,699 |
| `KYC_PROFILES` | 40,000 |
| `NPS_SURVEYS` | 20,933 |
| `POLICY_DOCUMENTS` | 18 |
| `REFUNDS` | 31,027 |
| `SANCTIONS_SCREENING` | 5,992 |
| `SAR_FILINGS` | 1,038 |
| `STRUCTURING_REVIEWS` | 9,759 |
| `TRANSFERS` | 1,219,785 |

### Model score tables (ANALYTICS)

| Table | Rows |
|---|---|
| `AGENT_COLLUSION_SCORES` | 800 |
| `ATO_SESSION_SCORES` | 374,771 |
| `CHARGEBACK_SCORES` | 304,761 |
| `FRAUD_RING_SCORES` | 40,000 |
| `MULE_SCORES` | 86,146 |
| `SCAM_SCORES` | 499,436 |
| `SCREENING_TRIAGE_SCORES` | 5,992 |
| `STRUCTURING_SCORES` | 26,835 |
| `SYNTHETIC_ID_SCORES` | 40,000 |
| `TRANSFER_FRAUD_SCORES` | 499,436 |

### ANALYTICS views (26)

`AGENT_NETWORK`, `ALERT_DETAIL`, `CASE_DETAIL`, `COMPLIANCE_FILINGS`, `CUSTOMER_360`, `CUSTOMER_MODEL_SCORES`, `CUSTOMER_PROFILE`, `DIGITAL_SESSION_DETAIL`, `DISPUTE_ACTIVITY`, `FRAUD_360`, `FRAUD_LOSS_MONTHLY`, `FRAUD_RING_CLUSTERS`, `KYC_DETAIL`, `SCREENING_DETAIL`, `TRANSFER_DETAIL`, `V_AGENT_FEATURES`, `V_ATO_FEATURES`, `V_CHARGEBACK_FEATURES`, `V_MULE_FEATURES`, `V_RING_FEATURES`, `V_SCAM_FEATURES`, `V_SCREENING_FEATURES`, `V_STRUCTURING_FEATURES`, `V_SYNTHETIC_ID_FEATURES`, `V_TRANSFER_BASE`, `V_TRANSFER_FRAUD_FEATURES`

Agent-safe, masked views: `CUSTOMER_PROFILE`, `CUSTOMER_360`, `FRAUD_360`, `KYC_DETAIL`, `TRANSFER_DETAIL`, `FRAUD_LOSS_MONTHLY`, `ALERT_DETAIL`, `CASE_DETAIL`, `DISPUTE_ACTIVITY`, `AGENT_NETWORK`, `SCREENING_DETAIL`, `COMPLIANCE_FILINGS`, `DIGITAL_SESSION_DETAIL`, `CUSTOMER_MODEL_SCORES`, `FRAUD_RING_CLUSTERS`. ML feature views are `V_*_FEATURES` and `V_TRANSFER_BASE`.

## Repository files

| File | Purpose |
|---|---|
| `README.md`, `BUILD_LOG.md` | Overview and the dated build log |
| `agent.md` | The agent description and routing table |
| `agent (1).md` | The original build prompt (unchanged) |
| `docs/AGENT_SETUP.md`, `docs/questions.md`, `docs/DEPLOYMENT_SUMMARY.md` | Setup, questions and deployment results |
| `docs/RAW_COLUMNS.md` | RAW column reference extracted after step 2 |
| `docs/images/*.svg` | Five diagrams, built by `scripts/build_svgs.py` and checked by `scripts/check_svg.py` |
| `sql/**` | Steps 1 to 9 |
| `notebooks/07_ml_models.py`, `.ipynb`, `environment.yml` | Model training |
| `scripts/deploy.py` | Runs the steps; reruns step 7 after step 3 |
| `scripts/test_agent.py` | 16-question agent test |
| `scripts/build_agent_sql.py` | Generates `sql/agent/09_create_agent.sql` as valid JSON |
| `scripts/build_svgs.py`, `check_svg.py`, `build_notebook.py` | Diagrams and notebook tooling |
| `ria_logo_no_person.svg`, `Snowflake_Logo.svg` | Logos used at the top of every document |
