#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.13.5"
# dependencies = [
#   "boto3",
#   "psycopg",
#   "duckdb",
#   "requests",
# ]
# ///

import os
import time

import duckdb
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config
import psycopg
import requests

def wait_for_postgres(host="postgres", user=None, password=None, db=None, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            conn = psycopg.connect(
                host=host, user=user, password=password, dbname=db, connect_timeout=2
            )
            conn.close()
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError("Postgres did not become ready in time")

def wait_for_minio(endpoint, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            resp = requests.head(f"{endpoint}/minio/health/live", timeout=2)
            if resp.status_code == 200:
                return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("MinIO did not become ready in time")

def main():
    # Load environment
    pg_user   = os.environ["POSTGRES_USER"]
    pg_pass   = os.environ["POSTGRES_PASSWORD"]
    pg_db     = os.environ["POSTGRES_DB"]
    aws_key    = os.environ["AWS_ACCESS_KEY_ID"]
    aws_secret = os.environ["AWS_SECRET_ACCESS_KEY"]
    aws_region = os.environ.get("AWS_REGION", "us-east-1")
    aws_ep     = os.environ["AWS_ENDPOINT_URL"]
    bucket     = os.environ["BUCKET"]

    # Wait for dependencies
    wait_for_postgres(user=pg_user, password=pg_pass, db=pg_db)
    wait_for_minio(aws_ep)

    # Ensure bucket exists
    s3 = boto3.client(
        "s3",
        endpoint_url=aws_ep,
        aws_access_key_id=aws_key,
        aws_secret_access_key=aws_secret,
        region_name=aws_region,
        config=Config(signature_version='s3v4')
    )
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError:
        s3.create_bucket(Bucket=bucket)

    # Initialize or attach DuckLake
    con = duckdb.connect()
    con.execute("INSTALL ducklake;")
    con.execute("INSTALL postgres;")

    attach_sql = f"""
    ATTACH 'ducklake:postgres:dbname={pg_db} host=postgres user={pg_user} password={pg_pass}'
    AS the_ducklake (DATA_PATH 's3://{bucket}/lake/');
    """
    con.execute(attach_sql)
    con.execute("USE the_ducklake;")

    # Keep the container alive
    print("DuckLake init complete; container is now running.")
    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()