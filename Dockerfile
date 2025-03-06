# Tahap Build
FROM --platform=$BUILDPLATFORM golang:alpine AS build

RUN apk --no-cache add ca-certificates git build-base bash gcc musl-dev g++ make linux-headers bash curl tar xz

WORKDIR /tmp/musl-cross-make
RUN curl -L https://github.com/richfelker/musl-cross-make/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1 && \
    echo "TARGET = aarch64-linux-musl" > config.mak && \
    echo "OUTPUT = /usr/local/musl-cross-make" >> config.mak && \
    make -j$(nproc)


ENV PATH="/usr/local/musl-cross-make/bin:$PATH"
RUN aarch64-linux-musl-gcc --version
RUN apk --no-cache add upx

# Build cloudflared
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

# Build sdns
WORKDIR /src/sdns
ARG TARGETARCH
ENV GOARCH=${TARGETARCH}
ENV CGO_ENABLED=1
ENV CC=aarch64-linux-musl-gcc
ENV AS=aarch64-linux-musl-as
RUN ${CC} --version
COPY go.mod go.sum ./
RUN go mod download && go mod verify && go mod tidy
COPY . ./
RUN go build -trimpath -ldflags "-linkmode external -extldflags -static -s -w" -o /sdns && \
    strip --strip-all /sdns && \
    upx -7 --no-lzma /sdns

# Build dnscrypt-proxy
WORKDIR /src/dnscrypt_proxy
ARG DNSCRYPT_PROXY_VERSION=master
ADD https://github.com/ivannajwan22/dnscrypt-proxy/archive/${DNSCRYPT_PROXY_VERSION}.tar.gz /tmp/dnscrypt-proxy.tar.gz
RUN tar xzf /tmp/dnscrypt-proxy.tar.gz --strip 1
WORKDIR /src/dnscrypt_proxy/dnscrypt-proxy
RUN go mod download && go mod verify && go mod tidy
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=${TARGETVARIANT#v} go build -v -ldflags="-s -w" -o /dnscrypt-proxy
WORKDIR /config/dnscrypt_proxy
RUN cp -a /src/dnscrypt_proxy/dnscrypt-proxy.toml /config/dnscrypt_proxy/dnscrypt-proxy.toml

# Tahap Runtime
FROM busybox:stable-musl

COPY --from=build /cloudflared /usr/local/bin/cloudflared
COPY --from=build /sdns /usr/local/bin/sdns
COPY --from=build /dnscrypt-proxy /usr/local/bin/dnscrypt-proxy
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /config/dnscrypt_proxy /config/dnscrypt_proxy
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 53/tcp 53/udp 6053/tcp 6053/udp 5053/tcp 5053/udp 853 8053 8080

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=2 \
    CMD nslookup -type=a google.com ${CLOUDFLARED_CHECK:-127.0.0.1:5053} && \
        nslookup -type=a google.com ${SDNS_CHECK:-127.0.0.1:53} && \
        nslookup -type=a google.com ${DNSCRYPT_CHECK:-127.0.0.1:6053} || exit 1

CMD ["/start.sh"]