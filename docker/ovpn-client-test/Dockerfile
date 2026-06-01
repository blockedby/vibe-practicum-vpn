FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash ca-certificates curl dnsutils iproute2 iptables openvpn tcpdump procps \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh run-tests.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/run-tests.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
