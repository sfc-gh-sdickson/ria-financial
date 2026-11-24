"""Build reports/daily_fraud_brief.html: a self-contained Daily Fraud Brief from live Ria Financial data.

The report runs in a sandbox with no network, so every number is queried here and embedded in the HTML.
Re-run this script to refresh it:  python scripts/build_daily_brief.py --connection AWS161
"""
import argparse
import base64
import datetime
import html
import json
import pathlib

import snowflake.connector

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "reports" / "daily_fraud_brief.html"
DB = "RIA_FINANCIAL_INTELLIGENCE"
ASOF = f"(SELECT MAX(CREATED_AT)::DATE FROM {DB}.RAW.TRANSFERS)"

SQL = {
    "daily": f"""SELECT t.CREATED_AT::DATE AS DAY, COUNT(*) AS TRANSFERS, ROUND(SUM(t.SEND_AMOUNT_USD)) AS VOLUME_USD,
       COUNT_IF(s.RISK_TIER = 'High') AS HIGH_TIER, COUNT_IF(s.RISK_TIER = 'Medium') AS MEDIUM_TIER,
       ROUND(SUM(IFF(s.RISK_TIER = 'High', t.SEND_AMOUNT_USD, 0))) AS HIGH_TIER_USD, COUNT_IF(t.IS_FRAUD) AS CONFIRMED_FRAUD
FROM {DB}.RAW.TRANSFERS t JOIN {DB}.ANALYTICS.TRANSFER_FRAUD_SCORES s ON s.TRANSFER_ID = t.TRANSFER_ID
WHERE t.CREATED_AT >= DATEADD(DAY, -13, {ASOF})
GROUP BY 1 ORDER BY 1""",
    "top_transfers": f"""SELECT TRANSFER_ID, CUSTOMER_ID, CORRIDOR_NAME, CHANNEL, FUNDING_TYPE, SEND_AMOUNT_USD, FRAUD_PROBABILITY, FRAUD_RISK_TIER, STATUS
FROM {DB}.ANALYTICS.TRANSFER_DETAIL
WHERE TRANSFER_DATE = {ASOF} AND FRAUD_PROBABILITY IS NOT NULL
ORDER BY FRAUD_PROBABILITY DESC LIMIT 10""",
    "ato": f"""SELECT CUSTOMER_ID, SESSION_ID, LOGIN_AT, ATO_PROBABILITY, ATO_RISK_TIER, IP_COUNTRY, IS_NEW_DEVICE, FAILED_ATTEMPTS, PASSWORD_RESET_24H, BENEFICIARY_ADDED
FROM {DB}.ANALYTICS.DIGITAL_SESSION_DETAIL
WHERE LOGIN_DATE >= DATEADD(DAY, -1, {ASOF}) AND ATO_PROBABILITY IS NOT NULL
ORDER BY ATO_PROBABILITY DESC LIMIT 8""",
    "ato_counts": f"""SELECT COUNT_IF(ATO_RISK_TIER = 'High') AS HIGH_SESSIONS, COUNT(DISTINCT IFF(ATO_RISK_TIER = 'High', CUSTOMER_ID, NULL)) AS HIGH_CUSTOMERS
FROM {DB}.ANALYTICS.DIGITAL_SESSION_DETAIL WHERE LOGIN_DATE >= DATEADD(DAY, -1, {ASOF}) AND ATO_PROBABILITY IS NOT NULL""",
    "backlog": f"""SELECT QUEUE, COUNT_IF(IS_OPEN) AS OPEN_ALERTS, COUNT_IF(IS_OPEN_OVER_30_DAYS) AS OPEN_OVER_30_DAYS, COUNT_IF(IS_OPEN AND IS_UNASSIGNED) AS UNASSIGNED
FROM {DB}.ANALYTICS.ALERT_DETAIL GROUP BY QUEUE ORDER BY OPEN_ALERTS DESC""",
    "cases": f"""SELECT COUNT_IF(IS_OPEN) AS OPEN_CASES, COUNT_IF(STATUS = 'Pending SAR Decision') AS PENDING_SAR_DECISION,
       COUNT_IF(IS_OPEN AND PRIORITY = 'P1') AS OPEN_P1, COUNT_IF(IS_OPEN_OVER_30_DAYS) AS OPEN_OVER_30_DAYS
FROM {DB}.ANALYTICS.CASE_DETAIL""",
    "sar": f"""SELECT FILING_ID, ACTIVITY_TYPE, FILING_STATUS, DUE_DATE, DAYS_UNTIL_DUE, IS_OVERDUE, AMOUNT_USD
FROM {DB}.ANALYTICS.COMPLIANCE_FILINGS WHERE FILING_TYPE = 'SAR' AND (IS_OVERDUE OR IS_AT_RISK)
ORDER BY DUE_DATE LIMIT 10""",
    "sar_counts": f"""SELECT COUNT_IF(IS_OVERDUE) AS OVERDUE, COUNT_IF(IS_AT_RISK) AS AT_RISK FROM {DB}.ANALYTICS.COMPLIANCE_FILINGS WHERE FILING_TYPE = 'SAR'""",
    "ctr": f"""SELECT COUNT_IF(FILING_STATUS = 'Pending') AS PENDING_CTR FROM {DB}.ANALYTICS.COMPLIANCE_FILINGS WHERE FILING_TYPE = 'CTR'""",
    "screening": f"""SELECT SCREENING_ID, LIST_SOURCE, SCREENED_PARTY, TRUE_MATCH_PROBABILITY, TRIAGE_TIER, MATCH_SCORE, SEND_AMOUNT_USD, HOURS_TO_DISPOSITION AS HOURS_OPEN
FROM {DB}.ANALYTICS.SCREENING_DETAIL WHERE IS_OPEN AND TRUE_MATCH_PROBABILITY IS NOT NULL ORDER BY TRUE_MATCH_PROBABILITY DESC LIMIT 5""",
    "screening_counts": f"""SELECT COUNT(*) AS OPEN_HITS, COUNT_IF(TRIAGE_TIER = 'High') AS HIGH_TIER, COUNT_IF(TRIAGE_TIER = 'Medium') AS MEDIUM_TIER
FROM {DB}.ANALYTICS.SCREENING_DETAIL WHERE IS_OPEN AND TRUE_MATCH_PROBABILITY IS NOT NULL""",
    "mules": f"SELECT {DB}.ANALYTICS.AGENT_GET_MULE_BENEFICIARIES(5)",
    "agents": f"SELECT {DB}.ANALYTICS.AGENT_GET_AGENT_COLLUSION_RISK(5)",
    "rings": f"SELECT {DB}.ANALYTICS.AGENT_GET_FRAUD_RINGS(5)",
    "scam": f"SELECT {DB}.ANALYTICS.AGENT_GET_SCAM_VICTIM_ALERTS(7)",
}


