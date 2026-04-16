#!/usr/bin/env bash
# =============================================================================
# Script Name: log_analyzer.sh
# Description: Parse and analyze log files with pattern matching and reporting
# Version:     1.2.0
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="1.2.0"

# ─── Colors ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
LOG_FILE=""
LOG_TYPE="auto"
TOP_COUNT=10
OUTPUT_FORMAT="text"
FILTER_LEVEL=""
DATE_FROM=""
DATE_TO=""
SEARCH_PATTERN=""
OUTPUT_FILE=""

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${RESET}
Advanced log file analyzer

${BOLD}USAGE:${RESET}
    ${SCRIPT_NAME} --file LOG_FILE [OPTIONS]

${BOLD}REQUIRED:${RESET}
    -f, --file FILE         Log file to analyze

${BOLD}OPTIONS:${RESET}
    -t, --type TYPE         Log type: apache|nginx|syslog|auth|auto (default: auto)
    -n, --top N             Show top N results (default: 10)
    --format FORMAT         Output format: text|csv|json (default: text)
    --level LEVEL           Filter by level: ERROR|WARN|INFO|DEBUG
    --from DATE             Start date (YYYY-MM-DD)
    --to DATE               End date (YYYY-MM-DD)
    -p, --pattern PATTERN   Search for pattern (grep regex)
    -o, --output FILE       Write output to file
    -h, --help              Show this help

${BOLD}EXAMPLES:${RESET}
    ${SCRIPT_NAME} --file /var/log/apache2/access.log --top 10
    ${SCRIPT_NAME} --file /var/log/syslog --level ERROR --from 2024-01-01
    ${SCRIPT_NAME} --file /var/log/auth.log --pattern "Failed password"
    ${SCRIPT_NAME} --file /var/log/nginx/access.log --format csv --output report.csv
EOF
}

# ─── Parse Args ───────────────────────────────────────────────────────────────
parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file)      LOG_FILE="${2:?'Log file required'}"; shift ;;
            -t|--type)      LOG_TYPE="${2:?'Log type required'}"; shift ;;
            -n|--top)       TOP_COUNT="${2:?'Count required'}"; shift ;;
            --format)       OUTPUT_FORMAT="${2:?'Format required'}"; shift ;;
            --level)        FILTER_LEVEL="${2:?'Level required'}"; shift ;;
            --from)         DATE_FROM="${2:?'Date required'}"; shift ;;
            --to)           DATE_TO="${2:?'Date required'}"; shift ;;
            -p|--pattern)   SEARCH_PATTERN="${2:?'Pattern required'}"; shift ;;
            -o|--output)    OUTPUT_FILE="${2:?'Output file required'}"; shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              echo "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

# ─── Detect Log Type ──────────────────────────────────────────────────────────
detect_log_type() {
    local file="$1"

    if [[ "${LOG_TYPE}" != "auto" ]]; then
        return
    fi

    # Check filename patterns
    case "$(basename "${file}")" in
        access.log*|*access*)    LOG_TYPE="apache" ;;
        error.log*)              LOG_TYPE="apache_error" ;;
        auth.log*|secure*)       LOG_TYPE="auth" ;;
        syslog*|messages*)       LOG_TYPE="syslog" ;;
        *)
            # Check content
            local first_line
            first_line="$(head -1 "${file}" 2>/dev/null)"
            if echo "${first_line}" | grep -qE '"\w+ /[^ ]+ HTTP/[0-9.]+'; then
                LOG_TYPE="apache"
            elif echo "${first_line}" | grep -qE '^[A-Z][a-z]{2}\s+[0-9]'; then
                LOG_TYPE="syslog"
            else
                LOG_TYPE="generic"
            fi
            ;;
    esac

    echo -e "${CYAN}Detected log type: ${LOG_TYPE}${RESET}"
}

# ─── Header ───────────────────────────────────────────────────────────────────
print_section() {
    echo -e "\n${BOLD}${BLUE}▶ $1${RESET}"
    printf "  %s\n" "$(printf '─%.0s' {1..50})"
}

