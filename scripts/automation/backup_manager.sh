#!/usr/bin/env bash
# =============================================================================
# Script Name: backup_manager.sh
# Description: Automated backup with compression, encryption, and rotation
# Version:     1.5.0
# Usage:       ./backup_manager.sh [OPTIONS]
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Constants ────────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="1.5.0"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="/var/log/backup_manager.log"

# ─── Colors ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
SOURCE_DIR=""
DEST_DIR=""
RETAIN_DAYS=7
COMPRESS=true
ENCRYPT=false
GPG_RECIPIENT=""
EXCLUDE_PATTERNS=()
DRY_RUN=false
NOTIFY_EMAIL=""
BACKUP_NAME=""

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local message="$*"
    local entry="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}"

    echo "${entry}" | tee -a "${LOG_FILE}" 2>/dev/null || echo "${entry}"

    case "${level}" in
        INFO)  echo -e "${GREEN}[INFO]${RESET}  ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${RESET}  ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${RESET} ${message}" >&2 ;;
        SUCCESS) echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} ${message}" ;;
    esac
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${RESET}
Automated backup manager with compression and rotation

${BOLD}USAGE:${RESET}
    ${SCRIPT_NAME} --source DIR --dest DIR [OPTIONS]

${BOLD}REQUIRED:${RESET}
    -s, --source DIR        Source directory to backup
    -d, --dest DIR          Destination directory for backups

${BOLD}OPTIONS:${RESET}
    -n, --name NAME         Backup name (default: source dir name)
    -r, --retain DAYS       Days to retain backups (default: 7)
    -e, --encrypt           Encrypt backup with GPG
    -g, --gpg-recipient ID  GPG recipient for encryption
    -x, --exclude PATTERN   Exclude pattern (can be used multiple times)
    --no-compress           Disable compression
    --dry-run               Simulate without creating backup
    --email EMAIL           Send notification email
    -h, --help              Show this help

${BOLD}EXAMPLES:${RESET}
    ${SCRIPT_NAME} --source /var/www --dest /backup
    ${SCRIPT_NAME} --source /home --dest /backup --retain 14 --email admin@example.com
    ${SCRIPT_NAME} --source /etc --dest /backup --encrypt --gpg-recipient admin@example.com
    ${SCRIPT_NAME} --source /data --dest /backup --exclude "*.tmp" --exclude "*.log"
EOF
}

# ─── Parse Arguments ──────────────────────────────────────────────────────────
parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)    SOURCE_DIR="${2:?'Source directory required'}"; shift ;;
            -d|--dest)      DEST_DIR="${2:?'Destination directory required'}"; shift ;;
            -n|--name)      BACKUP_NAME="${2:?'Backup name required'}"; shift ;;
            -r|--retain)    RETAIN_DAYS="${2:?'Retention days required'}"; shift ;;
            -e|--encrypt)   ENCRYPT=true ;;
            -g|--gpg-recipient) GPG_RECIPIENT="${2:?'GPG recipient required'}"; shift ;;
            -x|--exclude)   EXCLUDE_PATTERNS+=("${2:?'Exclude pattern required'}"); shift ;;
            --no-compress)  COMPRESS=false ;;
            --dry-run)      DRY_RUN=true ;;
            --email)        NOTIFY_EMAIL="${2:?'Email required'}"; shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              log ERROR "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

# ─── Validation ───────────────────────────────────────────────────────────────
validate_inputs() {
    local errors=0

    # Check source directory
    if [[ -z "${SOURCE_DIR}" ]]; then
        log ERROR "Source directory is required (--source)"
        ((errors++))
    elif [[ ! -d "${SOURCE_DIR}" ]]; then
        log ERROR "Source directory does not exist: ${SOURCE_DIR}"
        ((errors++))
    elif [[ ! -r "${SOURCE_DIR}" ]]; then
        log ERROR "Source directory is not readable: ${SOURCE_DIR}"
        ((errors++))
    fi

    # Check destination
    if [[ -z "${DEST_DIR}" ]]; then
        log ERROR "Destination directory is required (--dest)"
        ((errors++))
    fi

    # Validate retention days
    if ! [[ "${RETAIN_DAYS}" =~ ^[0-9]+$ ]] || [[ "${RETAIN_DAYS}" -lt 1 ]]; then
        log ERROR "Retention days must be a positive integer"
        ((errors++))
    fi

    # Encryption checks
    if [[ "${ENCRYPT}" == true ]]; then
        if ! command -v gpg &>/dev/null; then
            log ERROR "GPG not found but encryption requested"
            ((errors++))
        fi
        if [[ -z "${GPG_RECIPIENT}" ]]; then
            log ERROR "GPG recipient required when encryption is enabled"
            ((errors++))
        fi
    fi

    [[ ${errors} -gt 0 ]] && { log ERROR "${errors} validation error(s) found"; exit 1; }

    # Set backup name if not provided
    BACKUP_NAME="${BACKUP_NAME:-$(basename "${SOURCE_DIR}")}"

    log INFO "Validation passed"
}

