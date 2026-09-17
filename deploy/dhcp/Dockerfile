FROM python:3.12.14-slim-trixie@sha256:7a8b475003c4fe15a2cd4e55e5cfc2f3560bdc9333d624f24cdd6d4340fd7a17
RUN apt-get update \
    && apt-get install --yes --no-install-recommends kea-dhcp4-server \
    && rm -rf /var/lib/apt/lists/*

# Share configuration and control with the unprivileged application (UID/GID 1000).
RUN mkdir -p /etc/kea /dhcp/control /var/lib/kea \
    && chown -R 1000:1000 /etc/kea /dhcp/control /var/lib/kea \
    && chmod 2770 /etc/kea /var/lib/kea \
    && chown 0:1000 /dhcp/control \
    && chmod 0750 /dhcp/control \
    && rm -f /etc/kea/kea-dhcp4.conf
