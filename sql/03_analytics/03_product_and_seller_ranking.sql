-- =========================================================
-- FILE 3: PRODUCT AND SELLER RANKING
-- =========================================================


-- Q1. Which product categories contribute the most GMV?
WITH category_sales AS (
    SELECT
        p.product_category_name_english AS category,
        SUM(f.price) AS gmv,
        COUNT(DISTINCT f.order_id) AS delivered_orders,
        COUNT(DISTINCT f.product_id) AS products_sold
    FROM analytics.fact_orders AS f
    JOIN analytics.dim_product AS p
        ON f.product_id = p.product_id
    WHERE f.order_status = 'delivered'
    GROUP BY p.product_category_name_english
)
SELECT
    category,
    gmv,
    delivered_orders,
    products_sold,
    ROUND(
        100.0 * gmv / NULLIF(SUM(gmv) OVER (), 0),
        2
    ) AS gmv_share_percent,
    DENSE_RANK() OVER (
        ORDER BY gmv DESC
    ) AS category_rank
FROM category_sales
ORDER BY category_rank, category;


-- Q2. Which are the top three products in each category?
-- DENSE_RANK preserves ties, so a category can return
-- more than three products if the scores are tied.
WITH product_sales AS (
    SELECT
        p.product_category_name_english AS category,
        f.product_id,
        SUM(f.price) AS gmv,
        COUNT(DISTINCT f.order_id) AS delivered_orders,
        SUM(f.order_item_id * 0 + 1) AS item_rows
    FROM analytics.fact_orders AS f
    JOIN analytics.dim_product AS p
        ON f.product_id = p.product_id
    WHERE f.order_status = 'delivered'
    GROUP BY
        p.product_category_name_english,
        f.product_id
),
ranked_products AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY category
            ORDER BY gmv DESC
        ) AS product_rank
    FROM product_sales
)
SELECT
    category,
    product_id,
    gmv,
    delivered_orders,
    product_rank
FROM ranked_products
WHERE product_rank <= 3
ORDER BY category, product_rank, product_id;


-- Q3. Which 10 products generate the highest total GMV?
SELECT
    product_id,
    SUM(price) AS gmv,
    COUNT(*) AS delivered_items,
    COUNT(DISTINCT order_id) AS delivered_orders
FROM analytics.fact_orders
WHERE order_status = 'delivered'
GROUP BY product_id
ORDER BY gmv DESC
LIMIT 10;


-- Q4. Which products account for approximately 80% of GMV?
-- Review cumulative_gmv_share_percent to identify the
-- point where the cumulative total reaches 80%.
WITH product_sales AS (
    SELECT
        product_id,
        SUM(price) AS gmv
    FROM analytics.fact_orders
    WHERE order_status = 'delivered'
    GROUP BY product_id
),
pareto AS (
    SELECT
        product_id,
        gmv,
        SUM(gmv) OVER (
            ORDER BY gmv DESC, product_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_gmv,
        SUM(gmv) OVER () AS total_gmv
    FROM product_sales
)
SELECT
    product_id,
    gmv,
    ROUND(
        100.0 * gmv / NULLIF(total_gmv, 0),
        2
    ) AS product_gmv_share_percent,
    cumulative_gmv,
    ROUND(
        100.0 * cumulative_gmv / NULLIF(total_gmv, 0),
        2
    ) AS cumulative_gmv_share_percent
FROM pareto
ORDER BY gmv DESC, product_id;


-- Q5. Which 10 sellers generate the most delivered-item GMV?
-- seller_id is retrieved from the raw order-item table,
-- because the current fact table does not contain it.
WITH seller_item_sales AS (
    SELECT
        f.order_id,
        f.order_item_id,
        oi.seller_id,
        f.price,
        f.freight_value
    FROM analytics.fact_orders AS f
    JOIN raw.olist_order_items_dataset AS oi
        ON f.order_id = oi.order_id
       AND f.order_item_id = oi.order_item_id
    WHERE f.order_status = 'delivered'
)
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    SUM(sis.price) AS gmv,
    SUM(sis.freight_value) AS freight_value,
    COUNT(*) AS delivered_items,
    COUNT(DISTINCT sis.order_id) AS delivered_orders
FROM seller_item_sales AS sis
JOIN raw.olist_sellers_dataset AS s
    ON sis.seller_id = s.seller_id
GROUP BY
    s.seller_id,
    s.seller_city,
    s.seller_state
ORDER BY gmv DESC
LIMIT 10;


-- Q6. Which seller states generate the highest GMV,
-- and how does the average seller contribution compare?
WITH seller_item_sales AS (
    SELECT
        f.order_id,
        f.order_item_id,
        oi.seller_id,
        f.price
    FROM analytics.fact_orders AS f
    JOIN raw.olist_order_items_dataset AS oi
        ON f.order_id = oi.order_id
       AND f.order_item_id = oi.order_item_id
    WHERE f.order_status = 'delivered'
),
seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_state,
        SUM(sis.price) AS seller_gmv,
        COUNT(*) AS delivered_items,
        COUNT(DISTINCT sis.order_id) AS seller_order_count
    FROM seller_item_sales AS sis
    JOIN raw.olist_sellers_dataset AS s
        ON sis.seller_id = s.seller_id
    GROUP BY s.seller_id, s.seller_state
)
SELECT
    seller_state,
    COUNT(*) AS sellers,
    SUM(seller_gmv) AS state_gmv,
    ROUND(AVG(seller_gmv), 2) AS average_seller_gmv,
    SUM(delivered_items) AS delivered_items,
    SUM(seller_order_count) AS seller_order_associations
FROM seller_metrics
GROUP BY seller_state
ORDER BY state_gmv DESC;


-- Q7. Which products have a higher or lower average item
-- price than other products in their category?
WITH product_prices AS (
    SELECT
        p.product_category_name_english AS category,
        f.product_id,
        AVG(f.price) AS average_item_price,
        SUM(f.price) AS gmv
    FROM analytics.fact_orders AS f
    JOIN analytics.dim_product AS p
        ON f.product_id = p.product_id
    WHERE f.order_status = 'delivered'
    GROUP BY
        p.product_category_name_english,
        f.product_id
),
benchmarks AS (
    SELECT
        *,
        AVG(average_item_price) OVER (
            PARTITION BY category
        ) AS category_average_product_price
    FROM product_prices
)
SELECT
    category,
    product_id,
    ROUND(average_item_price, 2) AS average_item_price,
    ROUND(category_average_product_price, 2)
        AS category_average_product_price,
    ROUND(
        100.0 * (
            average_item_price - category_average_product_price
        ) / NULLIF(category_average_product_price, 0),
        2
    ) AS price_difference_percent,
    gmv
FROM benchmarks
ORDER BY category, price_difference_percent DESC NULLS LAST;