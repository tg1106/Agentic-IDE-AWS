# Sandbox image: python:3.12-slim + g++ for C++17 compilation.
# SAFETY: this image is run with --network none, --read-only, --cap-drop ALL,
# --pids-limit 64, --memory 256m, and a non-root --user flag by sandbox.py.
# Do not relax any of those flags without explicit approval (see AGENTS.md).
FROM python:3.12-slim

# Install g++ (Debian bookworm package — pinned via apt's reproducible cache).
# libstdc++ is pulled in as a dependency automatically.
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ \
 && rm -rf /var/lib/apt/lists/*

# Create a dedicated non-root user that matches a typical non-root host UID.
# sandbox.py passes --user $(id -u):$(id -g) at runtime, which overrides this,
# but having a non-root user baked in means the image is safe even if the
# --user flag is accidentally omitted.
RUN groupadd -g 1001 sandbox \
 && useradd  -u 1001 -g sandbox -s /bin/sh -M sandbox

USER sandbox
WORKDIR /work