# ─── General Stats ────────────────────────────────────────────────────────────
analyze_general() {
    local file="$1"

    print_section "General Statistics"

    local total_lines size first_entry last_entry

    total_lines="$(wc -l < "${file}")"
    size="$(du -sh "${file}" | cut -f1)"
    first_entry="$(head -1 "${file}" 2>/dev/null | cut -c1-80)"
    last_entry="$(tail -1 "${file}" 2>/dev/null | cut -c1-80)"

    printf "  %-25s %s\n" "File:"         "${file}"
    printf "  %-25s %s\n" "Size:"         "${size}"
    printf "  %-25s %s\n" "Total Lines:"  "${total_lines}"
    printf "  %-25s %s\n" "Log Type:"     "${LOG_TYPE}"

    # Error/Warning counts
    local error_count warn_count
    error_count="$(grep -ciE '(error|critical|fatal|crit)' "${file}" 2>/dev/null || echo 0)"
    warn_count="$(grep -ciE '(warn|warning)' "${file}" 2>/dev/null || echo 0)"

    printf "  %-25s ${RED}%s${RESET}\n"    "Error/Critical:"  "${error_count}"
    printf "  %-25s ${YELLOW}%s${RESET}\n" "Warnings:"        "${warn_count}"
    printf "  %-25s %s\n" "First Entry:"  "${first_entry}"
    printf "  %-25s %s\n" "Last Entry:"   "${last_entry}"
}

# ─── Apache/Nginx Analysis ────────────────────────────────────────────────────
analyze_apache() {
    local file="$1"

    print_section "HTTP Request Analysis"

    # Total requests
    local total_reqs
    total_reqs="$(wc -l < "${file}")"
    printf "  %-25s %s\n" "Total Requests:" "${total_reqs}"

    # Top IP addresses
    print_section "Top ${TOP_COUNT} IP Addresses"
    printf "  %-8s %s\n" "COUNT" "IP ADDRESS"
    printf "  %s\n" "$(printf '─%.0s' {1..40})"
    awk '{print $1}' "${file}" | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{printf "  %-8s %s\n", $1, $2}'

    # HTTP Status codes
    print_section "HTTP Status Code Distribution"
    printf "  %-8s %-8s %s\n" "COUNT" "CODE" "DESCRIPTION"
    printf "  %s\n" "$(printf '─%.0s' {1..50})"
    awk '{print $9}' "${file}" | \
        sort | uniq -c | sort -rn | \
        awk '{
            desc = "Unknown"
            if ($2 == 200) desc = "OK"
            else if ($2 == 301) desc = "Moved Permanently"
            else if ($2 == 302) desc = "Found (Redirect)"
            else if ($2 == 400) desc = "Bad Request"
            else if ($2 == 401) desc = "Unauthorized"
            else if ($2 == 403) desc = "Forbidden"
            else if ($2 == 404) desc = "Not Found"
            else if ($2 == 500) desc = "Internal Server Error"
            else if ($2 == 503) desc = "Service Unavailable"
            printf "  %-8s %-8s %s\n", $1, $2, desc
        }'

    # Top requested URLs
    print_section "Top ${TOP_COUNT} Requested URLs"
    printf "  %-8s %s\n" "COUNT" "URL"
    printf "  %s\n" "$(printf '─%.0s' {1..60})"
    awk '{print $7}' "${file}" | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{printf "  %-8s %s\n", $1, $2}'

    # Top User Agents
    print_section "Top ${TOP_COUNT} User Agents"
    awk -F'"' '{print $6}' "${file}" | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{
            agent = ""
            for(i=2; i<=NF; i++) agent = agent " " $i
            printf "  %-8s %s\n", $1, substr(agent, 1, 60)
        }'

    # Traffic by hour
    print_section "Traffic by Hour"
    awk '{print $4}' "${file}" | \
        cut -d: -f2 | \
        sort | uniq -c | \
        awk '{printf "  Hour %s: %s requests\n", $2, $1}'

    # Error requests (4xx, 5xx)
    print_section "Error Requests (4xx, 5xx)"
    awk '$9 ~ /^[45]/' "${file}" | \
        awk '{printf "  [%s] %s → %s %s\n", $9, $1, $6, $7}' | \
        head -"${TOP_COUNT}"

    # Bandwidth analysis
    print_section "Bandwidth Analysis"
    awk '$10 ~ /^[0-9]+$/ {total += $10; count++}
         END {
             printf "  Total Bytes: %d\n", total
             printf "  Avg Bytes/req: %.0f\n", total/count
         }' "${file}"
}

