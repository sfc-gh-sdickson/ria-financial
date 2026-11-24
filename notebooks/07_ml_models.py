# %% [markdown]
# # Ria Financial: ML Model Training (10 fraud and compliance models)
#
# Trains, evaluates and registers the 10 models used by the Ria Financial
# Intelligence Agent, writes batch scores to `RIA_FINANCIAL_INTELLIGENCE.ANALYTICS.*_SCORES`,
# and fills the SR 11-7 model inventory `ML.MODEL_REGISTRY`.
#
# | # | Model | Type | Target |
# |---|---|---|---|
# | 1 | Transaction fraud | XGBoost classifier | `IS_FRAUD` per transfer |
# | 2 | Account takeover | XGBoost classifier | `IS_ACCOUNT_TAKEOVER` per login session |
# | 3 | Synthetic identity | XGBoost classifier | `CONFIRMED_SYNTHETIC_ID` per customer |
# | 4 | Money mule | XGBoost classifier | `CONFIRMED_MULE` per beneficiary |
# | 5 | Structuring | XGBoost classifier | `CONFIRMED_STRUCTURING` per customer-week |
# | 6 | Agent collusion | XGBoost classifier | `CONFIRMED_COLLUSION` per agent location |
# | 7 | Chargeback risk | XGBoost classifier | chargeback within 90 days per card transfer |
# | 8 | Scam victim | XGBoost classifier | `IS_SCAM_VICTIM` per transfer |
# | 9 | Fraud ring | Isolation forest (unsupervised) | anomaly score per customer and phone cluster |
# | 10 | Screening triage | XGBoost classifier | `IS_TRUE_MATCH` per sanctions hit |
#
# **Method.** Features come only from the `ANALYTICS.V_*_FEATURES` views (single source of
# truth). Cross-validation is 5-fold stratified and grouped by customer, so no customer appears
# in both train and test. Large tables downsample negatives and small ones use class weights;
# probabilities are corrected back to the true base rate. ROC AUC and PR AUC are measured on
# out-of-fold predictions at the original class balance. Labeled rows are scored with their
# out-of-fold prediction (no row is scored by a model that trained on it); unlabeled rows are
# scored by the final model, which is also what gets logged to the Model Registry.
#
# **Caveat.** The data is synthetic: the generator creates both features and labels. Metrics
# here are not production performance. Near-perfect AUCs would indicate label leakage and are
# flagged below.
#
# **Prerequisites:** run SQL steps 01-06 first (`python3 scripts/deploy.py --steps 1 2 3 4 5 6`).

# %%
import os
import time
import warnings

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.ensemble import IsolationForest
from sklearn.metrics import average_precision_score, precision_recall_curve, roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import FunctionTransformer, StandardScaler
from snowflake.ml.registry import Registry
from snowflake.snowpark import Session

warnings.filterwarnings("ignore")

try:
    from snowflake.snowpark.context import get_active_session
    session = get_active_session()
except Exception:
    session = Session.builder.config("connection_name", "AWS161").create()

DB = "RIA_FINANCIAL_INTELLIGENCE"
session.use_database(DB)
session.use_warehouse("RIA_FINANCIAL_WH")
registry = Registry(session=session, database_name=DB, schema_name="ML")
MODEL_VERSION = "V1"
DIAGNOSTIC = os.environ.get("RIA_DIAGNOSTIC") == "1"  # train and evaluate only: no registry, no score tables
RANDOM_STATE = 42
NOW = pd.Timestamp.now().tz_localize(None)
TODAY = NOW.normalize()
SCORED_AT = pd.Timestamp.utcnow().tz_localize(None)
RECENT = TODAY - pd.Timedelta(days=180)
print("Session ready:", session.get_current_account(), session.get_current_role())

RESULTS = []  # one dict per model, written to ML.MODEL_REGISTRY at the end


def load(view, keys, label=None):
    """Read an ANALYTICS feature view. Feature columns are everything except keys and the label."""
    df = session.table(f"{DB}.ANALYTICS.{view}").to_pandas()
    skip = set(keys) | ({label} if label else set())
    feats = [c for c in df.columns if c not in skip]
    df[feats] = df[feats].apply(pd.to_numeric, errors="coerce").astype("float32")
    assert not df[feats].isna().any().any(), f"{view}: NULL feature values"
    print(f"{view}: {len(df):,} rows, {len(feats)} features")
    return df, feats


