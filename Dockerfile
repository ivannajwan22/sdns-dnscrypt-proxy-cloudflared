# Stage 1: Build Stage
FROM golang:alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    ca-certificates \
    gcc \
    git \
    musl-dev \
    binutils-gold \
    upx

# Define architecture as a build argument
ARG TARGETARCH
ENV GOARCH=${TARGETARCH}

# Set working directory
WORKDIR /src

# Copy Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source code
COPY . .

# Build the sdns binary with static linking
RUN go build -trimpath -ldflags "-linkmode external -extldflags -static -s -w" -o /tmp/sdns && \
    strip --strip-all /tmp/sdns && \
    upx --best /tmp/sdns

# Stage 2: Runtime Stage
FROM scratch

# Copy necessary files for runtime
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /tmp/sdns /sdns

# Expose necessary ports
EXPOSE 53/tcp 53/udp 853 8053 8080

# Set the entrypoint
ENTRYPOINT ["/sdns"]