def b64(name):
    return base64.b64encode((ROOT / name).read_bytes()).decode()


def esc(x):
    return html.escape("" if x is None else str(x))


def money(x):
    return f"${float(x):,.0f}"


def pct(x, d=1):
    return f"{100 * float(x):.{d}f}%"


def table(cols, rows):
    head = "".join(f"<th>{esc(c)}</th>" for c, _ in cols)
    body = "".join("<tr>" + "".join(f"<td>{esc(fn(r))}</td>" for _, fn in cols) + "</tr>" for r in rows)
    if not rows:
        body = f'<tr><td colspan="{len(cols)}">None today.</td></tr>'
    return f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def tier(t):
    return f'<span class="tier {esc(t).lower()}">{esc(t)}</span>'


def run(cur, sql):
    cur.execute(sql)
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def chart_card(cid, title, sql, preview_html, info, section_id):
    return f"""<h2 id="{section_id}">{esc(title)}</h2>
<div class="chart-card">
  <div class="chart-card-tools" role="group" aria-label="Chart views">
    <button type="button" class="active" data-view="chart" aria-pressed="true">Chart</button>
    <button type="button" data-view="sql" aria-pressed="false">SQL</button>
    <button type="button" data-view="preview" aria-pressed="false">Preview</button>
    <button type="button" data-view="info" aria-pressed="false">Info</button>
  </div>
  <div class="cc-panel active" data-panel="chart"><div class="chart-box"><canvas id="{cid}"></canvas></div></div>
  <div class="cc-panel" data-panel="sql"><div class="cc-sql"><button type="button" class="cc-copy">Copy</button><pre><code>{esc(sql)}</code></pre></div></div>
  <div class="cc-panel" data-panel="preview">{preview_html}</div>
  <div class="cc-panel cc-info" data-panel="info">{info}</div>
  <p class="cc-status" role="status" aria-live="polite"></p>
</div>"""


