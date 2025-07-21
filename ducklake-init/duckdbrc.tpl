-- ducklake-init/duckdbrc.tpl

-- DuckDB + MinIO HTTPFS config
SET s3_url_style           = 'path';
SET s3_endpoint            = 'minio:9000';
SET s3_access_key_id       = '$AWS_ACCESS_KEY_ID';
SET s3_secret_access_key   = '$AWS_SECRET_ACCESS_KEY';
SET s3_region              = '$AWS_REGION';
SET s3_use_ssl             = false;

-- Auto-attach your lakehouse
ATTACH 'ducklake:postgres:dbname=$POSTGRES_DB host=postgres user=$POSTGRES_USER password=$POSTGRES_PASSWORD'
AS the_ducklake  (DATA_PATH 's3://$BUCKET/lake/');
USE the_ducklake;