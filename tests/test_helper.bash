# Common helpers for the bats suites.

# Puts a stub bin directory first on PATH; call from setup().
setup_stub_path() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    PATH="$STUB_BIN:$PATH"
    return 0
}

# stub_command <name> <script body...> — creates an executable stub on the stub PATH.
stub_command() {
    local name=$1
    shift
    printf '#!/usr/bin/env bash\n%s\n' "$*" > "$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
    return 0
}
