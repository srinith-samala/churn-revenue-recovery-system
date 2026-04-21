-- ============================================================
-- CUSTOMER ANALYTICS SQL — Cohort, Retention, LTV, RFM
-- Engine: SQLite-compatible (standard SQL + window functions)
-- ============================================================


-- ============================================================
-- A. COHORT ANALYSIS — Group users by first purchase month
-- ============================================================
WITH first_purchase AS (
    SELECT
        customer_id,
        DATE(MIN(invoice_date), 'start of month') AS cohort_month
    FROM transactions
    GROUP BY customer_id
),
customer_activity AS (
    SELECT
        t.customer_id,
        fp.cohort_month,
        DATE(t.invoice_date, 'start of month') AS activity_month
    FROM transactions t
    JOIN first_purchase fp ON t.customer_id = fp.customer_id
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
),
cohort_activity AS (
    SELECT
        cohort_month,
        activity_month,
        COUNT(DISTINCT customer_id) AS active_customers,
        CAST(
            (strftime('%Y', activity_month) - strftime('%Y', cohort_month)) * 12 +
            (strftime('%m', activity_month) - strftime('%m', cohort_month))
        AS INTEGER) AS period_number
    FROM customer_activity
    GROUP BY cohort_month, activity_month
)
SELECT
    ca.cohort_month,
    ca.period_number,
    cs.cohort_customers,
    ca.active_customers,
    ROUND(100.0 * ca.active_customers / cs.cohort_customers, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON ca.cohort_month = cs.cohort_month
ORDER BY ca.cohort_month, ca.period_number;


-- ============================================================
-- B. RETENTION — Month-wise Retention %
-- ============================================================
WITH monthly_active AS (
    SELECT
        customer_id,
        DATE(invoice_date, 'start of month') AS active_month
    FROM transactions
    GROUP BY customer_id, DATE(invoice_date, 'start of month')
),
retained AS (
    SELECT
        curr.active_month AS month,
        COUNT(DISTINCT curr.customer_id)  AS active_users,
        COUNT(DISTINCT prev.customer_id)  AS retained_users
    FROM monthly_active curr
    LEFT JOIN monthly_active prev
        ON curr.customer_id = prev.customer_id
        AND prev.active_month = DATE(curr.active_month, '-1 month')
    GROUP BY curr.active_month
)
SELECT
    month,
    active_users,
    retained_users,
    ROUND(100.0 * retained_users / NULLIF(LAG(active_users) OVER (ORDER BY month), 0), 2) AS retention_rate_pct
FROM retained
ORDER BY month;


-- ============================================================
-- C. LTV — Total Revenue Per Customer
-- ============================================================
WITH customer_revenue AS (
    SELECT
        t.customer_id,
        c.customer_name,
        c.segment,
        c.city,
        COUNT(DISTINCT t.invoice_id)       AS total_orders,
        SUM(t.amount)                       AS total_revenue,
        MIN(t.invoice_date)                 AS first_purchase,
        MAX(t.invoice_date)                 AS last_purchase,
        ROUND(SUM(t.amount) / COUNT(DISTINCT t.invoice_id), 2) AS avg_order_value,
        JULIANDAY(MAX(t.invoice_date)) - JULIANDAY(MIN(t.invoice_date)) AS lifespan_days
    FROM transactions t
    JOIN customers c ON t.customer_id = c.customer_id
    GROUP BY t.customer_id, c.customer_name, c.segment, c.city
),
ltv AS (
    SELECT
        *,
        ROUND(total_revenue, 2) AS ltv,
        CASE
            WHEN lifespan_days > 0
            THEN ROUND(total_revenue * 365.0 / lifespan_days, 2)
            ELSE total_revenue
        END AS projected_annual_ltv,
        CASE
            WHEN total_revenue >= 50000 THEN 'Platinum'
            WHEN total_revenue >= 20000 THEN 'Gold'
            WHEN total_revenue >= 8000  THEN 'Silver'
            ELSE 'Bronze'
        END AS ltv_tier
    FROM customer_revenue
)
SELECT *
FROM ltv
ORDER BY total_revenue DESC;


-- ============================================================
-- D. RFM SEGMENTATION
-- ============================================================
WITH reference_date AS (
    SELECT DATE(MAX(invoice_date)) AS max_date FROM transactions
),
rfm_raw AS (
    SELECT
        t.customer_id,
        c.customer_name,
        c.segment,
        CAST(JULIANDAY((SELECT max_date FROM reference_date)) -
             JULIANDAY(MAX(t.invoice_date)) AS INTEGER) AS recency_days,
        COUNT(DISTINCT t.invoice_id)   AS frequency,
        ROUND(SUM(t.amount), 2)        AS monetary
    FROM transactions t
    JOIN customers c ON t.customer_id = c.customer_id
    GROUP BY t.customer_id, c.customer_name, c.segment
),
rfm_scores AS (
    SELECT
        *,
        CASE
            WHEN recency_days <= 30  THEN 5
            WHEN recency_days <= 60  THEN 4
            WHEN recency_days <= 90  THEN 3
            WHEN recency_days <= 180 THEN 2
            ELSE 1
        END AS r_score,
        CASE
            WHEN frequency >= 20 THEN 5
            WHEN frequency >= 15 THEN 4
            WHEN frequency >= 10 THEN 3
            WHEN frequency >= 5  THEN 2
            ELSE 1
        END AS f_score,
        CASE
            WHEN monetary >= 50000 THEN 5
            WHEN monetary >= 25000 THEN 4
            WHEN monetary >= 10000 THEN 3
            WHEN monetary >= 5000  THEN 2
            ELSE 1
        END AS m_score
    FROM rfm_raw
),
rfm_segments AS (
    SELECT
        *,
        ROUND((r_score + f_score + m_score) / 3.0, 2) AS rfm_avg,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'New Customers'
            WHEN r_score >= 3 AND f_score >= 2                  THEN 'Potential Loyalists'
            WHEN r_score = 2  AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score = 1  AND f_score >= 3                  THEN 'Cant Lose Them'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3 THEN 'Hibernating'
            ELSE 'Lost'
        END AS rfm_segment
    FROM rfm_scores
)
SELECT
    customer_id,
    customer_name,
    segment,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_avg,
    rfm_segment
FROM rfm_segments
ORDER BY rfm_avg DESC;


-- ============================================================
-- E. REVENUE AT RISK — Top 20% Risky Customers
--    (churn_scores table created by Python model notebook)
-- ============================================================
WITH revenue_at_risk AS (
    SELECT
        cs.customer_id,
        cs.churn_prob,
        cs.ltv,
        ROUND(cs.churn_prob * cs.ltv, 2) AS revenue_at_risk,
        rfm.rfm_segment,
        rfm.recency_days,
        rfm.frequency,
        rfm.monetary,
        NTILE(5) OVER (ORDER BY cs.churn_prob * cs.ltv DESC) AS risk_quintile
    FROM churn_scores cs
    JOIN rfm_segments rfm ON cs.customer_id = rfm.customer_id
)
SELECT
    customer_id,
    rfm_segment,
    recency_days,
    frequency,
    ROUND(churn_prob * 100, 1)   AS churn_prob_pct,
    ltv,
    revenue_at_risk,
    CASE
        WHEN rfm_segment IN ('Champions','Loyal Customers') AND churn_prob > 0.6
            THEN 'VIP Re-engagement Campaign'
        WHEN rfm_segment IN ('At Risk','Cant Lose Them')
            THEN 'Urgent Win-back Campaign'
        WHEN rfm_segment = 'Hibernating'
            THEN 'Reactivation Email Series'
        ELSE 'Discount + Personalized Outreach'
    END AS recommended_action
FROM revenue_at_risk
WHERE risk_quintile = 1
ORDER BY revenue_at_risk DESC;
