#!/usr/bin/env bash
# =============================================================================
# Script Name: network_scanner.sh
# Description: Scan network for hosts, open ports and services
# Version:     1.1.0
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="1.1.0"

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
NETWORK_RANGE=""
TARGET_HOST=""
PORT_RANGE="1-1024"
TIMEOUT=1
SCAN_TYPE="ping"
OUTPUT_FILE=""
COMMON_PORTS=(21 22 23 25 53 80 110 143 443 445 3306 3389 5432 6379 8080 8443 27017)

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${RESET}
Network scanner for hosts and ports

${BOLD}USAGE:${RESET}
    ${SCRIPT_NAME} [OPTIONS]

${BOLD}OPTIONS:${RESET}
    -r, --range CIDR        Network range to scan (e.g., 192.168.1.0/24)
    -H, --host HOST         Single host to scan
    -p, --ports RANGE       Port range (default: 1-1024)
    -t, --timeout N         Timeout in seconds (default: 1)
    -T, --type TYPE         Scan type: ping|port|full (default: ping)
    -o, --output FILE       Save results to file
    -h, --help              Show this help

${BOLD}EXAMPLES:${RESET}
    ${SCRIPT_NAME} --range 192.168.1.0/24
    ${SCRIPT_NAME} --host 192.168.1.1 --type port
    ${SCRIPT_NAME} --range 10.0.0.0/24 --type full --output scan.txt
EOF
}

# ─── Parse Args ───────────────────────────────────────────────────────────────
parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--range)   NETWORK_RANGE="${2:?}"; shift ;;
            -H|--host)    TARGET_HOST="${2:?}"; shift ;;
            -p|--ports)   PORT_RANGE="${2:?}"; shift ;;
            -t|--timeout) TIMEOUT="${2:?}"; shift ;;
            -T|--type)    SCAN_TYPE="${2:?}"; shift ;;
            -o|--output)  OUTPUT_FILE="${2:?}"; shift ;;
            -h|--help)    usage; exit 0 ;;
            *)            echo "Unknown: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

# ─── CIDR to IP Range ─────────────────────────────────────────────────────────
cidr_to_hosts() {
    local cidr="$1"
    local network mask prefix

    network="${cidr%/*}"
    prefix="${cidr#*/}"

    # Convert network address to integer
    local IFS='.'
    read -ra octets <<< "${network}"
    IFS=$'\n\t'

    local net_int=$(( (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3] ))
    local host_bits=$(( 32 - prefix ))
    local num_hosts=$(( (1 << host_bits) - 2 ))  # Exclude network and broadcast

    local start=$(( net_int + 1 ))

    for (( i=0; i<num_hosts && i<254; i++ )); do
        local ip_int=$(( start + i ))
        printf "%d.%d.%d.%d\n" \
            "$(( (ip_int >> 24) & 255 ))" \
            "$(( (ip_int >> 16) & 255 ))" \
            "$(( (ip_int >> 8) & 255 ))" \
            "$(( ip_int & 255 ))"
    done
}

# ─── Ping Scan ────────────────────────────────────────────────────────────────
ping_host() {
    local host="$1"
    if ping -c 1 -W "${TIMEOUT}" "${host}" &>/dev/null 2>&1; then
        echo "${host}"
        return 0
    fi
    return 1
}