# ─── Auth Log Analysis ────────────────────────────────────────────────────────
analyze_auth() {
    local file="$1"

    print_section "Authentication Analysis"

    # Failed logins
    local failed_count
    failed_count="$(grep -c "Failed password" "${file}" 2>/dev/null || echo 0)"
    local success_count
    success_count="$(grep -c "Accepted" "${file}" 2>/dev/null || echo 0)"

    printf "  %-25s ${RED}%s${RESET}\n"   "Failed Logins:"     "${failed_count}"
    printf "  %-25s ${GREEN}%s${RESET}\n" "Successful Logins:" "${success_count}"

    # Top attacking IPs
    print_section "Top ${TOP_COUNT} Attacking IPs"
    grep "Failed password" "${file}" 2>/dev/null | \
        awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{printf "  %-8s %s\n", $1, $2}'

    # Target usernames
    print_section "Top ${TOP_COUNT} Targeted Usernames"
    grep "Failed password" "${file}" 2>/dev/null | \
        awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}' | \
        grep -v "invalid" | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{printf "  %-8s %s\n", $1, $2}'

    # Successful logins
    print_section "Recent Successful Logins"
    grep "Accepted" "${file}" 2>/dev/null | \
        awk '{printf "  %s %s %s - User: %s From: %s\n", $1, $2, $3, $9, $11}' | \
        tail -"${TOP_COUNT}"

    # Login attempts by hour
    print_section "Failed Login Attempts by Hour"
    grep "Failed password" "${file}" 2>/dev/null | \
        awk '{print $3}' | cut -d: -f1 | \
        sort | uniq -c | \
        awk '{printf "  %s:00 - %s attempts\n", $2, $1}'
}

# ─── Syslog Analysis ──────────────────────────────────────────────────────────
analyze_syslog() {
    local file="$1"

    print_section "Syslog Analysis"

    # Events by severity
    print_section "Events by Severity Level"
    for level in EMERGENCY ALERT CRITICAL ERROR WARNING NOTICE INFO DEBUG; do
        local count
        count="$(grep -ci "${level}" "${file}" 2>/dev/null || echo 0)"
        [[ ${count} -gt 0 ]] && printf "  %-12s %s\n" "${level}:" "${count}"
    done

    # Events by service
    print_section "Top ${TOP_COUNT} Services"
    awk '{print $5}' "${file}" | \
        sed 's/\[.*//' | \
        sort | uniq -c | sort -rn | \
        head -"${TOP_COUNT}" | \
        awk '{printf "  %-8s %s\n", $1, $2}'

    # Recent errors
    print_section "Recent Error Messages"
    grep -iE "(error|critical|fail|fatal)" "${file}" 2>/dev/null | \
        tail -"${TOP_COUNT}" | \
        awk '{
            line = ""
            for(i=5; i<=NF; i++) line = line " " $i
            printf "  [%s %s %s] %s\n", $1, $2, $3, substr(line, 1, 70)
        }'
}

# ─── Pattern Search ───────────────────────────────────────────────────────────
search_pattern() {
    local file="$1"
    local pattern="$2"

    print_section "Pattern Search: '${pattern}'"

    local match_count
    match_count="$(grep -c "${pattern}" "${file}" 2>/dev/null || echo 0)"
    printf "  %-25s %s\n" "Matches Found:" "${match_count}"

    echo ""
    grep -n "${pattern}" "${file}" 2>/dev/null | \
        head -"${TOP_COUNT}" | \
        awk -F: '{printf "  Line %-6s %s\n", $1":", substr($0, index($0,$2))}'
}

