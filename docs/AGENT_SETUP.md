<table width="100%"><tr>
<td align="left"><img src="../ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="../Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Agent setup

## Prerequisites

- A Snowflake connection named `AWS161` in `~/.snowflake/connections.toml` with a role that can create databases, warehouses and agents (`ACCOUNTADMIN` was used).
- Python 3.11 with `snowflake-connector-python`, `snowflake-snowpark-python`, `snowflake-ml-python`, `scikit-learn`, `xgboost` and `pandas` (see `notebooks/environment.yml`).
- Cortex Analyst, Cortex Search and the Snowflake Model Registry enabled in the account.

## Build

```bash
python3 scripts/deploy.py --connection AWS161           # steps 1 to 9
python3 scripts/deploy.py --connection AWS161 --steps 5 6   # selected steps
```

| Step | File | What it does |
|---|---|---|
| 1 | `sql/setup/01_database_and_schema.sql` | Replaces `RIA_FINANCIAL_INTELLIGENCE` (RAW, ANALYTICS, ML) and `RIA_FINANCIAL_WH` (MEDIUM) |
| 2 | `sql/setup/02_create_tables.sql` | 27 RAW tables with column comments |
| 3 | `sql/data/03_generate_synthetic_data.sql` | Synthetic data, about two minutes. Truncates every RAW table first |
| 4 | `sql/views/04_create_views.sql` | Views, ML feature views and score tables (`CREATE IF NOT EXISTS`) |
| 5 | `sql/views/05_create_semantic_views.sql` | 10 semantic views |
| 6 | `sql/search/06_create_cortex_search.sql` | 6 Cortex Search services |
| 7 | `notebooks/07_ml_models.py` | Trains, registers and scores 10 models. 10 to 20 minutes |
| 8 | `sql/ml/08_ml_wrapper_functions.sql` | 13 agent functions |
| 9 | `sql/agent/09_create_agent.sql` | `RIA_FINANCIAL_AGENT` and `GRANT USAGE ... TO ROLE PUBLIC` |

`CREATE OR REPLACE DATABASE` in step 1 drops the previous build.

## Rerunning step 3

Step 3 regenerates every ID, so the model scores become stale. `deploy.py` detects this and reruns step 7 automatically when you run step 3 without it. If you run the SQL by hand, run `python3 notebooks/07_ml_models.py` afterwards. Until you do, the model tools return stale or empty results.

## Tools

| Type | Tools |
|---|---|
| Cortex Analyst (10) | `TransferAnalytics`, `CaseAnalytics`, `FraudLossAnalytics`, `DisputeAnalytics`, `AgentNetworkAnalytics`, `ScreeningAnalytics`, `ComplianceAnalytics`, `KycAnalytics`, `DigitalChannelAnalytics`, `Customer360Analytics` |
| Cortex Search (6) | `FraudTypologySearch`, `CaseNotesSearch`, `SarNarrativeSearch`, `PolicySearch`, `ComplaintSearch`, `CustomerFeedbackSearch` |
| Functions, model tools (10) | `GetTransactionFraudScore`, `GetAccountTakeoverRisk`, `GetSyntheticIdentityRisk`, `GetMuleBeneficiaries`, `GetStructuringAlerts`, `GetAgentCollusionRisk`, `GetChargebackRisk`, `GetScamVictimAlerts`, `GetFraudRings`, `GetScreeningTriage` |
| Functions, other (3) | `GetFraudOverview`, `GetModelRegistry`, `GetCustomer360` |
| Chart (1) | `data_to_chart` |

Function parameter names match the tool `input_schema` property names: `days_back`, `weeks_back`, `top_n`, `transfer_id_filter` and `customer_id_filter`.

## Privileges

The agent runs tools with the caller's role. `GRANT USAGE ON AGENT ... TO ROLE PUBLIC` lets any role open the agent, but each tool also needs access to the objects behind it: `USAGE` on `RIA_FINANCIAL_INTELLIGENCE`, its schemas and `RIA_FINANCIAL_WH`, `SELECT` on the ANALYTICS views and score tables, `USAGE` on the 10 semantic views, 6 search services and 13 functions. These grants were intentionally **not** added, because they would expose the data to every role in the account. Add them for the roles you choose.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Model tools return empty lists | Scores are missing. Run `python3 notebooks/07_ml_models.py` |
| `Database ... does not exist or not authorized` | The calling role lacks access. Use `ACCOUNTADMIN` or grant access |
| A model question returns only counts | The window is too small. Ask for a longer period, for example 30 days |
| Semantic view creation fails on a ratio metric | Reference other metrics (`fl.net_loss_usd`), not `SUM(column)` with the same name as a metric |
| Notebook stops at a registry check | The warehouse predictions did not match local predictions. Do not skip the check; investigate the feature types |
