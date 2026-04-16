#!/usr/bin/env bash
# =============================================================================
# Script Name: file_organizer.sh
# Description: Intelligently organize files by type, date, or size
# Version:     1.3.0
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly VERSION="1.3.0"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ─── Colors ───────────────────────────────────────────────────────────────────
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ─── File Type Mappings ───────────────────────────────────────────────────────
declare -A FILE_TYPES=(
    # Images
    [jpg]="Images" [jpeg]="Images" [png]="Images" [gif]="Images"
    [bmp]="Images" [svg]="Images" [webp]="Images" [ico]="Images"
    [tiff]="Images" [raw]="Images" [heic]="Images" [psd]="Images"

    # Videos
    [mp4]="Videos" [mkv]="Videos" [avi]="Videos" [mov]="Videos"
    [wmv]="Videos" [flv]="Videos" [webm]="Videos" [m4v]="Videos"

    # Audio
    [mp3]="Audio" [wav]="Audio" [flac]="Audio" [aac]="Audio"
    [ogg]="Audio" [m4a]="Audio" [wma]="Audio"

    # Documents
    [pdf]="Documents" [doc]="Documents" [docx]="Documents"
    [txt]="Documents" [rtf]="Documents" [odt]="Documents"
    [md]="Documents"  [rst]="Documents"

    # Spreadsheets
    [xls]="Spreadsheets" [xlsx]="Spreadsheets" [csv]="Spreadsheets"
    [ods]="Spreadsheets"

    # Presentations
    [ppt]="Presentations" [pptx]="Presentations" [odp]="Presentations"

    # Archives
    [zip]="Archives" [tar]="Archives" [gz]="Archives" [bz2]="Archives"
    [xz]="Archives"  [rar]="Archives" [7z]="Archives" [tgz]="Archives"

    # Code
    [sh]="Code/Shell"   [bash]="Code/Shell"  [zsh]="Code/Shell"
    [py]="Code/Python"  [pyc]="Code/Python"
    [js]="Code/JavaScript" [ts]="Code/JavaScript" [jsx]="Code/JavaScript"
    [html]="Code/Web"   [css]="Code/Web"     [scss]="Code/Web"
    [java]="Code/Java"  [class]="Code/Java"  [jar]="Code/Java"
    [c]="Code/C"        [cpp]="Code/C"       [h]="Code/C"
    [go]="Code/Go"      [rs]="Code/Rust"     [rb]="Code/Ruby"
    [php]="Code/PHP"    [sql]="Code/SQL"

    # Data
    [json]="Data" [xml]="Data" [yaml]="Data" [yml]="Data"
    [toml]="Data" [ini]="Data" [conf]="Data" [cfg]="Data"

    # Executables
    [exe]="Executables" [dmg]="Executables" [deb]="Executables"
    [rpm]="Executables" [AppImage]="Executables"

    # Fonts
    [ttf]="Fonts" [otf]="Fonts" [woff]="Fonts" [woff2]="Fonts"
)

# ─── Defaults ─────────────────────────────────────────────────────────────────
SOURCE_DIR=""
DEST_DIR=""
ORGANIZE_BY="type"
DRY_RUN=false
MOVE_FILES=false
VERBOSE=false
CREATE_DATE_SUBDIR=false
UNDO_LOG=""
STATS_MODE=false
MIN_SIZE=0
MAX_SIZE=0

declare -A MOVE_COUNT
declare -A MOVE_SIZES

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${RESET}
Intelligent file organizer

${BOLD}USAGE:${RESET}
    ${SCRIPT_NAME} --source DIR --dest DIR [OPTIONS]

${BOLD}REQUIRED:${RESET}
    -s, --source DIR        Source directory
    -d, --dest DIR          Destination directory