# ─── Check Available Space ────────────────────────────────────────────────────
check_disk_space() {
    local source_size dest_available

    source_size="$(du -sb "${SOURCE_DIR}" 2>/dev/null | awk '{print $1}')"
    dest_available="$(df -B1 "${DEST_DIR}" 2>/dev/null | awk 'NR==2{print $4}')"

    if [[ -n "${source_size}" && -n "${dest_available}" ]]; then
        # Need at least 110% of source size (for safety margin)
        local required=$(( source_size * 110 / 100 ))
        if [[ "${dest_available}" -lt "${required}" ]]; then
            log WARN "Low disk space: Available $(numfmt --to=iec ${dest_available} 2>/dev/null || \
                echo "${dest_available}B"), Required ~$(numfmt --to=iec ${required} 2>/dev/null || \
                echo "${required}B")"
        else
            local avail_human
            avail_human="$(numfmt --to=iec ${dest_available} 2>/dev/null || echo "${dest_available}B")"
            log INFO "Disk space check passed. Available: ${avail_human}"
        fi
    fi
}

# ─── Create Backup ────────────────────────────────────────────────────────────
create_backup() {
    local backup_dir="${DEST_DIR}/${BACKUP_NAME}"
    local backup_file
    local extension="tar"
    local start_time end_time duration

    [[ "${COMPRESS}" == true ]] && extension="tar.gz"

    backup_file="${backup_dir}/${BACKUP_NAME}_${TIMESTAMP}.${extension}"

    # Create destination
    if [[ "${DRY_RUN}" == false ]]; then
        mkdir -p "${backup_dir}" || {
            log ERROR "Failed to create backup directory: ${backup_dir}"
            exit 1
        }
    fi

    log INFO "Starting backup: ${SOURCE_DIR} → ${backup_file}"
    [[ "${DRY_RUN}" == true ]] && log WARN "DRY RUN MODE - No files will be written"

    start_time="$(date +%s)"

    # Build tar command
    local tar_opts=("-cf")
    [[ "${COMPRESS}" == true ]] && tar_opts=("-czf")

    # Add excludes
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=("--exclude=${pattern}")
    done

    # Always exclude common noise
    exclude_args+=(
        "--exclude=*.tmp"
        "--exclude=*.swp"
        "--exclude=.DS_Store"
        "--exclude=__pycache__"
        "--exclude=node_modules"
        "--exclude=.git"
    )

    if [[ "${DRY_RUN}" == false ]]; then
        # Create the archive with progress
        if tar "${tar_opts[@]}" "${backup_file}" \
               "${exclude_args[@]}" \
               --checkpoint=1000 \
               --checkpoint-action=dot \
               -C "$(dirname "${SOURCE_DIR}")" \
               "$(basename "${SOURCE_DIR}")" 2>/dev/null; then
            echo ""  # New line after dots
        else
            log ERROR "tar command failed"
            exit 1
        fi
    else
        log INFO "[DRY RUN] Would run: tar ${tar_opts[*]} ${backup_file} ${exclude_args[*]} ${SOURCE_DIR}"
    fi

    end_time="$(date +%s)"
    duration=$(( end_time - start_time ))

    # Encrypt if requested
    if [[ "${ENCRYPT}" == true && "${DRY_RUN}" == false ]]; then
        encrypt_backup "${backup_file}"
        backup_file="${backup_file}.gpg"
    fi

    # Generate checksum
    if [[ "${DRY_RUN}" == false ]] && [[ -f "${backup_file}" ]]; then
        local checksum
        checksum="$(sha256sum "${backup_file}" | awk '{print $1}')"
        echo "${checksum}  ${backup_file}" > "${backup_file}.sha256"
        log INFO "Checksum: ${checksum}"

        local file_size
        file_size="$(du -sh "${backup_file}" | cut -f1)"
        log SUCCESS "Backup created: ${backup_file} (${file_size}) in ${duration}s"

        # Write metadata
        write_metadata "${backup_file}" "${duration}" "${checksum}"
    fi

    echo "${backup_file}"
}

# ─── Encrypt Backup ───────────────────────────────────────────────────────────
encrypt_backup() {
    local file="$1"

    log INFO "Encrypting backup with GPG (recipient: ${GPG_RECIPIENT})..."

    if gpg --batch --yes \
           --recipient "${GPG_RECIPIENT}" \
           --output "${file}.gpg" \
           --encrypt "${file}" 2>/dev/null; then
        rm -f "${file}"
        log INFO "Encryption successful: ${file}.gpg"
    else
        log ERROR "GPG encryption failed"
        exit 1
    fi
}

# ─── Write Metadata ───────────────────────────────────────────────────────────
write_metadata() {
    local backup_file="$1"
    local duration="$2"
    local checksum="$3"
    local meta_file="${backup_file}.meta"

    cat > "${meta_file}" <<EOF
backup_file=${backup_file}
source_dir=${SOURCE_DIR}
backup_name=${BACKUP_NAME}
timestamp=${TIMESTAMP}
date=$(date '+%Y-%m-%d %H:%M:%S')
duration_seconds=${duration}
compressed=${COMPRESS}
encrypted=${ENCRYPT}
sha256=${checksum}
hostname=$(hostname)
user=$(whoami)
version=${VERSION}
EOF

    log INFO "Metadata written: ${meta_file}"
}

