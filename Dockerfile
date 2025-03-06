# Build sdns (isolated with golang:bookworm)
FROM golang:bookworm AS sdns-build
RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*
# Unduh UPX manual dari GitHub
RUN wget -O /tmp/upx.tar.xz https://github.com/upx/upx/releases/download/v5.0.0/upx-5.0.0-arm64_linux.tar.xz && \
    tar -xJf /tmp/upx.tar.xz -C /usr/local/bin --strip-components=1 upx-5.0.0-arm64_linux/upx && \
    rm /tmp/upx.tar.xz
WORKDIR /src/sdns
COPY go.mod go.sum ./
RUN go mod download && go mod verify && go mod tidy
COPY . ./
ARG TARGETOS TARGETARCH TARGETVARIANT
RUN CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT#v} \
    go build -trimpath -ldflags "-linkmode external -extldflags -static -s -w" -o /sdns && \
    strip --strip-all /sdns && \
    upx -7 --no-lzma /sdns && \
    file /sdns

# Build dnscrypt-proxy
FROM golang:alpine AS dnscrypt-build
RUN apk --no-cache add ca-certificates git build-base upx
WORKDIR /src/dnscrypt_proxy
ARG DNSCRYPT_PROXY_VERSION=master
ADD https://github.com/ivannajwan22/dnscrypt-proxy/archive/${DNSCRYPT_PROXY_VERSION}.tar.gz /tmp/dnscrypt-proxy.tar.gz
RUN tar xzf /tmp/dnscrypt-proxy.tar.gz --strip 1
WORKDIR /src/dnscrypt_proxy/dnscrypt-proxy
RUN go mod download && go mod verify && go mod tidy
ARG TARGETOS TARGETARCH TARGETVARIANT
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT#v} \
    go build -v -ldflags="-s -w" -o /dnscrypt-proxy
WORKDIR /config/dnscrypt_proxy
RUN cp -a /src/dnscrypt_proxy/dnscrypt-proxy.toml /config/dnscrypt_proxy/dnscrypt-proxy.toml

# Build cloudflared
FROM golang:alpine AS cloudflared-build
RUN apk --no-cache add ca-certificates git build-base bash gcc musl-dev binutils-gold upx
WORKDIR /src/cloudflared
ARG VERSION=master
ENV GO111MODULE=on CGO_ENABLED=0
RUN git clone --depth=1 --branch ${VERSION} https://github.com/cloudflare/cloudflared.git . && \
    go mod download && go mod verify && go mod tidy && \
    bash -x .teamcity/install-cloudflare-go.sh
ARG TARGETOS TARGETARCH TARGETVARIANT
RUN if [ "${TARGETVARIANT}" = "v6" ] && [ "${TARGETARCH}" = "arm" ]; then export GOARM=6; fi && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CONTAINER_BUILD=1 make LINK_FLAGS="-w -s" cloudflared && \
    mv cloudflared /cloudflared

# Tahap Runtime
FROM busybox:stable-musl
COPY --from=cloudflared-build /cloudflared /usr/local/bin/cloudflared
COPY --from=sdns-build /sdns /usr/local/bin/sdns
COPY --from=dnscrypt-build /dnscrypt-proxy /usr/local/bin/dnscrypt-proxy
COPY --from=dnscrypt-build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=dnscrypt-build /config/dnscrypt_proxy /config/dnscrypt_proxy
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 53/tcp 53/udp 6053/tcp 6053/udp 5053/tcp 5053/udp 853 8053 8080

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=2 \
    CMD nslookup -type=a google.com ${CLOUDFLARED_CHECK:-127.0.0.1:5053} && \
        nslookup -type=a google.com ${SDNS_CHECK:-127.0.0.1:53} && \
        nslookup -type=a google.com ${DNSCRYPT_CHECK:-127.0.0.1:6053} || exit 1

CMD ["/start.sh"]