# ─── Port Scan ────────────────────────────────────────────────────────────────
scan_port() {
    local host="$1"
    local port="$2"

    if (echo >/dev/tcp/"${host}"/"${port}") &>/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ─── Get Service Name ─────────────────────────────────────────────────────────
get_service() {
    local port="$1"
    local services=(
        [21]="FTP"       [22]="SSH"      [23]="Telnet"  [25]="SMTP"
        [53]="DNS"       [80]="HTTP"     [110]="POP3"   [143]="IMAP"
        [443]="HTTPS"    [445]="SMB"     [3306]="MySQL" [3389]="RDP"
        [5432]="PostgreSQL" [6379]="Redis" [8080]="HTTP-Alt"
        [8443]="HTTPS-Alt" [27017]="MongoDB"
    )

    echo "${services[$port]:-Unknown}"
}

# ─── Scan Single Host Ports ───────────────────────────────────────────────────
scan_host_ports() {
    local host="$1"
    local open_ports=()

    echo -e "\n${BOLD}Scanning ports on ${host}...${RESET}"

    if [[ "${PORT_RANGE}" == "common" ]]; then
        # Scan common ports
        for port in "${COMMON_PORTS[@]}"; do
            if timeout "${TIMEOUT}" bash -c \
               "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
                local service
                service="$(get_service "${port}")"
                open_ports+=("${port}")
                printf "  ${GREEN}%-6s %-15s %s${RESET}\n" "${port}" "OPEN" "${service}"
            fi
        done
    else
        # Scan range
        local start_port end_port
        start_port="${PORT_RANGE%-*}"
        end_port="${PORT_RANGE#*-}"

        for (( port=start_port; port<=end_port; port++ )); do
            if timeout "${TIMEOUT}" bash -c \
               "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
                local service
                service="$(get_service "${port}")"
                open_ports+=("${port}")
                printf "  ${GREEN}%-6s %-15s %s${RESET}\n" "${port}" "OPEN" "${service}"
            fi
        done
    fi

    echo -e "  Open ports: ${#open_ports[@]}"
}

# ─── Network Ping Sweep ───────────────────────────────────────────────────────
ping_sweep() {
    local range="$1"
    local live_hosts=()
    local total=0
    local pids=()

    echo -e "\n${BOLD}Ping sweep: ${range}${RESET}"
    echo -e "Timeout: ${TIMEOUT}s per host\n"

    # Generate hosts list
    local hosts_file
    hosts_file="$(mktemp)"
    cidr_to_hosts "${range}" > "${hosts_file}"

    total="$(wc -l < "${hosts_file}")"
    echo -e "Scanning ${total} hosts...\n"

    printf "  %-20s %-15s %s\n" "IP Address" "Status" "Hostname"
    printf "  %s\n" "$(printf '─%.0s' {1..50})"

    # Parallel ping scan
    local results_file
    results_file="$(mktemp)"

    while IFS= read -r host; do
        {
            if ping -c 1 -W "${TIMEOUT}" "${host}" &>/dev/null 2>&1; then
                local hostname
                hostname="$(dig +short -x "${host}" 2>/dev/null | head -1 | \
                           sed 's/\.$//' || echo "N/A")"
                echo "${host}|UP|${hostname:-N/A}"
            fi
        } &

        # Limit parallel jobs
        if [[ $(jobs -r | wc -l) -ge 20 ]]; then
            wait -n 2>/dev/null || wait
        fi
    done < "${hosts_file}" >> "${results_file}"

    wait  # Wait for all background jobs

    # Display results
    local up_count=0
    while IFS='|' read -r ip status hostname; do
        printf "  ${GREEN}%-20s %-15s %s${RESET}\n" "${ip}" "${status}" "${hostname}"
        ((up_count++))
    done < <(sort -t. -k1,1n -k2,2n -k3,3n -k4,4n "${results_file}")

    echo ""
    echo -e "  ${GREEN}Live hosts: ${up_count}/${total}${RESET}"

    rm -f "${hosts_file}" "${results_file}"

    return "${up_count}"
}

# ─── Full Scan ────────────────────────────────────────────────────────────────
full_scan() {
    local target="$1"

    echo -e "\n${BOLD}Full scan: ${target}${RESET}"
    echo -e "${CYAN}═══════════════════════════════════${RESET}"

    # Basic info
    echo -e "\n${BOLD}Host Information:${RESET}"
    printf "  %-20s %s\n" "Target:"    "${target}"
    printf "  %-20s %s\n" "Timestamp:" "$(date '+%Y-%m-%d %H:%M:%S')"

    # DNS resolution
    local hostname
    hostname="$(dig +short "${target}" 2>/dev/null | head -1 || \
                host "${target}" 2>/dev/null | head -1 || echo "N/A")"
    printf "  %-20s %s\n" "Hostname:"  "${hostname}"

    # Ping test
    if ping -c 3 -W 2 "${target}" &>/dev/null 2>&1; then
        local rtt
        rtt="$(ping -c 3 "${target}" 2>/dev/null | \
               tail -1 | awk -F'/' '{print $5}' || echo "N/A")"
        printf "  %-20s ${GREEN}UP${RESET} (avg RTT: %sms)\n" "Status:" "${rtt}"
    else
        printf "  %-20s ${RED}DOWN or BLOCKED${RESET}\n" "Status:"
    fi

    # OS detection (basic TTL analysis)
    local ttl
    ttl="$(ping -c 1 "${target}" 2>/dev/null | grep -oP 'ttl=\K[0-9]+' || echo 0)"
    if [[ ${ttl} -gt 0 ]]; then
        local os_guess
        if [[ ${ttl} -le 64 ]]; then
            os_guess="Linux/Unix"
        elif [[ ${ttl} -le 128 ]]; then
            os_guess="Windows"
        else
            os_guess="Network Device"
        fi
        printf "  %-20s %s (TTL: %s)\n" "OS Guess:" "${os_guess}" "${ttl}"
    fi

    # Port scan
    echo -e "\n${BOLD}Port Scan (Common Ports):${RESET}"
    printf "  %-8s %-15s %-15s %s\n" "PORT" "STATE" "SERVICE" "VERSION"
    printf "  %s\n" "$(printf '─%.0s' {1..60})"

    for port in "${COMMON_PORTS[@]}"; do
        if timeout "${TIMEOUT}" bash -c \
           "echo >/dev/tcp/${target}/${port}" 2>/dev/null; then
            local service
            service="$(get_service "${port}")"

            # Try to grab banner
            local banner
            banner="$(timeout 2 bash -c \
                "echo '' | nc -w2 ${target} ${port} 2>/dev/null | head -1 | tr -d '\r\n'" \
                2>/dev/null | cut -c1-30 || echo "")"

            printf "  ${GREEN}%-8s %-15s %-15s %s${RESET}\n" \
                "${port}/tcp" "open" "${service}" "${banner}"
        fi
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "\n${BOLD}${BLUE}╔═══════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║  Network Scanner v${VERSION}      ║${RESET}"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════╝${RESET}"

    # Redirect output if requested
    if [[ -n "${OUTPUT_FILE}" ]]; then
        exec > >(tee -a "${OUTPUT_FILE}")
        log_info "Saving results to: ${OUTPUT_FILE}"
    fi

    case "${SCAN_TYPE}" in
        ping)
            if [[ -n "${NETWORK_RANGE}" ]]; then
                ping_sweep "${NETWORK_RANGE}"
            elif [[ -n "${TARGET_HOST}" ]]; then
                if ping_host "${TARGET_HOST}"; then
                    echo -e "${GREEN}${TARGET_HOST} is UP${RESET}"
                else
                    echo -e "${RED}${TARGET_HOST} is DOWN or unreachable${RESET}"
                fi
            fi
            ;;
        port)
            local target="${TARGET_HOST:-}"
            [[ -z "${target}" ]] && { echo "Host required for port scan (--host)"; exit 1; }
            scan_host_ports "${target}"
            ;;
        full)
            local target="${TARGET_HOST:-}"
            [[ -z "${target}" ]] && { echo "Host required for full scan (--host)"; exit 1; }
            full_scan "${target}"

            # Also sweep if range provided
            [[ -n "${NETWORK_RANGE}" ]] && ping_sweep "${NETWORK_RANGE}"
            ;;
        *)
            echo "Unknown scan type: ${SCAN_TYPE}"
            exit 1
            ;;
    esac

    echo ""
}

main "$@"