# ─── Rotate Old Backups ───────────────────────────────────────────────────────
rotate_backups() {
    local backup_dir="${DEST_DIR}/${BACKUP_NAME}"
    local deleted_count=0
    local freed_space=0

    log INFO "Rotating backups older than ${RETAIN_DAYS} days..."

    if [[ "${DRY_RUN}" == false ]]; then
        while IFS= read -r -d '' old_backup; do
            local file_size
            file_size="$(stat -c%s "${old_backup}" 2>/dev/null || echo 0)"
            freed_space=$(( freed_space + file_size ))

            rm -f "${old_backup}" "${old_backup}.sha256" "${old_backup}.meta" 2>/dev/null || true
            log INFO "Deleted old backup: $(basename "${old_backup}")"
            ((deleted_count++))
        done < <(find "${backup_dir}" \
                      -maxdepth 1 \
                      -name "${BACKUP_NAME}_*.tar*" \
                      -mtime "+${RETAIN_DAYS}" \
                      -print0 2>/dev/null)
    else
        local count
        count="$(find "${backup_dir}" \
                      -maxdepth 1 \
                      -name "${BACKUP_NAME}_*.tar*" \
                      -mtime "+${RETAIN_DAYS}" 2>/dev/null | wc -l)"
        log INFO "[DRY RUN] Would delete ${count} old backup(s)"
    fi

    if [[ ${deleted_count} -gt 0 ]]; then
        local freed_human
        freed_human="$(numfmt --to=iec ${freed_space} 2>/dev/null || echo "${freed_space}B")"
        log INFO "Rotation complete: Deleted ${deleted_count} backup(s), freed ${freed_human}"
    else
        log INFO "No old backups to rotate"
    fi
}

# ─── List Backups ─────────────────────────────────────────────────────────────
list_backups() {
    local backup_dir="${DEST_DIR}/${BACKUP_NAME}"

    if [[ ! -d "${backup_dir}" ]]; then
        log WARN "No backups found for: ${BACKUP_NAME}"
        return
    fi

    echo ""
    echo -e "${BOLD}Existing Backups:${RESET}"
    printf "  %-50s %-12s %s\n" "File" "Size" "Date"
    printf "  %s\n" "$(printf '─%.0s' {1..80})"

    local total_size=0

    while IFS= read -r backup; do
        local size date_created
        size="$(du -sh "${backup}" 2>/dev/null | cut -f1)"
        date_created="$(stat -c '%y' "${backup}" 2>/dev/null | cut -d. -f1)"

        printf "  %-50s %-12s %s\n" "$(basename "${backup}")" "${size}" "${date_created}"
    done < <(find "${backup_dir}" \
                  -maxdepth 1 \
                  -name "${BACKUP_NAME}_*.tar*" \
                  ! -name "*.meta" ! -name "*.sha256" \
                  -type f \
                  | sort -r 2>/dev/null)
}

# ─── Send Notification ────────────────────────────────────────────────────────
send_notification() {
    local backup_file="$1"
    local status="$2"

    [[ -z "${NOTIFY_EMAIL}" ]] && return

    local subject="[Backup ${status}] ${BACKUP_NAME} - $(date '+%Y-%m-%d %H:%M')"
    local body

    body="Backup Report\n"
    body+="═══════════════════════════════\n"
    body+="Name:     ${BACKUP_NAME}\n"
    body+="Source:   ${SOURCE_DIR}\n"
    body+="Dest:     ${backup_file}\n"
    body+="Status:   ${status}\n"
    body+="Date:     $(date)\n"
    body+="Host:     $(hostname)\n"
    body+="Retained: ${RETAIN_DAYS} days\n"

    if command -v mail &>/dev/null; then
        echo -e "${body}" | mail -s "${subject}" "${NOTIFY_EMAIL}" && \
            log INFO "Notification sent to: ${NOTIFY_EMAIL}" || \
            log WARN "Failed to send notification email"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    validate_inputs
    check_disk_space

    echo -e "\n${BOLD}${BLUE}══ Backup Manager v${VERSION} ══${RESET}"
    echo -e "  Source:  ${SOURCE_DIR}"
    echo -e "  Dest:    ${DEST_DIR}"
    echo -e "  Retain:  ${RETAIN_DAYS} days"
    echo -e "  Compress: ${COMPRESS}"
    echo -e "  Encrypt:  ${ENCRYPT}"
    echo ""

    local backup_file exit_code=0

    if backup_file="$(create_backup)"; then
        rotate_backups
        list_backups
        send_notification "${backup_file}" "SUCCESS"
        log SUCCESS "Backup process completed successfully"
    else
        send_notification "" "FAILED"
        log ERROR "Backup process failed"
        exit_code=1
    fi

    exit ${exit_code}
}

main "$@"