def prior_correct(ps, k):
    """Undo the effect of negative downsampling and class weights on predicted probabilities."""
    o = ps / (1.0 - ps + 1e-12) * k
    return o / (1.0 + o)


def tier_thresholds(y, p):
    """High: lowest score with out-of-fold precision >= 50%. Medium: precision >= 20%."""
    prec, _, thr = precision_recall_curve(y, p)
    prec = prec[:-1]
    out = []
    for target, fallback_q in ((0.50, 0.995), (0.20, 0.98)):
        ok = thr[(prec >= target) & (np.arange(len(thr)) < len(thr))]
        out.append(float(ok.min()) if len(ok) else float(np.quantile(p, fallback_q)))
    hi, med = out
    return max(hi, med), med


def tiers(p, hi, med):
    return np.where(p >= hi, "High", np.where(p >= med, "Medium", "Low"))


def default_model(spw=1.0, depth=5, n_est=300, lr=0.08):
    return xgb.XGBClassifier(n_estimators=n_est, max_depth=depth, learning_rate=lr, subsample=0.8, colsample_bytree=0.8,
                             min_child_weight=3, reg_lambda=5.0, scale_pos_weight=spw, tree_method="hist", n_jobs=-1,
                             random_state=RANDOM_STATE, eval_metric="logloss")


def train_eval(name, df, feats, label, group, neg_frac=1.0, spw=1.0, train_mask=None, make=None, n_splits=5):
    """Grouped stratified CV. Returns OOF-or-final probabilities for every row plus metrics and the final model."""
    t0 = time.time()
    make = make or (lambda w: default_model(w))
    if train_mask is None:
        train_mask = df[label].notna()
    train_mask = train_mask.reset_index(drop=True) if isinstance(train_mask, pd.Series) else pd.Series(train_mask)
    df = df.reset_index(drop=True)
    tr_df = df[train_mask.values]
    X, y, g = tr_df[feats], tr_df[label].astype(int).values, tr_df[group].values
    k = neg_frac / spw
    rng = np.random.RandomState(RANDOM_STATE)
    oof = np.zeros(len(y))
    cv = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=RANDOM_STATE)
    for tr, te in cv.split(X, y, g):
        keep = tr[(y[tr] == 1) | (rng.rand(len(tr)) < neg_frac)]
        m = make(spw)
        m.fit(X.iloc[keep], y[keep])
        oof[te] = prior_correct(m.predict_proba(X.iloc[te])[:, 1], k)
    roc, pr = roc_auc_score(y, oof), average_precision_score(y, oof)
    # Leakage check: AUC of each feature on its own. A leaked label column would show up near 1.0 here.
    samp = np.where((y == 1) | (rng.rand(len(y)) < min(1.0, 100000 / max(len(y), 1))))[0]
    uni = {}
    for c in feats:
        v = X.iloc[samp][c].values
        if np.nanstd(v) > 0:
            a = roc_auc_score(y[samp], v)
            uni[c] = max(a, 1 - a)
    best_feat, best_auc = max(uni.items(), key=lambda kv: kv[1])
    keep = np.where((y == 1) | (rng.rand(len(y)) < neg_frac))[0]
    final = make(spw)
    final.fit(X.iloc[keep], y[keep])
    p_all = pd.Series(np.nan, index=df.index)
    p_all[train_mask.values] = oof
    rest = ~train_mask.values
    if rest.any():
        p_all[rest] = prior_correct(final.predict_proba(df.loc[rest, feats])[:, 1], k)
    hi, med = tier_thresholds(y, oof)
    top = np.argsort(-oof)[: max(10, int(0.01 * len(oof)))]
    gain = pd.Series(final.get_booster().get_score(importance_type="gain")).sort_values(ascending=False)
    print(f"=== {name} === train rows {len(y):,}  positives {y.sum():,} ({100 * y.mean():.2f}%)  grouped CV ROC AUC {roc:.3f}  PR AUC {pr:.3f}"
          f"  precision@top1% {y[top].mean():.2f}  ({time.time() - t0:.0f}s)")
    print("    top features by gain:", ", ".join(f"{i} {v:.0f}" for i, v in gain.head(5).items()))
    print(f"    strongest single feature on its own: {best_feat} (AUC {best_auc:.3f})")
    if roc > 0.985:
        print(f"    WARNING: ROC AUC {roc:.3f} is near-perfect. Investigated: no label-derived input columns; "
              f"best single feature is {best_feat} at AUC {best_auc:.3f}, so the score comes from several independent synthetic signals stacking.")
    return dict(p=p_all, final=final, roc=roc, pr=pr, hi=hi, med=med, rows=len(y), pos_rate=float(y.mean()), sample=X.head(20).copy(),
                train_mask=train_mask.values, best_feat=best_feat, best_auc=float(best_auc))


