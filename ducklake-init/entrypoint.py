#!/usr/bin/env -S uv run --script --prerelease=allow
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
from string import Template
import time

import duckdb
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config
import psycopg
import requests


def dump_duckdbrc():
    tpl = Template(open("/duckdbrc.tpl").read())
    content = tpl.substitute(
        AWS_ACCESS_KEY_ID=os.environ["AWS_ACCESS_KEY_ID"],
        AWS_SECRET_ACCESS_KEY=os.environ["AWS_SECRET_ACCESS_KEY"],
        AWS_REGION=os.environ.get("AWS_REGION", "us-east-1"),
        POSTGRES_DB=os.environ["POSTGRES_DB"],
        POSTGRES_USER=os.environ["POSTGRES_USER"],
        POSTGRES_PASSWORD=os.environ["POSTGRES_PASSWORD"],
        BUCKET=os.environ["BUCKET"],
    )
    with open("/root/.duckdbrc", "w") as f:
        f.write(content)


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

    # 1) Render ~/.duckdbrc so both CLI and Python API sessions will
    #    pick up the HTTPFS settings + auto-ATTACH.
    dump_duckdbrc()

    # 2) Wait on Postgres & MinIO, ensure bucket, then bootstrap/attach via Python API…
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

    # 1) install extensions
    con.install_extension("ducklake")
    con.install_extension("postgres")  

    # 2) configure HTTPFS for MinIO
    for key, val in {
        "s3_url_style":    "path",
        "s3_endpoint":     "minio:9000",
        "s3_access_key_id":     os.environ["AWS_ACCESS_KEY_ID"],
        "s3_secret_access_key": os.environ["AWS_SECRET_ACCESS_KEY"],
        "s3_region":            os.environ.get("AWS_REGION", "us-east-1"),
        "s3_use_ssl":           "false",
    }.items():
        con.execute(f"SET {key}='{val}';")

    # 3) now attach/initialize DuckLake
    attach_sql = f"""
    ATTACH 'ducklake:postgres:dbname={pg_db} host=postgres user={pg_user} password={pg_pass}'
    AS the_ducklake (DATA_PATH 's3://{bucket}/lake/');
    """
    con.execute(attach_sql)
    con.execute("USE the_ducklake;")

    # 4)Keep the container alive
    print("DuckLake init complete; container is now running.")
    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()