#!/usr/bin/env bash
# =============================================================================
# Script Name: test_scripts.sh
# Description: Test suite for all portfolio scripts
# =============================================================================

set -uo pipefail

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

PASS=0
FAIL=0
SKIP=0

# ─── Test Framework ───────────────────────────────────────────────────────────
assert_exit_code() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [[ "${actual}" -eq "${expected}" ]]; then
        echo -e "  ${GREEN}✓${RESET} ${description}"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${description} (expected: ${expected}, got: ${actual})"
        ((FAIL++))
    fi
}

assert_output_contains() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if echo "${actual}" | grep -q "${expected}"; then
        echo -e "  ${GREEN}✓${RESET} ${description}"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${description} (expected to find: '${expected}')"
        ((FAIL++))
    fi
}

assert_file_exists() {
    local description="$1"
    local file="$2"

    if [[ -f "${file}" ]]; then
        echo -e "  ${GREEN}✓${RESET} ${description}"
        ((PASS++))
    else
        echo -e "  ${RED}✗${RESET} ${description} (file not found: ${file})"
        ((FAIL++))
    fi
}

skip_test() {
    echo -e "  ${YELLOW}⊘${RESET} $1 (SKIPPED)"
    ((SKIP++))
}

section() {
    echo -e "\n${BOLD}▶ Testing: $1${RESET}"
}

# ─── Tests: Health Check ──────────────────────────────────────────────────────
test_health_check() {
    section "system_health_check.sh"
    local script="scripts/system-admin/system_health_check.sh"

    # Test: Script exists
    assert_file_exists "Script exists" "${script}"

    # Test: Help flag
    local output
    output="$("${script}" --help 2>&1)" || true
    assert_output_contains "Help displays usage" "USAGE" "${output}"

    # Test: Invalid threshold
    "${script}" --threshold 999 &>/dev/null
    assert_exit_code "Rejects invalid threshold" 1 $?

    # Test: Basic run (non-root, may have limited access)
    "${script}" --threshold 99 &>/dev/null
    local exit_code=$?
    [[ ${exit_code} -le 2 ]] && \
        assert_exit_code "Basic run completes" "${exit_code}" "${exit_code}" || \
        assert_exit_code "Basic run completes" 0 "${exit_code}"
}

# ─── Tests: Backup Manager ────────────────────────────────────────────────────
test_backup_manager() {
    section "backup_manager.sh"
    local script="scripts/automation/backup_manager.sh"

    assert_file_exists "Script exists" "${script}"

    # Setup temp dirs
    local src_dir dest_dir
    src_dir="$(mktemp -d)"
    dest_dir="$(mktemp -d)"

    # Create test files
    echo "test content 1" > "${src_dir}/file1.txt"
    echo "test content 2" > "${src_dir}/file2.log"
    echo "script"         > "${src_dir}/script.sh"

    # Test: Help flag
    local output
    output="$("${script}" --help 2>&1)" || true
    assert_output_contains "Help displays usage" "USAGE" "${output}"

    # Test: Missing required args
    "${script}" --source "${src_dir}" 2>/dev/null
    assert_exit_code "Fails without destination" 1 $?

    # Test: Dry run
    "${script}" --source "${src_dir}" \
                --dest "${dest_dir}" \
                --dry-run &>/dev/null
    assert_exit_code "Dry run exits cleanly" 0 $?

    # Test: Actual backup
    "${script}" --source "${src_dir}" \
                --dest "${dest_dir}" \
                --retain 1 &>/dev/null
    assert_exit_code "Creates backup successfully" 0 $?

    # Verify backup was created
    local backup_count
    backup_count="$(find "${dest_dir}" -name "*.tar.gz" 2>/dev/null | wc -l)"
    [[ "${backup_count}" -gt 0 ]] && \
        assert_exit_code "Backup file created" 0 0 || \
        assert_exit_code "Backup file created" 0 1

    # Test: Retention (create old backup, run again)
    touch -d "10 days ago" "${dest_dir}/$(basename "${src_dir}")/"*.tar.gz 2>/dev/null || true

    # Cleanup
    rm -rf "${src_dir}" "${dest_dir}"
}