CSS = """
:root { color-scheme: light dark; --card: light-dark(#ffffff, #1b2433); --line: light-dark(#e5e7eb, #374151); --muted: light-dark(#6b7280, #9ca3af); --accent: #29b5e8; }
* { box-sizing: border-box; }
body { font-family: -apple-system, system-ui, "Segoe UI", sans-serif; max-width: 980px; width: 100%; margin: 0 auto; padding: clamp(16px, 4vw, 28px); color: light-dark(#1f2937, #e5e7eb); background: light-dark(#f6f8fb, #0f1520); line-height: 1.5; }
h1, h2, h3 { color: light-dark(#0f172a, #f1f5f9); margin: 0; }
h2 { font-size: 18px; margin: 30px 0 10px; padding-top: 6px; }
a { color: light-dark(#2563eb, #60a5fa); }
img, svg { max-width: 100%; height: auto; }
.top { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; background: #fff; border-radius: 12px; padding: 12px 18px; box-shadow: 0 1px 4px rgba(0,0,0,.12); }
.top img { display: block; height: 96px; width: auto; max-width: 45%; object-fit: contain; }  /* 96px = 1 inch, well under the 2 inch limit */
.title { margin: 22px 0 4px; display: flex; align-items: baseline; justify-content: space-between; flex-wrap: wrap; gap: 8px; }
.title h1 { font-size: clamp(22px, 5vw, 30px); }
.asof { color: var(--muted); font-size: 14px; }
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin-top: 16px; }
.kpi { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
.kpi .label { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
.kpi .value { font-size: 26px; font-weight: 700; margin-top: 2px; }
.kpi .delta { font-size: 12px; color: var(--muted); }
.kpi.alert { border-left: 4px solid #e8530e; }
.actions { background: var(--card); border: 1px solid var(--line); border-left: 4px solid var(--accent); border-radius: 10px; padding: 6px 18px 10px; margin-top: 18px; }
.actions h2 { margin-top: 10px; }
.actions ol { margin: 6px 0 0; padding-left: 20px; }
.actions li { margin: 5px 0; }
.table-wrap { overflow-x: auto; margin: 8px 0 4px; background: var(--card); border: 1px solid var(--line); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
th, td { padding: 7px 10px; text-align: left; border-bottom: 1px solid var(--line); white-space: nowrap; }
th { background: light-dark(#f3f4f6, #222c3d); font-weight: 600; }
tr:last-child td { border-bottom: 0; }
.tier { padding: 1px 8px; border-radius: 999px; font-size: 12px; font-weight: 600; }
.tier.high { background: light-dark(#fde2d6, #5b2410); color: light-dark(#b33f08, #ffb08a); }
.tier.medium { background: light-dark(#fff3c4, #4d3d0a); color: light-dark(#8a6a00, #ffd966); }
.tier.low { background: light-dark(#e2f5e8, #12361f); color: light-dark(#007a31, #7bd99a); }
.grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 14px; }
.note { color: var(--muted); font-size: 13px; margin: 6px 0 0; }
.chart-box { position: relative; width: 100%; height: 100%; }
.chart-box > canvas { width: 100% !important; height: 100% !important; }
.chart-card { position: relative; margin: 22px 0 8px; border-top: 1px solid var(--line); }
.chart-card-tools { position: absolute; top: -13px; right: 12px; z-index: 2; display: flex; gap: 2px; align-items: center; height: 26px; padding: 0 6px; border: 1px solid transparent; border-radius: 999px; background: Canvas; box-shadow: 0 1px 4px rgba(0,0,0,.1); opacity: 0; pointer-events: none; transition: opacity .15s, border-color .15s; }
.chart-card:hover .chart-card-tools, .chart-card:focus-within .chart-card-tools { opacity: 1; pointer-events: auto; border-color: var(--line); }
@media (hover: none) { .chart-card-tools { opacity: 1; pointer-events: auto; border-color: var(--line); } }
.chart-card-tools button { padding: 4px 9px; border: 0; border-bottom: 2px solid transparent; background: none; color: var(--muted); font: inherit; font-size: 12px; font-weight: 500; line-height: 14px; cursor: pointer; white-space: nowrap; }
.chart-card-tools button:hover, .chart-card-tools button.active { color: CanvasText; }
.chart-card-tools button.active { border-bottom-color: var(--accent); }
.chart-card-tools button:focus-visible, .cc-copy:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.cc-panel { display: none; height: 320px; overflow: auto; padding-top: 10px; }
.cc-panel.active { display: block; }
.cc-panel pre { margin: 0; padding: 16px; border: 1px solid var(--line); border-radius: 5px; background: light-dark(#f9fafb, #111827); font: 12px/1.6 ui-monospace, Menlo, monospace; overflow: auto; }
.cc-sql { position: relative; }
.cc-copy { position: absolute; top: 8px; right: 8px; padding: 3px 10px; border: 1px solid var(--line); border-radius: 4px; background: Canvas; color: inherit; font: inherit; font-size: 13px; cursor: pointer; }
.cc-info p { margin: 0 0 9px; font-size: 14px; }
.cc-status { min-height: 18px; margin: 6px 0 0; font-size: 12px; color: var(--muted); }
@media (max-width: 500px) { .chart-card-tools { right: 0; gap: 0; padding: 0 2px; } .chart-card-tools button { padding: 4px 6px; font-size: 11px; } }
footer { margin-top: 34px; padding-top: 14px; border-top: 1px solid var(--line); color: var(--muted); font-size: 12px; }
"""