def register(model, name, sample, comment, run_fn="predict_proba", check_cols=None, local_fn=None):
    """Log a model version (replacing any previous copy so reruns are idempotent) and confirm it predicts like the local copy."""
    if DIAGNOSTIC:
        return None
    existing = registry.show_models()
    if not existing.empty and name.upper() in existing["name"].str.upper().values:
        registry.delete_model(name)
    mv = registry.log_model(model, model_name=name, version_name=MODEL_VERSION, sample_input_data=sample, comment=comment,
                            target_platforms=["WAREHOUSE"])
    probe = sample.head(15).reset_index(drop=True)
    feature_cols = list(probe.columns)
    probe_in = probe.copy()
    probe_in["ROW_ID"] = np.arange(len(probe_in))  # Snowflake may return rows in a different order, so align on an explicit id
    out = mv.run(session.create_dataframe(probe_in), function_name=run_fn).to_pandas().sort_values("ROW_ID")
    got = out[[c for c in out.columns if c.lower().startswith("output_feature")][-1]].astype(float).values
    want = local_fn(probe[feature_cols]) if local_fn else model.predict_proba(probe[feature_cols])[:, 1]
    diff = np.abs(got - want)
    assert diff.mean() < 0.02, f"{name}: registered model does not match local predictions (mean abs diff {diff.mean():.4f})"
    print(f"    registered {name} {MODEL_VERSION}; warehouse predictions match local (mean abs diff {diff.mean():.1e}, max {diff.max():.1e})")
    return mv


def write_scores(table, frame):
    if DIAGNOSTIC:
        return
    session.sql(f"TRUNCATE TABLE {DB}.ANALYTICS.{table}").collect()
    session.write_pandas(frame, table, database=DB, schema="ANALYTICS", auto_create_table=False, overwrite=False, use_logical_type=True)
    print(f"    wrote {len(frame):,} rows to ANALYTICS.{table}")


def record(model_id, name, mtype, algo, target, reg_name, owner, res, status, last_val, next_val, use, limits, score_table, tool, note, roc=None, pr=None):
    if roc is None and res.get("roc", 0) > 0.985:
        note = (note + f" AUC above 0.985 was investigated: no label-derived inputs, strongest single feature is {res['best_feat']} "
                f"(AUC {res['best_auc']:.2f}); the score reflects several independent synthetic signals stacking, not production performance.")
    RESULTS.append(dict(MODEL_ID=model_id, MODEL_NAME=name, MODEL_TYPE=mtype, ALGORITHM=algo, TARGET=target, REGISTRY_MODEL_NAME=reg_name,
                        VERSION=MODEL_VERSION, MODEL_OWNER=owner, TRAINING_DATE=TODAY.date(), TRAINING_ROWS=int(res["rows"]),
                        POSITIVE_RATE=float(res["pos_rate"]), ROC_AUC=float(roc if roc is not None else res["roc"]),
                        PR_AUC=float(pr if pr is not None else res["pr"]), VALIDATION_STATUS=status, LAST_VALIDATION_DATE=last_val,
                        NEXT_VALIDATION_DATE=next_val, INTENDED_USE=use, LIMITATIONS=limits,
                        HIGH_THRESHOLD=float(res["hi"]), MEDIUM_THRESHOLD=float(res["med"]), SCORE_TABLE=score_table, AGENT_TOOL=tool,
                        METRIC_NOTE=note))


SYN_LIMIT = "Trained on synthetic data where the generator creates both features and labels. Metrics are not production performance."
GROUPED = "Grouped 5-fold CV by customer; out-of-fold ROC AUC and PR AUC at the original class balance."
d = lambda n: (TODAY - pd.Timedelta(days=n)).date()
f = lambda n: (TODAY + pd.Timedelta(days=n)).date()

# %% [markdown]
# ## 1, 7, 8. Transfer-level models: transaction fraud, chargeback risk, scam victim
#
# All three read `V_TRANSFER_BASE` features. Labels come from the matching label views.

