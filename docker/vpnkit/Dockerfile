FROM golang:1.24-bookworm AS vibe-vpn-builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/vibe-vpn ./cmd/vibe-vpn

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl iproute2 iptables nftables openvpn tcpdump bash procps tar \
 && curl -fsSL -o /tmp/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v1.13.11/sing-box-1.13.11-linux-amd64.tar.gz \
 && tar -xzf /tmp/sing-box.tar.gz -C /tmp \
 && install -m 0755 /tmp/sing-box-1.13.11-linux-amd64/sing-box /usr/local/bin/sing-box \
 && rm -rf /var/lib/apt/lists/* /tmp/sing-box.tar.gz /tmp/sing-box-1.13.11-linux-amd64
COPY --from=vibe-vpn-builder /out/vibe-vpn /usr/local/bin/vibe-vpn
COPY docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-routing.sh /usr/local/bin/vibe-vpn \
 && install -d -m 0755 /etc/vibe-vpn /var/lib/vibe-vpn /var/log/vibe-vpn
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
