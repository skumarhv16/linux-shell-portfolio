#!/usr/bin/env bash
# =============================================================================
# Script Name: system_health_check.sh
# Description: Comprehensive system health monitoring and reporting tool
# Author:      Your Name
# Version:     2.0.0
# Usage:       ./system_health_check.sh [OPTIONS]
# Options:
#   -r, --report        Generate detailed HTML report
#   -e, --email EMAIL   Send report to email address
#   -t, --threshold N   Alert threshold percentage (default: 80)
#   -v, --verbose       Enable verbose output
#   -h, --help          Show this help message
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Constants ────────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="2.0.0"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_DIR="/var/log/health_check"
readonly LOG_FILE="${LOG_DIR}/health_${TIMESTAMP}.log"
readonly REPORT_DIR="/tmp/health_reports"
readonly REPORT_FILE="${REPORT_DIR}/report_${TIMESTAMP}.html"

# ─── Colors ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ─── Default Configuration ────────────────────────────────────────────────────
THRESHOLD=80
VERBOSE=false
GENERATE_REPORT=false
EMAIL_ADDRESS=""
ISSUES_FOUND=0

# ─── Logging Functions ────────────────────────────────────────────────────────
setup_logging() {
    mkdir -p "${LOG_DIR}" "${REPORT_DIR}" 2>/dev/null || {
        LOG_DIR="/tmp/health_check_logs"
        mkdir -p "${LOG_DIR}"
        LOG_FILE="${LOG_DIR}/health_${TIMESTAMP}.log"
    }
}

log() {
    local level="$1"
    shift
    local message="$*"
    local log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
    echo "${log_entry}" >> "${LOG_FILE}" 2>/dev/null || true

    case "${level}" in
        INFO)    echo -e "${GREEN}[INFO]${RESET}  ${message}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${RESET}  ${message}" ;;
        ERROR)   echo -e "${RED}[ERROR]${RESET} ${message}" >&2 ;;
        DEBUG)   [[ "${VERBOSE}" == true ]] && echo -e "${CYAN}[DEBUG]${RESET} ${message}" ;;
        HEADER)  echo -e "\n${BOLD}${BLUE}══ ${message} ══${RESET}" ;;
    esac
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${RESET}
Comprehensive system health monitoring tool

${BOLD}USAGE:${RESET}
    ${SCRIPT_NAME} [OPTIONS]

${BOLD}OPTIONS:${RESET}
    -r, --report          Generate HTML report
    -e, --email EMAIL     Send report to email
    -t, --threshold N     Alert threshold % (default: ${THRESHOLD})
    -v, --verbose         Verbose output
    -h, --help            Show this help

${BOLD}EXAMPLES:${RESET}
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --report --threshold 90
    ${SCRIPT_NAME} --report --email admin@example.com
EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--report)    GENERATE_REPORT=true ;;
            -e|--email)     EMAIL_ADDRESS="${2:?'Email address required'}"; shift ;;
            -t|--threshold) THRESHOLD="${2:?'Threshold value required'}"; shift ;;
            -v|--verbose)   VERBOSE=true ;;
            -h|--help)      usage; exit 0 ;;
            *)              log ERROR "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    # Validate threshold
    if ! [[ "${THRESHOLD}" =~ ^[0-9]+$ ]] || \
       [[ "${THRESHOLD}" -lt 1 ]] || [[ "${THRESHOLD}" -gt 100 ]]; then
        log ERROR "Threshold must be a number between 1 and 100"
        exit 1
    fi
}

# ─── Dependency Check ─────────────────────────────────────────────────────────
check_dependencies() {
    local deps=("awk" "df" "free" "uptime" "ps" "grep" "sed" "cut")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing required commands: ${missing[*]}"
        exit 1
    fi

    log DEBUG "All dependencies satisfied"
}