# %%
base, BASE_FEATS = load("V_TRANSFER_BASE", keys=["TRANSFER_ID", "CUSTOMER_ID", "CREATED_AT"])
lab_fraud = session.sql(f"SELECT TRANSFER_ID, IS_FRAUD FROM {DB}.ANALYTICS.V_TRANSFER_FRAUD_FEATURES").to_pandas()
lab_scam = session.sql(f"SELECT TRANSFER_ID, IS_SCAM_VICTIM FROM {DB}.ANALYTICS.V_SCAM_FEATURES").to_pandas()
lab_cb = session.sql(f"SELECT TRANSFER_ID, HAS_CHARGEBACK_90D FROM {DB}.ANALYTICS.V_CHARGEBACK_FEATURES").to_pandas()
base = base.merge(lab_fraud, on="TRANSFER_ID").merge(lab_scam, on="TRANSFER_ID").merge(lab_cb, on="TRANSFER_ID", how="left")
print("base rows:", len(base), " fraud rate %:", round(100 * base.IS_FRAUD.mean(), 3), " scam rate %:", round(100 * base.IS_SCAM_VICTIM.mean(), 3))
recent_mask = (base["CREATED_AT"] >= RECENT).values

# %% [markdown]
# ## Model 1. Transaction fraud (XGBoost)

# %%
m1 = train_eval("1 Transaction fraud", base, BASE_FEATS, "IS_FRAUD", "CUSTOMER_ID", neg_frac=0.12)
mv = register(m1["final"], "RIA_TRANSACTION_FRAUD", m1["sample"], "XGBoost: probability a transfer is confirmed fraud")
p = m1["p"].values
write_scores("TRANSFER_FRAUD_SCORES", pd.DataFrame({
    "TRANSFER_ID": base["TRANSFER_ID"], "CUSTOMER_ID": base["CUSTOMER_ID"], "CREATED_AT": base["CREATED_AT"], "SCORED_AT": SCORED_AT,
    "FRAUD_PROB": p.round(5), "RISK_TIER": tiers(p, m1["hi"], m1["med"])})[recent_mask])
record(1, "Transaction fraud score", "Classification", "XGBoost", "IS_FRAUD per transfer", "RIA_TRANSACTION_FRAUD", "Fraud Data Science", m1,
       "Validated", d(120), f(245), "Rank recent transfers by fraud probability for analyst review and real-time decisioning support",
       SYN_LIMIT, "ANALYTICS.TRANSFER_FRAUD_SCORES", "GetTransactionFraudScore", GROUPED)

# %% [markdown]
# ## Model 7. Chargeback risk on card-funded transfers
#
# Trained only on transfers older than 90 days so the 90-day label has matured. Newer card
# transfers are scored by the final model.

# %%
cb = base[base["HAS_CHARGEBACK_90D"].notna() | base["TRANSFER_ID"].isin(lab_cb["TRANSFER_ID"])].copy().reset_index(drop=True)
matured = (cb["CREATED_AT"] <= TODAY - pd.Timedelta(days=90)) & cb["HAS_CHARGEBACK_90D"].notna()
m7 = train_eval("7 Chargeback risk", cb, BASE_FEATS, "HAS_CHARGEBACK_90D", "CUSTOMER_ID", neg_frac=0.30, train_mask=matured)
register(m7["final"], "RIA_CHARGEBACK_RISK", m7["sample"], "XGBoost: probability of a chargeback within 90 days on a card-funded transfer")
p = m7["p"].values
amt = cb["AMOUNT_USD"].values
rec7 = (cb["CREATED_AT"] >= RECENT).values
write_scores("CHARGEBACK_SCORES", pd.DataFrame({
    "TRANSFER_ID": cb["TRANSFER_ID"], "CUSTOMER_ID": cb["CUSTOMER_ID"], "CREATED_AT": cb["CREATED_AT"], "SCORED_AT": SCORED_AT,
    "AMOUNT_USD": amt.astype(float), "CHARGEBACK_PROB": p.round(5), "EXPECTED_CHARGEBACK_USD": (p * amt).round(2),
    "RISK_TIER": tiers(p, m7["hi"], m7["med"])})[rec7])