# ─── Date Filtering ───────────────────────────────────────────────────────────
apply_date_filter() {
    local file="$1"
    local tmp_file

    if [[ -z "${DATE_FROM}" && -z "${DATE_TO}" ]]; then
        echo "${file}"
        return
    fi

    tmp_file="$(mktemp /tmp/log_filter_XXXXXX)"

    if [[ -n "${DATE_FROM}" && -n "${DATE_TO}" ]]; then
        awk -v from="${DATE_FROM}" -v to="${DATE_TO}" '
            {
                # Extract date from common log formats
                match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)
                date = substr($0, RSTART, RLENGTH)
                if (date >= from && date <= to) print
            }
        ' "${file}" > "${tmp_file}"
    elif [[ -n "${DATE_FROM}" ]]; then
        awk -v from="${DATE_FROM}" '
            {
                match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)
                date = substr($0, RSTART, RLENGTH)
                if (date >= from) print
            }
        ' "${file}" > "${tmp_file}"
    fi

    echo "${tmp_file}"
}

# ─── Output to CSV ────────────────────────────────────────────────────────────
output_csv() {
    local file="$1"
    local csv_file="${OUTPUT_FILE:-log_analysis_${TIMESTAMP}.csv}"

    echo "ip,requests,timestamp" > "${csv_file}"
    awk '{print $1}' "${file}" | \
        sort | uniq -c | sort -rn | \
        awk -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            '{printf "%s,%s,%s\n", $2, $1, ts}' >> "${csv_file}"

    echo -e "${GREEN}CSV exported to: ${csv_file}${RESET}"
}

# ─── Output to JSON ───────────────────────────────────────────────────────────
output_json() {
    local file="$1"
    local json_file="${OUTPUT_FILE:-log_analysis_${TIMESTAMP}.json}"

    {
        echo "{"
        echo "  \"generated\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        echo "  \"log_file\": \"${file}\","
        echo "  \"log_type\": \"${LOG_TYPE}\","
        echo "  \"total_lines\": $(wc -l < "${file}"),"
        echo "  \"top_ips\": ["

        local first=true
        awk '{print $1}' "${file}" | \
            sort | uniq -c | sort -rn | \
            head -"${TOP_COUNT}" | \
            while read -r count ip; do
                [[ "${first}" == true ]] && first=false || echo ","
                printf '    {"ip": "%s", "requests": %s}' "${ip}" "${count}"
            done
        echo ""
        echo "  ]"
        echo "}"
    } > "${json_file}"

    echo -e "${GREEN}JSON exported to: ${json_file}${RESET}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    # Validate
    [[ -z "${LOG_FILE}" ]] && { echo "Log file required"; usage; exit 1; }
    [[ ! -f "${LOG_FILE}" ]] && { echo "File not found: ${LOG_FILE}"; exit 1; }
    [[ ! -r "${LOG_FILE}" ]] && { echo "File not readable: ${LOG_FILE}"; exit 1; }

    echo -e "\n${BOLD}${BLUE}╔══════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║    Log Analyzer v${VERSION}      ║${RESET}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════╝${RESET}\n"

    detect_log_type "${LOG_FILE}"

    # Apply date filter
    local working_file
    working_file="$(apply_date_filter "${LOG_FILE}")"

    # Run analysis
    analyze_general "${working_file}"

    case "${LOG_TYPE}" in
        apache|nginx) analyze_apache  "${working_file}" ;;
        auth)         analyze_auth    "${working_file}" ;;
        syslog)       analyze_syslog  "${working_file}" ;;
        *)            analyze_syslog  "${working_file}" ;;
    esac

    # Pattern search
    [[ -n "${SEARCH_PATTERN}" ]] && search_pattern "${working_file}" "${SEARCH_PATTERN}"

    # Output format
    case "${OUTPUT_FORMAT}" in
        csv)  output_csv  "${working_file}" ;;
        json) output_json "${working_file}" ;;
    esac

    # Cleanup temp file
    [[ "${working_file}" != "${LOG_FILE}" ]] && rm -f "${working_file}"

    echo -e "\n${GREEN}${BOLD}Analysis complete.${RESET}\n"
}

main "$@"
