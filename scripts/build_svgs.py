"""Generate the five Ria Financial architecture diagrams in docs/images from live Snowflake numbers.

Style copies the Rocket Lab / Cathay Bank template: white background, drop shadow on every box, centered text,
connectors that start and end on box edges. Header carries the Ria logo on the left and the Snowflake logo on the
right (embedded as data URIs so the SVGs render anywhere). Every text is fit-checked against its box while the
SVG is built, then scripts/check_svg.py verifies the written files.

Usage: python scripts/build_svgs.py --connection AWS161
"""
import argparse
import base64
import json
import pathlib

import snowflake.connector

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "images"
FONT = 'font-family="Segoe UI, Arial, sans-serif"'
BLUE, GREEN, ORANGE, PURPLE = "#29b5e8", "#00a843", "#e8530e", "#7b61ff"
TINT = {BLUE: ("#eaf7fc", "#0e7fad"), GREEN: ("#edf9f0", "#007a31"), ORANGE: ("#fff3ed", "#b33f08"), PURPLE: ("#f3f0ff", "#5a3ec8")}
AGENT_FILL, AGENT_SUB = "#0e7fad", "#d6f1fb"


def b64(path):
    return base64.b64encode(pathlib.Path(path).read_bytes()).decode()


RIA = b64(ROOT / "ria_logo_no_person.svg")
SNOW = b64(ROOT / "Snowflake_Logo.svg")


PROBLEMS = []


