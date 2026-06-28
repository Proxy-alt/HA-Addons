#!/usr/bin/env bats
# Tests for the write_invidious_config() function.
# Each test calls write_invidious_config() and inspects the generated YAML.

load helpers/common

setup() {
    setup_tmpdir
    load_invidious_run "${FIXTURES_DIR}/options_defaults.json"
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_config_gen() {
    local fixture="${1:-${FIXTURES_DIR}/options_defaults.json}"
    OPTIONS="${fixture}"
    write_invidious_config
}

# ---------------------------------------------------------------------------
# Regression: opt() false-value bug
# Previously opt() used `// empty` which jq evaluates as the alternative for
# both null AND false, causing every boolean false option to be written as an
# empty value (YAML null) instead of "false".
# ---------------------------------------------------------------------------

@test "boolean false options are written as 'false', not empty" {
    run_config_gen
    assert_file_contains 'https_only: false'
    assert_file_contains 'statistics_enabled: false'
    assert_file_contains 'full_refresh: false'
    assert_file_contains 'cache_annotations: false'
}

@test "boolean false user-preference options are written as 'false', not empty" {
    run_config_gen
    assert_file_contains '  thin_mode: false'
    assert_file_contains '  annotations: false'
    assert_file_contains '  autoplay: false'
    assert_file_contains '  listen: false'
    assert_file_contains '  save_player_pos: false'
}

# ---------------------------------------------------------------------------
# YAML validity
# ---------------------------------------------------------------------------

@test "default options produce valid YAML" {
    run_config_gen
    assert_valid_yaml "${CONFIG_FILE}"
}

@test "options with companion produce valid YAML" {
    run_config_gen "${FIXTURES_DIR}/options_companion.json"
    assert_valid_yaml "${CONFIG_FILE}"
}

@test "options with http proxy produce valid YAML" {
    run_config_gen "${FIXTURES_DIR}/options_http_proxy_auth.json"
    assert_valid_yaml "${CONFIG_FILE}"
}

@test "options with admins produce valid YAML" {
    run_config_gen "${FIXTURES_DIR}/options_admins.json"
    assert_valid_yaml "${CONFIG_FILE}"
}

@test "options with alt domains produce valid YAML" {
    run_config_gen "${FIXTURES_DIR}/options_alt_domains.json"
    assert_valid_yaml "${CONFIG_FILE}"
}

# ---------------------------------------------------------------------------
# DB section
# ---------------------------------------------------------------------------

@test "config contains hardcoded db credentials" {
    run_config_gen
    assert_file_contains 'user: kemal'
    assert_file_contains 'password: kemal'
    assert_file_contains 'host: 127.0.0.1'
    assert_file_contains 'port: 5432'
    assert_file_contains 'dbname: invidious'
}

@test "check_tables: true is written from defaults" {
    run_config_gen
    assert_file_contains 'check_tables: true'
}

# ---------------------------------------------------------------------------
# Server section
# ---------------------------------------------------------------------------

@test "port is always hardcoded to 3000" {
    run_config_gen
    assert_file_contains 'port: 3000'
}

@test "host_binding is always 0.0.0.0" {
    run_config_gen
    assert_file_contains 'host_binding: "0.0.0.0"'
}

@test "hmac_key is written from the HMAC_KEY variable" {
    run_config_gen
    assert_file_contains 'hmac_key: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"'
}

@test "external_port=0 is omitted from the config" {
    run_config_gen
    assert_file_not_contains 'external_port'
}

@test "external_port=8080 is included in the config" {
    run_config_gen "${FIXTURES_DIR}/options_external_port.json"
    assert_file_contains 'external_port: 8080'
}

@test "alternative_domains block is omitted when list is empty" {
    run_config_gen
    assert_file_not_contains 'alternative_domains'
}

@test "alternative_domains block is written when list is non-empty" {
    run_config_gen "${FIXTURES_DIR}/options_alt_domains.json"
    assert_file_contains 'alternative_domains:'
    assert_file_contains '  - "inv.onion"'
    assert_file_contains '  - "inv.i2p"'
}

# ---------------------------------------------------------------------------
# Outbound network section
# ---------------------------------------------------------------------------

@test "http_proxy block is omitted when host is empty" {
    run_config_gen
    assert_file_not_contains 'http_proxy:'
}

@test "http_proxy block appears when host is set" {
    run_config_gen "${FIXTURES_DIR}/options_http_proxy.json"
    assert_file_contains 'http_proxy:'
    assert_file_contains '  host: "proxy.internal"'
    assert_file_contains '  port: 8080'
}

@test "http_proxy user and password are omitted when empty" {
    run_config_gen "${FIXTURES_DIR}/options_http_proxy.json"
    # Use quoted patterns to distinguish proxy "user:" from db "user: kemal"
    assert_file_not_contains '  user: "'
    assert_file_not_contains '  password: "'
}

@test "http_proxy user and password are included when set" {
    run_config_gen "${FIXTURES_DIR}/options_http_proxy_auth.json"
    assert_file_contains '  user: "proxyuser"'
    assert_file_contains '  password: "proxypass"'
}

@test "disable_proxy false is written as YAML boolean false" {
    run_config_gen
    assert_file_contains 'disable_proxy: false'
}

@test "pool_size integer is written correctly" {
    run_config_gen
    assert_file_contains 'pool_size: 100'
}

@test "force_resolve is omitted when empty" {
    run_config_gen
    assert_file_not_contains 'force_resolve:'
}

@test "cookies field is omitted when empty" {
    run_config_gen
    assert_file_not_contains 'cookies:'
}

# ---------------------------------------------------------------------------
# Users & accounts section
# ---------------------------------------------------------------------------

@test "admins block is omitted when list is empty" {
    run_config_gen
    assert_file_not_contains 'admins:'
}

@test "admins block is written when list is non-empty" {
    run_config_gen "${FIXTURES_DIR}/options_admins.json"
    assert_file_contains 'admins:'
    assert_file_contains '  - "admin1"'
    assert_file_contains '  - "admin2"'
}

# ---------------------------------------------------------------------------
# Miscellaneous section
# ---------------------------------------------------------------------------

@test "banner is omitted when empty" {
    run_config_gen
    assert_file_not_contains 'banner:'
}

@test "banner is written when set" {
    run_config_gen "${FIXTURES_DIR}/options_admins.json"
    assert_file_contains 'banner: "Welcome to this Invidious instance!"'
}

@test "use_pubsub_feeds 'false' produces YAML false" {
    run_config_gen
    assert_file_contains 'use_pubsub_feeds: false'
}

@test "use_pubsub_feeds 'true' produces YAML true" {
    local opts="${TEST_TMPDIR}/opts_pubsub.json"
    jq '.use_pubsub_feeds = "true"' "${FIXTURES_DIR}/options_defaults.json" > "${opts}"
    OPTIONS="${opts}"
    write_invidious_config
    assert_file_contains 'use_pubsub_feeds: true'
}

@test "use_pubsub_feeds integer string produces plain integer" {
    local opts="${TEST_TMPDIR}/opts_pubsub_int.json"
    jq '.use_pubsub_feeds = "5"' "${FIXTURES_DIR}/options_defaults.json" > "${opts}"
    OPTIONS="${opts}"
    write_invidious_config
    assert_file_contains 'use_pubsub_feeds: 5'
}

@test "use_pubsub_feeds invalid string falls back to false" {
    local opts="${TEST_TMPDIR}/opts_pubsub_bad.json"
    jq '.use_pubsub_feeds = "yes"' "${FIXTURES_DIR}/options_defaults.json" > "${opts}"
    OPTIONS="${opts}"
    write_invidious_config
    assert_file_contains 'use_pubsub_feeds: false'
}

# ---------------------------------------------------------------------------
# Companion section
# ---------------------------------------------------------------------------

@test "companion block is omitted when companion_private_url is empty" {
    run_config_gen
    assert_file_not_contains 'invidious_companion:'
    assert_file_not_contains 'invidious_companion_key:'
}

@test "companion block is written when companion_private_url is set" {
    run_config_gen "${FIXTURES_DIR}/options_companion.json"
    assert_file_contains 'invidious_companion:'
    assert_file_contains '  - private_url: "http://companion:8282/companion"'
    assert_file_contains 'invidious_companion_key: "secret1234567890"'
}

@test "companion public_url is written when set" {
    run_config_gen "${FIXTURES_DIR}/options_companion.json"
    assert_file_contains '    public_url: "https://companion.example.com"'
}

@test "companion public_url is omitted when empty" {
    local opts="${TEST_TMPDIR}/opts_companion_nopub.json"
    jq '.companion_public_url = ""' "${FIXTURES_DIR}/options_companion.json" > "${opts}"
    OPTIONS="${opts}"
    write_invidious_config
    assert_file_not_contains 'public_url:'
}

# BUG: companion_key empty while companion_private_url is set — no validation
@test "BUG: empty companion_key is silently written when companion_private_url is set" {
    run_config_gen "${FIXTURES_DIR}/options_companion_no_key.json"
    # The companion block is generated even with an empty key — this is a bug
    assert_file_contains 'invidious_companion_key: ""'
}

# ---------------------------------------------------------------------------
# Default user preferences
# ---------------------------------------------------------------------------

@test "locale is written in user preferences" {
    run_config_gen
    assert_file_contains '  locale: "en-US"'
}

@test "feed_menu list items are written under default_user_preferences" {
    run_config_gen
    assert_file_contains '  feed_menu:'
    assert_file_contains '    - "Popular"'
    assert_file_contains '    - "Trending"'
    assert_file_contains '    - "Subscriptions"'
    assert_file_contains '    - "Playlists"'
}

@test "empty feed_menu produces an empty YAML sequence, not null" {
    run_config_gen "${FIXTURES_DIR}/options_empty_feed_menu.json"

    local feed_menu_type
    feed_menu_type="$(python3 -c "
import yaml, sys
with open('${CONFIG_FILE}') as f:
    cfg = yaml.safe_load(f)
prefs = cfg.get('default_user_preferences', {})
val = prefs.get('feed_menu')
print(type(val).__name__)
")"
    [ "${feed_menu_type}" = "list" ]
}

@test "captions are written as a 3-element list" {
    run_config_gen "${FIXTURES_DIR}/options_empty_feed_menu.json"
    assert_file_contains '  captions:'
    assert_file_contains '    - "English"'
    assert_file_contains '    - "Spanish"'
}

@test "comments are written as a 2-element list" {
    run_config_gen
    assert_file_contains '  comments:'
    assert_file_contains '    - "youtube"'
}

# comments_2 default is "" — this always emits an empty string entry in the list
@test "empty comments_2 always emits an empty string entry in the comments list" {
    run_config_gen
    # Check that an empty-string entry exists in the comments block
    assert_file_matches '    - ""'
}
