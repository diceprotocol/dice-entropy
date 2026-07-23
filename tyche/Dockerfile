ARG RUST_VERSION=1.88.0

FROM rust:${RUST_VERSION} AS build

WORKDIR /src
COPY . .

RUN --mount=type=cache,target=/root/.cargo/registry \
    cargo build --release

FROM rust:${RUST_VERSION}
COPY --from=build /src/target/release/tyche /usr/local/bin/
