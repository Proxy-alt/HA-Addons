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
    CONFIG_LINK="${TEST_TMPDIR}/opt-config.yml"
    OPTIONS_SNAPSHOT="${CONFIG_DIR}/.last_options.json"
    HMAC_KEY="${hmac_key}"
}

# ---------------------------------------------------------------------------
# Source fabric-server run.sh with mocked environment.
# main() is guarded by a BASH_SOURCE check so only functions and globals load.
# After sourcing, path/endpoint variables are pointed at the temp dir.
# ---------------------------------------------------------------------------
load_fabric_run() {
    local fixture="${1:-${FIXTURES_DIR}/options_fabric_defaults.json}"

    export BASHIO_LIB="${MOCK_BASHIO}"

    # shellcheck source=/dev/null
    source "${REPO_DIR}/fabric-server/rootfs/run.sh"

    OPTIONS="${fixture}"
    SERVER_DIR="${TEST_TMPDIR}/server"
    ADDON_CONFIG_DIR="${TEST_TMPDIR}/addon_config"
    DATA_DIR="${TEST_TMPDIR}/data"
    MODS_DIR="${SERVER_DIR}/mods"
    MANAGED_FILE="${DATA_DIR}/.managed_mods"
    LAUNCHER_JAR="${SERVER_DIR}/fabric-server-launch.jar"
    VERSION_MARKER="${DATA_DIR}/.fabric_version"
    OPS_BASELINE="${DATA_DIR}/.synced_ops"
    WHITELIST_BASELINE="${DATA_DIR}/.synced_whitelist"
    JAVA_BIN="/bin/true"
    mkdir -p "${MODS_DIR}" "${DATA_DIR}" "${ADDON_CONFIG_DIR}"
}

# Offline curl replacement for fabric-server tests. Routes by URL:
#  * Modrinth version queries → one canned version, except slugs listed in
#    ${FABRIC_MOCK_EMPTY} (space-separated) which return an empty array.
#  * Mojang profile lookups   → a fixed UUID.
#  * Any download (-o <dest>) → writes a dummy file to <dest>.
# Define `curl() { fabric_mock_curl "$@"; }` in a test to activate it.
fabric_mock_curl() {
    local out="" url="" prev=""
    local a
    for a in "$@"; do
        if [[ "${prev}" == "-o" ]]; then out="${a}"; prev=""; continue; fi
        case "${a}" in
            -o) prev="-o";;
            http://*|https://*) url="${a}";;
        esac
    done

    if [[ -n "${out}" ]]; then
        echo "dummy" > "${out}"
        return 0
    fi

    case "${url}" in
        *meta.fabricmc.net/v2/versions/game*)
            echo '[{"version":"1.21.4","stable":true}]'
            ;;
        *meta.fabricmc.net/v2/versions/loader*)
            echo '[{"version":"0.16.10","stable":true}]'
            ;;
        *meta.fabricmc.net/v2/versions/installer*)
            echo '[{"version":"1.0.1","stable":true}]'
            ;;
        *api.modrinth.com/v2/project/*/version*)
            local slug="${url#*/project/}"; slug="${slug%%/version*}"
            if [[ " ${FABRIC_MOCK_EMPTY:-} " == *" ${slug} "* ]]; then
                echo "[]"
            else
                printf '[{"date_published":"2026-01-01T00:00:00Z","files":[{"primary":true,"url":"https://cdn.example/%s.jar","filename":"%s.jar"}]}]' "${slug}" "${slug}"
            fi
            ;;
        *api.mojang.com/users/profiles/minecraft/*)
            echo '{"id":"853c80ef3c3749fdaa49938b674adae6","name":"jeb_"}'
            ;;
        *) echo "[]";;
    esac
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