${BOLD}OPTIONS:${RESET}
    -b, --by MODE           Organize by: type|date|size|extension (default: type)
    --move                  Move files (default: copy)
    --dry-run               Simulate without moving/copying
    --date-subdir           Create date subdirectories (YYYY/MM)
    --stats                 Show statistics only, don't organize
    --min-size BYTES        Skip files smaller than size
    --max-size BYTES        Skip files larger than size
    -v, --verbose           Verbose output
    -h, --help              Show this help

${BOLD}EXAMPLES:${RESET}
    ${SCRIPT_NAME} --source ~/Downloads --dest ~/Organized
    ${SCRIPT_NAME} --source ~/Downloads --dest ~/Organized --by date --date-subdir
    ${SCRIPT_NAME} --source ~/Desktop --dest ~/Sorted --move --dry-run
    ${SCRIPT_NAME} --source /data --dest /organized --by extension
EOF
}

# ─── Parse Args ───────────────────────────────────────────────────────────────
parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)    SOURCE_DIR="${2:?}"; shift ;;
            -d|--dest)      DEST_DIR="${2:?}"; shift ;;
            -b|--by)        ORGANIZE_BY="${2:?}"; shift ;;
            --move)         MOVE_FILES=true ;;
            --dry-run)      DRY_RUN=true ;;
            --date-subdir)  CREATE_DATE_SUBDIR=true ;;
            --stats)        STATS_MODE=true ;;
            --min-size)     MIN_SIZE="${2:?}"; shift ;;
            --max-size)     MAX_SIZE="${2:?}"; shift ;;
            -v|--verbose)   VERBOSE=true ;;
            -h|--help)      usage; exit 0 ;;
            *)              echo "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

# ─── Log ──────────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    case "${level}" in
        INFO)    echo -e "${GREEN}[INFO]${RESET}  $*" ;;
        WARN)    echo -e "${YELLOW}[WARN]${RESET}  $*" ;;
        VERBOSE) [[ "${VERBOSE}" == true ]] && echo -e "  → $*" ;;
        HEADER)  echo -e "\n${BOLD}${BLUE}══ $* ══${RESET}" ;;
    esac
}

# ─── Get Category by Type ─────────────────────────────────────────────────────
get_category_by_type() {
    local filename="$1"
    local ext

    # Get lowercase extension
    ext="${filename##*.}"
    ext="${ext,,}"

    # Look up in map
    if [[ -n "${FILE_TYPES[$ext]+_}" ]]; then
        echo "${FILE_TYPES[$ext]}"
    else
        echo "Others"
    fi
}

# ─── Get Category by Date ─────────────────────────────────────────────────────
get_category_by_date() {
    local filepath="$1"
    local year month

    year="$(stat -c '%y' "${filepath}" 2>/dev/null | cut -d'-' -f1 || date +%Y)"
    month="$(stat -c '%y' "${filepath}" 2>/dev/null | cut -d'-' -f2 || date +%m)"

    if [[ "${CREATE_DATE_SUBDIR}" == true ]]; then
        echo "${year}/${month}"
    else
        echo "${year}"
    fi
}

# ─── Get Category by Size ─────────────────────────────────────────────────────
get_category_by_size() {
    local filepath="$1"
    local size

    size="$(stat -c%s "${filepath}" 2>/dev/null || echo 0)"

    if [[ ${size} -lt 102400 ]]; then           # < 100KB
        echo "Small_under_100KB"
    elif [[ ${size} -lt 10485760 ]]; then        # < 10MB
        echo "Medium_100KB-10MB"
    elif [[ ${size} -lt 1073741824 ]]; then      # < 1GB
        echo "Large_10MB-1GB"
    else                                          # >= 1GB
        echo "Huge_over_1GB"
    fi
}

# ─── Get Category by Extension ───────────────────────────────────────────────
get_category_by_extension() {
    local filename="$1"
    local ext="${filename##*.}"

    # If no extension
    [[ "${filename}" == "${ext}" ]] && echo "No_Extension" && return

    echo "${ext^^}"
}