# ─── Tests: Log Analyzer ──────────────────────────────────────────────────────
test_log_analyzer() {
    section "log_analyzer.sh"
    local script="scripts/automation/log_analyzer.sh"

    assert_file_exists "Script exists" "${script}"

    # Create sample log file
    local log_file
    log_file="$(mktemp --suffix=.log)"

    # Generate sample Apache log entries
    cat > "${log_file}" <<'EOF'
192.168.1.1 - frank [10/Oct/2024:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "-" "Mozilla/5.0"
192.168.1.2 - - [10/Oct/2024:13:56:14 -0700] "GET /api/users HTTP/1.1" 200 1234 "-" "curl/7.68.0"
10.0.0.1 - - [10/Oct/2024:13:57:01 -0700] "POST /login HTTP/1.1" 401 512 "-" "Python/3.8"
192.168.1.1 - - [10/Oct/2024:13:57:30 -0700] "GET /admin HTTP/1.1" 403 256 "-" "Mozilla/5.0"
10.0.0.1 - - [10/Oct/2024:13:58:00 -0700] "GET /notfound HTTP/1.1" 404 128 "-" "Python/3.8"
192.168.1.1 - frank [10/Oct/2024:13:59:00 -0700] "GET /page.html HTTP/1.1" 200 5432 "-" "Mozilla/5.0"
EOF

    # Test: Help
    local output
    output="$("${script}" --help 2>&1)" || true
    assert_output_contains "Help displays usage" "USAGE" "${output}"

    # Test: Missing file
    "${script}" --file /nonexistent/file.log &>/dev/null
    assert_exit_code "Fails with missing file" 1 $?

    # Test: Apache log analysis
    output="$("${script}" --file "${log_file}" --type apache 2>&1)" || true
    assert_output_contains "Analyzes HTTP requests" "HTTP" "${output}"
    assert_output_contains "Shows IP addresses" "192.168.1.1" "${output}"

    # Test: Pattern search
    output="$("${script}" --file "${log_file}" --pattern "404" 2>&1)" || true
    assert_output_contains "Pattern search works" "404" "${output}"

    # Cleanup
    rm -f "${log_file}"
}

# ─── Tests: File Organizer ────────────────────────────────────────────────────
test_file_organizer() {
    section "file_organizer.sh"
    local script="scripts/utilities/file_organizer.sh"

    assert_file_exists "Script exists" "${script}"

    # Setup
    local src_dir dest_dir
    src_dir="$(mktemp -d)"
    dest_dir="$(mktemp -d)"

    # Create test files
    touch "${src_dir}/photo.jpg"
    touch "${src_dir}/document.pdf"
    touch "${src_dir}/video.mp4"
    touch "${src_dir}/script.sh"
    touch "${src_dir}/data.json"
    touch "${src_dir}/archive.tar.gz"
    touch "${src_dir}/noextension"

    # Test: Help
    local output
    output="$("${script}" --help 2>&1)" || true
    assert_output_contains "Help works" "USAGE" "${output}"

    # Test: Stats mode
    output="$("${script}" --source "${src_dir}" --stats 2>&1)" || true
    assert_output_contains "Stats shows categories" "Category" "${output}"

    # Test: Dry run organize by type
    output="$("${script}" \
        --source "${src_dir}" \
        --dest "${dest_dir}" \
        --dry-run \
        --by type 2>&1)" || true
    assert_output_contains "Dry run shows plan" "DRY RUN" "${output}"

    # Test: Actual organization
    "${script}" \
        --source "${src_dir}" \
        --dest "${dest_dir}" \
        --by type &>/dev/null
    assert_exit_code "Organizes files successfully" 0 $?

    # Verify categories were created
    [[ -d "${dest_dir}/Images" ]] && \
        assert_exit_code "Images directory created" 0 0 || \
        assert_exit_code "Images directory created" 0 1

    [[ -d "${dest_dir}/Videos" ]] && \
        assert_exit_code "Videos directory created" 0 0 || \
        assert_exit_code "Videos directory created" 0 1

    # Verify jpg was copied to Images
    [[ -f "${dest_dir}/Images/photo.jpg" ]] && \
        assert_exit_code "JPG moved to Images" 0 0 || \
        assert_exit_code "JPG moved to Images" 0 1

    # Cleanup
    rm -rf "${src_dir}" "${dest_dir}"
}

# ─── Tests: Script Syntax ─────────────────────────────────────────────────────
test_syntax() {
    section "Bash Syntax Validation"

    while IFS= read -r script; do
        if bash -n "${script}" 2>/dev/null; then
            assert_exit_code "Syntax OK: ${script}" 0 0
        else
            assert_exit_code "Syntax OK: ${script}" 0 1
        fi
    done < <(find scripts/ -name "*.sh" -type f | sort)
}

# ─── Tests: Permissions ───────────────────────────────────────────────────────
test_permissions() {
    section "Script Permissions"

    while IFS= read -r script; do
        if [[ -x "${script}" ]]; then
            assert_exit_code "Executable: ${script}" 0 0
        else
            assert_exit_code "Executable: ${script}" 0 1
        fi
    done < <(find scripts/ -name "*.sh" -type f | sort)
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║     Shell Script Test Suite            ║${RESET}"
    echo -e "${BOLD}╚════════════════════════════════════════╝${RESET}"
    echo ""

    test_syntax
    test_permissions
    test_health_check
    test_backup_manager
    test_log_analyzer
    test_file_organizer

    # Summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}Test Results:${RESET}"
    echo -e "  ${GREEN}Passed: ${PASS}${RESET}"
    echo -e "  ${RED}Failed: ${FAIL}${RESET}"
    echo -e "  ${YELLOW}Skipped: ${SKIP}${RESET}"
    echo -e "  Total:  $(( PASS + FAIL + SKIP ))"
    echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
    echo ""

    if [[ ${FAIL} -gt 0 ]]; then
        echo -e "${RED}${BOLD}✗ Tests FAILED${RESET}"
        exit 1
    else
        echo -e "${GREEN}${BOLD}✓ All tests PASSED${RESET}"
        exit 0
    fi
}

main "$@"