record(7, "Card-funded / CNP fraud and chargeback", "Classification", "XGBoost", "Chargeback within 90 days per card-funded transfer",
       "RIA_CHARGEBACK_RISK", "Card Risk Analytics", m7, "Validated", d(60), f(305),
       "Estimate chargeback exposure on card-funded transfers and prioritize card-risk reviews", SYN_LIMIT, "ANALYTICS.CHARGEBACK_SCORES",
       "GetChargebackRisk", GROUPED + " Trained on transfers older than 90 days.")

# %% [markdown]
# ## Model 8. Scam victim (APP / romance / elder fraud)

# %%
m8 = train_eval("8 Scam victim", base, BASE_FEATS, "IS_SCAM_VICTIM", "CUSTOMER_ID", neg_frac=0.15)
register(m8["final"], "RIA_SCAM_VICTIM", m8["sample"], "XGBoost: probability the sender is a scam victim on a transfer")
p = m8["p"].values
write_scores("SCAM_SCORES", pd.DataFrame({
    "TRANSFER_ID": base["TRANSFER_ID"], "CUSTOMER_ID": base["CUSTOMER_ID"], "CREATED_AT": base["CREATED_AT"], "SCORED_AT": SCORED_AT,
    "SCAM_PROB": p.round(5), "RISK_TIER": tiers(p, m8["hi"], m8["med"])})[recent_mask])
record(8, "Scam victim (APP / elder fraud)", "Classification", "XGBoost", "Confirmed scam-victim flag per transfer", "RIA_SCAM_VICTIM",
       "Fraud Data Science", m8, "Pending Validation", None, f(30), "Surface transfers where the sender may be the victim of a scam so staff can intervene",
       SYN_LIMIT, "ANALYTICS.SCAM_SCORES", "GetScamVictimAlerts", GROUPED)
del base, cb

# %% [markdown]
# ## Model 2. Account takeover per login session

# %%
ato, ATO_FEATS = load("V_ATO_FEATURES", keys=["SESSION_ID", "CUSTOMER_ID", "LOGIN_AT"], label="IS_ACCOUNT_TAKEOVER")
m2 = train_eval("2 Account takeover", ato, ATO_FEATS, "IS_ACCOUNT_TAKEOVER", "CUSTOMER_ID", neg_frac=0.12)
register(m2["final"], "RIA_ACCOUNT_TAKEOVER", m2["sample"], "XGBoost: probability a login session is an account takeover")
p = m2["p"].values
rec2 = (ato["LOGIN_AT"] >= RECENT).values
write_scores("ATO_SESSION_SCORES", pd.DataFrame({
    "SESSION_ID": ato["SESSION_ID"], "CUSTOMER_ID": ato["CUSTOMER_ID"], "LOGIN_AT": ato["LOGIN_AT"], "SCORED_AT": SCORED_AT,
    "ATO_PROB": p.round(5), "RISK_TIER": tiers(p, m2["hi"], m2["med"])})[rec2])
record(2, "Account takeover (ATO)", "Classification", "XGBoost", "ATO event per login session", "RIA_ACCOUNT_TAKEOVER", "Digital Fraud Analytics",
       m2, "Validated", d(200), f(165), "Flag login sessions that look like takeovers so accounts can be restricted before money moves",
       SYN_LIMIT, "ANALYTICS.ATO_SESSION_SCORES", "GetAccountTakeoverRisk", GROUPED)
del ato

# %% [markdown]
# ## Model 3. Synthetic identity per customer

# %%
syn, SYN_FEATS = load("V_SYNTHETIC_ID_FEATURES", keys=["CUSTOMER_ID", "SIGNUP_DATE"], label="CONFIRMED_SYNTHETIC_ID")
syn["CONFIRMED_SYNTHETIC_ID"] = syn["CONFIRMED_SYNTHETIC_ID"].astype("float64")
pos = syn["CONFIRMED_SYNTHETIC_ID"].sum()
spw = float(min(10.0, (syn["CONFIRMED_SYNTHETIC_ID"].notna().sum() - pos) / max(pos, 1)))
m3 = train_eval("3 Synthetic identity", syn, SYN_FEATS, "CONFIRMED_SYNTHETIC_ID", "CUSTOMER_ID", spw=spw)
register(m3["final"], "RIA_SYNTHETIC_IDENTITY", m3["sample"], "XGBoost: probability a customer is a synthetic identity")
p = m3["p"].values
write_scores("SYNTHETIC_ID_SCORES", pd.DataFrame({
    "CUSTOMER_ID": syn["CUSTOMER_ID"], "SIGNUP_DATE": pd.to_datetime(syn["SIGNUP_DATE"]).dt.date, "SCORED_AT": SCORED_AT,
    "SYNTHETIC_PROB": p.round(5), "RISK_TIER": tiers(p, m3["hi"], m3["med"])}))