class Svg:
    def __init__(self, w, h, title, subtitle):
        self.w, self.h, self.rects, self.parts = w, h, [], []
        self.parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" {FONT}>')
        self.parts.append('  <defs>\n    <filter id="sh">\n      <feDropShadow dx="1" dy="2" stdDeviation="3" flood-color="#000" flood-opacity="0.12"/>\n    </filter>\n'
                          '    <filter id="shLg">\n      <feDropShadow dx="2" dy="3" stdDeviation="5" flood-color="#000" flood-opacity="0.15"/>\n    </filter>\n  </defs>')
        self.parts.append(f'  <rect width="{w}" height="{h}" fill="#ffffff"/>')
        # header: Ria logo left, Snowflake logo right
        self.parts.append(f'  <image x="24" y="10" width="64" height="64" href="data:image/svg+xml;base64,{RIA}"/>')
        sw = round(44 * 1625 / 368)
        self.parts.append(f'  <image x="{w - 24 - sw}" y="22" width="{sw}" height="44" href="data:image/svg+xml;base64,{SNOW}"/>')
        self.text(w / 2, 40, title, 24, "#1a1a2e", bold=True)
        self.text(w / 2, 64, subtitle, 12, "#666")

    # ---- primitives
    def _fit(self, x, y, s, size, anchor, bold):
        width = len(s) * size * (0.60 if bold else 0.55)
        x0 = x - width / 2 if anchor == "middle" else (x - width if anchor == "end" else x)
        x1 = x0 + width
        inside = [r for r in self.rects if r[0] <= x <= r[0] + r[2] and r[1] <= y - size * 0.4 <= r[1] + r[3]]
        box = min(inside, key=lambda r: r[2] * r[3]) if inside else (0, 0, self.w, self.h)
        if x0 < box[0] + 3 or x1 > box[0] + box[2] - 3 or y > box[1] + box[3] - 1:
            PROBLEMS.append(f'text "{s[:70]}" (~{width:.0f}px) overflows box {box}')

    def text(self, x, y, s, size, fill, anchor="middle", bold=False):
        s = s.replace("&", "&amp;")
        self._fit(x, y, s, size, anchor, bold)
        weight = ' font-weight="bold"' if bold else ""
        self.parts.append(f'  <text x="{x:g}" y="{y:g}" text-anchor="{anchor}" fill="{fill}" font-size="{size}"{weight}>{s}</text>')

    def box(self, x, y, w, h, fill, stroke=None, rx=8, big=False):
        self.rects.append((x, y, w, h))
        st = f' stroke="{stroke}" stroke-width="1.5"' if stroke else ""
        self.parts.append(f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{st} filter="url(#{"shLg" if big else "sh"})"/>')

    def card(self, x, y, w, h, color, head, lines=(), head_size=13, line_size=11, line_gap=20, first=None):
        fill, dark = TINT[color]
        self.box(x, y, w, h, fill, color, rx=10)
        self.text(x + w / 2, y + 26, head, head_size, dark, bold=True)
        yy = first or y + 52
        for ln in lines:
            if isinstance(ln, tuple):
                self.text(x + w / 2, yy, ln[0], line_size, ln[1])
            else:
                self.text(x + w / 2, yy, ln, line_size, "#555")
            yy += line_gap

    def line(self, x1, y1, x2, y2, color, dash=False, width=1.5):
        d = ' stroke-dasharray="5,3"' if dash else ""
        self.parts.append(f'  <line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"{d}/>')

    def arrow_right(self, x1, y, x2, color):
        self.line(x1, y, x2 - 2, y, color)
        self.parts.append(f'  <polygon points="{x2 - 4},{y - 4} {x2 + 6},{y} {x2 - 4},{y + 4}" fill="{color}"/>')

    def arrow_down(self, x, y1, y2, color):
        self.line(x, y1, x, y2 - 2, color)
        self.parts.append(f'  <polygon points="{x - 4},{y2 - 4} {x},{y2 + 6} {x + 4},{y2 - 4}" fill="{color}"/>')

    def elbow_down(self, x1, y1, ymid, x2, y2, color):
        self.parts.append(f'  <polyline points="{x1},{y1} {x1},{ymid} {x2},{ymid} {x2},{y2 - 2}" fill="none" stroke="{color}" stroke-width="1.5"/>')
        self.parts.append(f'  <polygon points="{x2 - 4},{y2 - 4} {x2},{y2 + 6} {x2 + 4},{y2 - 4}" fill="{color}"/>')

    def save(self, name):
        self.parts.append("</svg>")
        (OUT / name).write_text("\n".join(self.parts) + "\n")
        print("wrote", name)


def facts(conn):
    cur = conn.cursor()
    q = lambda s: cur.execute(s).fetchone()[0]
    f = {}
    db = "RIA_FINANCIAL_INTELLIGENCE"
    f["raw_tables"] = q(f"SELECT COUNT(*) FROM {db}.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='RAW'")
    f["views"] = q(f"SELECT COUNT(*) FROM {db}.INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA='ANALYTICS'")
    f["customers"] = q(f"SELECT COUNT(*) FROM {db}.RAW.CUSTOMERS")
    f["transfers"] = q(f"SELECT COUNT(*) FROM {db}.RAW.TRANSFERS")
    f["sessions"] = q(f"SELECT COUNT(*) FROM {db}.RAW.APP_SESSIONS")
    f["alerts"] = q(f"SELECT COUNT(*) FROM {db}.RAW.FRAUD_ALERTS")
    f["cases"] = q(f"SELECT COUNT(*) FROM {db}.RAW.FRAUD_CASES")
    f["fraud_pct"] = float(q(f"SELECT ROUND(100*AVG(IS_FRAUD::INT),2) FROM {db}.RAW.TRANSFERS"))
    f["raw_rows"] = q(f"SELECT SUM(ROW_COUNT) FROM {db}.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='RAW'")
    cur.execute(f"SELECT MODEL_ID, MODEL_NAME, ALGORITHM, ROC_AUC, PR_AUC, POSITIVE_RATE, TRAINING_ROWS, VALIDATION_STATUS, NEXT_VALIDATION_DATE < CURRENT_DATE() FROM {db}.ML.MODEL_REGISTRY ORDER BY MODEL_ID")
    f["models"] = cur.fetchall()
    f["scores"] = {t: q(f"SELECT COUNT(*) FROM {db}.ANALYTICS.{t}") for t in
                   ["TRANSFER_FRAUD_SCORES", "ATO_SESSION_SCORES", "SYNTHETIC_ID_SCORES", "MULE_SCORES", "STRUCTURING_SCORES", "AGENT_COLLUSION_SCORES",
                    "CHARGEBACK_SCORES", "SCAM_SCORES", "FRAUD_RING_SCORES", "SCREENING_TRIAGE_SCORES"]}
    f["high"] = q(f"SELECT COUNT_IF(COMPOSITE_MODEL_RISK_TIER='High') FROM {db}.ANALYTICS.CUSTOMER_MODEL_SCORES")
    f["rings"] = q(f"SELECT COUNT(*) FROM {db}.ANALYTICS.FRAUD_RING_CLUSTERS")
    f["open_alerts"] = q(f"SELECT COUNT_IF(STATUS<>'Closed') FROM {db}.RAW.FRAUD_ALERTS")
    f["past_due_models"] = q(f"SELECT COUNT_IF(NEXT_VALIDATION_DATE < CURRENT_DATE()) FROM {db}.ML.MODEL_REGISTRY")
    tr = ROOT / "docs" / "test_results.json"
    f["test"] = json.loads(tr.read_text()) if tr.exists() else {"passed": 0, "total": 16}
    return f


SHORT = {1: "Transaction fraud", 2: "Account takeover", 3: "Synthetic identity", 4: "Money mule", 5: "Structuring", 6: "Agent collusion",
         7: "Chargeback risk", 8: "Scam victim", 9: "Fraud ring (anomaly)", 10: "Screening triage"}


def n(x):
    return f"{int(x):,}"


# --------------------------------------------------------------------------- 1. architecture
def architecture(f):
    s = Svg(1200, 1010, "Ria Financial Intelligence Agent Architecture", "Snowflake Intelligence + Cortex AI | Cross-border fraud, AML, KYC and Customer 360")
    s.box(300, 95, 600, 50, BLUE, rx=10)
    s.text(600, 126, "Users: Fraud Ops, AML, Sanctions, Agent Oversight, Compliance", 14, "#ffffff", bold=True)
    s.arrow_down(600, 145, 175, BLUE)
    s.box(300, 185, 600, 65, AGENT_FILL, rx=12, big=True)
    s.text(600, 212, "RIA_FINANCIAL_AGENT", 18, "#ffffff", bold=True)
    s.text(600, 234, "Snowflake Intelligence Agent | 30 Tools | Natural Language", 12, AGENT_SUB)
    for x2, c in ((160, BLUE), (450, GREEN), (740, ORANGE), (1040, PURPLE)):
        s.line(600 + (x2 - 600) * 0.3, 250, x2, 285, c, dash=True)

    sv = ["RIA_TRANSFERS_SV", "RIA_CASES_SV", "RIA_FRAUD_LOSS_SV", "RIA_DISPUTES_SV", "RIA_AGENT_NETWORK_SV", "RIA_SCREENING_SV", "RIA_COMPLIANCE_SV", "RIA_KYC_SV",
          "RIA_DIGITAL_SV", "RIA_CUSTOMER_360_SV"]
    s.box(20, 285, 280, 290, "#eaf7fc", BLUE, rx=10)
    s.text(160, 308, "Cortex Analyst (10)", 14, "#0e7fad", bold=True)
    s.text(160, 326, "Text-to-SQL | Semantic Views", 11, BLUE)
    s.line(30, 336, 290, 336, "#b3e5fc", width=1)
    for i, name in enumerate(sv):
        s.text(35, 356 + i * 21, name, 10, "#444" if i < 9 else "#0e7fad", anchor="start", bold=(i == 9))

    srch = [("RIA_TYPOLOGY_SEARCH", "typology guides"), ("RIA_CASE_NOTES_SEARCH", "case notes"), ("RIA_SAR_NARRATIVE_SEARCH", "SAR narratives"),
            ("RIA_POLICY_SEARCH", "policies"), ("RIA_COMPLAINT_SEARCH", "complaints"), ("RIA_FEEDBACK_SEARCH", "NPS comments")]
    s.box(320, 285, 260, 290, "#edf9f0", GREEN, rx=10)
    s.text(450, 308, "Cortex Search (6)", 14, "#007a31", bold=True)
    s.text(450, 326, "Unstructured retrieval", 11, GREEN)
    s.line(330, 336, 570, 336, "#b8e6c4", width=1)
    for i, (name, what) in enumerate(srch):
        s.text(335, 360 + i * 34, name, 10, "#444", anchor="start", bold=True)
        s.text(335, 375 + i * 34, what, 9, "#888", anchor="start")

    fn = ["GetFraudOverview", "GetTransactionFraudScore", "GetAccountTakeoverRisk", "GetSyntheticIdentityRisk", "GetMuleBeneficiaries", "GetStructuringAlerts",
          "GetAgentCollusionRisk", "GetChargebackRisk", "GetScamVictimAlerts", "GetFraudRings", "GetScreeningTriage", "GetModelRegistry", "GetCustomer360"]
    s.box(600, 285, 280, 290, "#fff3ed", ORANGE, rx=10)
    s.text(740, 308, "Agent functions (13)", 14, "#b33f08", bold=True)
    s.text(740, 326, "10 model tools + 3 helpers", 11, ORANGE)
    s.line(610, 336, 870, 336, "#f7c9b0", width=1)
    for i, name in enumerate(fn):
        s.text(615, 354 + i * 16.5, name, 10, "#444" if 0 < i < 11 else "#b33f08", anchor="start", bold=(i in (0, 11, 12)))

    s.box(900, 285, 280, 290, "#f3f0ff", PURPLE, rx=10)
    s.text(1040, 308, "ML models (10)", 14, "#5a3ec8", bold=True)
    s.text(1040, 326, "Model Registry | batch scores", 11, PURPLE)
    s.line(910, 336, 1170, 336, "#d4cbff", width=1)
    for i, m in enumerate(f["models"]):
        s.text(915, 356 + i * 21, f"{m[0]:>2}  {SHORT[m[0]]}", 10, "#444", anchor="start")

    s.elbow_down(160, 575, 610, 160, 640, BLUE)
    s.elbow_down(450, 575, 610, 450, 640, GREEN)
    s.elbow_down(740, 575, 610, 740, 640, ORANGE)
    s.elbow_down(1040, 575, 610, 1040, 640, PURPLE)

    s.card(20, 650, 560, 200, BLUE, "ANALYTICS schema", [f"{f['views']} views and 10 model score tables", "Masked CUSTOMER_PROFILE, CUSTOMER_360, FRAUD_360",
           "TRANSFER_DETAIL, ALERT_DETAIL, CASE_DETAIL, DISPUTE_ACTIVITY", "11 ML feature views (V_*_FEATURES)", ("Names are initials only. No SSNs, PANs or full accounts.", "#888")],
           line_gap=26, first=700)
    s.card(620, 650, 560, 200, GREEN, "RAW schema", [f"{f['raw_tables']} tables | {n(f['raw_rows'])} rows", f"{n(f['customers'])} customers | {n(f['transfers'])} transfers | {n(f['sessions'])} sessions",
           f"{n(f['alerts'])} alerts | {n(f['cases'])} cases | SAR, CTR, sanctions, KYC", "Cards stored as token, BIN and last 4 only (PCI DSS)", ("All data is synthetic.", "#888")],
           line_gap=26, first=700)
    s.box(20, 870, 1160, 100, "#f8f9fa", "#dde1e6", rx=12)
    s.text(600, 900, "RIA_FINANCIAL_INTELLIGENCE | Warehouse RIA_FINANCIAL_WH | Account AWS161", 12, "#1a1a2e", bold=True)
    s.text(600, 924, "Every fraud score, risk tier and probability is a model prediction trained on synthetic data and is labelled that way by the agent.", 11, "#555")
    s.text(600, 946, "ML.MODEL_REGISTRY holds the SR 11-7 inventory for all 10 models.", 11, "#555")
    s.save("architecture.svg")


# --------------------------------------------------------------------------- 2. agent tool decision
def tool_decision(f):
    s = Svg(1200, 930, "Agent Tool Decision", "How RIA_FINANCIAL_AGENT routes a question to one of 30 tools")
    s.box(400, 95, 400, 50, BLUE, rx=10)
    s.text(600, 126, "User question", 15, "#ffffff", bold=True)
    s.arrow_down(600, 145, 175, BLUE)
    s.box(300, 185, 600, 56, AGENT_FILL, rx=12, big=True)
    s.text(600, 211, "Orchestration (model: auto)", 16, "#ffffff", bold=True)
    s.text(600, 230, "Picks the tool by question shape", 11, AGENT_SUB)
    cols = [
        (20, BLUE, "Operational analytics", "Cortex Analyst", [("Transfers by corridor, channel", "TransferAnalytics"), ("Alert and case backlog, aging", "CaseAnalytics"),
                ("Fraud losses and recoveries", "FraudLossAnalytics"), ("Chargebacks, refunds, ACH", "DisputeAnalytics"), ("Agent and branch network", "AgentNetworkAnalytics"),
                ("Sanctions screening outcomes", "ScreeningAnalytics"), ("SAR and CTR filings", "ComplianceAnalytics"), ("KYC, PEP, EDD", "KycAnalytics"),
                ("Sessions, devices, logins", "DigitalChannelAnalytics"), ("Value, NPS, recency", "Customer360Analytics")]),
        (320, PURPLE, "The 10 model questions", "Function tools", [("Highest fraud probability", "GetTransactionFraudScore"), ("Account-takeover risk", "GetAccountTakeoverRisk"),
                ("Synthetic identities", "GetSyntheticIdentityRisk"), ("Money mules", "GetMuleBeneficiaries"), ("Structuring", "GetStructuringAlerts"),
                ("Agent collusion", "GetAgentCollusionRisk"), ("Chargeback exposure", "GetChargebackRisk"), ("Scam victims", "GetScamVictimAlerts"),
                ("Fraud rings", "GetFraudRings"), ("Sanctions triage", "GetScreeningTriage")]),
        (620, ORANGE, "Briefs and governance", "Function tools", [("Fraud snapshot", "GetFraudOverview"), ("One customer's brief", "GetCustomer360"), ("Model inventory", "GetModelRegistry")]),
        (920, GREEN, "Documents", "Cortex Search", [("Typologies, red flags", "FraudTypologySearch"), ("Investigator notes", "CaseNotesSearch"), ("SAR narratives", "SarNarrativeSearch"),
                ("Policies", "PolicySearch"), ("Complaints", "ComplaintSearch"), ("NPS comments", "CustomerFeedbackSearch")]),
    ]
    for x, color, head, sub, rows in cols:
        w = 260 if x < 900 else 260
        s.line(600 + (x + w / 2 - 600) * 0.25, 241, x + w / 2, 275, color, dash=True)
        fill, dark = TINT[color]
        h = 60 + 49 * len(rows) if len(rows) > 3 else 60 + 49 * len(rows)
        s.box(x, 280, w, h, fill, color, rx=10)
        s.text(x + w / 2, 304, head, 13, dark, bold=True)
        s.text(x + w / 2, 322, sub, 10, color)
        for i, (shape, tool) in enumerate(rows):
            y = 336 + i * 49
            s.box(x + 10, y, w - 20, 42, "#ffffff", color, rx=6)
            s.text(x + w / 2, y + 17, shape, 10, "#555")
            s.text(x + w / 2, y + 33, tool, 10, dark, bold=True)
    s.box(620, 560, 260, 150, "#f8f9fa", "#dde1e6", rx=10)
    s.text(750, 586, "Every brief ends with actions", 11, "#1a1a2e", bold=True)
    s.text(750, 610, "KYC risk rating, latest model", 10, "#555")
    s.text(750, 626, "scores, open alerts and cases,", 10, "#555")
    s.text(750, 642, "and 90-day transfer volume,", 10, "#555")
    s.text(750, 666, "then one or two next actions.", 10, "#555")
    s.text(750, 692, "Charts: data_to_chart", 10, "#888")
    s.text(600, 880, "16 sample questions are built into the agent spec: the 10 model questions plus 6 general ones.", 11, "#666")
    s.text(600, 902, "Tool count: 10 Analyst + 6 Search + 13 functions + 1 chart = 30", 10, "#999")
    s.save("agent_tool_decision.svg")


# --------------------------------------------------------------------------- 3. customer 360
def customer_360(f):
    s = Svg(1100, 720, "Customer 360 and Fraud 360", "ANALYTICS.CUSTOMER_360 and ANALYTICS.FRAUD_360 | one row per customer | masked for GLBA")
    s.box(340, 95, 420, 80, AGENT_FILL, rx=12, big=True)
    s.text(550, 126, "CUSTOMER_360  +  FRAUD_360", 16, "#ffffff", bold=True)
    s.text(550, 148, f"{n(f['customers'])} customers | initials only, masked email, last-4 phone", 11, AGENT_SUB)
    s.text(550, 165, "Agent entry: GetCustomer360 (customer ID)", 10, AGENT_SUB)
    xs = [(30, BLUE), (300, GREEN), (570, ORANGE), (840, PURPLE)]
    for (x, c) in xs:
        s.line(550, 175, x + 125, 215, c)
    s.card(30, 220, 250, 190, BLUE, "Profile and KYC", ["Segment, loyalty tier, age band", "KYC risk rating (L / M / H)", "PEP and EDD status", "ID verification, review dates", ("Source of funds, occupation", "#888")], line_gap=26, first=268)
    s.card(300, 220, 250, 190, GREEN, "Value and frequency", ["Lifetime value (fees + FX margin)", "Transfers per month, 90-day volume", "Complaints and open complaints", "Latest NPS and category", ("Rule-based recency (not a model)", "#888")], line_gap=26, first=268)
    s.card(570, 220, 250, 190, ORANGE, "Fraud and compliance", ["Open alerts and open cases", "Confirmed fraud, net loss", "Chargebacks, ACH returns", "Screening hits, SAR and CTR counts", ("Alert to case to disposition trail", "#888")], line_gap=26, first=268)
    s.card(840, 220, 230, 190, PURPLE, "Model scores", ["Synthetic identity", "Account takeover (30 days)", "Transaction fraud (90 days)", "Structuring (8 weeks), ring link", ("Composite tier: highest of all", "#888")], line_gap=26, first=268)
    s.box(60, 450, 980, 170, "#f8f9fa", "#dde1e6", rx=12)
    s.text(550, 478, "How the model scores get here", 13, "#1a1a2e", bold=True)
    s.text(550, 506, "Score tables are written by notebooks/07_ml_models.py and rolled up by ANALYTICS.CUSTOMER_MODEL_SCORES.", 12, "#555")
    s.text(550, 528, "Labeled rows carry their out-of-fold score, so no row is scored by a model that trained on it.", 12, "#555")
    s.text(550, 556, f"{n(f['high'])} customers are in the High composite model risk tier today.", 12, "#555")
    s.text(550, 584, "Every score is a model prediction trained on synthetic data and is labelled that way by the agent.", 11, "#888")
    s.text(550, 660, "Semantic view: RIA_CUSTOMER_360_SV | Functions: AGENT_GET_CUSTOMER_360, AGENT_GET_FRAUD_OVERVIEW", 11, "#999")
    s.text(550, 684, "Scores are empty until notebooks/07_ml_models.py has run after the latest data load. deploy.py reruns it after step 3.", 10, "#aaa")
    s.save("customer_360.svg")


# --------------------------------------------------------------------------- 4. deployment flow
def deployment(f):
    s = Svg(1100, 840, "Deployment Flow", "Execution Order: Steps 01-09 | python3 scripts/deploy.py --connection AWS161")
    row1 = [(40, 230, BLUE, "01 Infrastructure", "Database, Schemas, Warehouse"), (320, 230, BLUE, "02 Tables", f"{f['raw_tables']} RAW Tables"),
            (600, 230, ORANGE, "03 Synthetic Data", f"{n(f['customers'])} Customers, {n(f['transfers'])} Transfers"), (880, 180, GREEN, "04 Views", f"{f['views']} Views + Score Tables")]
    row2 = [(40, 230, GREEN, "05 Semantic Views", "10 Cortex Analyst Views"), (320, 230, GREEN, "06 Cortex Search", "6 Search Services"),
            (600, 230, PURPLE, "07 ML Models", "10 Models, Registry + Scores"), (880, 180, ORANGE, "08 Functions", "13 Agent Functions")]
    for y, row in ((95, row1), (235, row2)):
        for i, (x, w, c, head, sub) in enumerate(row):
            fill, dark = TINT[c]
            s.box(x, y, w, 64, fill, c, rx=8)
            s.text(x + w / 2, y + 26, head, 13, dark, bold=True)
            s.text(x + w / 2, y + 46, sub, 10, "#555")
            if i < 3:
                nx = row[i + 1][0]
                s.arrow_right(x + w, y + 32, nx - 8, row[i + 1][2] if i < 2 else c)
    s.elbow_down(970, 159, 197, 155, 235, GREEN)
    s.elbow_down(970, 299, 337, 550, 375, ORANGE)
    s.box(300, 375, 500, 70, AGENT_FILL, rx=12, big=True)
    s.text(550, 404, "09 RIA_FINANCIAL_AGENT", 16, "#ffffff", bold=True)
    s.text(550, 426, "30 Tools: 10 Analyst + 6 Search + 13 Functions + chart", 12, AGENT_SUB)
    s.box(40, 480, 1020, 220, "#f8f9fa", "#dde1e6", rx=12)
    s.text(550, 508, "Verified on AWS161 - RIA_FINANCIAL_INTELLIGENCE", 13, "#1a1a2e", bold=True)
    cards = [(60, BLUE, "Data", f"{n(f['transfers'])} transfers, fraud {f['fraud_pct']}%"), (310, GREEN, "Models", "10 trained, registered, scored"),
             (560, ORANGE, "Governance", f"{f['past_due_models']} models past validation date"), (810, PURPLE, "Agent test", f"scripts/test_agent.py {f['test']['passed']}/{f['test']['total']}")]
    for x, c, head, sub in cards:
        fill, dark = TINT[c]
        s.box(x, 526, 230, 68, "#ffffff", c, rx=8)
        s.text(x + 115, 552, head, 12, dark, bold=True)
        s.text(x + 115, 572, sub, 10, "#555")
    s.text(550, 628, "Step 7 is notebooks/07_ml_models.py and takes 10 to 20 minutes (each model is logged to the Registry).", 11, "#666")
    s.text(550, 650, "Rerunning step 3 changes every ID, so deploy.py reruns step 7 afterwards to retrain and rescore.", 11, "#666")
    s.text(550, 672, "The Cortex Agent is created last. Grant roles access to the database objects the agent tools read.", 10, "#888")
    s.text(550, 760, "Warehouse RIA_FINANCIAL_WH | Role ACCOUNTADMIN | Review before sharing", 10, "#aaa")
    s.save("deployment_flow.svg")


# --------------------------------------------------------------------------- 5. ML models
def ml_models(f):
    rows = 10
    s = Svg(1200, 790, "ML Model Pipeline", "Snowflake Model Registry | 10 fraud and compliance models | notebooks/07_ml_models.py")
    s.card(20, 90, 220, 400, BLUE, "Feature views", ["ANALYTICS.V_*_FEATURES", ("One view per model family", "#555"), ("Features: FLOAT, no NULLs", "#555"), ("Single source for", "#555"),
           ("training and scoring", "#555"), ("Prior-activity features", "#555"), ("look backwards only", "#555"), ("Labels are outcomes,", "#888"), ("never inputs", "#888")],
           head_size=12, line_size=10, line_gap=26, first=130)
    s.arrow_right(240, 290, 278, BLUE)
    s.card(290, 90, 250, 400, PURPLE, "Training method", [("5-fold CV grouped by customer", "#555"), ("Negatives downsampled or class", "#555"), ("weights, then probabilities", "#555"), ("corrected to the true base rate", "#555"), ("ROC AUC and PR AUC are measured", "#555"),
           ("out of fold at the real class mix", "#555"), ("Tiers: High = precision 50%+", "#555"), ("Medium = precision 20%+", "#555"), ("AUC above 0.985 is checked for", "#888"), ("leakage and documented", "#888")],
           head_size=12, line_size=10, line_gap=26, first=130)
    s.arrow_right(540, 290, 568, PURPLE)
    y0 = 90
    for i, m in enumerate(f["models"]):
        c = ORANGE if m[0] in (1, 7, 8) else (PURPLE if m[0] == 9 else BLUE)
        fill, dark = TINT[c]
        y = y0 + i * 40
        s.box(580, y, 600, 36, fill, c, rx=6)
        s.text(595, y + 23, f"{m[0]:>2}  {SHORT[m[0]]}", 11, dark, anchor="start", bold=True)
        tag = "Isolation forest" if m[0] == 9 else "XGBoost"
        s.text(1000, y + 15, f"{tag} | ROC AUC {float(m[3]):.3f}", 10, "#555")
        s.text(1000, y + 29, f"PR AUC {float(m[4]):.3f} | positives {100 * float(m[5]):.2f}%", 9, "#888")
    s.box(20, 510, 1160, 200, "#f8f9fa", "#dde1e6", rx=10)
    s.text(600, 536, "How scores reach the agent", 13, "#1a1a2e", bold=True)
    s.box(40, 554, 250, 110, "#ffffff", PURPLE, rx=8)
    s.text(165, 580, "Registry V1", 12, "#5a3ec8", bold=True)
    s.text(165, 604, "RIA_FINANCIAL_INTELLIGENCE.ML", 10, "#555")
    s.text(165, 624, "10 models, predictions checked", 10, "#555")
    s.text(165, 644, "against the warehouse copy", 9, "#888")
    s.arrow_right(290, 609, 348, PURPLE)
    s.box(360, 554, 280, 110, "#ffffff", ORANGE, rx=8)
    s.text(500, 580, "ANALYTICS.*_SCORES (10 tables)", 12, "#b33f08", bold=True)
    s.text(500, 604, "Transfer, session, customer, beneficiary,", 10, "#555")
    s.text(500, 624, "week, agent, screening hit", 10, "#555")
    s.text(500, 644, "Kept across step 3 and 4 reruns", 9, "#888")
    s.arrow_right(640, 609, 698, ORANGE)
    s.box(710, 554, 450, 110, "#ffffff", GREEN, rx=8)
    s.text(935, 580, "Agent functions and ML.MODEL_REGISTRY", 12, "#007a31", bold=True)
    s.text(935, 604, "Ten model tools read the score tables", 10, "#555")
    s.text(935, 624, "GetModelRegistry lists owner, version, metrics, validation", 10, "#555")
    s.text(935, 644, f"{f['past_due_models']} models are past their validation date today", 9, "#888")
    s.text(600, 740, "Synthetic data: the generator creates both features and labels. Do not quote these metrics as production performance.", 11, "#999")
    s.text(600, 762, "Run: python3 notebooks/07_ml_models.py", 10, "#aaa")
    s.save("ml_models.svg")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="AWS161")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    conn = snowflake.connector.connect(connection_name=args.connection)
    f = facts(conn)
    conn.close()
    architecture(f)
    tool_decision(f)
    customer_360(f)
    deployment(f)
    ml_models(f)
    if PROBLEMS:
        print("\nTEXT DOES NOT FIT:")
        print("\n".join(PROBLEMS))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
