-- =========================================================
-- FILE 4: LOGISTICS AND DELIVERY
-- =========================================================


-- Q1. How does actual delivery time relate to review scores?
-- Aggregate reviews by order before joining, to avoid
-- multiplying order-level delivery times by review rows.
WITH reviews_by_order AS (
    SELECT
        order_id,
        AVG(review_score)::numeric(4, 2) AS average_review_score
    FROM raw.olist_order_reviews_dataset
    GROUP BY order_id
),
delivered_orders AS (
    SELECT
        order_id,
        EXTRACT(
            EPOCH FROM (
                order_delivered_customer_date
                - order_purchase_timestamp
            )
        ) / 86400.0 AS actual_delivery_days
    FROM raw.olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
)
SELECT
    r.average_review_score,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(d.actual_delivery_days)::numeric, 2)
        AS average_delivery_days
FROM delivered_orders AS d
JOIN reviews_by_order AS r
    ON d.order_id = r.order_id
GROUP BY r.average_review_score
ORDER BY r.average_review_score;


-- Q2. Do late deliveries receive different review scores?
WITH reviews_by_order AS (
    SELECT
        order_id,
        AVG(review_score)::numeric(4, 2) AS average_review_score
    FROM raw.olist_order_reviews_dataset
    GROUP BY order_id
),
delivery_status AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date
                 > order_estimated_delivery_date
            THEN 'Late'
            ELSE 'On time or early'
        END AS delivery_performance
    FROM raw.olist_orders_dataset
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    ds.delivery_performance,
    COUNT(*) AS reviewed_orders,
    ROUND(AVG(r.average_review_score), 2) AS average_review_score
FROM delivery_status AS ds
JOIN reviews_by_order AS r
    ON ds.order_id = r.order_id
GROUP BY ds.delivery_performance
ORDER BY ds.delivery_performance;


-- Q3. Which customer states experience the longest
-- delivery times and highest late-delivery rates?
WITH order_delivery AS (
    SELECT
        o.order_id,
        c.customer_state,
        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_purchase_timestamp
            )
        ) / 86400.0 AS actual_delivery_days,
        (
            o.order_delivered_customer_date
            > o.order_estimated_delivery_date
        ) AS was_late
    FROM raw.olist_orders_dataset AS o
    JOIN raw.olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(actual_delivery_days)::numeric, 2)
        AS average_delivery_days,
    COUNT(*) FILTER (
        WHERE was_late
    ) AS late_orders,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE NOT was_late
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_percent
FROM order_delivery
GROUP BY customer_state
ORDER BY on_time_delivery_percent ASC;


-- Q4. Which customer states have the highest freight cost
-- relative to delivered-item price?
SELECT
    c.customer_state,
    SUM(oi.price) AS item_gmv,
    SUM(oi.freight_value) AS total_freight,
    ROUND(
        100.0 * SUM(oi.freight_value)
        / NULLIF(SUM(oi.price), 0),
        2
    ) AS freight_as_percent_of_item_price
FROM raw.olist_orders_dataset AS o
JOIN raw.olist_customers_dataset AS c
    ON o.customer_id = c.customer_id
JOIN raw.olist_order_items_dataset AS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY freight_as_percent_of_item_price DESC;


-- Q5. Which seller states meet the item shipping-limit
-- deadline for dispatch to the carrier?
-- This measures the order-level carrier handoff timestamp
-- against each item's shipping_limit_date.
SELECT
    s.seller_state,
    COUNT(*) AS items_with_dispatch_data,
    COUNT(*) FILTER (
        WHERE o.order_delivered_carrier_date
              <= oi.shipping_limit_date
    ) AS on_time_dispatch_items,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE o.order_delivered_carrier_date
                  <= oi.shipping_limit_date
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_dispatch_percent,
    ROUND(
        AVG(
            EXTRACT(
                EPOCH FROM (
                    o.order_delivered_carrier_date
                    - oi.shipping_limit_date
                )
            ) / 86400.0
        )::numeric,
        2
    ) AS average_days_vs_deadline
FROM raw.olist_order_items_dataset AS oi
JOIN raw.olist_orders_dataset AS o
    ON oi.order_id = o.order_id
JOIN raw.olist_sellers_dataset AS s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_carrier_date IS NOT NULL
  AND oi.shipping_limit_date IS NOT NULL
GROUP BY s.seller_state
ORDER BY on_time_dispatch_percent ASC;


-- Q6. Which seller-state to customer-state routes have
-- the longest average delivery times?
-- One row per order and seller/customer state combination.
WITH route_orders AS (
    SELECT DISTINCT
        o.order_id,
        s.seller_state,
        c.customer_state,
        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_purchase_timestamp
            )
        ) / 86400.0 AS actual_delivery_days,
        (
            o.order_delivered_customer_date
            > o.order_estimated_delivery_date
        ) AS was_late
    FROM raw.olist_orders_dataset AS o
    JOIN raw.olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    JOIN raw.olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id
    JOIN raw.olist_sellers_dataset AS s
        ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    seller_state,
    customer_state,
    COUNT(*) AS order_route_records,
    ROUND(AVG(actual_delivery_days)::numeric, 2)
        AS average_delivery_days,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE was_late
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS late_delivery_percent
FROM route_orders
GROUP BY seller_state, customer_state
ORDER BY average_delivery_days DESC
LIMIT 30;


-- Q7. Which 20 delivered orders had the greatest delays
-- relative to their estimated delivery dates?
SELECT
    order_id,
    order_purchase_timestamp,
    order_estimated_delivery_date,
    order_delivered_customer_date,
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    order_delivered_customer_date
                    - order_purchase_timestamp
                )
            ) / 86400.0
        )::numeric,
        2
    ) AS actual_delivery_days,
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    order_delivered_customer_date
                    - order_estimated_delivery_date
                )
            ) / 86400.0
        )::numeric,
        2
    ) AS days_late
FROM raw.olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL
  AND order_delivered_customer_date
      > order_estimated_delivery_date
ORDER BY days_late DESC
LIMIT 20;