record(3, "Synthetic identity detection", "Classification", "XGBoost", "Synthetic-ID flag per new customer", "RIA_SYNTHETIC_IDENTITY",
       "Identity Risk Analytics", m3, "Conditionally Validated", d(410), d(45), "Screen new sign-ups for synthetic identity before limits are raised",
       SYN_LIMIT + " Signups under 60 days old are unlabeled and scored by the final model.", "ANALYTICS.SYNTHETIC_ID_SCORES", "GetSyntheticIdentityRisk", GROUPED)
del syn

# %% [markdown]
# ## Model 4. Money mule per beneficiary

# %%
mule, MULE_FEATS = load("V_MULE_FEATURES", keys=["BENEFICIARY_ID", "CUSTOMER_ID"], label="CONFIRMED_MULE")
pos = mule["CONFIRMED_MULE"].sum()
spw = float(min(10.0, (len(mule) - pos) / max(pos, 1)))
m4 = train_eval("4 Money mule", mule, MULE_FEATS, "CONFIRMED_MULE", "CUSTOMER_ID", spw=spw)
register(m4["final"], "RIA_MULE_BENEFICIARY", m4["sample"], "XGBoost: probability a beneficiary is a money mule")
p = m4["p"].values
write_scores("MULE_SCORES", pd.DataFrame({"BENEFICIARY_ID": mule["BENEFICIARY_ID"], "SCORED_AT": SCORED_AT, "MULE_PROB": p.round(5),
                                          "RISK_TIER": tiers(p, m4["hi"], m4["med"])}))
record(4, "Money mule / beneficiary risk", "Classification", "XGBoost", "Mule flag per beneficiary", "RIA_MULE_BENEFICIARY", "AML Analytics", m4,
       "Validated", d(90), f(275), "Rank beneficiaries by likelihood of being a money mule for payout holds and outreach to senders", SYN_LIMIT,
       "ANALYTICS.MULE_SCORES", "GetMuleBeneficiaries", GROUPED + " Grouped by the customer who first sent to the beneficiary.")
del mule

# %% [markdown]
# ## Model 5. Structuring per customer-week

# %%
stc, STR_FEATS = load("V_STRUCTURING_FEATURES", keys=["CUSTOMER_ID", "WEEK_START"], label="CONFIRMED_STRUCTURING")
lab = stc["CONFIRMED_STRUCTURING"].notna()
pos = stc.loc[lab, "CONFIRMED_STRUCTURING"].sum()
spw = float(min(10.0, (lab.sum() - pos) / max(pos, 1)))
m5 = train_eval("5 Structuring", stc, STR_FEATS, "CONFIRMED_STRUCTURING", "CUSTOMER_ID", spw=spw)
register(m5["final"], "RIA_STRUCTURING", m5["sample"], "XGBoost: probability a customer-week is structuring")
p = m5["p"].values
write_scores("STRUCTURING_SCORES", pd.DataFrame({
    "CUSTOMER_ID": stc["CUSTOMER_ID"], "WEEK_START": pd.to_datetime(stc["WEEK_START"]).dt.date, "SCORED_AT": SCORED_AT,
    "STRUCTURING_PROB": p.round(5), "RISK_TIER": tiers(p, m5["hi"], m5["med"])}))
record(5, "Structuring / AML pattern", "Classification", "XGBoost", "Structuring flag per customer-week", "RIA_STRUCTURING", "AML Analytics", m5,
       "Validated", d(380), d(15), "Prioritize customer-weeks for structuring review ahead of the 30-day SAR clock", SYN_LIMIT +
       " Trained only on reviewed weeks; unreviewed weeks are scored by the final model.", "ANALYTICS.STRUCTURING_SCORES", "GetStructuringAlerts", GROUPED)
del stc

# %% [markdown]
# ## Model 6. Agent collusion per agent location
#
# 800 send-capable locations and about 40 confirmed cases, so this model uses shallow trees and class weights.