# ─── Check Size Filters ───────────────────────────────────────────────────────
passes_size_filter() {
    local filepath="$1"
    local size

    size="$(stat -c%s "${filepath}" 2>/dev/null || echo 0)"

    [[ "${MIN_SIZE}" -gt 0 && "${size}" -lt "${MIN_SIZE}" ]] && return 1
    [[ "${MAX_SIZE}" -gt 0 && "${size}" -gt "${MAX_SIZE}" ]] && return 1

    return 0
}

# ─── Process File ─────────────────────────────────────────────────────────────
process_file() {
    local filepath="$1"
    local filename
    filename="$(basename "${filepath}")"

    # Skip hidden files
    [[ "${filename}" == .* ]] && return

    # Skip if not regular file
    [[ ! -f "${filepath}" ]] && return

    # Apply size filter
    passes_size_filter "${filepath}" || {
        log VERBOSE "Skipped (size filter): ${filename}"
        return
    }

    # Get destination category
    local category
    case "${ORGANIZE_BY}" in
        type)      category="$(get_category_by_type "${filename}")" ;;
        date)      category="$(get_category_by_date "${filepath}")" ;;
        size)      category="$(get_category_by_size "${filepath}")" ;;
        extension) category="$(get_category_by_extension "${filename}")" ;;
        *)         category="Others" ;;
    esac

    local dest_dir="${DEST_DIR}/${category}"
    local dest_file="${dest_dir}/${filename}"

    # Handle filename conflicts
    if [[ -f "${dest_file}" ]]; then
        local base="${filename%.*}"
        local ext="${filename##*.}"
        [[ "${base}" == "${ext}" ]] && ext=""
        dest_file="${dest_dir}/${base}_${TIMESTAMP}${ext:+.${ext}}"
    fi

    # Track stats
    local file_size
    file_size="$(stat -c%s "${filepath}" 2>/dev/null || echo 0)"
    MOVE_COUNT["${category}"]=$(( ${MOVE_COUNT["${category}"]:-0} + 1 ))
    MOVE_SIZES["${category}"]=$(( ${MOVE_SIZES["${category}"]:-0} + file_size ))

    log VERBOSE "${category}/ ← ${filename}"

    if [[ "${DRY_RUN}" == false ]]; then
        mkdir -p "${dest_dir}"

        if [[ "${MOVE_FILES}" == true ]]; then
            mv "${filepath}" "${dest_file}"
        else
            cp -p "${filepath}" "${dest_file}"
        fi

        # Log to undo file
        echo "${filepath}|${dest_file}" >> "${UNDO_LOG}"
    fi
}

# ─── Show Statistics ──────────────────────────────────────────────────────────
show_stats_only() {
    log HEADER "Source Directory Statistics: ${SOURCE_DIR}"

    declare -A type_count

    while IFS= read -r -d '' file; do
        local filename ext category
        filename="$(basename "${file}")"
        ext="${filename##*.}"
        ext="${ext,,}"

        if [[ -n "${FILE_TYPES[$ext]+_}" ]]; then
            category="${FILE_TYPES[$ext]}"
        else
            category="Others"
        fi

        type_count["${category}"]=$(( ${type_count["${category}"]:-0} + 1 ))
    done < <(find "${SOURCE_DIR}" -maxdepth 1 -type f -print0)

    printf "\n  %-30s %-10s\n" "Category" "Count"
    printf "  %s\n" "$(printf '─%.0s' {1..45})"

    local total=0
    for category in $(echo "${!type_count[@]}" | tr ' ' '\n' | sort); do
        printf "  %-30s %s\n" "${category}" "${type_count[$category]}"
        total=$(( total + type_count["${category}"] ))
    done

    printf "  %s\n" "$(printf '─%.0s' {1..45})"
    printf "  %-30s %s\n" "TOTAL" "${total}"

    echo ""
    echo -e "  Total size: $(du -sh "${SOURCE_DIR}" | cut -f1)"
}

