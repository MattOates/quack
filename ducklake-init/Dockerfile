FROM ghcr.io/astral-sh/uv:bookworm-slim

# Install OS libs needed for healthchecks & building psycopg2
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      libpq-dev \
      build-essential \
 && rm -rf /var/lib/apt/lists/*

# Install the latest duckdb CLI client
RUN curl https://install.duckdb.org | sh
ENV PATH="/root/.duckdb/cli/latest:$PATH"
CMD duckdb --version

# Copy DuckDB CLI init file so every duckdb session picks up MinIO settings
COPY duckdbrc.tpl /duckdbrc.tpl

COPY entrypoint.py /entrypoint.py
RUN chmod +x /entrypoint.py

ENTRYPOINT ["/entrypoint.py"]