#!/bin/bash
# shellcheck disable=SC1091
set -euo pipefail

source "${BASHIO_LIB:-/usr/lib/bashio/bashio.sh}"

OPTIONS="${OPTIONS:-/data/options.json}"
CONF_DIR="${CONF_DIR:-/etc/freeradius/3.0}"
CLIENTS_CONF="${CLIENTS_CONF:-${CONF_DIR}/clients.conf}"
USERS_FILE="${USERS_FILE:-${CONF_DIR}/mods-config/files/authorize}"
EAP_FILE="${EAP_FILE:-${CONF_DIR}/mods-available/eap}"
CERTS_DIR="${CERTS_DIR:-/data/certs}"
FREERADIUS_BIN="${FREERADIUS_BIN:-/usr/sbin/freeradius}"

# Uses select(. != null) so that boolean false is returned as "false" rather
# than being silently discarded by jq's // empty alternative operator.
opt() { jq -r --arg k "$1" '.[$k] | select(. != null)' "${OPTIONS}"; }

# Reads a scalar field nested under the top-level "eap" object.
eap_opt() { jq -r --arg k "$1" '.eap[$k] | select(. != null)' "${OPTIONS}"; }

# ---------------------------------------------------------------------------
# Self-signed CA + server certificate used for EAP-TLS/PEAP/TTLS's TLS
# tunnel. Generated once per install and persisted to /data rather than
# baked into the image, so every install that pulls this add-on doesn't
# share the same private key (same reasoning as the Cync LAN add-on's
# device certificate).
# ---------------------------------------------------------------------------
generate_certs() {
    mkdir -p "${CERTS_DIR}"

    if [[ -f "${CERTS_DIR}/ca.pem" && -f "${CERTS_DIR}/server.pem" && -f "${CERTS_DIR}/server.key" ]]; then
        return 0
    fi

    bashio::log.info "Generating a self-signed CA and server certificate for EAP-TLS/PEAP/TTLS..."

    openssl genrsa -out "${CERTS_DIR}/ca.key" 4096 >/dev/null 2>&1
    openssl req -x509 -new -nodes -key "${CERTS_DIR}/ca.key" -sha256 -days 3650 \
        -subj "/CN=FreeRADIUS-CA" -out "${CERTS_DIR}/ca.pem" >/dev/null 2>&1

    openssl genrsa -out "${CERTS_DIR}/server.key" 2048 >/dev/null 2>&1
    openssl req -new -key "${CERTS_DIR}/server.key" -subj "/CN=freeradius" \
        -out "${CERTS_DIR}/server.csr" >/dev/null 2>&1
    openssl x509 -req -in "${CERTS_DIR}/server.csr" -CA "${CERTS_DIR}/ca.pem" -CAkey "${CERTS_DIR}/ca.key" \
        -CAcreateserial -out "${CERTS_DIR}/server.pem" -days 3650 -sha256 >/dev/null 2>&1
    rm -f "${CERTS_DIR}/server.csr" "${CERTS_DIR}/ca.srl"

    chmod 600 "${CERTS_DIR}"/*.key
}

# ---------------------------------------------------------------------------
# clients.conf — NAS clients (e.g. the Hostapd add-on) allowed to send
# requests to this server.
# ---------------------------------------------------------------------------
write_clients_conf() {
    local count=0 name ipaddr secret client_json

    if [[ "$(jq '.clients | length' "${OPTIONS}")" -eq 0 ]]; then
        bashio::log.fatal "No RADIUS clients configured. Add at least one entry to clients. Refusing to start."
        return 1
    fi

    while IFS= read -r client_json; do
        name="$(jq -r '.name | select(. != null)' <<<"${client_json}")"
        ipaddr="$(jq -r '.ipaddr | select(. != null)' <<<"${client_json}")"
        secret="$(jq -r '.secret | select(. != null)' <<<"${client_json}")"

        if [[ -z "${name}" || -z "${ipaddr}" || -z "${secret}" ]]; then
            bashio::log.fatal "A RADIUS client entry is missing name, ipaddr, or secret. Refusing to start."
            return 1
        fi
        count=$((count + 1))
    done < <(jq -c '.clients[]' "${OPTIONS}")

    bashio::log.info "Writing ${count} RADIUS client(s)..."

    {
        while IFS= read -r client_json; do
            name="$(jq -r '.name' <<<"${client_json}")"
            ipaddr="$(jq -r '.ipaddr' <<<"${client_json}")"
            secret="$(jq -r '.secret' <<<"${client_json}")"

            printf 'client %s {\n' "${name}"
            printf '    ipaddr = %s\n' "${ipaddr}"
            printf '    secret = %s\n' "${secret}"
            printf '}\n\n'
        done < <(jq -c '.clients[]' "${OPTIONS}")
    } > "${CLIENTS_CONF}"
}

# ---------------------------------------------------------------------------
# mods-config/files/authorize — local users for password-based EAP methods
# (PEAP/TTLS tunnel MSCHAPv2 needs the plaintext Cleartext-Password to
# validate the tunneled credentials). Not required for EAP-TLS-only setups,
# where the client certificate itself is the credential.
# ---------------------------------------------------------------------------
write_users_file() {
    local count=0 username password user_json

    {
        while IFS= read -r user_json; do
            username="$(jq -r '.username | select(. != null)' <<<"${user_json}")"
            password="$(jq -r '.password | select(. != null)' <<<"${user_json}")"

            [[ -z "${username}" ]] && continue

            printf '%s\tCleartext-Password := "%s"\n' "${username}" "${password}"
            count=$((count + 1))
        done < <(jq -c '.users[]' "${OPTIONS}")
    } > "${USERS_FILE}"

    if [[ "${count}" -eq 0 ]]; then
        bashio::log.warning "No RADIUS users configured — PEAP/TTLS logins will fail until at least one is added (not required for EAP-TLS-only setups)."
    fi
}

# ---------------------------------------------------------------------------
# Write the eap module config from scratch rather than patching the
# Debian package's shipped copy — patching in place means trusting that
# specific directives (e.g. require_client_cert) are present and
# uncommented in whatever version of the package happens to be installed,
# which isn't guaranteed. Generating the whole file keeps this in the same
# style as clients.conf/hostapd.conf above and removes that guesswork.
# ---------------------------------------------------------------------------
write_eap_config() {
    local eap_type verify_cert

    eap_type="$(eap_opt default_eap_type)"
    verify_cert="$([[ "$(eap_opt tls_verify_client_cert)" == "true" ]] && echo yes || echo no)"

    cat > "${EAP_FILE}" <<EOF
eap {
	default_eap_type = ${eap_type}
	timer_expire     = 60
	ignore_unknown_eap_types = no
	cisco_accounting_username_bug = no
	max_sessions = \${max_requests}

	tls-config tls-common {
		private_key_file = ${CERTS_DIR}/server.key
		certificate_file = ${CERTS_DIR}/server.pem
		ca_file = ${CERTS_DIR}/ca.pem
		random_file = /dev/urandom
		fragment_size = 1024
		include_length = yes
		check_crl = no
		cipher_list = "DEFAULT"
		require_client_cert = ${verify_cert}
		cache {
			enable = no
		}
		verify {
		}
		ocsp {
			enable = no
		}
	}

	tls {
		tls = tls-common
	}

	ttls {
		tls = tls-common
		default_eap_type = md5
		copy_request_to_tunnel = no
		use_tunneled_reply = no
		virtual_server = "inner-tunnel"
	}

	peap {
		tls = tls-common
		default_eap_type = mschapv2
		copy_request_to_tunnel = no
		use_tunneled_reply = no
		virtual_server = "inner-tunnel"
	}

	mschapv2 {
	}
}
EOF
}

main() {
    generate_certs
    write_clients_conf || return 1
    write_users_file
    write_eap_config

    bashio::log.info "Starting FreeRADIUS..."
    exec "${FREERADIUS_BIN}" -f -l stdout
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
