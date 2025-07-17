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

COPY entrypoint.py /entrypoint.py
RUN chmod +x /entrypoint.py

ENTRYPOINT ["/entrypoint.py"]