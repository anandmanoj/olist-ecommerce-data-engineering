-- =========================================================
-- FILE 2: CUSTOMER COHORTS, RETENTION, AND LTV
-- Customer identity: customer_unique_id
-- =========================================================


-- Q1. What percentage of each acquisition cohort returns
-- in subsequent months?
WITH customer_months AS (
    SELECT DISTINCT
        customer_unique_id,
        DATE_TRUNC('month', order_purchase_date)::date
            AS order_month
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
),
first_month AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM customer_months
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT
        fm.cohort_month,
        cm.order_month,
        (
            (
                EXTRACT(YEAR FROM cm.order_month)
                - EXTRACT(YEAR FROM fm.cohort_month)
            ) * 12
            +
            EXTRACT(MONTH FROM cm.order_month)
            - EXTRACT(MONTH FROM fm.cohort_month)
        )::int AS month_number,
        cm.customer_unique_id
    FROM customer_months AS cm
    JOIN first_month AS fm
        ON cm.customer_unique_id = fm.customer_unique_id
),
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM first_month
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    ca.month_number,
    cs.cohort_size,
    COUNT(DISTINCT ca.customer_unique_id) AS active_customers,
    ROUND(
        100.0 * COUNT(DISTINCT ca.customer_unique_id)
        / NULLIF(cs.cohort_size, 0),
        2
    ) AS retention_percent
FROM cohort_activity AS ca
JOIN cohort_sizes AS cs
    ON ca.cohort_month = cs.cohort_month
GROUP BY
    ca.cohort_month,
    ca.month_number,
    cs.cohort_size
ORDER BY ca.cohort_month, ca.month_number;


-- Q2. What percentage of customers made at least two
-- delivered orders?
WITH customer_orders AS (
    SELECT DISTINCT
        customer_unique_id,
        order_id
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
),
customer_order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS order_count
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (
        WHERE order_count >= 2
    ) AS repeat_customers,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE order_count >= 2
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_purchase_rate_percent
FROM customer_order_counts;


-- Q3. How many customers fall into each order-frequency
-- bucket?
WITH customer_orders AS (
    SELECT DISTINCT
        customer_unique_id,
        order_id
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
),
customer_order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS order_count
    FROM customer_orders
    GROUP BY customer_unique_id
),
buckets AS (
    SELECT
        CASE
            WHEN order_count = 1 THEN '1 order'
            WHEN order_count = 2 THEN '2 orders'
            WHEN order_count BETWEEN 3 AND 5 THEN '3-5 orders'
            ELSE '6+ orders'
        END AS order_bucket,
        CASE
            WHEN order_count = 1 THEN 1
            WHEN order_count = 2 THEN 2
            WHEN order_count BETWEEN 3 AND 5 THEN 3
            ELSE 4
        END AS bucket_order
    FROM customer_order_counts
)
SELECT
    order_bucket,
    COUNT(*) AS customers,
    ROUND(
        100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS customer_share_percent
FROM buckets
GROUP BY order_bucket, bucket_order
ORDER BY bucket_order;


-- Q4. Which 20 customers generated the highest observed
-- lifetime GMV?
SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS delivered_orders,
    SUM(price) AS lifetime_gmv,
    MIN(order_purchase_date) AS first_purchase_date,
    MAX(order_purchase_date) AS most_recent_purchase_date
FROM analytics.fact_orders
WHERE order_status = 'delivered'
  AND customer_unique_id IS NOT NULL
GROUP BY customer_unique_id
ORDER BY lifetime_gmv DESC
LIMIT 20;


-- Q5. How does lifetime GMV differ between one-time buyers
-- and repeat buyers?
WITH customer_value AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(price) AS lifetime_gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN order_count = 1 THEN 'One-time buyer'
        ELSE 'Repeat buyer'
    END AS customer_segment,
    COUNT(*) AS customers,
    ROUND(AVG(lifetime_gmv), 2) AS average_lifetime_gmv,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY lifetime_gmv)::numeric,
        2
    ) AS median_lifetime_gmv,
    ROUND(AVG(order_count), 2) AS average_delivered_orders
FROM customer_value
GROUP BY customer_segment
ORDER BY customer_segment;


-- Q6. Which customer states have the highest customer
-- lifetime GMV and repeat-purchase rate?
WITH customer_value AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(price) AS lifetime_gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    dc.customer_state,
    COUNT(*) AS customers,
    ROUND(AVG(cv.lifetime_gmv), 2) AS average_lifetime_gmv,
    COUNT(*) FILTER (
        WHERE cv.order_count >= 2
    ) AS repeat_customers,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE cv.order_count >= 2
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_percent
FROM customer_value AS cv
JOIN analytics.dim_customer AS dc
    ON cv.customer_unique_id = dc.customer_unique_id
GROUP BY dc.customer_state
ORDER BY average_lifetime_gmv DESC;


-- Q7. Can customers be segmented using recency,
-- purchase frequency, and monetary value (RFM)?
-- Quartile score 1 represents the strongest value on
-- each metric: most recent, most frequent, or highest GMV.
WITH customer_metrics AS (
    SELECT
        customer_unique_id,
        MAX(order_purchase_date) AS last_purchase_date,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(price) AS lifetime_gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
),
snapshot AS (
    SELECT MAX(order_purchase_date) AS snapshot_date
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
),
rfm AS (
    SELECT
        cm.customer_unique_id,
        (s.snapshot_date - cm.last_purchase_date)
            AS recency_days,
        cm.order_count,
        cm.lifetime_gmv
    FROM customer_metrics AS cm
    CROSS JOIN snapshot AS s
)
SELECT
    customer_unique_id,
    recency_days,
    order_count,
    lifetime_gmv,
    NTILE(4) OVER (
        ORDER BY recency_days ASC
    ) AS recency_quartile,
    NTILE(4) OVER (
        ORDER BY order_count DESC
    ) AS frequency_quartile,
    NTILE(4) OVER (
        ORDER BY lifetime_gmv DESC
    ) AS monetary_quartile
FROM rfm
ORDER BY lifetime_gmv DESC;