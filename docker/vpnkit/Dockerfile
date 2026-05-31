FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl iproute2 iptables nftables openvpn tcpdump bash procps \
 && curl -fsSL -o /tmp/sing-box.deb https://github.com/SagerNet/sing-box/releases/download/v1.10.7/sing-box_1.10.7_linux_amd64.deb \
 && apt-get install -y /tmp/sing-box.deb \
 && rm -rf /var/lib/apt/lists/* /tmp/sing-box.deb
COPY entrypoint.sh setup-routing.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-routing.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
