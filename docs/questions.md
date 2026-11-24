<table width="100%"><tr>
<td align="left"><img src="../ria_logo_no_person.svg" alt="Ria" height="72"></td>
<td align="right"><img src="../Snowflake_Logo.svg" alt="Snowflake" height="56"></td>
</tr></table>

# Questions to ask the agent

The first 16 are the sample questions built into the agent spec and checked by `scripts/test_agent.py`.

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

## More questions by area

**Fraud operations**
- Give me a fraud and compliance overview.
- Which corridors have the highest confirmed fraud rate this quarter?
- What share of confirmed fraud comes from card-funded transfers, and how does that compare with bank-funded?
- Show net fraud loss and recoveries by month as a line chart.

**Cases and alerts**
- How many alerts are unassigned, and which queue has the most?
- Which analysts have the highest false-positive rate on closed alerts?
- Show open cases by type and priority.

**Disputes and returns**
- Which NACHA return codes are most common on bank-funded transfers?
- How many Reg E disputes were resolved after 90 days?
- What is the refund on-time rate against the 3 business day timeline?

**Agent network and digital**
- Which agent locations have overdue AML training?
- How many failed logins came from foreign IPs this month?
- Which devices are emulators or rooted?

**Compliance and KYC**
- How many CTRs are pending, and what is the average days to file a SAR?
- How many customers have EDD required but not completed?
- Which PEP customers have a review overdue?

**Documents**
- What are the red flags for account takeover?
- What does our policy say about the SAR filing deadline?
- What are customers saying in complaints about refunds?

**Customer 360**
- Compare lifetime value and complaints by segment.
- Which loyalty tier has the most lapsed customers?
- Give me a Customer 360 brief for customer C000500.

## How answers are labelled

Every model figure is reported with its risk tier and a note that it is a prediction trained on synthetic data. Customer and fraud briefs finish with one or two next actions.
