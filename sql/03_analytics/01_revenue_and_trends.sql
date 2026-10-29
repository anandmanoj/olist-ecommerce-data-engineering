-- =========================================================
-- FILE 1: REVENUE AND TRENDS
-- Revenue definition: delivered-item GMV = SUM(price)
-- =========================================================


-- Q1. How does monthly GMV, freight, and order value change?
SELECT
    DATE_TRUNC('month', order_purchase_date)::date AS sales_month,
    SUM(price) AS monthly_gmv,
    SUM(freight_value) AS monthly_freight,
    COUNT(DISTINCT order_id) AS delivered_orders,
    COUNT(DISTINCT customer_unique_id) AS active_customers,
    ROUND(
        SUM(price) / NULLIF(COUNT(DISTINCT order_id), 0),
        2
    ) AS gmv_per_order
FROM analytics.fact_orders
WHERE order_status = 'delivered'
GROUP BY 1
ORDER BY 1;


-- Q2. What is the month-over-month GMV growth percentage?
WITH month_calendar AS (
    SELECT month_start::date AS sales_month
    FROM GENERATE_SERIES(
        TIMESTAMP '2016-01-01',
        TIMESTAMP '2018-12-01',
        INTERVAL '1 month'
    ) AS gs(month_start)
),
monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_purchase_date)::date AS sales_month,
        SUM(price) AS gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
    GROUP BY 1
),
monthly AS (
    SELECT
        mc.sales_month,
        COALESCE(ms.gmv, 0::numeric) AS gmv
    FROM month_calendar AS mc
    LEFT JOIN monthly_sales AS ms
        ON mc.sales_month = ms.sales_month
),
growth AS (
    SELECT
        sales_month,
        gmv,
        LAG(gmv) OVER (ORDER BY sales_month) AS previous_month_gmv
    FROM monthly
)
SELECT
    sales_month,
    gmv,
    previous_month_gmv,
    ROUND(
        100.0 * (gmv - previous_month_gmv)
        / NULLIF(previous_month_gmv, 0),
        2
    ) AS mom_growth_percent
FROM growth
ORDER BY sales_month;


-- Q3. What is the cumulative GMV over time?
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_purchase_date)::date AS sales_month,
        SUM(price) AS gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
    GROUP BY 1
)
SELECT
    sales_month,
    gmv,
    SUM(gmv) OVER (
        ORDER BY sales_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_gmv
FROM monthly_sales
ORDER BY sales_month;


-- Q4. What is the rolling three-month average GMV?
WITH month_calendar AS (
    SELECT month_start::date AS sales_month
    FROM GENERATE_SERIES(
        TIMESTAMP '2016-01-01',
        TIMESTAMP '2018-12-01',
        INTERVAL '1 month'
    ) AS gs(month_start)
),
monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_purchase_date)::date AS sales_month,
        SUM(price) AS gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
    GROUP BY 1
),
monthly AS (
    SELECT
        mc.sales_month,
        COALESCE(ms.gmv, 0::numeric) AS gmv
    FROM month_calendar AS mc
    LEFT JOIN monthly_sales AS ms
        ON mc.sales_month = ms.sales_month
)
SELECT
    sales_month,
    gmv,
    ROUND(
        AVG(gmv) OVER (
            ORDER BY sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS rolling_3_month_avg_gmv
FROM monthly
ORDER BY sales_month;


-- Q5. How does quarterly GMV change compared with the
-- previous quarter?
WITH quarter_calendar AS (
    SELECT quarter_start::date AS quarter_start
    FROM GENERATE_SERIES(
        TIMESTAMP '2016-01-01',
        TIMESTAMP '2018-10-01',
        INTERVAL '3 months'
    ) AS gs(quarter_start)
),
quarter_sales AS (
    SELECT
        DATE_TRUNC('quarter', order_purchase_date)::date
            AS quarter_start,
        SUM(price) AS gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
    GROUP BY 1
),
quarters AS (
    SELECT
        qc.quarter_start,
        COALESCE(qs.gmv, 0::numeric) AS gmv
    FROM quarter_calendar AS qc
    LEFT JOIN quarter_sales AS qs
        ON qc.quarter_start = qs.quarter_start
),
comparison AS (
    SELECT
        quarter_start,
        gmv,
        LAG(gmv) OVER (
            ORDER BY quarter_start
        ) AS previous_quarter_gmv
    FROM quarters
)
SELECT
    quarter_start,
    gmv,
    previous_quarter_gmv,
    ROUND(
        100.0 * (gmv - previous_quarter_gmv)
        / NULLIF(previous_quarter_gmv, 0),
        2
    ) AS qoq_growth_percent
FROM comparison
ORDER BY quarter_start;


-- Q6. Which weekdays have the highest average daily GMV?
-- Calendar dates without sales are included as zero-sales days.
WITH daily_gmv AS (
    SELECT
        d.date_key,
        d.day_of_week,
        d.day_name,
        COALESCE(SUM(f.price), 0::numeric) AS gmv
    FROM analytics.dim_date AS d
    LEFT JOIN analytics.fact_orders AS f
        ON d.date_key = f.order_purchase_date
       AND f.order_status = 'delivered'
    GROUP BY
        d.date_key,
        d.day_of_week,
        d.day_name
)
SELECT
    day_of_week,
    day_name,
    COUNT(*) AS calendar_days,
    ROUND(AVG(gmv), 2) AS average_daily_gmv
FROM daily_gmv
GROUP BY day_of_week, day_name
ORDER BY day_of_week;


-- Q7. How many monthly active customers are new versus
-- returning customers?
WITH customer_months AS (
    SELECT DISTINCT
        customer_unique_id,
        DATE_TRUNC('month', order_purchase_date)::date
            AS order_month
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
),
first_purchase AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS first_order_month
    FROM customer_months
    GROUP BY customer_unique_id
)
SELECT
    cm.order_month,
    COUNT(*) AS active_customers,
    COUNT(*) FILTER (
        WHERE cm.order_month = fp.first_order_month
    ) AS new_customers,
    COUNT(*) FILTER (
        WHERE cm.order_month > fp.first_order_month
    ) AS returning_customers
FROM customer_months AS cm
JOIN first_purchase AS fp
    ON cm.customer_unique_id = fp.customer_unique_id
GROUP BY cm.order_month
ORDER BY cm.order_month;