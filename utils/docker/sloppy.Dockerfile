# syntax=docker/dockerfile:1.7
FROM swift:6.2-jammy AS builder
RUN apt-get update && apt-get install -y libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
ARG SWIFT_BUILD_CONFIGURATION=release
COPY Package.swift ./
COPY Package.resolved ./
RUN --mount=type=cache,id=sloppy-swiftpm,target=/root/.swiftpm \
    --mount=type=cache,id=sloppy-swift-cache,target=/root/.cache \
    swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN --mount=type=cache,id=sloppy-swiftpm,target=/root/.swiftpm \
    --mount=type=cache,id=sloppy-swift-cache,target=/root/.cache \
    --mount=type=cache,id=sloppy-core-build,target=/workspace/.build \
    set -eux; \
    swift build -c "${SWIFT_BUILD_CONFIGURATION}" --product sloppy; \
    mkdir -p /artifacts; \
    mkdir -p /artifacts/Sloppy_sloppy.resources; \
    mkdir -p /artifacts/Sloppy_sloppy.bundle; \
    SLOPPY_BIN="$(find .build -type f -path "*/${SWIFT_BUILD_CONFIGURATION}/sloppy" | head -n 1)"; \
    strip "$SLOPPY_BIN" || true; \
    cp "$SLOPPY_BIN" /artifacts/sloppy; \
    RESOURCE_DIR="$(find .build -type d \( -name 'Sloppy_sloppy.resources' -o -name 'Sloppy_sloppy.bundle' \) | head -n 1 || true)"; \
    if [ -n "${RESOURCE_DIR}" ]; then \
    cp -R "$RESOURCE_DIR"/. "/artifacts/$(basename "$RESOURCE_DIR")"; \
    fi

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    libsqlite3-dev \
    libcurl4 \
    libxml2 \
    libicu70 \
    libbsd0 \
    libedit2 \
    libncursesw6 \
    zlib1g \
    libgcc-s1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /root
RUN mkdir -p /root/.sloppy /etc/sloppy /var/lib/sloppy
COPY --from=builder /usr/lib/swift /usr/lib/swift
COPY --from=builder /artifacts/sloppy /usr/bin/sloppy
COPY --from=builder /artifacts/Sloppy_sloppy.resources /usr/bin/Sloppy_sloppy.resources
COPY --from=builder /artifacts/Sloppy_sloppy.bundle /usr/bin/Sloppy_sloppy.bundle
EXPOSE 25101
CMD ["/usr/bin/sloppy"]