# ─── System Information ───────────────────────────────────────────────────────
get_system_info() {
    log HEADER "System Information"

    local hostname os_info kernel arch uptime_info

    hostname="$(hostname -f 2>/dev/null || hostname)"
    kernel="$(uname -r)"
    arch="$(uname -m)"
    uptime_info="$(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}' | awk '{print $3,$4}')"

    # Get OS info cross-platform
    if [[ -f /etc/os-release ]]; then
        os_info="$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    elif command -v lsb_release &>/dev/null; then
        os_info="$(lsb_release -d | cut -f2)"
    else
        os_info="$(uname -s)"
    fi

    printf "  %-20s %s\n" "Hostname:"    "${hostname}"
    printf "  %-20s %s\n" "OS:"          "${os_info}"
    printf "  %-20s %s\n" "Kernel:"      "${kernel}"
    printf "  %-20s %s\n" "Architecture:" "${arch}"
    printf "  %-20s %s\n" "Uptime:"      "${uptime_info}"
    printf "  %-20s %s\n" "Date/Time:"   "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "  %-20s %s\n" "Current User:" "$(whoami)"

    log DEBUG "System info collected"
}

# ─── CPU Analysis ─────────────────────────────────────────────────────────────
check_cpu() {
    log HEADER "CPU Usage"

    local cpu_usage cpu_cores load_avg_1 load_avg_5 load_avg_15

    # CPU usage via top (1 sample)
    cpu_usage="$(top -bn1 | grep "Cpu(s)" | \
        awk '{print $2 + $4}' | \
        awk '{printf "%.1f", $1}')"

    # Fallback for different top formats
    if [[ -z "${cpu_usage}" ]]; then
        cpu_usage="$(vmstat 1 1 2>/dev/null | tail -1 | awk '{print 100 - $15}')"
    fi

    cpu_cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"

    # Load averages
    read -r load_avg_1 load_avg_5 load_avg_15 _ < /proc/loadavg

    printf "  %-25s %s%%\n" "CPU Usage:" "${cpu_usage:-N/A}"
    printf "  %-25s %s\n"   "CPU Cores:" "${cpu_cores}"
    printf "  %-25s %s, %s, %s\n" "Load Average (1/5/15m):" \
        "${load_avg_1}" "${load_avg_5}" "${load_avg_15}"

    # CPU model
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model
        cpu_model="$(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
        printf "  %-25s %s\n" "CPU Model:" "${cpu_model}"
    fi

    # Alert check
    local cpu_int="${cpu_usage%.*}"
    if [[ "${cpu_int:-0}" -ge "${THRESHOLD}" ]]; then
        log WARN "CPU usage is HIGH: ${cpu_usage}% (threshold: ${THRESHOLD}%)"
        ((ISSUES_FOUND++))
        return 1
    else
        log INFO "CPU usage is normal: ${cpu_usage}%"
    fi

    return 0
}

# ─── Memory Analysis ──────────────────────────────────────────────────────────
check_memory() {
    log HEADER "Memory Usage"

    local total used free available cached mem_percent swap_total swap_used swap_percent

    # Parse /proc/meminfo for accurate readings
    if [[ -f /proc/meminfo ]]; then
        total="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
        free="$(awk '/MemFree/ {print $2}' /proc/meminfo)"
        available="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
        cached="$(awk '/^Cached/ {print $2}' /proc/meminfo)"
        swap_total="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
        swap_used="$(awk '/SwapFree/ {print $2}' /proc/meminfo)"
        used=$(( total - available ))
        mem_percent=$(( used * 100 / total ))

        # Convert kB to human-readable
        local to_mb=$(( 1024 ))
        printf "  %-20s %s MB\n" "Total Memory:"  "$(( total / to_mb ))"
        printf "  %-20s %s MB\n" "Used Memory:"   "$(( used / to_mb ))"
        printf "  %-20s %s MB\n" "Free Memory:"   "$(( free / to_mb ))"
        printf "  %-20s %s MB\n" "Available:"     "$(( available / to_mb ))"
        printf "  %-20s %s MB\n" "Cached:"        "$(( cached / to_mb ))"
        printf "  %-20s %s%%\n"  "Usage:"         "${mem_percent}"

        # Swap info
        if [[ "${swap_total}" -gt 0 ]]; then
            swap_percent=$(( (swap_total - swap_used) * 100 / swap_total ))
            printf "  %-20s %s MB / %s MB (%s%%)\n" "Swap Used:" \
                "$(( (swap_total - swap_used) / to_mb ))" \
                "$(( swap_total / to_mb ))" \
                "${swap_percent}"
        else
            printf "  %-20s %s\n" "Swap:" "Not configured"
        fi
    else
        # Fallback to free command
        free -m | awk 'NR==2{printf "  %-20s %s MB / %s MB (%.1f%%)\n",
            "Memory:", $3, $2, $3*100/$2}'
        mem_percent="$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')"
    fi

    # Alert check
    if [[ "${mem_percent:-0}" -ge "${THRESHOLD}" ]]; then
        log WARN "Memory usage is HIGH: ${mem_percent}% (threshold: ${THRESHOLD}%)"
        ((ISSUES_FOUND++))

        # Show top memory consumers
        echo ""
        echo -e "  ${YELLOW}Top Memory Consumers:${RESET}"
        ps aux --sort=-%mem 2>/dev/null | \
            awk 'NR>1 && NR<=6 {printf "  %-10s %-8s %s\n", $1, $4"%", $11}' || true
    else
        log INFO "Memory usage is normal: ${mem_percent:-N/A}%"
    fi
}

