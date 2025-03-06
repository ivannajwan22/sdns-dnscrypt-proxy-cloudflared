# Tahap Build
FROM --platform=$BUILDPLATFORM golang:alpine AS build

RUN apk --no-cache add ca-certificates git build-base bash gcc musl-dev binutils-gold upx

# Build sdns
WORKDIR /src/sdns
ARG TARGETARCH
ENV GOARCH=${TARGETARCH}
ENV CGO_ENABLED=1
COPY go.mod go.sum ./
RUN go mod download && go mod verify && go mod tidy
COPY . ./
RUN go build -trimpath -ldflags "-linkmode external -extldflags -static -s -w" -o /sdns && \
    strip --strip-all /sdns && \
    upx -7 --no-lzma /sdns

# Tahap Runtime
FROM busybox:stable-musl

COPY --from=build /sdns /usr/local/bin/sdns
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 53/tcp 53/udp 6053/tcp 6053/udp 5053/tcp 5053/udp 853 8053 8080

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=2 \
    CMD nslookup -type=a google.com ${SDNS_CHECK:-127.0.0.1:53} || exit 1

CMD ["sdns"]