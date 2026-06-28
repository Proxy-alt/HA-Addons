#!/usr/bin/env bash
# Shared helpers loaded by every bats test file via: load helpers/common

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
FIXTURES_DIR="${TESTS_DIR}/fixtures"
MOCK_BASHIO="${TESTS_DIR}/helpers/bashio_mock.sh"
MOCK_BIN_DIR="${TESTS_DIR}/mocks/bin"

# ---------------------------------------------------------------------------
# Per-test temp directory
# ---------------------------------------------------------------------------
setup_tmpdir() {
    TEST_TMPDIR="$(mktemp -d)"
}

teardown_tmpdir() {
    [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "${TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# Source invidious run.sh with mocked environment.
# main() is guarded by a BASH_SOURCE check in run.sh so only functions and
# global variable assignments execute on source — no postgres/invidious start.
# After sourcing, override path variables to point at safe temp locations.
# ---------------------------------------------------------------------------
load_invidious_run() {
    local fixture="${1:-${FIXTURES_DIR}/options_defaults.json}"
    local hmac_key="${2:-abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890}"

    export BASHIO_LIB="${MOCK_BASHIO}"
    export PATH="${MOCK_BIN_DIR}:${PATH}"

    # shellcheck source=/dev/null
    source "${REPO_DIR}/invidious/rootfs/run.sh"

    # Override path variables so tests write to a safe temp location.
    OPTIONS="${fixture}"
    CONFIG_DIR="${TEST_TMPDIR}/invidious"
    CONFIG_FILE="${TEST_TMPDIR}/config.yml"
    HMAC_KEY="${hmac_key}"
}

# ---------------------------------------------------------------------------
# YAML validation via python3 + PyYAML
# ---------------------------------------------------------------------------
assert_valid_yaml() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except Exception as e:
    print(f"Invalid YAML: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ---------------------------------------------------------------------------
# Simple string assertions (no bats-assert dependency required)
# ---------------------------------------------------------------------------
assert_file_contains() {
    local pattern="$1"
    local file="${CONFIG_FILE}"
    if ! grep -qF "${pattern}" "${file}"; then
        echo "ASSERTION FAILED: file does not contain: ${pattern}"
        echo "--- config file ---"
        cat "${file}"
        return 1
    fi
}

assert_file_not_contains() {
    local pattern="$1"
    local file="${CONFIG_FILE}"
    if grep -qF "${pattern}" "${file}"; then
        echo "ASSERTION FAILED: file should NOT contain: ${pattern}"
        echo "--- config file ---"
        cat "${file}"
        return 1
    fi
}

assert_file_matches() {
    local pattern="$1"
    local file="${CONFIG_FILE}"
    if ! grep -qE "${pattern}" "${file}"; then
        echo "ASSERTION FAILED: file does not match regex: ${pattern}"
        echo "--- config file ---"
        cat "${file}"
        return 1
    fi
}
