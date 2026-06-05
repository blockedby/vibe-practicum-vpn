FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash ca-certificates curl dnsutils iproute2 iptables iputils-ping openvpn tcpdump procps \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh run-tests.sh profile-check.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/run-tests.sh /usr/local/bin/profile-check.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
