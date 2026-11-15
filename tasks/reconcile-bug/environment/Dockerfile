FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY reconcile.py /app/reconcile.py

CMD ["bash"]
