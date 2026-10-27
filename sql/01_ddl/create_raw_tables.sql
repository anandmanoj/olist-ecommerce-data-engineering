CREATE SCHEMA IF NOT EXISTS raw;

-- 1. customers

CREATE TABLE raw.olist_customers_dataset (
    customer_id VARCHAR(32) NOT NULL,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix INT,
    customer_city VARCHAR(32),
    customer_state VARCHAR(2),

    CONSTRAINT pk_olist_customers_dataset 
    PRIMARY KEY(customer_id)
);

--2. geolocation

CREATE TABLE raw.olist_geolocation_dataset (
    geolocation_zip_code_prefix INT NOT NULL,
    geolocation_lat DOUBLE PRECISION NOT NULL,
    geolocation_lng DOUBLE PRECISION NOT NULL,
    geolocation_city VARCHAR(38) NOT NULL,
    geolocation_state VARCHAR(2) NOT NULL

);

--3 prdouct category translation

CREATE TABLE raw.product_category_name_translation (
    product_category_name VARCHAR(46) NOT NULL,
    product_category_name_english VARCHAR(39) NOT NULL,

    CONSTRAINT pk_product_category_name_translation 
    PRIMARY KEY(product_category_name)
);

--4. products

CREATE TABLE raw.olist_products_dataset (
    product_id VARCHAR(32) NOT NULL,
    product_category_name VARCHAR NULL,
    product_name_lenght INT NULL,
    product_description_lenght INT NULL,
    product_photos_qty INT NULL,
    product_weight_g INT NULL,
    product_length_cm INT NULL,
    product_height_cm INT NULL,
    product_width_cm INT NULL,

    CONSTRAINT pk_olist_products_dataset 
    PRIMARY KEY (product_id)
);

--5. sellers

CREATE TABLE raw.olist_sellers_dataset (
    seller_id VARCHAR(32) NOT NULL,
    seller_zip_code_prefix INT NOT NULL,
    seller_city VARCHAR(40) NOT NULL,
    seller_state VARCHAR(2) NOT NULL,

    CONSTRAINT pk_olist_sellers_dataset 
    PRIMARY KEY(seller_id)
);

--6. orders

CREATE TABLE raw.olist_orders_dataset (
    order_id VARCHAR(32) NOT NULL,
    customer_id VARCHAR(32) NOT NULL,
    order_status VARCHAR(11) NOT NULL,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP NULL,
    order_delivered_carrier_date TIMESTAMP NULL,
    order_delivered_customer_date TIMESTAMP NULL,
    order_estimated_delivery_date TIMESTAMP NOT NULL,

    CONSTRAINT pk_olist_orders_dataset 
    PRIMARY KEY(order_id),

    CONSTRAINT fk_orders_customer
    FOREIGN KEY(customer_id)
    REFERENCES raw.olist_customers_dataset(customer_id)
);

--7. order items

CREATE TABLE raw.olist_order_items_dataset (
    order_id VARCHAR(32) NOT NULL,
    order_item_id INT NOT NULL,
    product_id VARCHAR(32) NOT NULL,
    seller_id VARCHAR(32) NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    freight_value NUMERIC(10,2) NOT NULL,

    CONSTRAINT pk_olist_order_items_dataset 
    PRIMARY KEY(order_id,  order_item_id),

    CONSTRAINT fk_order_items_order
    FOREIGN KEY (order_id)
    REFERENCES raw.olist_orders_dataset(order_id),

    CONSTRAINT fk_order_items_product
    FOREIGN KEY (product_id)
    REFERENCES raw.olist_products_dataset(product_id),

    CONSTRAINT fk_order_items_seller
    FOREIGN KEY (seller_id)
    REFERENCES raw.olist_sellers_dataset(seller_id)

);

--8. order payments

CREATE TABLE raw.olist_order_payments_dataset (
    order_id VARCHAR(32) NOT NULL,
    payment_sequential INT NOT NULL,
    payment_type VARCHAR(11) NOT NULL,
    payment_installments INT NOT NULL,
    payment_value NUMERIC(10,2) NOT NULL,
    
    CONSTRAINT pk_olist_order_payments_dataset 
    PRIMARY KEY(order_id, payment_sequential),

    CONSTRAINT fk_order_payments_order
    FOREIGN KEY(order_id)
    REFERENCES raw.olist_orders_dataset(order_id)
);

--9. order reviews

CREATE TABLE raw.olist_order_reviews_dataset (
    review_id VARCHAR(32) NOT NULL,
    order_id VARCHAR(32) NOT NULL,
    review_score INT NOT NULL,
    review_comment_title VARCHAR NULL,
    review_comment_message VARCHAR NULL,
    review_creation_date TIMESTAMP NOT NULL,
    review_answer_timestamp  TIMESTAMP NOT NULL,
    
    CONSTRAINT pk_olist_order_reviews_dataset 
    PRIMARY KEY(review_id, order_id),

    CONSTRAINT fk_order_reviews_order
    FOREIGN KEY(order_id)
    REFERENCES raw.olist_orders_dataset (order_id)
);



