<table width="100%"><tr>
<td align="left"><img src="../ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="../Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Build report

How long the Ria Financial project took to build, and what it cost in Snowflake credits and AI tokens. Back to the [README](../README.md).

Source: `SNOWFLAKE.ACCOUNT_USAGE` (`WAREHOUSE_METERING_HISTORY`, `METERING_HISTORY`, `CORTEX_AGENT_USAGE_HISTORY`, `CORTEX_ANALYST_USAGE_HISTORY`, `CORTEX_SEARCH_DAILY_USAGE_HISTORY`, `CORTEX_CODE_DESKTOP_USAGE_HISTORY`) for account `AWS161`, user `SNOWMAN`, on 2026-11-23 (Mountain time).

## Summary

| Measure | Value |
|---|---|
| Build time, first prompt to push | about 6 h 20 min on the clock (15:05 to 21:27) |
| Active build time | about 3 h 30 min (15:14 to 18:40), including the full test run, diagrams and docs |
| Follow-up | about 15 min at 21:15 to 21:27: corrections to the build log, GitHub repo, this report. No AI use between 18:40 and 21:00 |
| Snowflake credits (data, models, agent) | **17.65** |
| Cortex Code credits (the AI that built it) | **19.46** |
| **Total credits** | **37.11** |
| Cortex Code tokens | **92,252,792** across 230 requests (about 92 million, 93% of them cached reads) |
| Agent test tokens | 5,684,230 across 33 agent requests |

## Time

| Phase | When | What happened |
|---|---|---|
| Setup and design | 15:05 to 16:00 | Read `agent (1).md` and the Rocket Lab template, then built the database, 27 tables and the first data generator |
| Data realism | 16:00 to 17:40 | Generator rebuilt several times to remove near-perfect model scores. Views, 10 semantic views, 6 search services |
| Models and agent | 17:40 to 18:00 | 10 models trained and registered, 13 functions, agent created |
| Test, diagrams, docs | 18:00 to 18:40 | Final data rebuild with automatic rescoring (about 10 min for step 7), 16/16 agent test, 5 SVGs, README and docs, build log |
| Follow-up | 21:15 to 21:27 | Build log corrections, GitHub repo, repo rename, this report |

Phase boundaries are taken from file timestamps and usage records, so they are approximate.

## Snowflake credits: 17.65

| Item | Credits | Notes |
|---|---|---|
| Warehouse `RIA_FINANCIAL_WH` | 13.54 | 13.29 compute + 0.25 cloud services. By hour: 16:00 5.08, 17:00 5.50, 18:00 2.95. Mostly data generation (about 2 min per run, run many times), feature views and model scoring |
| Cortex Agent `RIA_FINANCIAL_AGENT` | 3.81 | 33 requests: the 16-question test run twice plus probes |
| Cortex Analyst | 0.27 | Semantic view checks and agent tool calls |
| Cortex Search serving | 0.04 | 6 services |
| **Total** | **17.65** | |

## Cortex Code credits and tokens: 19.46 credits

| Model | Requests | Output tokens | Cache read | Cache write | Fresh input |
|---|---|---|---|---|---|
| claude-sonnet-5-5 | 157 | 599,328 | 76,759,239 | 6,364,182 | 338 |
| claude-opus-5-5 | 72 | 100,554 | 8,607,356 | 428,825 | 172 |
| claude-haiku-5-5 | 2 | 24 | 0 | 0 | 764 |
| **Total** | 230 | **699,906** | **85,366,595** | **6,793,007** | **1,274** |

Credits by hour: 15:00 4.06, 16:00 3.08, 17:00 4.47, 18:00 6.88, 21:00 1.02. Total tokens reported by Snowflake: 92,252,792. Most of that is the conversation being re-read from cache on every request. The model produced about 0.7 million tokens of new text and code.

## Cost per deliverable (rough)

| Deliverable | Count |
|---|---|
| Credits per RAW table | 1.37 (37.11 / 27) |
| Credits per model | 3.7 (37.11 / 10) |
| Credits per agent tool | 1.2 (37.11 / 30) |

## What is not counted

- Usage views lag by up to a few hours, so anything after about 21:25 may not be included.
- The Cortex Code figure covers every Desktop request by `SNOWMAN` from 15:00 onward. I assumed all of it belongs to this project.
- Search service indexing, the Model Registry, and storage for the 2.7M rows are not separate lines in these views, and are small or folded into the warehouse figure.
- A small serverless task charge (0.06 credits) in the same window was left out because it cannot be tied to this project.
- Time spent by you reviewing outside the chat is not measured.
