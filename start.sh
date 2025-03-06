#!/bin/sh

# Jalankan cloudflared dengan opsi dari variabel lingkungan
export TUNNEL_ORIGIN_CERT=${TUNNEL_ORIGIN_CERT:-/etc/cloudflared/cert.pem}
export NO_AUTOUPDATE=${NO_AUTOUPDATE:-true}
CLOUDFLARED_OPTS=${CLOUDFLARED_OPTS:---no-autoupdate proxy-dns --address 0.0.0.0 --address ::0 --port 5053}
/usr/local/bin/cloudflared $CLOUDFLARED_OPTS &

# Jalankan sdns dengan opsi dari variabel lingkungan
SDNS_OPTS=${SDNS_OPTS:-}  # Default kosong, sesuaikan kalo ada opsi wajib
/usr/local/bin/sdns $SDNS_OPTS &

# Jalankan dnscrypt-proxy dengan opsi dari variabel lingkungan
DNSCRYPT_OPTS=${DNSCRYPT_OPTS:--config /config/dnscrypt_proxy/dnscrypt-proxy.toml}
/usr/local/bin/dnscrypt-proxy $DNSCRYPT_OPTS &

# Jaga container tetap hidup
tail -f /dev/null