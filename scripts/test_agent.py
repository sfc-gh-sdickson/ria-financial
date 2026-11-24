"""Run the 16 sample questions through RIA_FINANCIAL_AGENT and check each one.

A question passes when the expected tool was used, its result is non-empty (for the 10 model questions the score
counts and ranked lists must be populated), and the agent wrote an answer.

Usage:
    python scripts/test_agent.py --connection AWS161
    python scripts/test_agent.py --only 1 4 11     # run selected question numbers
"""
import argparse
import datetime
import json
import pathlib
import re
import time

import snowflake.connector

AGENT = "SNOWFLAKE_INTELLIGENCE.AGENTS.RIA_FINANCIAL_AGENT"

# (question, tools that count as correct, JSON path checks for model questions)
QUESTIONS = [
    ("Which transfers in the last 7 days have the highest fraud probability?", ["GetTransactionFraudScore"], {"scored_transfers": 0, "top_transfers": []}),
    ("Which customer accounts show the highest account-takeover risk this week?", ["GetAccountTakeoverRisk"], {"customers_scored": 0, "top_customers": []}),
    ("How many new sign-ups this month are likely synthetic identities?", ["GetSyntheticIdentityRisk"], {"new_signups_scored": 0, "top_customers": []}),
    ("Which beneficiaries are most likely to be money mules, and how much have they received?", ["GetMuleBeneficiaries"], {"beneficiaries_scored": 0, "top_beneficiaries": []}),
    ("Which senders look like they are structuring transfers just under $10,000?", ["GetStructuringAlerts"], {"customer_weeks_scored": 0, "top_customer_weeks": []}),
    ("Which agent locations have the highest collusion risk score?", ["GetAgentCollusionRisk"], {"locations_scored": 0, "top_locations": []}),
    ("What is the predicted chargeback exposure on card-funded transfers this month?", ["GetChargebackRisk"], {"card_funded_transfers_scored": 0, "predicted_chargeback_exposure_usd": 0}),
    ("Which recent transfers look like the sender is a scam victim?", ["GetScamVictimAlerts"], {"transfers_scored": 0, "top_transfers": []}),
    ("What are the largest suspected fraud rings and how many accounts does each link?", ["GetFraudRings"], {"clusters_of_3_or_more_accounts": 0, "top_clusters": []}),
    ("Which open sanctions screening hits are most likely true matches and should be worked first?", ["GetScreeningTriage"], {"open_hits": 0, "work_first": []}),
    ("What is our fraud loss rate by corridor this quarter?", ["FraudLossAnalytics"], None),
    ("How many alerts are open past 30 days, and which queue owns them?", ["CaseAnalytics", "GetFraudOverview"], None),
    ("Are any SAR filings at risk of missing the 30-day deadline?", ["ComplianceAnalytics", "GetFraudOverview"], None),
    ("Give me a Customer 360 brief for customer C000123.", ["GetCustomer360"], {"customer_id": 0, "model_scores": {}}),
    ("What is the sanctions screening false-positive rate by list source?", ["ScreeningAnalytics"], None),
    ("Which models in the registry are past their validation date?", ["GetModelRegistry"], {"models": 0, "inventory": []}),
]


def parse(resp):
    tools, results, text = [], [], []
    for item in resp.get("content", []):
        t = item.get("type")
        if t == "tool_use":
            tools.append(item["tool_use"].get("name"))
        elif t == "tool_result":
            tr = item.get("tool_result", {})
            results.append((tr.get("name"), json.dumps(tr)))
            for c in tr.get("content", []):
                j = c.get("json", {})
                if isinstance(j, dict) and isinstance(j.get("result"), str):
                    try:
                        results.append((tr.get("name"), json.loads(j["result"])))
                    except ValueError:
                        pass
        elif t == "text":
            text.append(item.get("text", ""))
    return tools, results, " ".join(text).strip()


def non_empty(results, checks):
    """For model questions every named field must be present and non-empty (a number above 0 or a non-empty list)."""
    for name, res in results:
        if isinstance(res, dict) and all(k in res for k in checks):
            for k, empty in checks.items():
                v = res[k]
                if v is None or v == empty or (isinstance(empty, (list, dict)) and len(v) == 0) or (isinstance(empty, (int, float)) and v == 0):
                    return False, f"{k} is empty"
            return True, "scores returned"
    return False, "no function result with the expected fields"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="AWS161")
    parser.add_argument("--only", nargs="*", type=int)
    args = parser.parse_args()
    cur = snowflake.connector.connect(connection_name=args.connection).cursor()
    passed = total = 0
    log = []
    for i, (q, expected, checks) in enumerate(QUESTIONS, 1):
        if args.only and i not in args.only:
            continue
        total += 1
        body = json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": q}]}]})
        start = time.time()
        try:
            raw = cur.execute("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(%s, %s)", (AGENT, body)).fetchone()[0]
            tools, results, text = parse(json.loads(raw))
            used = [t for t in tools if t in expected]
            ok_tool = bool(used)
            ok_data, why = (True, "tool result returned")
            if checks is not None:
                ok_data, why = non_empty(results, checks)
            elif not results or any(re.search(r'"status"\s*:\s*"error"', r[1]) for r in results if isinstance(r[1], str)):
                ok_data, why = False, "tool returned an error or no result"
            ok = ok_tool and ok_data and len(text) > 40
            passed += ok
            log.append({"n": i, "question": q, "passed": bool(ok), "tools": tools, "seconds": round(time.time() - start)})
            print(f"[{i:2d}] {'PASS' if ok else 'FAIL'} ({time.time() - start:.0f}s) {q}")
            print(f"       tools: {tools}  expected one of: {expected}  data: {why}")
            print(f"       answer: {text[:300].replace(chr(10), ' ')}")
        except Exception as e:
            log.append({"n": i, "question": q, "passed": False, "error": str(e)[:200]})
            print(f"[{i:2d}] FAIL ({time.time() - start:.0f}s) {q}\n       error: {str(e)[:300]}")
    print(f"\n{passed}/{total} questions passed")
    if not args.only:
        out = pathlib.Path(__file__).resolve().parent.parent / "docs" / "test_results.json"
        out.write_text(json.dumps({"passed": passed, "total": total, "run_at": datetime.datetime.now().isoformat(timespec="seconds"), "questions": log}, indent=2))


if __name__ == "__main__":
    main()
