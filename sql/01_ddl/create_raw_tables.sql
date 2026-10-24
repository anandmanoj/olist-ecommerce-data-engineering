-- customer_id	customer_unique_id	customer_zip_code_prefix	customer_city	customer_state

CREATE TABLE raw.olist_customers_dataset (
    customer_id VARCHAR(32) NOT NULL,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix INT,
    customer_city VARCHAR(32),
    customer_state VARCHAR(2),
    CONSTRAINT pk_olist_customers_dataset PRIMARY KEY(customer_id)
);

CREATE TABLE raw.olist_geolocation_dataset (
    geolocation_zip_code_prefix INT NOT NULL,
    geolocation_lat DOUBLE PRECISION NOT NULL,
    geolocation_lng DOUBLE PRECISION NOT NULL,
    geolocation_city VARCHAR(38) NOT NULL,
    geolocation_state VARCHAR(2) NOT NULL,

);

CREATE TABLE raw.olist_order_items_dataset (
    order_id VARCHAR(32) NOT NULL,
    order_item_id INT NOT NULL,
    product_id VARCHAR(32) NOT NULL,
    seller_id VARCHAR(32) NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    freight_value NUMERIC(10,2) NOT NULL

    CONSTRAINT pk_olist_order_items_dataset PRIMARY KEY(order_id,  order_item_id)

);