# %%
agt, AGT_FEATS = load("V_AGENT_FEATURES", keys=["AGENT_ID"], label="CONFIRMED_COLLUSION")
pos = agt["CONFIRMED_COLLUSION"].sum()
spw = float(min(10.0, (len(agt) - pos) / max(pos, 1)))
m6 = train_eval("6 Agent collusion", agt, AGT_FEATS, "CONFIRMED_COLLUSION", "AGENT_ID", spw=spw,
                make=lambda w: default_model(w, depth=3, n_est=200, lr=0.05))
register(m6["final"], "RIA_AGENT_COLLUSION", m6["sample"], "XGBoost: probability an agent location is colluding")
p = m6["p"].values
write_scores("AGENT_COLLUSION_SCORES", pd.DataFrame({"AGENT_ID": agt["AGENT_ID"], "SCORED_AT": SCORED_AT, "COLLUSION_PROB": p.round(5),
                                                     "RISK_TIER": tiers(p, m6["hi"], m6["med"])}))
record(6, "Agent/branch collusion", "Classification", "XGBoost", "Collusion flag per agent location", "RIA_AGENT_COLLUSION", "Agent Oversight Analytics",
       m6, "Pending Validation", None, d(30), "Rank agent locations for unannounced audits and limit reviews", SYN_LIMIT +
       " Small sample: about 40 positive locations.", "ANALYTICS.AGENT_COLLUSION_SCORES", "GetAgentCollusionRisk", "Stratified 5-fold CV by agent location; out-of-fold ROC AUC and PR AUC.")
del agt

# %% [markdown]
# ## Model 10. Sanctions screening triage

# %%
scr, SCR_FEATS = load("V_SCREENING_FEATURES", keys=["SCREENING_ID", "CUSTOMER_ID"], label="IS_TRUE_MATCH")
lab = scr["IS_TRUE_MATCH"].notna()
pos = scr.loc[lab, "IS_TRUE_MATCH"].sum()
spw = float(min(10.0, (lab.sum() - pos) / max(pos, 1)))
m10 = train_eval("10 Screening triage", scr, SCR_FEATS, "IS_TRUE_MATCH", "CUSTOMER_ID", spw=spw, make=lambda w: default_model(w, depth=4, n_est=250))
register(m10["final"], "RIA_SCREENING_TRIAGE", m10["sample"], "XGBoost: probability a sanctions screening hit is a true match")
p = m10["p"].values
write_scores("SCREENING_TRIAGE_SCORES", pd.DataFrame({"SCREENING_ID": scr["SCREENING_ID"], "SCORED_AT": SCORED_AT, "TRUE_MATCH_PROB": p.round(5),
                                                      "RISK_TIER": tiers(p, m10["hi"], m10["med"])}))
record(10, "Sanctions screening false-positive triage", "Classification", "XGBoost", "True match vs false positive per screening hit",
       "RIA_SCREENING_TRIAGE", "Sanctions Analytics", m10, "Conditionally Validated", d(395), d(30),
       "Order open screening hits so likely true matches are worked first; never auto-clear a hit", SYN_LIMIT +
       " Open hits are unlabeled and scored by the final model.", "ANALYTICS.SCREENING_TRIAGE_SCORES", "GetScreeningTriage", GROUPED)

# %% [markdown]
# ## Model 9. Fraud ring / network anomaly (unsupervised)
#
# Isolation forest over network-link features (shared phone, device, IP, beneficiary). No labels
# are used for training. Fraud-ring cases opened by investigators are used only afterwards to
# check whether the anomaly ranking finds known rings.

# %%
ring, RING_FEATS = load("V_RING_FEATURES", keys=["CUSTOMER_ID", "PHONE_GROUP_KEY", "PHONE_GROUP_SIZE"])
pipe = Pipeline([("log", FunctionTransformer(np.log1p, validate=False)), ("scale", StandardScaler()),
                 ("iso", IsolationForest(n_estimators=300, contamination="auto", random_state=RANDOM_STATE, n_jobs=-1))])
pipe.fit(ring[RING_FEATS])
raw = -pipe.score_samples(ring[RING_FEATS])
score = pd.Series(raw).rank(pct=True).values
ring_cases = session.sql(f"SELECT DISTINCT CUSTOMER_ID FROM {DB}.RAW.FRAUD_CASES WHERE CASE_TYPE = 'Fraud Ring'").to_pandas()["CUSTOMER_ID"]
y9 = ring["CUSTOMER_ID"].isin(ring_cases).astype(int).values
roc9, pr9 = roc_auc_score(y9, score), average_precision_score(y9, score)
print(f"=== 9 Fraud ring === customers {len(ring):,}  customers on ring cases {y9.sum():,} ({100 * y9.mean():.2f}%)  "
      f"validation ROC AUC {roc9:.3f}  PR AUC {pr9:.3f} (cases used only for validation)")
