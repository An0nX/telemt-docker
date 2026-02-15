# syntax=docker/dockerfile:1.7

ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main

FROM --platform=$TARGETPLATFORM rust:alpine AS build

ARG TELEMT_REPO
ARG TELEMT_REF

ENV CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_TERM_COLOR=always \
    CARGO_PROFILE_RELEASE_LTO=true \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
    CARGO_PROFILE_RELEASE_DEBUG=false \
    OPENSSL_STATIC=1

WORKDIR /src

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      ca-certificates git \
      build-base musl-dev pkgconf perl \
      binutils \
      openssl-dev openssl-libs-static \
      zlib-dev zlib-static \
    && update-ca-certificates

RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" . \
    || (git init . && git remote add origin "${TELEMT_REPO}" \
        && git fetch --depth=1 origin "${TELEMT_REF}" \
        && git checkout --detach FETCH_HEAD)

RUN rustup component add rustfmt

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    set -eux; \
    \
    cargo fmt --all; \
    \
    if [ ! -f Cargo.lock ]; then cargo generate-lockfile; fi; \
    \
    (cargo fix --bin "telemt" -p telemt --allow-dirty --allow-staged || true); \
    \
    cargo fmt --all; \
    \
    cargo build --release --locked --bin telemt; \
    \
    mkdir -p /out; \
    install -Dm755 target/release/telemt /out/telemt; \
    strip /out/telemt; \
    \
    if readelf -lW /out/telemt | grep -q "Requesting program interpreter"; then \
      echo "ERROR: telemt is dynamically linked -> cannot run in distroless/static"; \
      exit 1; \
    fi

FROM gcr.io/distroless/static:nonroot AS runtime

STOPSIGNAL SIGINT

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/telemt /usr/local/bin/telemt

WORKDIR /tmp

EXPOSE 443/tcp 9090/tcp

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/telemt"]
CMD ["/etc/telemt.toml"]