# ─── Print Summary ────────────────────────────────────────────────────────────
print_summary() {
    log HEADER "Organization Summary"

    printf "\n  %-30s %-10s %s\n" "Category" "Files" "Size"
    printf "  %s\n" "$(printf '─%.0s' {1..55})"

    local total_files=0
    local total_bytes=0

    for category in $(echo "${!MOVE_COUNT[@]}" | tr ' ' '\n' | sort); do
        local size_human
        size_human="$(numfmt --to=iec ${MOVE_SIZES[$category]:-0} 2>/dev/null || \
                      echo "${MOVE_SIZES[$category]:-0}B")"

        printf "  %-30s %-10s %s\n" \
            "${category}" \
            "${MOVE_COUNT[$category]}" \
            "${size_human}"

        total_files=$(( total_files + MOVE_COUNT["${category}"] ))
        total_bytes=$(( total_bytes + MOVE_SIZES["${category}"]:-0 ))
    done

    local total_size_human
    total_size_human="$(numfmt --to=iec ${total_bytes} 2>/dev/null || echo "${total_bytes}B")"

    printf "  %s\n" "$(printf '─%.0s' {1..55})"
    printf "  %-30s %-10s %s\n" "TOTAL" "${total_files}" "${total_size_human}"

    echo ""
    local action="Copied"
    [[ "${MOVE_FILES}" == true ]] && action="Moved"
    [[ "${DRY_RUN}" == true ]]    && action="[DRY RUN] Would ${action,,}"

    log INFO "${action} ${total_files} file(s)"
    [[ -f "${UNDO_LOG}" ]] && log INFO "Undo log: ${UNDO_LOG}"
}

# ─── Undo Last Operation ──────────────────────────────────────────────────────
undo_last() {
    local undo_file="${1:-}"

    [[ -z "${undo_file}" || ! -f "${undo_file}" ]] && {
        echo "Usage: ${SCRIPT_NAME} --undo UNDO_LOG_FILE"
        exit 1
    }

    local count=0
    while IFS='|' read -r original dest; do
        if [[ -f "${dest}" ]]; then
            mv "${dest}" "${original}"
            log INFO "Restored: ${original}"
            ((count++))
        fi
    done < "${undo_file}"

    log INFO "Restored ${count} file(s)"
    rm -f "${undo_file}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    # Validate
    [[ ! -d "${SOURCE_DIR}" ]] && { echo "Source not found: ${SOURCE_DIR}"; exit 1; }

    UNDO_LOG="${DEST_DIR:-/tmp}/undo_${TIMESTAMP}.log"

    echo -e "\n${BOLD}${BLUE}══ File Organizer v${VERSION} ══${RESET}"
    echo -e "  Source:  ${SOURCE_DIR}"
    echo -e "  Dest:    ${DEST_DIR:-N/A}"
    echo -e "  Mode:    ${ORGANIZE_BY}"
    echo -e "  Action:  $([ "${MOVE_FILES}" == true ] && echo 'Move' || echo 'Copy')"
    [[ "${DRY_RUN}" == true ]] && echo -e "  ${YELLOW}DRY RUN MODE${RESET}"
    echo ""

    # Stats mode only
    if [[ "${STATS_MODE}" == true ]]; then
        show_stats_only
        exit 0
    fi

    [[ -z "${DEST_DIR}" ]] && { echo "Destination required for organizing"; exit 1; }

    # Process all files
    log INFO "Scanning ${SOURCE_DIR}..."
    local file_count=0

    while IFS= read -r -d '' filepath; do
        process_file "${filepath}"
        ((file_count++))
    done < <(find "${SOURCE_DIR}" -maxdepth 1 -type f -print0 | sort -z)

    print_summary

    echo -e "${GREEN}${BOLD}Done!${RESET}\n"
}

main "$@"
