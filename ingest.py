
from decimal import Decimal
from pathlib import Path
import os

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


# --------------------------------------------------
# 1. Project paths and database configuration
# --------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data" / "raw"

load_dotenv(BASE_DIR / ".env")

password = os.getenv("PGPASSWORD")

if not password:
    raise RuntimeError(
        "PGPASSWORD is missing. Check your .env file."
    )

database_url = URL.create(
    "postgresql+psycopg2",
    username=os.getenv("PGUSER", "postgres"),
    password=password,
    host=os.getenv("PGHOST", "localhost"),
    port=int(os.getenv("PGPORT", "5432")),
    database=os.getenv("PGDATABASE", "olist_ecommerce"),
)

engine = create_engine(
    database_url,
    pool_pre_ping=True,
)


# --------------------------------------------------
# 2. Load order: parent tables before child tables
# --------------------------------------------------

LOAD_PLAN = [
    ("olist_customers_dataset.csv", "olist_customers_dataset"),
    ("olist_geolocation_dataset.csv", "olist_geolocation_dataset"),
    (
        "product_category_name_translation.csv",
        "product_category_name_translation",
    ),
    ("olist_products_dataset.csv", "olist_products_dataset"),
    ("olist_sellers_dataset.csv", "olist_sellers_dataset"),
    ("olist_orders_dataset.csv", "olist_orders_dataset"),
    ("olist_order_items_dataset.csv", "olist_order_items_dataset"),
    ("olist_order_payments_dataset.csv", "olist_order_payments_dataset"),
    ("olist_order_reviews_dataset.csv", "olist_order_reviews_dataset"),
]


# --------------------------------------------------
# 3. Columns that need special conversion
# --------------------------------------------------

TIMESTAMP_COLUMNS = {
    "olist_order_items_dataset": ["shipping_limit_date"],
    "olist_orders_dataset": [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ],
    "olist_order_reviews_dataset": [
        "review_creation_date",
        "review_answer_timestamp",
    ],
}

# These columns use integer types in our DDL but may
# be read as floats by pandas because they contain NULLs.
INTEGER_COLUMNS = {
    "olist_products_dataset": [
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
}

MONEY_COLUMNS = {
    "olist_order_items_dataset": ["price", "freight_value"],
    "olist_order_payments_dataset": ["payment_value"],
}


def prepare_chunk(chunk, table_name):
    """Validate and convert values before inserting them."""

    # Convert timestamp strings into datetime values.
    for col in TIMESTAMP_COLUMNS.get(table_name, []):
        original = chunk[col]
        parsed = pd.to_datetime(original, errors="coerce")

        invalid = original.notna() & parsed.isna()

        if invalid.any():
            examples = original[invalid].head(5).tolist()
            raise ValueError(
                f"Invalid timestamps in {table_name}.{col}: "
                f"{examples}"
            )

        chunk[col] = parsed

    # Convert nullable numeric columns to Python integers
    # or None, so NULLs can be inserted into PostgreSQL.
    for col in INTEGER_COLUMNS.get(table_name, []):
        values = pd.to_numeric(chunk[col], errors="raise")
        fractional = values.notna() & (values % 1 != 0)

        if fractional.any():
            raise ValueError(
                f"Fractional values found in integer column "
                f"{table_name}.{col}"
            )

        chunk[col] = values.map(
            lambda value: None
            if pd.isna(value)
            else int(value)
        ).astype(object)

    # Use Decimal for monetary values stored as NUMERIC.
    for col in MONEY_COLUMNS.get(table_name, []):
        chunk[col] = chunk[col].map(
            lambda value: None
            if pd.isna(value)
            else Decimal(str(value))
        )

    return chunk


# --------------------------------------------------
# 4. Validate the files and database connection
# --------------------------------------------------

missing_files = [
    filename
    for filename, _ in LOAD_PLAN
    if not (DATA_DIR / filename).is_file()
]

if missing_files:
    raise FileNotFoundError(
        f"CSV files missing from {DATA_DIR}: {missing_files}"
    )

with engine.connect() as connection:
    database_name = connection.execute(
        text("SELECT current_database()")
    ).scalar_one()

    print(f"Connected to database: {database_name}")

    if database_name != "olist_ecommerce":
        raise RuntimeError(
            f"Unexpected database: {database_name}"
        )


# --------------------------------------------------
# 5. Load all tables inside one transaction
# --------------------------------------------------

try:
    with engine.begin() as connection:

        # Refuse to append into tables that already have data.
        # This avoids accidental duplicate loads.
        for _, table_name in LOAD_PLAN:
            count = connection.execute(
                text(f'SELECT COUNT(*) FROM raw."{table_name}"')
            ).scalar_one()

            if count > 0:
                raise RuntimeError(
                    f"raw.{table_name} already contains "
                    f"{count:,} rows. Load stopped to avoid duplicates."
                )

        for filename, table_name in LOAD_PLAN:
            csv_path = DATA_DIR / filename
            loaded_rows = 0

            print(f"\nLoading {filename}...")

            # Read large files in batches to limit memory use.
            for chunk in pd.read_csv(csv_path, chunksize=50_000):
                chunk = prepare_chunk(chunk, table_name)

                chunk.to_sql(
                    name=table_name,
                    con=connection,
                    schema="raw",
                    if_exists="append",
                    index=False,
                    chunksize=5_000,
                    method="multi",
                )

                loaded_rows += len(chunk)

            print(
                f"Loaded {loaded_rows:,} rows "
                f"into raw.{table_name}"
            )

    print("\nAll CSV files loaded successfully!")

except Exception:
    print(
        "\nIngestion failed. The current run's database "
        "transaction has been rolled back."
    )
    raise

finally:
    engine.dispose()
