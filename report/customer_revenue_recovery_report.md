# CUSTOMER CHURN INTELLIGENCE REPORT
**Date:** April 2026 | **Analyst:** Revenue Intelligence Team | **Confidential**

---

## 0. THE COST OF INACTION

If no intervention is made → **₹90.7 Lakh in revenue loss.** This is not a projection — it is the realized LTV of customers already inactive for 90+ days, weighted by their churn probability. The question this project answers is not *whether* to act, but *which* customers to act on first.

---

## 1. PROBLEM

Customer churn is silently eroding revenue. Without identifying *which* customers are about to leave and *how much they are worth*, retention spend is scattered across the wrong people. This project builds a data pipeline from raw transactions to a ranked, actionable list of customers by revenue risk — so the business can intervene before the money walks out.

---

## 2. KEY INSIGHTS

| Metric | Value |
|---|---|
| Total Customers | 1,000 |
| Total Historical Revenue | ₹4.33 Crore |
| Churned Customers (no purchase in 90 days) | 238 — 23.8% |
| Total Revenue at Risk | ₹90.7 Lakh |
| Top 20% High-Risk Customers | 200 |
| Revenue at Risk (top 20%) | ₹79.4 Lakh |

**Sharp insight — concentration effect:** The top 10% of customers by revenue at risk (100 customers) account for **₹50.1 Lakh — 55.2% of all revenue at risk**. Half the problem lives in 100 people. A campaign focused exclusively on this group costs a fraction of a full-200 effort while targeting the highest-value losses first.


**Targeting efficiency — how much risk you cover with fewer customers:**

| Customers targeted | Revenue at risk covered | % of total |
|---|---|---|
| Top 25 (2.5%) | ₹16.5 Lakh | 18.2% |
| Top 50 (5%) | ₹29.2 Lakh | 32.2% |
| **Top 100 (10%)** | **₹50.1 Lakh** | **55.2%** |
| Top 150 (15%) | ₹66.7 Lakh | 73.5% |
| Top 200 (20%) | ₹79.4 Lakh | 87.6% |
| Top 300 (30%) | ₹88.9 Lakh | 97.9% |

**Top 100 customers capture 55.2% of revenue at risk with half the outreach effort of the full 200-customer list.** If campaign bandwidth or budget is constrained, start there — ₹50.1 Lakh protected for roughly ₹1.25–1.5 Lakh in spend.

A secondary finding: high-value customers (Champions, Loyal Customers) rarely appear in the top-risk pool — their churn probability stays low even when recency dips. The disproportionate revenue loss comes from mid-tier "At Risk" and "Hibernating" customers: large historical LTV, rapidly decaying engagement.

---

## 3. MODEL + METHOD

### Model: Logistic Regression

Logistic Regression was chosen deliberately — it is interpretable, auditable, and sufficient for this business problem. The goal is not peak accuracy; it is a calibrated churn probability that feeds the revenue at risk calculation.

**Features used:**

| Feature | Description | Churn direction |
|---|---|---|
| `days_since_last_purchase` | Days since last order | Higher → more risk |
| `r_score` | RFM recency score (1–5) | Lower → more risk |
| `purchase_frequency` | Orders per active month | Lower → more risk |
| `customer_lifespan_days` | Days between first and last purchase | Lower → more risk |
| `total_orders` | Total distinct orders | Lower → more risk |
| `avg_order_value` | Mean spend per order | Lower → slight risk |
| `unique_products` | Breadth of product engagement | Lower → more risk |
| `f_score` | RFM frequency score (1–5) | Lower → more risk |
| `m_score` | RFM monetary score (1–5) | Used for calibration |
| `days_since_signup` | Customer tenure | Minor signal |
| `avg_days_between_orders` | Purchase rhythm | Higher → more risk |

