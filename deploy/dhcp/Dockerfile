FROM python:3.12.14-slim-trixie@sha256:7a8b475003c4fe15a2cd4e55e5cfc2f3560bdc9333d624f24cdd6d4340fd7a17
RUN apt-get update \
    && apt-get install --yes --no-install-recommends kea-dhcp4-server \
    && rm -rf /var/lib/apt/lists/*
