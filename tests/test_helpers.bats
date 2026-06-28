#!/usr/bin/env bats
# Unit tests for the opt() and yaml_bool_or_str() helper functions.

load helpers/common

setup() {
    setup_tmpdir
    load_invidious_run "${FIXTURES_DIR}/options_defaults.json"
}

teardown() {
    teardown_tmpdir
}

# ---------------------------------------------------------------------------
# opt()
# ---------------------------------------------------------------------------

@test "opt: reads an existing string key" {
    result="$(opt log_level)"
    [ "${result}" = "Info" ]
}

@test "opt: reads a boolean key as string" {
    result="$(opt popular_enabled)"
    [ "${result}" = "true" ]
}

@test "opt: reads an integer key as string" {
    result="$(opt pool_size)"
    [ "${result}" = "100" ]
}

@test "opt: returns empty string for a missing key" {
    result="$(opt nonexistent_key)"
    [ -z "${result}" ]
}

@test "opt: returns empty string for an explicitly-empty string value" {
    result="$(opt domain)"
    [ -z "${result}" ]
}

@test "opt: reads a float key correctly (jq preserves decimal point)" {
    result="$(opt speed)"
    # jq 1.7+ preserves trailing zeros: 1.0 stays "1.0", not "1"
    [ "${result}" = "1.0" ]
}

@test "opt: reads array length correctly via jq" {
    count="$(jq '.feed_menu | length' "${OPTIONS}")"
    [ "${count}" = "4" ]
}

# Regression: opt() previously used `// empty` which jq treats as "return
# the alternative when the value is false OR null", silently dropping every
# boolean false value and emitting an empty string instead.
@test "opt: boolean false is returned as the string 'false', not empty" {
    # statistics_enabled defaults to false in options_defaults.json
    result="$(opt statistics_enabled)"
    [ "${result}" = "false" ]
}

@test "opt: boolean true is returned as the string 'true'" {
    result="$(opt popular_enabled)"
    [ "${result}" = "true" ]
}

@test "opt: null-valued key returns empty (not the string 'null')" {
    local opts_with_null="${TEST_TMPDIR}/opts_null.json"
    jq '.domain = null' "${OPTIONS}" > "${opts_with_null}"
    OPTIONS="${opts_with_null}"
    result="$(opt domain)"
    [ -z "${result}" ]
}

# ---------------------------------------------------------------------------
# yaml_bool_or_str()
# ---------------------------------------------------------------------------

@test "yaml_bool_or_str: 'true' passes through unquoted" {
    result="$(yaml_bool_or_str "true")"
    [ "${result}" = "true" ]
}

@test "yaml_bool_or_str: 'false' passes through unquoted" {
    result="$(yaml_bool_or_str "false")"
    [ "${result}" = "false" ]
}

@test "yaml_bool_or_str: string 'dash' is wrapped in double quotes" {
    result="$(yaml_bool_or_str "dash")"
    [ "${result}" = '"dash"' ]
}

@test "yaml_bool_or_str: string 'invidious' is wrapped in double quotes" {
    result="$(yaml_bool_or_str "invidious")"
    [ "${result}" = '"invidious"' ]
}

@test "yaml_bool_or_str: empty string is wrapped in double quotes" {
    result="$(yaml_bool_or_str "")"
    [ "${result}" = '""' ]
}

@test "yaml_bool_or_str: numeric-looking string is wrapped in double quotes" {
    result="$(yaml_bool_or_str "42")"
    [ "${result}" = '"42"' ]
}

@test "yaml_bool_or_str: 'True' (capital T) is NOT treated as boolean" {
    result="$(yaml_bool_or_str "True")"
    [ "${result}" = '"True"' ]
}

@test "yaml_bool_or_str: 'False' (capital F) is NOT treated as boolean" {
    result="$(yaml_bool_or_str "False")"
    [ "${result}" = '"False"' ]
}
