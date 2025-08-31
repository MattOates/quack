FROM ghcr.io/astral-sh/uv:bookworm-slim

ARG TARGETARCH

# Install OS libs needed for healthchecks & building psycopg2
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      libpq-dev \
      build-essential \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Install the latest preview duckdb CLI client
RUN curl -fL --progress-bar --output duckdb-binaries-linux-$TARGETARCH.zip https://artifacts.duckdb.org/latest/duckdb-binaries-linux-$TARGETARCH.zip && \
    unzip duckdb-binaries-linux-$TARGETARCH.zip && \
    unzip duckdb_cli-linux-$TARGETARCH.zip && \
    chmod +x duckdb && \
    mv duckdb /usr/local/bin/ && \
    rm -f *.zip

# Setup env for the latest preview duckdb CLI client
CMD ["duckdb", "--version"]

# Copy DuckDB CLI init file so every duckdb session picks up MinIO settings
COPY duckdbrc.tpl /duckdbrc.tpl

COPY entrypoint.py /entrypoint.py
RUN chmod +x /entrypoint.py

ENTRYPOINT ["/entrypoint.py"]