#!/usr/bin/env bash
# Build one of the Skald examples.
#
# Usage:
#   ./build.sh                       # builds 01_hello (default)
#   ./build.sh 01_hello              # builds examples/01_hello
#   ./build.sh 01_hello run          # builds and runs
#   RELEASE=1 ./build.sh …           # strips the F12 debug inspector
#
# Examples build with -debug by default so the F12 inspector is
# available while exercising the gallery. Shipping apps should build
# without -debug (the whole inspector is `when ODIN_DEBUG`-gated, so
# release binaries don't contain the code or the F12 handler).
#
# The -collection:gui flag points at the project root so `import "gui:skald"`
# resolves the same way from any example.
#
# Runa is the pure-Odin text engine that replaces fontstash. The
# vendored copy ships inside Skald at skald/third_party/runa/, so
# clones of Skald build standalone — no sibling checkout needed.
# Override RUNA_PATH=/path/to/checkout to develop against an external
# runa tree (the runa-integration soak path).
# Pass SKALD_RUNA=1 to actually route text through runa; without it
# the collection is still resolved (the import statement is
# unconditional) but fontstash drives the renderer.
set -euo pipefail

cd "$(dirname "$0")"

EXAMPLE="${1:-01_hello}"
ACTION="${2:-build}"

mkdir -p build

DEBUG_FLAG="-debug"
if [[ "${RELEASE:-0}" == "1" ]]; then
    DEBUG_FLAG="-o:speed"
fi

RUNA_PATH="${RUNA_PATH:-./skald/third_party}"
RUNA_DEFINE=""
if [[ "${SKALD_RUNA:-0}" == "1" ]]; then
    RUNA_DEFINE="-define:SKALD_RUNA=true"
fi

odin build "examples/${EXAMPLE}" \
    -collection:gui=. \
    -collection:runa="${RUNA_PATH}" \
    ${DEBUG_FLAG} \
    ${RUNA_DEFINE} \
    -out:"build/${EXAMPLE}"

if [[ "$ACTION" == "run" ]]; then
    exec "./build/${EXAMPLE}"
fi