JS = """
const D = JSON.parse(document.getElementById('brief-data').textContent);
const ink = getComputedStyle(document.body).color;
if (window.Chart) { Chart.defaults.color = ink; Chart.defaults.borderColor = 'rgba(128,128,128,.25)'; }
function safe(fn) { try { fn(); } catch (e) { console.error(e); } }
safe(function () { new Chart(document.getElementById('daily'), {
  type: 'bar',
  data: { labels: D.daily.map(r => r.day.slice(5)), datasets: [
    { type: 'bar', label: 'High tier', data: D.daily.map(r => r.high), backgroundColor: '#e8530e', stack: 's' },
    { type: 'bar', label: 'Medium tier', data: D.daily.map(r => r.medium), backgroundColor: '#f2b84b', stack: 's' },
    { type: 'line', label: 'Confirmed fraud (lags)', data: D.daily.map(r => r.confirmed), borderColor: '#7b61ff', backgroundColor: '#7b61ff', tension: .25, yAxisID: 'y' } ] },
  options: { responsive: true, maintainAspectRatio: false, scales: { x: { stacked: true }, y: { stacked: false, beginAtZero: true, title: { display: true, text: 'Transfers' } } }, plugins: { legend: { position: 'bottom' } } }
}); });
safe(function () { new Chart(document.getElementById('backlog'), {
  type: 'bar',
  data: { labels: D.backlog.map(r => r.queue), datasets: [
    { label: 'Open alerts', data: D.backlog.map(r => r.open), backgroundColor: '#29b5e8' },
    { label: 'Open over 30 days', data: D.backlog.map(r => r.over30), backgroundColor: '#e8530e' },
    { label: 'Unassigned', data: D.backlog.map(r => r.unassigned), backgroundColor: '#7b61ff' } ] },
  options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true } }, plugins: { legend: { position: 'bottom' } } }
}); });
document.querySelectorAll('.chart-card').forEach(function (card) {
  const buttons = card.querySelectorAll('[data-view]');
  const status = card.querySelector('.cc-status');
  buttons.forEach(function (button) {
    button.addEventListener('click', function () {
      buttons.forEach(function (b) { b.classList.toggle('active', b === button); b.setAttribute('aria-pressed', String(b === button)); });
      card.querySelectorAll('.cc-panel').forEach(function (p) { p.classList.toggle('active', p.dataset.panel === button.dataset.view); });
      status.textContent = '';
    });
  });
  const copy = card.querySelector('.cc-copy');
  if (copy) copy.addEventListener('click', function () {
    const declined = function () { status.textContent = 'SQL was not copied. Select it and copy it manually.'; };
    status.textContent = 'Confirm the copy in the dialog...';
    try { navigator.clipboard.writeText(card.querySelector('.cc-sql code').textContent).then(function () { status.textContent = 'SQL copied.'; }, declined); } catch (e) { declined(); }
  });
});
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--connection", default="AWS161")
    args = ap.parse_args()
    cur = snowflake.connector.connect(connection_name=args.connection, warehouse="RIA_FINANCIAL_WH").cursor()
    asof = cur.execute(f"SELECT {ASOF}").fetchone()[0]
    R = {k: run(cur, v) for k, v in SQL.items() if not k.startswith(("mules", "agents", "rings", "scam"))}
    F = {k: json.loads(cur.execute(SQL[k]).fetchone()[0]) for k in ("mules", "agents", "rings", "scam")}

    daily = R["daily"]
    day = daily[-1]
    prior = daily[-8:-1]
    avg = lambda key: sum(float(r[key]) for r in prior) / max(len(prior), 1)
    d_pct = lambda cur_v, base: "n/a" if not base else f"{(float(cur_v) - base) / base * 100:+.0f}% vs 7-day avg ({base:,.0f})"
    ato_c = R["ato_counts"][0]
    cs = R["cases"][0]
    sc = R["screening_counts"][0]
    bl = R["backlog"]
    open_alerts = sum(int(r["OPEN_ALERTS"]) for r in bl)
    over30 = sum(int(r["OPEN_OVER_30_DAYS"]) for r in bl)
    unassigned = sum(int(r["UNASSIGNED"]) for r in bl)
    sar = R["sar"]
    n_over, n_risk = int(R["sar_counts"][0]["OVERDUE"]), int(R["sar_counts"][0]["AT_RISK"])
    top = R["top_transfers"]
    paid_high = [r for r in top if r["FRAUD_RISK_TIER"] == "High" and r["STATUS"] in ("Paid", "Available for Pickup")]

    kpis = [
        ("Transfers", f"{int(day['TRANSFERS']):,}", d_pct(day["TRANSFERS"], avg("TRANSFERS")), False),
        ("Send volume", money(day["VOLUME_USD"]), d_pct(day["VOLUME_USD"], avg("VOLUME_USD")), False),
        ("High-tier transfers", f"{int(day['HIGH_TIER']):,}", d_pct(day["HIGH_TIER"], avg("HIGH_TIER")), True),
        ("High-tier value", money(day["HIGH_TIER_USD"]), "model-flagged, USD", True),
        ("Open alerts", f"{open_alerts:,}", f"{over30:,} over 30 days, {unassigned:,} unassigned", over30 > 0),
        ("SARs due in 10 days", f"{n_risk}", f"{n_over} already overdue", n_over > 0),
        ("High-tier ATO customers", f"{int(ato_c['HIGH_CUSTOMERS'])}", "last 2 days", True),
        ("Open sanctions hits", f"{int(sc['OPEN_HITS'])}", f"{int(sc['HIGH_TIER'])} High, {int(sc['MEDIUM_TIER'])} Medium tier", int(sc["HIGH_TIER"]) > 0),
    ]
    kpi_html = "".join(f'<div class="kpi{" alert" if a else ""}"><div class="label">{esc(l)}</div><div class="value">{esc(v)}</div><div class="delta">{esc(d)}</div></div>' for l, v, d, a in kpis)

    acts = []
    if paid_high:
        acts.append(f"Review the {len(paid_high)} High-tier transfers from the day that have already paid out or are waiting for pickup. Hold any still at the counter.")
    if int(ato_c["HIGH_CUSTOMERS"]):
        acts.append(f"Contact or restrict the {int(ato_c['HIGH_CUSTOMERS'])} customers with High-tier account-takeover sessions in the last two days, starting with the top of the list below.")
    if n_over or n_risk:
        acts.append(f"File or escalate the {n_over} overdue and {n_risk} at-risk SARs. The earliest is {sar[0]['FILING_ID']}, due {sar[0]['DUE_DATE']}.")
    if int(sc["HIGH_TIER"]):
        acts.append(f"Work the {int(sc['HIGH_TIER'])} High-tier sanctions hits first. Never clear a hit from a model score alone.")
    if over30:
        acts.append(f"Clear the {over30:,} alerts open past 30 days, led by {bl[0]['QUEUE']}.")
    acts_html = "".join(f"<li>{esc(a)}</li>" for a in acts[:5])

    top_tbl = table([("Transfer", lambda r: r["TRANSFER_ID"]), ("Customer", lambda r: r["CUSTOMER_ID"]), ("Corridor", lambda r: r["CORRIDOR_NAME"]),
                     ("Channel", lambda r: r["CHANNEL"]), ("Funded by", lambda r: r["FUNDING_TYPE"]), ("Amount", lambda r: money(r["SEND_AMOUNT_USD"])),
                     ("Probability", lambda r: pct(r["FRAUD_PROBABILITY"])), ("Tier", lambda r: r["FRAUD_RISK_TIER"]), ("Status", lambda r: r["STATUS"])], top)
    top_tbl = top_tbl.replace("<td>High</td>", f"<td>{tier('High')}</td>").replace("<td>Medium</td>", f"<td>{tier('Medium')}</td>").replace("<td>Low</td>", f"<td>{tier('Low')}</td>")
    ato_tbl = table([("Customer", lambda r: r["CUSTOMER_ID"]), ("Login", lambda r: str(r["LOGIN_AT"])[:16]), ("Probability", lambda r: pct(r["ATO_PROBABILITY"])), ("Tier", lambda r: r["ATO_RISK_TIER"]),
                     ("IP country", lambda r: r["IP_COUNTRY"]), ("New device", lambda r: "yes" if r["IS_NEW_DEVICE"] else "no"), ("Failed logins", lambda r: r["FAILED_ATTEMPTS"]),
                     ("Password reset", lambda r: "yes" if r["PASSWORD_RESET_24H"] else "no"), ("Beneficiary added", lambda r: "yes" if r["BENEFICIARY_ADDED"] else "no")], R["ato"])
    ato_tbl = ato_tbl.replace("<td>High</td>", f"<td>{tier('High')}</td>").replace("<td>Medium</td>", f"<td>{tier('Medium')}</td>")
    sar_tbl = table([("SAR", lambda r: r["FILING_ID"]), ("Activity", lambda r: r["ACTIVITY_TYPE"]), ("Status", lambda r: r["FILING_STATUS"]), ("Due", lambda r: r["DUE_DATE"]),
                     ("Days left", lambda r: ("OVERDUE" if r["IS_OVERDUE"] else r["DAYS_UNTIL_DUE"])), ("Amount", lambda r: money(r["AMOUNT_USD"]))], sar)
    scr_tbl = table([("Hit", lambda r: r["SCREENING_ID"]), ("List", lambda r: r["LIST_SOURCE"]), ("Party", lambda r: r["SCREENED_PARTY"]), ("Probability", lambda r: pct(r["TRUE_MATCH_PROBABILITY"])),
                     ("Tier", lambda r: r["TRIAGE_TIER"]), ("Match score", lambda r: r["MATCH_SCORE"]), ("Amount", lambda r: money(r["SEND_AMOUNT_USD"])), ("Hours open", lambda r: r["HOURS_OPEN"])], R["screening"])
    scr_tbl = scr_tbl.replace("<td>High</td>", f"<td>{tier('High')}</td>").replace("<td>Medium</td>", f"<td>{tier('Medium')}</td>").replace("<td>Low</td>", f"<td>{tier('Low')}</td>")
    mule_tbl = table([("Beneficiary", lambda r: r["beneficiary_id"]), ("Country", lambda r: r["country"]), ("Probability", lambda r: pct(r["mule_probability"])), ("Senders", lambda r: r["distinct_senders"]),
                      ("Transfers", lambda r: r["transfers_received"]), ("Received", lambda r: money(r["total_received_usd"]))], F["mules"]["top_beneficiaries"])
    agent_tbl = table([("Location", lambda r: r["agent_name"]), ("City", lambda r: f"{r['city']}, {r['country']}"), ("Probability", lambda r: pct(r["collusion_probability"])), ("Audit", lambda r: r["audit_rating"]),
                       ("Just-under-threshold sends", lambda r: f"{r['pct_sends_just_under_thresholds']}%"), ("Cancel rate", lambda r: f"{r['cancellation_rate_pct']}%")], F["agents"]["top_locations"])
    ring_tbl = table([("Cluster", lambda r: r["cluster_id"]), ("Accounts", lambda r: r["accounts_linked"]), ("Anomaly score", lambda r: r["cluster_anomaly_score"]), ("90-day volume", lambda r: money(r["volume_90d_usd"])),
                      ("Open cases", lambda r: r["open_cases"])], F["rings"]["top_clusters"])

    data = {
        "daily": [{"day": str(r["DAY"]), "high": int(r["HIGH_TIER"]), "medium": int(r["MEDIUM_TIER"]), "confirmed": int(r["CONFIRMED_FRAUD"])} for r in daily],
        "backlog": [{"queue": r["QUEUE"], "open": int(r["OPEN_ALERTS"]), "over30": int(r["OPEN_OVER_30_DAYS"]), "unassigned": int(r["UNASSIGNED"])} for r in bl],
    }
    daily_prev = table([("Day", lambda r: r["DAY"]), ("Transfers", lambda r: f"{int(r['TRANSFERS']):,}"), ("High", lambda r: r["HIGH_TIER"]), ("Medium", lambda r: r["MEDIUM_TIER"]), ("Confirmed fraud", lambda r: r["CONFIRMED_FRAUD"])], daily)
    back_prev = table([("Queue", lambda r: r["QUEUE"]), ("Open", lambda r: r["OPEN_ALERTS"]), ("Over 30 days", lambda r: r["OPEN_OVER_30_DAYS"]), ("Unassigned", lambda r: r["UNASSIGNED"])], bl)
    c1 = chart_card("daily", "Model-flagged transfers, last 14 days", SQL["daily"], daily_prev,
                    "<p><strong>What this shows:</strong> transfers per day that the transaction-fraud model put in the High or Medium tier, with confirmed fraud as a line.</p>"
                    "<p><strong>Source:</strong> RAW.TRANSFERS joined to ANALYTICS.TRANSFER_FRAUD_SCORES.</p>"
                    "<p><strong>Caveat:</strong> confirmed fraud lags by days, so the most recent days look low. Scores are predictions from a model trained on synthetic data.</p>", "flagged-transfers")
    c2 = chart_card("backlog", "Alert backlog by queue", SQL["backlog"], back_prev,
                    "<p><strong>What this shows:</strong> alerts not yet closed, how many have been open over 30 days, and how many have no analyst.</p>"
                    "<p><strong>Source:</strong> ANALYTICS.ALERT_DETAIL.</p><p><strong>Caveat:</strong> a closed alert is dropped, so this is the live backlog, not a history.</p>", "alert-backlog")

    scam = F["scam"]
    sections = [
        {"id": "actions", "title": "Do today", "producerNotes": "Built from the counts in the other sections; re-run scripts/build_daily_brief.py to refresh."},
        {"id": "flagged-transfers", "title": "Model-flagged transfers", "dataSources": [{"type": "query", "sql": SQL["daily"]}]},
        {"id": "top-transfers", "title": "Top transfers by fraud probability", "dataSources": [{"type": "query", "sql": SQL["top_transfers"]}]},
        {"id": "account-takeover", "title": "Account takeover", "dataSources": [{"type": "query", "sql": SQL["ato"]}, {"type": "query", "sql": SQL["ato_counts"]}]},
        {"id": "alert-backlog", "title": "Alert backlog", "dataSources": [{"type": "query", "sql": SQL["backlog"]}, {"type": "query", "sql": SQL["cases"]}]},
        {"id": "compliance", "title": "Compliance deadlines", "dataSources": [{"type": "query", "sql": SQL["sar"]}, {"type": "query", "sql": SQL["sar_counts"]}, {"type": "query", "sql": SQL["screening"]}, {"type": "query", "sql": SQL["ctr"]}]},
        {"id": "networks", "title": "Mules, agents and rings", "dataSources": [{"type": "query", "sql": SQL[k]} for k in ("mules", "agents", "rings", "scam")]},
    ]
    meta = {"generated": datetime.date.today().isoformat(), "intent": "Daily Fraud Brief for Ria Financial, generated from RIA_FINANCIAL_INTELLIGENCE", "asOfDay": str(asof),
            "dataSources": [{"type": "query", "sql": SQL["daily"]}], "sections": sections}

    meta_json = json.dumps(meta, indent=1).replace("</", "<\\/")
    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="snowflake-source" content="cortex-agent-authored" />
<title>Daily Fraud Brief {esc(asof)}</title>
<script type="application/json" id="snowflake-report-metadata">
{meta_json}
</script>
<style>{CSS}</style>
</head>
<body>
<div class="top"><img src="data:image/svg+xml;base64,{b64('ria_logo_no_person.svg')}" alt="Ria"><img src="data:image/svg+xml;base64,{b64('Snowflake_Logo.svg')}" alt="Snowflake"></div>
<div class="title"><h1>Daily Fraud Brief</h1><div class="asof">Data as of {esc(asof)} | built {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}</div></div>
<p class="note">Ria Financial cross-border transfers. All data is synthetic. Every risk tier and probability is a model prediction trained on synthetic data.</p>
<div class="kpis">{kpi_html}</div>
<div class="actions" id="actions"><h2>Do today</h2><ol>{acts_html}</ol></div>
{c1}
<h2 id="top-transfers">Top 10 transfers by fraud probability on {esc(asof)}</h2>
{top_tbl}
<p class="note">{len(paid_high)} of these High-tier transfers have already paid out or are awaiting pickup.</p>
<h2 id="account-takeover">Account takeover, last 2 days</h2>
<p class="note">{int(ato_c['HIGH_SESSIONS'])} High-tier sessions across {int(ato_c['HIGH_CUSTOMERS'])} customers. Highest-probability sessions:</p>
{ato_tbl}
{c2}
<p class="note">Cases: {int(cs['OPEN_CASES']):,} open, {int(cs['OPEN_P1'])} priority P1, {int(cs['PENDING_SAR_DECISION'])} waiting on a SAR decision, {int(cs['OPEN_OVER_30_DAYS'])} open over 30 days.</p>
<h2 id="compliance">Compliance deadlines</h2>
<h3>SARs overdue or due within 10 days</h3>
{sar_tbl}
<p class="note">Showing the earliest 10 of {n_over + n_risk} overdue or at-risk SARs.</p>
<p class="note">{int(R['ctr'][0]['PENDING_CTR'])} CTRs are pending filing.</p>
<h3 style="margin-top:18px">Open sanctions hits to work first</h3>
{scr_tbl}
<p class="note">{int(sc['OPEN_HITS'])} hits are open. A model score never clears a hit.</p>
<h2 id="networks">Mules, agents and rings</h2>
<div class="grid2"><div><h3>Likely money mules</h3>{mule_tbl}<p class="note">{F['mules']['high_tier_beneficiaries']:,} High-tier beneficiaries received {money(F['mules']['high_tier_total_received_usd'])}.</p></div>
<div><h3>Agent locations, collusion risk</h3>{agent_tbl}<p class="note">{F['agents']['high_tier_locations']} locations are High tier.</p></div></div>
<h3 style="margin-top:18px">Largest suspected fraud rings</h3>
{ring_tbl}
<p class="note">{F['rings']['clusters_of_3_or_more_accounts']} clusters of 3 or more accounts share a phone number. Scam-victim model, last 7 days: {scam['high_tier_transfers']} High-tier transfers worth {money(scam['high_tier_volume_usd'])}.</p>
<footer>Source: {DB} (RAW and ANALYTICS), Snowflake account AWS161. Model scores come from the registered RIA_* models. Confirmed fraud is an investigation outcome and lags several days. Refresh with <code>python scripts/build_daily_brief.py</code>.</footer>
<script id="brief-data" type="application/json">{json.dumps(data)}</script>
<script src="/libs/chart.js@4.4.4/chart.umd.js"></script>
<script>{JS}</script>
</body>
</html>
"""
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(page)
    print("wrote", OUT, f"{len(page):,} bytes | as of {asof} | actions {len(acts)}")


if __name__ == "__main__":
    main()