# ─── Disk Analysis ────────────────────────────────────────────────────────────
check_disk() {
    log HEADER "Disk Usage"

    local disk_alert=false

    # Print header
    printf "  %-20s %-10s %-10s %-10s %s\n" \
        "Mount Point" "Total" "Used" "Available" "Usage%"
    printf "  %s\n" "$(printf '─%.0s' {1..65})"

    # Check each filesystem
    while IFS= read -r line; do
        local filesystem mount total used avail percent

        filesystem="$(echo "${line}" | awk '{print $1}')"
        total="$(echo "${line}"     | awk '{print $2}')"
        used="$(echo "${line}"      | awk '{print $3}')"
        avail="$(echo "${line}"     | awk '{print $4}')"
        percent="$(echo "${line}"   | awk '{print $5}' | tr -d '%')"
        mount="$(echo "${line}"     | awk '{print $6}')"

        # Skip pseudo filesystems
        [[ "${filesystem}" =~ ^(tmpfs|devtmpfs|udev|overlay|shm)$ ]] && continue

        local color="${GREEN}"
        if [[ "${percent:-0}" -ge "${THRESHOLD}" ]]; then
            color="${RED}"
            disk_alert=true
            ((ISSUES_FOUND++))
        elif [[ "${percent:-0}" -ge $(( THRESHOLD - 10 )) ]]; then
            color="${YELLOW}"
        fi

        printf "  %-20s %-10s %-10s %-10s ${color}%s%%${RESET}\n" \
            "${mount}" "${total}" "${used}" "${avail}" "${percent}"

    done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2 || \
             df -h | tail -n +2)

    echo ""

    # Inode check
    log DEBUG "Checking inode usage..."
    printf "  %-20s %s\n" "Inode Usage:" ""
    df -i 2>/dev/null | awk 'NR>1 && !/tmpfs|devtmpfs/ {
        if ($5+0 > 80) print "  WARNING: " $6 " inodes at " $5
    }' || true

    if [[ "${disk_alert}" == true ]]; then
        log WARN "One or more disks exceed ${THRESHOLD}% usage threshold"

        # Show largest directories
        echo ""
        echo -e "  ${YELLOW}Largest Directories (top 5):${RESET}"
        du -sh /* 2>/dev/null | sort -rh | head -5 | \
            awk '{printf "  %-10s %s\n", $1, $2}' || true
    else
        log INFO "All disk partitions are within normal limits"
    fi
}

# ─── Process Analysis ─────────────────────────────────────────────────────────
check_processes() {
    log HEADER "Process Information"

    local total_procs zombie_procs running_procs

    total_procs="$(ps aux 2>/dev/null | wc -l)"
    total_procs=$(( total_procs - 1 ))  # Remove header
    zombie_procs="$(ps aux 2>/dev/null | awk '$8=="Z"' | wc -l)"
    running_procs="$(ps aux 2>/dev/null | awk '$8=="R"' | wc -l)"

    printf "  %-25s %s\n" "Total Processes:"   "${total_procs}"
    printf "  %-25s %s\n" "Running Processes:" "${running_procs}"
    printf "  %-25s %s\n" "Zombie Processes:"  "${zombie_procs}"

    # Alert on zombie processes
    if [[ "${zombie_procs}" -gt 0 ]]; then
        log WARN "Found ${zombie_procs} zombie process(es)"
        echo ""
        echo -e "  ${YELLOW}Zombie Processes:${RESET}"
        ps aux 2>/dev/null | awk 'NR==1 || $8=="Z"' | \
            awk '{printf "  %-8s %-8s %s\n", $1, $2, $11}' || true
        ((ISSUES_FOUND++))
    fi

    # Top CPU consumers
    echo ""
    echo -e "  ${CYAN}Top 5 CPU Consumers:${RESET}"
    printf "  %-12s %-8s %-8s %s\n" "USER" "PID" "CPU%" "COMMAND"
    ps aux --sort=-%cpu 2>/dev/null | \
        awk 'NR>1 && NR<=6 {printf "  %-12s %-8s %-8s %s\n", $1, $2, $3, $11}' || true

    # Top Memory consumers
    echo ""
    echo -e "  ${CYAN}Top 5 Memory Consumers:${RESET}"
    printf "  %-12s %-8s %-8s %s\n" "USER" "PID" "MEM%" "COMMAND"
    ps aux --sort=-%mem 2>/dev/null | \
        awk 'NR>1 && NR<=6 {printf "  %-12s %-8s %-8s %s\n", $1, $2, $4, $11}' || true
}

# ─── Network Analysis ─────────────────────────────────────────────────────────
check_network() {
    log HEADER "Network Status"

    # Network interfaces
    echo -e "  ${CYAN}Network Interfaces:${RESET}"
    if command -v ip &>/dev/null; then
        ip addr show 2>/dev/null | awk '
            /^[0-9]+:/ { iface=$2; gsub(/:/, "", iface) }
            /inet / { printf "  %-15s %s\n", iface, $2 }
        ' || true
    elif command -v ifconfig &>/dev/null; then
        ifconfig 2>/dev/null | awk '
            /^[a-z]/ { iface=$1 }
            /inet / { printf "  %-15s %s\n", iface, $2 }
        ' | grep -v "127.0.0.1" || true
    fi

    # Connection stats
    echo ""
    echo -e "  ${CYAN}Connection Statistics:${RESET}"
    if command -v ss &>/dev/null; then
        local established waiting time_wait
        established="$(ss -tan 2>/dev/null | grep ESTAB  | wc -l)"
        time_wait="$(ss -tan 2>/dev/null   | grep TIME-WAIT | wc -l)"
        waiting="$(ss -tan 2>/dev/null     | grep LISTEN | wc -l)"

        printf "  %-25s %s\n" "Established:"  "${established}"
        printf "  %-25s %s\n" "Listening:"    "${waiting}"
        printf "  %-25s %s\n" "TIME_WAIT:"    "${time_wait}"

        # Listening ports
        echo ""
        echo -e "  ${CYAN}Listening Ports:${RESET}"
        ss -tlnp 2>/dev/null | awk 'NR>1 {printf "  %-30s %s\n", $4, $6}' | head -10 || true
    fi

    # Connectivity test
    echo ""
    echo -e "  ${CYAN}Connectivity Tests:${RESET}"
    local hosts=("8.8.8.8" "1.1.1.1" "google.com")
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 2 "${host}" &>/dev/null 2>&1; then
            printf "  %-20s ${GREEN}✓ Reachable${RESET}\n" "${host}"
        else
            printf "  %-20s ${RED}✗ Unreachable${RESET}\n" "${host}"
        fi
    done
}

# ─── Security Check ───────────────────────────────────────────────────────────
check_security() {
    log HEADER "Security Overview"

    # Failed login attempts
    echo -e "  ${CYAN}Recent Failed SSH Logins:${RESET}"
    if [[ -f /var/log/auth.log ]]; then
        local failed_count
        failed_count="$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)"
        printf "  %-25s %s\n" "Failed attempts (total):" "${failed_count}"

        # Top attacking IPs
        grep "Failed password" /var/log/auth.log 2>/dev/null | \
            awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -5 | \
            awk '{printf "  %-25s %s attempts\n", $2, $1}' || true

    elif [[ -f /var/log/secure ]]; then
        grep "Failed password" /var/log/secure 2>/dev/null | tail -5 || true
    else
        echo "  Log file not accessible"
    fi

    # Logged in users
    echo ""
    echo -e "  ${CYAN}Currently Logged In Users:${RESET}"
    who 2>/dev/null | awk '{printf "  %-15s %-10s %s %s\n", $1, $2, $3, $4}' || true

    # Sudo access users
    echo ""
    echo -e "  ${CYAN}Users with Sudo Access:${RESET}"
    if [[ -f /etc/sudoers ]]; then
        grep -v "^#\|^$\|Defaults" /etc/sudoers 2>/dev/null | \
            awk '{printf "  %s\n", $0}' | head -10 || true
    fi

    # Last system logins
    echo ""
    echo -e "  ${CYAN}Last 5 Logins:${RESET}"
    last -n 5 2>/dev/null | head -5 | \
        awk '{printf "  %-10s %-15s %s %s %s %s\n", $1, $3, $4, $5, $6, $7}' || true

    # Check for world-writable files
    echo ""
    echo -e "  ${CYAN}World-Writable Files in /etc:${RESET}"
    find /etc -maxdepth 2 -perm -002 -type f 2>/dev/null | head -5 | \
        awk '{printf "  %s\n", $0}' || echo "  None found"
}

# ─── Service Status ───────────────────────────────────────────────────────────
check_services() {
    log HEADER "Critical Services Status"

    local services=("ssh" "sshd" "cron" "crond" "rsyslog" "syslog"
                    "NetworkManager" "networking" "firewalld" "ufw")

    for service in "${services[@]}"; do
        if command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet "${service}" 2>/dev/null; then
                printf "  %-25s ${GREEN}● Running${RESET}\n" "${service}:"
            elif systemctl list-unit-files "${service}.service" &>/dev/null 2>&1; then
                printf "  %-25s ${RED}● Stopped${RESET}\n" "${service}:"
            fi
        elif command -v service &>/dev/null; then
            if service "${service}" status &>/dev/null 2>&1; then
                printf "  %-25s ${GREEN}● Running${RESET}\n" "${service}:"
            fi
        fi
    done
}

# ─── Generate Report ──────────────────────────────────────────────────────────
generate_html_report() {
    log INFO "Generating HTML report: ${REPORT_FILE}"

    cat > "${REPORT_FILE}" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Health Report - $(hostname) - $(date)</title>
    <style>
        :root {
            --primary: #2563eb;
            --success: #16a34a;
            --warning: #d97706;
            --danger: #dc2626;
            --dark: #1e293b;
            --light: #f8fafc;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: var(--dark);
            color: #e2e8f0;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        header {
            background: linear-gradient(135deg, #1e3a5f, #2563eb);
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            text-align: center;
        }
        header h1 { font-size: 2rem; color: white; }
        header p { color: #93c5fd; margin-top: 8px; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #0f172a;
            border: 1px solid #1e293b;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
        }
        .stat-card .value {
            font-size: 2rem;
            font-weight: bold;
            color: var(--primary);
        }
        .stat-card .label { color: #64748b; margin-top: 5px; }
        .section {
            background: #0f172a;
            border: 1px solid #1e293b;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .section h2 {
            color: #60a5fa;
            border-bottom: 1px solid #1e293b;
            padding-bottom: 10px;
            margin-bottom: 15px;
        }
        .badge {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .badge-success { background: #14532d; color: #4ade80; }
        .badge-warning { background: #451a03; color: #fbbf24; }
        .badge-danger  { background: #450a0a; color: #f87171; }
        pre {
            background: #020617;
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            color: #a3e635;
        }
        footer {
            text-align: center;
            color: #475569;
            padding: 20px;
            margin-top: 30px;
        }
    </style>
</head>
<body>
<div class="container">
    <header>
        <h1>🐧 System Health Report</h1>
        <p>Host: <strong>$(hostname -f 2>/dev/null || hostname)</strong>
           | Generated: <strong>$(date '+%Y-%m-%d %H:%M:%S %Z')</strong>
           | Issues Found: <strong>${ISSUES_FOUND}</strong></p>
    </header>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="value">$(uptime | awk -F'average:' '{print $2}' | awk -F',' '{print $1}' | xargs)</div>
            <div class="label">Load Average (1m)</div>
        </div>
        <div class="stat-card">
            <div class="value">$(free | awk 'NR==2{printf "%.0f%%", $3*100/$2}')</div>
            <div class="label">Memory Used</div>
        </div>
        <div class="stat-card">
            <div class="value">$(df / | awk 'NR==2{print $5}')</div>
            <div class="label">Root Disk Used</div>
        </div>
        <div class="stat-card">
            <div class="value">$(ps aux | wc -l)</div>
            <div class="label">Processes Running</div>
        </div>
    </div>

    <div class="section">
        <h2>📊 Full Report Log</h2>
        <pre>$(cat "${LOG_FILE}" 2>/dev/null || echo "Log not available")</pre>
    </div>

    <footer>
        Generated by system_health_check.sh v${VERSION} |
        $(date '+%Y')
    </footer>
</div>
</body>
</html>
HTMLEOF

    log INFO "Report saved to: ${REPORT_FILE}"
}

# ─── Send Email ───────────────────────────────────────────────────────────────
send_email() {
    local email="${1}"

    if ! command -v mail &>/dev/null && ! command -v sendmail &>/dev/null; then
        log WARN "No mail command found. Install mailutils to send email."
        return 1
    fi

    local subject="[Health Report] $(hostname) - $(date '+%Y-%m-%d %H:%M') - Issues: ${ISSUES_FOUND}"
    local body

    body="System Health Report for $(hostname)\n"
    body+="Generated: $(date)\n"
    body+="Issues Found: ${ISSUES_FOUND}\n\n"
    body+="$(cat "${LOG_FILE}" 2>/dev/null)"

    echo -e "${body}" | mail -s "${subject}" "${email}" 2>/dev/null && \
        log INFO "Report emailed to: ${email}" || \
        log WARN "Failed to send email to: ${email}"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}              Health Check Summary         ${RESET}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${RESET}"

    if [[ "${ISSUES_FOUND}" -eq 0 ]]; then
        echo -e "  Status: ${GREEN}${BOLD}✓ ALL SYSTEMS HEALTHY${RESET}"
    elif [[ "${ISSUES_FOUND}" -le 2 ]]; then
        echo -e "  Status: ${YELLOW}${BOLD}⚠ WARNINGS FOUND (${ISSUES_FOUND})${RESET}"
    else
        echo -e "  Status: ${RED}${BOLD}✗ CRITICAL ISSUES (${ISSUES_FOUND})${RESET}"
    fi

    printf "  %-25s %s\n" "Issues Found:"    "${ISSUES_FOUND}"
    printf "  %-25s %s\n" "Threshold Used:"  "${THRESHOLD}%"
    printf "  %-25s %s\n" "Log File:"        "${LOG_FILE}"

    if [[ "${GENERATE_REPORT}" == true ]]; then
        printf "  %-25s %s\n" "HTML Report:" "${REPORT_FILE}"
    fi

    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${RESET}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    setup_logging
    check_dependencies

    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║     Linux System Health Check v${VERSION}    ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  Threshold: ${THRESHOLD}% | Log: ${LOG_FILE}"
    echo ""

    # Run all checks (allow failures, track issues)
    get_system_info
    check_cpu         || true
    check_memory      || true
    check_disk        || true
    check_processes   || true
    check_network     || true
    check_security    || true
    check_services    || true

    print_summary

    # Generate report if requested
    if [[ "${GENERATE_REPORT}" == true ]]; then
        generate_html_report
    fi

    # Send email if requested
    if [[ -n "${EMAIL_ADDRESS}" ]]; then
        send_email "${EMAIL_ADDRESS}"
    fi

    # Exit with error if critical issues found
    if [[ "${ISSUES_FOUND}" -ge 3 ]]; then
        exit 2
    elif [[ "${ISSUES_FOUND}" -ge 1 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