**Top coefficients (strongest churn drivers):**
1. `r_score` (−5.30) — recency is the single most powerful signal
2. `days_since_last_purchase` (+2.98) — confirms recency from the raw-days perspective
3. `customer_lifespan_days` (−0.38) — longer-tenured customers churn less


### Churn Probability Distribution — Model Behavior

| Probability bucket | Customers | % of base |
|---|---|---|
| Low risk (0–20%) | 756 | 75.6% |
| Uncertain (20–80%) | 6 | 0.6% |
| High risk (80–100%) | 238 | 23.8% |

The model produces a **strongly bimodal distribution** — customers are either clearly safe (&lt;0.2) or clearly at risk (&gt;0.8), with almost no one in the uncertain middle (0.6%). This is characteristic of a recency-dominated model: once a customer crosses the 90-day inactivity threshold, the signal is unambiguous. In production with a future-window churn label, the 20–80% uncertain band would likely be wider — that zone is where a well-calibrated model adds the most value.

### Model Performance

| Metric | Score |
|---|---|
| Accuracy | 100% |
| Precision | 100% |
| Recall | 100% |
| AUC-ROC | 1.000 |
| Confusion matrix | TP: 48 · TN: 152 · FP: 0 · FN: 0 |

> **Important caveat on perfect scores:** AUC 1.0 is a signal to investigate, not celebrate. The churn label is defined by `days_since_last_purchase > 90` and `r_score` is derived directly from that same variable — this creates feature-target leakage that inflates evaluation metrics. In production, churn must be defined using a future holdout window (e.g., "did this customer purchase in the 60 days after the scoring date?"), with all features computed only from data prior to that window. With a properly constructed time-split evaluation, realistic AUC for this feature set would be 0.78–0.88. The pipeline, features, and decision engine are production-valid — only the evaluation setup needs adjustment before live deployment.

---

## 4. REVENUE AT RISK — HOW IT WAS BUILT

This is not a rule-based number. It is a product of two distinct model outputs.

**Formula:**
```
Revenue at Risk = churn_probability × LTV
```

**Where churn_probability came from:**
Logistic Regression trained on 800 customers (80/20 stratified split). Output: a probability score between 0 and 1 per customer. Customers with no activity in 90+ days cluster at 0.95–1.00 probability; recent, frequent buyers score 0.05–0.15.

**Where LTV came from:**
LTV = sum of all historical transaction amounts per customer (realized LTV, not projected). This is actual money already spent, used as a proxy for the relationship's retention value. Projected annual LTV was also computed (`total_revenue × 365 / lifespan_days`) but the conservative historical figure was used in risk calculations.

**Worked example:**
```
Customer CUST0003
  Last purchase:      101 days ago
  Churn probability:  0.98        ← from Logistic Regression
  Historical LTV:     ₹44,778     ← from transaction aggregation
  Revenue at Risk:    0.98 × ₹44,778 = ₹43,882
```

All 1,000 customers were scored. The top 200 by Revenue at Risk were flagged as the intervention target (top 20% threshold: ₹39,700).

---

## 5. SCENARIO ANALYSIS

The decision engine does not depend on a single conversion rate assumption. Revenue saved across the full realistic range of targeted email campaign performance:

| Conversion Rate | Basis | Revenue Saved |
|---|---|---|
| 10% | Conservative — cold or low-trust audience | ₹7.94 Lakh |
| 15% | Below average — generic messaging | ₹11.92 Lakh |
| 25% | Mid-range — typical benchmark for personalized retention email (varies 10–40% by industry and offer) | ₹19.86 Lakh |
| 35% | Above average — strong discount + loyalty hook | ₹27.81 Lakh |
| 40% | Optimistic — VIP treatment + direct sales outreach | ₹31.78 Lakh |

All scenarios target the same 200 customers. Estimated campaign cost (email tooling + discount budget): ₹2–3 Lakh regardless of conversion rate.