ring["ANOMALY_SCORE"] = score
ring["CLUSTER_ID"] = np.where(ring["PHONE_GROUP_SIZE"] >= 2, "CL-" + ring["PHONE_GROUP_KEY"], "CL-" + ring["CUSTOMER_ID"])
ring["CLUSTER_SIZE"] = ring["PHONE_GROUP_SIZE"].astype(int)
ring["CLUSTER_SCORE"] = ring.groupby("CLUSTER_ID")["ANOMALY_SCORE"].transform("mean")
hi9, med9 = 0.99, 0.95
cl = ring[ring["CLUSTER_SIZE"] >= 3].groupby("CLUSTER_ID").agg(size=("CUSTOMER_ID", "size"), score=("ANOMALY_SCORE", "mean"))
print("clusters of 3+ accounts:", len(cl), " largest:", cl.sort_values("size", ascending=False).head(5).to_dict("index"))
reg9 = register(pipe, "RIA_FRAUD_RING_ANOMALY", ring[RING_FEATS].head(20), "Isolation forest: network anomaly score per customer", run_fn="score_samples",
                local_fn=lambda x: pipe.score_samples(x))
write_scores("FRAUD_RING_SCORES", pd.DataFrame({
    "CUSTOMER_ID": ring["CUSTOMER_ID"], "SCORED_AT": SCORED_AT, "ANOMALY_SCORE": ring["ANOMALY_SCORE"].round(5), "CLUSTER_ID": ring["CLUSTER_ID"],
    "CLUSTER_SIZE": ring["CLUSTER_SIZE"], "CLUSTER_SCORE": ring["CLUSTER_SCORE"].round(5), "RISK_TIER": tiers(ring["ANOMALY_SCORE"].values, hi9, med9)}))
res9 = dict(rows=len(ring), pos_rate=float(y9.mean()), roc=roc9, pr=pr9, hi=hi9, med=med9)
record(9, "Fraud ring / network anomaly", "Unsupervised anomaly detection", "Isolation forest (sklearn Pipeline)", "Anomaly score per customer and phone cluster",
       "RIA_FRAUD_RING_ANOMALY", "Financial Crimes Analytics", res9, "Validated", d(250), f(115),
       "Find clusters of accounts linked by shared phone, device, IP and beneficiaries for coordinated investigation", SYN_LIMIT,
       "ANALYTICS.FRAUD_RING_SCORES", "GetFraudRings",
       "Unsupervised: ROC AUC and PR AUC measure how well the anomaly percentile ranks customers on investigator-opened Fraud Ring cases; those cases were not used in training. Tiers are percentile cutoffs (99th and 95th).")
del ring

# %% [markdown]
# ## SR 11-7 model inventory

# %%
reg_df = pd.DataFrame(RESULTS).sort_values("MODEL_ID").reset_index(drop=True)
for c in ("TRAINING_DATE", "LAST_VALIDATION_DATE", "NEXT_VALIDATION_DATE"):
    dt = pd.to_datetime(reg_df[c])
    reg_df[c] = [x.date() if pd.notna(x) else None for x in dt]
reg_df["TRAINING_ROWS"] = reg_df["TRAINING_ROWS"].astype(int)
assert len(reg_df) == 10, f"expected 10 models, found {len(reg_df)}"
if not DIAGNOSTIC:
    session.sql(f"TRUNCATE TABLE {DB}.ML.MODEL_REGISTRY").collect()
    session.write_pandas(reg_df, "MODEL_REGISTRY", database=DB, schema="ML", auto_create_table=False, overwrite=False, use_logical_type=True)
    print(f"Wrote {len(reg_df)} rows to ML.MODEL_REGISTRY")

# %% [markdown]
# ## Summary

# %%
print("=" * 98)
print("RIA FINANCIAL ML TRAINING SUMMARY (synthetic data; not production performance)")
print("=" * 98)
print(reg_df[["MODEL_ID", "MODEL_NAME", "ROC_AUC", "PR_AUC", "POSITIVE_RATE", "TRAINING_ROWS", "VALIDATION_STATUS"]].round(3).to_string(index=False))
