BEGIN;

CREATE SCHEMA IF NOT EXISTS analytics;

-- Rebuild the analytics tables when this development script is rerun.
-- This drops existing model tables, not the raw data.
DROP TABLE IF EXISTS analytics.fact_orders;
DROP TABLE IF EXISTS analytics.dim_customer;
DROP TABLE IF EXISTS analytics.dim_product;
DROP TABLE IF EXISTS analytics.dim_date;


-- =========================================================
-- 1. DIM_CUSTOMER
-- Grain: one row per customer_unique_id
-- =========================================================

CREATE TABLE analytics.dim_customer AS
SELECT DISTINCT ON (customer_unique_id)
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM raw.olist_customers_dataset
WHERE customer_unique_id IS NOT NULL
ORDER BY customer_unique_id, customer_id;

ALTER TABLE analytics.dim_customer
ADD CONSTRAINT dim_customer_pk
PRIMARY KEY (customer_unique_id);


-- =========================================================
-- 2. DIM_PRODUCT
-- Grain: one row per product_id
-- =========================================================

CREATE TABLE analytics.dim_product AS
SELECT
    p.product_id,
    p.product_category_name AS product_category_name_original,
    COALESCE(
        NULLIF(BTRIM(t.product_category_name_english), ''),
        'uncategorized'
    ) AS product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM raw.olist_products_dataset AS p
LEFT JOIN raw.product_category_name_translation AS t
    ON p.product_category_name = t.product_category_name;

ALTER TABLE analytics.dim_product
ADD CONSTRAINT dim_product_pk
PRIMARY KEY (product_id);


-- =========================================================
-- 3. DIM_DATE
-- Grain: one row per calendar date
-- =========================================================

CREATE TABLE analytics.dim_date AS
SELECT
    calendar_date::date AS date_key,
    EXTRACT(YEAR FROM calendar_date)::int AS year,
    EXTRACT(MONTH FROM calendar_date)::int AS month,
    EXTRACT(DAY FROM calendar_date)::int AS day,
    EXTRACT(ISODOW FROM calendar_date)::int AS day_of_week,
    TO_CHAR(calendar_date, 'FMDay') AS day_name,
    (
        EXTRACT(ISODOW FROM calendar_date) IN (6, 7)
    ) AS is_weekend
FROM GENERATE_SERIES(
    DATE '2016-01-01',
    DATE '2018-12-31',
    INTERVAL '1 day'
) AS dates(calendar_date);

ALTER TABLE analytics.dim_date
ADD CONSTRAINT dim_date_pk
PRIMARY KEY (date_key);



-- =========================================================
-- 4. FACT_ORDERS
-- Grain: one row per (order_id, order_item_id)
-- =========================================================

CREATE TABLE analytics.fact_orders AS

WITH order_payment_totals AS (
    -- Aggregate multiple payment records to one row per order.
    SELECT
        order_id,
        SUM(payment_value) AS order_payment_value
    FROM raw.olist_order_payments_dataset
    GROUP BY order_id
),

item_base AS (
    SELECT
        o.order_id,
        oi.order_item_id,
        c.customer_unique_id,
        oi.product_id,
        o.order_purchase_timestamp,
        o.order_purchase_timestamp::date AS order_purchase_date,
        o.order_status,
        o.order_delivered_customer_date,
        oi.price,
        oi.freight_value,

        COALESCE(
            pay.order_payment_value,
            0::numeric
        ) AS order_payment_value,

        -- Total item price plus freight for each order.
        SUM(
            COALESCE(oi.price, 0::numeric)
            + COALESCE(oi.freight_value, 0::numeric)
        ) OVER (
            PARTITION BY o.order_id
        ) AS order_item_total

    FROM raw.olist_orders_dataset AS o

    JOIN raw.olist_customers_dataset AS c
        ON o.customer_id = c.customer_id

    JOIN raw.olist_order_items_dataset AS oi
        ON o.order_id = oi.order_id

    LEFT JOIN order_payment_totals AS pay
        ON o.order_id = pay.order_id
)

SELECT
    order_id,
    order_item_id,
    customer_unique_id,
    product_id,
    order_purchase_date,
    order_status,

    price,
    freight_value,

    -- Order-level amount repeated for reference.
    -- Do not SUM this column across fact rows.
    order_payment_value,

    -- Allocate order payment across items proportionally.
    CASE
        WHEN order_item_total IS NULL
          OR order_item_total = 0
        THEN 0::numeric

        ELSE
            order_payment_value
            * (
                COALESCE(price, 0::numeric)
                + COALESCE(freight_value, 0::numeric)
            )
            / order_item_total
    END AS payment_value,

    -- Delivery lag in whole days; NULL if not delivered.
    CASE
        WHEN order_delivered_customer_date IS NULL
        THEN NULL

        ELSE EXTRACT(
            DAY FROM (
                order_delivered_customer_date
                - order_purchase_timestamp
            )
        )::int
    END AS delivery_lag_days

FROM item_base;


-- =========================================================
-- 5. FACT TABLE KEYS AND RELATIONSHIPS
-- =========================================================

ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fact_orders_pk
PRIMARY KEY (order_id, order_item_id);

ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fact_orders_customer_fk
FOREIGN KEY (customer_unique_id)
REFERENCES analytics.dim_customer (customer_unique_id);

ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fact_orders_product_fk
FOREIGN KEY (product_id)
REFERENCES analytics.dim_product (product_id);

ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fact_orders_date_fk
FOREIGN KEY (order_purchase_date)
REFERENCES analytics.dim_date (date_key);

COMMIT;