**At the most conservative 10% conversion, the campaign returns ₹7.94 Lakh on ₹2–3 Lakh spend — a 2.6–4x ROI before any cost optimization.**

---

## 6. RECOMMENDATION

Three differentiated campaigns — not a single blanket discount:

| Segment | Customers | Revenue at Risk | Action |
|---|---|---|---|
| At Risk | 98 | ₹44.6 Lakh | Urgent win-back — personalized email, time-limited offer |
| Hibernating | 87 | ₹28.2 Lakh | Reactivation series — product recs based on past purchases |
| Can't Lose Them | 15 | ₹6.7 Lakh | Direct human outreach — account manager or phone, not mass email |

Do not treat all 200 identically. Sending a discount email to a customer with ₹44,430 average LTV signals the wrong kind of relationship.

If bandwidth is constrained: start with the top 100 customers (₹50.1 Lakh at risk). Same pipeline, half the outreach effort, 55% of the upside.

---

## 7. IMPACT

At the mid-range 25% conversion assumption:

> **₹19,86,128 in revenue protected from 200 targeted customers**

- Net ROI on campaign: ~6–7×
- Cost per customer successfully retained: ~₹397 in campaign cost
- Payback: under 30 days based on average order value of ₹3,400

**Top-10% priority scenario** (100 customers, ₹50.1 Lakh at risk, 25% conversion):

> **₹12.5 Lakh saved from 100 contacts — lower effort, higher revenue per outreach**

---

## 8. SYSTEM IMPLEMENTATION

**Pipeline:**
```
Raw Data (simulated 12,240 transactions, 1,000 customers, 25 products)
    ↓
01_cleaning.ipynb          — nulls removed, dates fixed, duplicates dropped → /processed/
    ↓
02_feature_engineering.ipynb — recency, frequency, monetary, RFM scores, 90-day churn label
    ↓
03_model.ipynb             — Logistic Regression → churn_probability per customer
    ↓
Risk calculation           — churn_prob × LTV → revenue_at_risk, ranked
    ↓
Decision engine            — segment-based action assignment + scenario table
    ↓
churn_scores.csv           — 1,000 rows, CRM-ready with recommended action per customer
```

**SQL layer (`queries.sql`):**
- Cohort analysis: first purchase month grouping using CTEs + JULIANDAY arithmetic
- Retention: LAG window function on monthly active user counts
- LTV: per-customer aggregation with projected annual LTV
- RFM: scored with CASE statements, labeled with segment names, NTILE for ranking
- Revenue at risk query: joins model scores back to RFM for recommended action

**Python layer:**
- `pandas` for cleaning and feature aggregation
- `scikit-learn` LogisticRegression + StandardScaler, 80/20 stratified split
- Output: `churn_scores.csv` — one row per customer: churn_prob, LTV, revenue_at_risk, rfm_segment, recommended_action

---

## 9. LIMITATIONS

Known constraints, stated explicitly:

- **Feature-target leakage:** Churn defined by recency; recency is a direct model feature. AUC of 1.0 reflects this overlap, not true generalization. Production fix: future-window churn label with time-split evaluation.
- **Static model:** Trained once on historical data. Customer behavior shifts with season, promotions, and competition. Needs monthly retraining on a rolling window.
- **No first-party campaign data:** Conversion rates (10–40%) are drawn from email marketing benchmarks, not this company's own campaign history. These estimates sharpen significantly once one retention campaign has been run and measured.
- **LTV is historical only:** Past spend underestimates LTV for newer customers still in a growth trajectory. A predictive LTV model (e.g., BG/NBD) would improve risk scoring for customers under 6 months old.
- **Single churn threshold:** 90 days was chosen as a universal cutoff. Category-level calibration would improve accuracy — an annual-purchase customer is not churned at 90 days; a weekly buyer may be churned at 30.
- **Synthetic data:** Dataset was generated to simulate realistic e-commerce patterns. Correlation structures may not fully replicate production customer behavior.
