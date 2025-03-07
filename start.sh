#!/bin/sh

# Fungsi untuk menjalankan aplikasi dengan prefix log
run_app() {
    app_name="$1"
    app_bin="$2"
    app_opts="$3"
    echo "[$app_name] Starting $app_name..."
    ($app_bin $app_opts 2>&1 | sed "s/^/[$app_name] /") &
    pid=$!
    echo "[$app_name] PID: $pid"
    eval "${app_name}_pid=$pid"  # Simpan PID untuk monitoring
}

# Trap untuk handle shutdown gracefully
trap 'echo "Shutting down..."; kill -TERM $sdns_pid $dnscrypt_pid $cloudflared_pid; wait; exit 0' TERM INT

# Konfigurasi dan jalankan sdns
SDNS_OPTS=${SDNS_OPTS:-}
run_app "sdns" "/usr/local/bin/sdns" "$SDNS_OPTS"

# Konfigurasi dan jalankan dnscrypt-proxy
DNSCRYPT_OPTS=${DNSCRYPT_OPTS:--config /config/dnscrypt_proxy/dnscrypt-proxy.toml}
run_app "dnscrypt" "/usr/local/bin/dnscrypt-proxy" "$DNSCRYPT_OPTS"

# Konfigurasi dan jalankan cloudflared
TUNNEL_ORIGIN_CERT=${TUNNEL_ORIGIN_CERT:-/etc/cloudflared/cert.pem}
NO_AUTOUPDATE=${NO_AUTOUPDATE:-true}
export TUNNEL_ORIGIN_CERT NO_AUTOUPDATE
CLOUDFLARED_OPTS=${CLOUDFLARED_OPTS:---no-autoupdate proxy-dns --address 0.0.0.0 --address ::0 --port 5053 --max-upstream-conns 0}
run_app "cloudflared" "/usr/local/bin/cloudflared" "$CLOUDFLARED_OPTS"

# Tunggu semua proses selesai (gantikan tail -f /dev/null)
wait