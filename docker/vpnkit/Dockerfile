FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl iproute2 iptables nftables openvpn tcpdump bash procps tar \
 && curl -fsSL -o /tmp/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v1.13.11/sing-box-1.13.11-linux-amd64.tar.gz \
 && tar -xzf /tmp/sing-box.tar.gz -C /tmp \
 && install -m 0755 /tmp/sing-box-1.13.11-linux-amd64/sing-box /usr/local/bin/sing-box \
 && rm -rf /var/lib/apt/lists/* /tmp/sing-box.tar.gz /tmp/sing-box-1.13.11-linux-amd64
COPY entrypoint.sh setup-routing.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-routing.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
