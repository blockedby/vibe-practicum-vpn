#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   sudo scripts/local/try-create-ap-hotspot.sh --iface wlan0 --uplink eth0 --ssid MyHotspot --pass MyPassword
#   sudo scripts/local/try-create-ap-hotspot.sh --stop --iface wlan0
#
# Minimal AP smoke-test wrapper for create_ap/linux-wifi-hotspot.

ACTION="start"
IFACE="wlan0"
UPLINK="eth0"
SSID="MyHotspot"
PASS="MyPassword"

USAGE='Usage: try-create-ap-hotspot.sh --iface wlan0 --uplink eth0 --ssid SSID --pass PASS | --stop --iface wlan0'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)
      IFACE=${2:?}
      shift 2
      ;;
    --uplink)
      UPLINK=${2:?}
      shift 2
      ;;
    --ssid)
      SSID=${2:?}
      shift 2
      ;;
    --pass)
      PASS=${2:?}
      shift 2
      ;;
    --stop)
      ACTION="stop"
      shift
      ;;
    -h|--help)
      echo "$USAGE"
      exit 0
      ;;
    *)
      echo "unknown arg: $1"
      echo "$USAGE"
      exit 1
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo), needed for iw/networking" >&2
  exit 1
fi

if ! command -v iw >/dev/null 2>&1; then
  echo "error: iw not installed (pacman -S iw)"
  exit 1
fi

echo "Checking AP mode on $IFACE..."
if ! iw dev "$IFACE" info >/dev/null 2>&1; then
  echo "error: interface $IFACE not found"
  exit 1
fi

PHY_INDEX=$(iw dev "$IFACE" info | awk '/wiphy/{print $2}')
if [[ -z "$PHY_INDEX" ]]; then
  echo "warning: could not map $IFACE to a PHY; AP mode check limited"
else
  PHY="phy${PHY_INDEX}"
  if iw phy "$PHY" info | awk '/Supported interface modes:/{flag=1;next}/^[^[:space:]]/{flag=0}flag' | grep -qE '^[[:space:]]*\* AP$' ; then
    echo "AP mode: present"
  else
    echo "warning: AP mode not confirmed on $IFACE (PHY: $PHY)"
  fi
fi

HAS_CREATE_AP=0
HAS_WIFI_HOTSPOT=0
if command -v create_ap >/dev/null 2>&1; then
  HAS_CREATE_AP=1
fi
if command -v wifi-hotspot >/dev/null 2>&1; then
  HAS_WIFI_HOTSPOT=1
fi

if [[ "$ACTION" == "stop" ]]; then
  if [[ $HAS_CREATE_AP -eq 1 ]]; then
    echo "Stopping create_ap on $IFACE"
    create_ap --stop "$IFACE" || true
  elif [[ $HAS_WIFI_HOTSPOT -eq 1 ]]; then
    echo "Stopping wifi-hotspot"
    if wifi-hotspot --stop 2>/dev/null; then
      :
    else
      wifi-hotspot || true
    fi
  else
    echo "No AP control tool installed; nothing to stop"
  fi
  exit 0
fi

if [[ $HAS_CREATE_AP -eq 0 && $HAS_WIFI_HOTSPOT -eq 0 ]]; then
  echo "error: create_ap/linux-wifi-hotspot not installed"
  echo "Install steps on Arch:"
  echo "  sudo pacman -S iw dnsmasq iptables iproute2 hostapd"
  echo "  yay -S linux-wifi-hotspot"
  exit 1
fi

# verify uplink
if ! ip link show "$UPLINK" >/dev/null 2>&1; then
  echo "warning: uplink '$UPLINK' not found"
  GATE_IF=$(ip route | awk '/^default/{print $5; exit}')
  if [[ -n "${GATE_IF:-}" && "$GATE_IF" != "$IFACE" && -n "$GATE_IF" ]]; then
    echo "Using detected default route interface as uplink: $GATE_IF"
    UPLINK=$GATE_IF
  else
    echo "No alternate uplink interface detected"
    if [[ $HAS_WIFI_HOTSPOT -eq 1 ]]; then
      echo "Falling back to wifi-hotspot"
      echo "Starting wifi-hotspot (uses configured defaults in application)"
      wifi-hotspot --start
      exit $?
    fi
    echo "error: can't start create_ap without valid uplink interface"
    ip -br link
    exit 1
  fi
fi

if [[ $HAS_CREATE_AP -eq 1 ]]; then
  echo "Starting create_ap hotspot: iface=$IFACE uplink=$UPLINK ssid=$SSID"
  create_ap "$IFACE" "$UPLINK" "$SSID" "$PASS"
else
  echo "Starting wifi-hotspot (uses configured defaults in application)"
  wifi-hotspot --start
fi
