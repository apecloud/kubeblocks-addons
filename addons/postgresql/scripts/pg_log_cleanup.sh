#!/bin/bash
# PostgreSQL Log Management Script
# This script provides log cleanup, monitoring, and status checking functionality

set -euo pipefail

# Configuration
LOG_DIR="${PGDATA:-/home/postgres/pgdata/pgroot/data}/log"
RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
CLEANUP_LOG="/home/postgres/.log_cleanup.log"
CLEANUP_LOG_MAX_LINES="${CLEANUP_LOG_MAX_LINES:-1000}"  # Maximum lines to keep in cleanup log
CLEANUP_LOG_RETENTION_DAYS="${CLEANUP_LOG_RETENTION_DAYS:-30}"  # Keep cleanup log for 30 days
PID_FILE="/tmp/log_cleanup.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "$@"
    fi
}

# Colored logging for status output
log_colored() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Validate configuration
validate_config() {
    if [[ ! -d "$LOG_DIR" ]]; then
        log_error "Log directory does not exist: $LOG_DIR"
        return 1
    fi

    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]]; then
        log_error "Invalid retention days: $RETENTION_DAYS (must be positive integer)"
        return 1
    fi

    log_info "Configuration validated successfully"
    log_debug "Log directory: $LOG_DIR"
    log_debug "Retention days: $RETENTION_DAYS"
    log_debug "Dry run: $DRY_RUN"
}

# Get disk usage
get_disk_usage() {
    local dir="$1"
    du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown"
}

# Clean up log files
cleanup_logs() {
    local log_dir="$1"
    local retention_days="$2"
    local dry_run="$3"

    log_info "Starting log cleanup process"
    log_info "Directory: $log_dir"
    log_info "Retention: $retention_days days"
    log_info "Dry run: $dry_run"

    # Get initial disk usage
    local initial_usage
    initial_usage=$(get_disk_usage "$log_dir")
    log_info "Initial log directory size: $initial_usage"

    # Find files to delete
    local file_patterns=("postgresql-*.log" "postgresql-*.csv" "postgresql-*.json")
    local total_files=0
    local total_size=0

    for pattern in "${file_patterns[@]}"; do
        log_debug "Processing pattern: $pattern"

        # Find files older than retention period
        local files
        files=$(find "$log_dir" -name "$pattern" -type f -mtime "+$retention_days" 2>/dev/null || true)

        if [[ -n "$files" ]]; then
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    local file_size
                    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                    total_size=$((total_size + file_size))
                    total_files=$((total_files + 1))

                    if [[ "$dry_run" == "true" ]]; then
                        log_info "Would delete: $file ($(numfmt --to=iec "$file_size"))"
                    else
                        log_info "Deleting: $file ($(numfmt --to=iec "$file_size"))"
                        rm -f "$file"
                    fi
                fi
            done <<< "$files"
        fi
    done

    # Summary
    local final_usage
    final_usage=$(get_disk_usage "$log_dir")

    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry run completed"
        log_info "Would delete $total_files files, freeing $(numfmt --to=iec "$total_size")"
    else
        log_info "Cleanup completed"
        log_info "Deleted $total_files files, freed $(numfmt --to=iec "$total_size")"
        log_info "Final log directory size: $final_usage"
    fi

    # Clean up empty directories (optional)
    if [[ "$dry_run" != "true" ]]; then
        find "$log_dir" -type d -empty -delete 2>/dev/null || true
    fi

    # Clean up the cleanup log itself
    if [[ "$dry_run" != "true" ]]; then
        cleanup_cleanup_log "$CLEANUP_LOG" "$CLEANUP_LOG_MAX_LINES" "$CLEANUP_LOG_RETENTION_DAYS"
    fi
}

# Clean up the cleanup log itself
cleanup_cleanup_log() {
    local cleanup_log="$1"
    local max_lines="$2"
    local retention_days="$3"

    if [[ ! -f "$cleanup_log" ]]; then
        return 0
    fi

    log_debug "Checking cleanup log: $cleanup_log"

    # Get current line count
    local current_lines
    current_lines=$(wc -l < "$cleanup_log" 2>/dev/null || echo 0)

    # Check if cleanup log is too large (by lines)
    if [[ $current_lines -gt $max_lines ]]; then
        log_debug "Cleanup log has $current_lines lines, trimming to $max_lines"

        # Keep only the last max_lines
        local temp_file="${cleanup_log}.tmp"
        tail -n "$max_lines" "$cleanup_log" > "$temp_file" && mv "$temp_file" "$cleanup_log"

        log_debug "Trimmed cleanup log to $max_lines lines"
    fi

    # Check if cleanup log is too old
    if [[ -n "$retention_days" ]] && [[ $retention_days -gt 0 ]]; then
        # Check file age
        local file_age_days
        if command -v stat >/dev/null 2>&1; then
            # Get file modification time in seconds since epoch
            local file_mtime
            file_mtime=$(stat -c %Y "$cleanup_log" 2>/dev/null || echo 0)
            local current_time
            current_time=$(date +%s)
            file_age_days=$(( (current_time - file_mtime) / 86400 ))

            if [[ $file_age_days -gt $retention_days ]]; then
                log_debug "Cleanup log is $file_age_days days old, rotating"

                # Archive old log and start fresh
                local archive_file="${cleanup_log}.$(date +%Y%m%d)"
                mv "$cleanup_log" "$archive_file"
                touch "$cleanup_log"

                # Remove archives older than retention period
                find "$(dirname "$cleanup_log")" -name "$(basename "$cleanup_log").*" -type f -mtime "+$retention_days" -delete 2>/dev/null || true

                log_debug "Rotated cleanup log, archived as $archive_file"
            fi
        fi
    fi
}

# Check if log cleanup daemon is running
check_daemon_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_colored "$GREEN" "✓ Log cleanup daemon is running (PID: $pid)"
            return 0
        else
            log_colored "$RED" "✗ Log cleanup daemon is not running (stale PID file)"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        log_colored "$RED" "✗ Log cleanup daemon is not running (no PID file)"
        return 1
    fi
}

# Get log directory statistics
get_log_stats() {
    if [[ ! -d "$LOG_DIR" ]]; then
        log_colored "$RED" "✗ Log directory does not exist: $LOG_DIR"
        return 1
    fi

    echo
    log_colored "$BLUE" "=== Log Directory Statistics ==="

    local total_files log_files csv_files total_size

    total_files=$(find "$LOG_DIR" -name "postgresql-*" -type f | wc -l)
    log_files=$(find "$LOG_DIR" -name "postgresql-*.log" -type f | wc -l)
    csv_files=$(find "$LOG_DIR" -name "postgresql-*.csv" -type f | wc -l)

    if command -v du >/dev/null 2>&1; then
        total_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    else
        total_size="unknown"
    fi

    echo "Directory: $LOG_DIR"
    echo "Total files: $total_files (Log: $log_files, CSV: $csv_files)"
    echo "Total size: $total_size"

    # Oldest and newest files
    local oldest_file newest_file

    oldest_file=$(find "$LOG_DIR" -name "postgresql-*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2- || echo "")
    newest_file=$(find "$LOG_DIR" -name "postgresql-*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")

    if [[ -n "$oldest_file" ]]; then
        local oldest_date
        oldest_date=$(stat -c %y "$oldest_file" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        echo "Oldest file: $(basename "$oldest_file") ($oldest_date)"
    fi

    if [[ -n "$newest_file" ]]; then
        local newest_date
        newest_date=$(stat -c %y "$newest_file" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        echo "Newest file: $(basename "$newest_file") ($newest_date)"
    fi
}

# Show recent cleanup activity
show_cleanup_activity() {
    echo
    log_colored "$BLUE" "=== Recent Cleanup Activity ==="

    if [[ -f "$CLEANUP_LOG" ]]; then
        echo "Last 10 cleanup operations:"
        tail -10 "$CLEANUP_LOG" | while IFS= read -r line; do
            if [[ "$line" == *"Cleanup completed"* ]]; then
                log_colored "$GREEN" "  $line"
            elif [[ "$line" == *"Starting log cleanup"* ]]; then
                log_colored "$YELLOW" "  $line"
            else
                echo "  $line"
            fi
        done

        echo
        echo "Cleanup log location: $CLEANUP_LOG"

        if command -v wc >/dev/null 2>&1; then
            local log_lines log_size
            log_lines=$(wc -l < "$CLEANUP_LOG" 2>/dev/null || echo "unknown")
            log_size=$(du -h "$CLEANUP_LOG" 2>/dev/null | cut -f1 || echo "unknown")
            echo "Total log entries: $log_lines"
            echo "Cleanup log size: $log_size"
            echo "Max lines limit: $CLEANUP_LOG_MAX_LINES"
            echo "Cleanup log retention: $CLEANUP_LOG_RETENTION_DAYS days"

            # Show warning if cleanup log is getting large
            if [[ "$log_lines" != "unknown" ]] && [[ $log_lines -gt $((CLEANUP_LOG_MAX_LINES * 8 / 10)) ]]; then
                log_colored "$YELLOW" "⚠️  Cleanup log is approaching size limit ($log_lines/$CLEANUP_LOG_MAX_LINES lines)"
            fi
        fi
    else
        log_colored "$YELLOW" "No cleanup log found at: $CLEANUP_LOG"
    fi
}

# Show configuration
show_config() {
    echo
    log_colored "$BLUE" "=== Configuration ==="
    echo "LOG_CLEANUP_ENABLED: ${LOG_CLEANUP_ENABLED:-not set}"
    echo "LOG_RETENTION_DAYS: ${LOG_RETENTION_DAYS:-not set}"
    echo "LOG_CLEANUP_INTERVAL: ${LOG_CLEANUP_INTERVAL:-not set}"
    echo "Log directory: $LOG_DIR"
    echo "Cleanup log: $CLEANUP_LOG"
    echo "Cleanup log max lines: $CLEANUP_LOG_MAX_LINES"
    echo "Cleanup log retention: $CLEANUP_LOG_RETENTION_DAYS days"
    echo "PID file: $PID_FILE"
    echo "Dry run: $DRY_RUN"
    echo "Verbose: $VERBOSE"
}

# Start cleanup daemon
start_daemon() {
    local interval="${1:-86400}"  # Default 24 hours

    if check_daemon_status >/dev/null 2>&1; then
        log_colored "$YELLOW" "Log cleanup daemon is already running"
        return 1
    fi

    log_colored "$BLUE" "Starting log cleanup daemon..."

    (
        # Initial delay to let PostgreSQL start
        sleep 300  # Wait 5 minutes before first cleanup

        while true; do
            if [[ -d "$LOG_DIR" ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting log cleanup..." >> "$CLEANUP_LOG"

                # Run cleanup
                "$0" --log-dir "$LOG_DIR" --retention-days "$RETENTION_DAYS" >> "$CLEANUP_LOG" 2>&1
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log directory does not exist: $LOG_DIR" >> "$CLEANUP_LOG"
            fi

            # Wait for next cleanup cycle
            sleep "$interval"
        done
    ) &

    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    log_colored "$GREEN" "✓ Log cleanup daemon started with PID $daemon_pid"
}

# Stop cleanup daemon
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log_colored "$GREEN" "✓ Log cleanup daemon stopped"
        else
            log_colored "$YELLOW" "Daemon was not running, cleaning up stale PID file"
            rm -f "$PID_FILE"
        fi
    else
        log_colored "$YELLOW" "No daemon PID file found"
    fi
}

# Show status
show_status() {
    log_colored "$BLUE" "=== PostgreSQL Log Cleanup Status ==="
    check_daemon_status
    get_log_stats
    show_cleanup_activity
    show_config
}

# Help function
show_help() {
    cat << EOF
PostgreSQL Log Management Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    cleanup         Clean up old log files (default)
    status          Show daemon status and log statistics
    start [INTERVAL] Start cleanup daemon (interval in seconds, default: 86400)
    stop            Stop cleanup daemon
    config          Show current configuration
    activity        Show recent cleanup activity
    help            Show this help message

Cleanup Options:
    -d, --log-dir DIR       Log directory path (default: /home/postgres/pgdata/log)
    -r, --retention-days N  Number of days to retain logs (default: 7)
    -n, --dry-run          Show what would be deleted without actually deleting
    -v, --verbose          Enable verbose output
    -h, --help             Show this help message

Environment Variables:
    PG_LOG_DIR                    Log directory path
    LOG_RETENTION_DAYS           Number of days to retain logs
    LOG_CLEANUP_ENABLED          Whether cleanup is enabled
    LOG_CLEANUP_INTERVAL         Cleanup interval in seconds
    CLEANUP_LOG_MAX_LINES        Maximum lines to keep in cleanup log (default: 1000)
    CLEANUP_LOG_RETENTION_DAYS   Days to retain cleanup log (default: 30)
    DRY_RUN                      Set to 'true' for dry run mode
    VERBOSE                      Set to 'true' for verbose output

Examples:
    $0                                    # Run cleanup with default settings
    $0 cleanup --dry-run --verbose       # Dry run with verbose output
    $0 status                            # Show status and statistics
    $0 start 3600                        # Start daemon with 1-hour interval
    $0 stop                              # Stop daemon
    $0 --log-dir /var/log/postgresql --retention-days 14

EOF
}

# Parse command and arguments
COMMAND="cleanup"  # Default command

# Check if first argument is a command
if [[ $# -gt 0 ]]; then
    case "$1" in
        "cleanup"|"status"|"start"|"stop"|"config"|"activity"|"help")
            COMMAND="$1"
            shift
            ;;
    esac
fi

# Parse remaining arguments for cleanup command
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -r|--retention-days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        [0-9]*)
            # Numeric argument for start command interval
            if [[ "$COMMAND" == "start" ]]; then
                START_INTERVAL="$1"
                shift
            else
                log_error "Unknown argument: $1"
                show_help
                exit 1
            fi
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    "cleanup")
        # Run cleanup
        log_info "PostgreSQL log cleanup starting"

        if ! validate_config; then
            exit 1
        fi

        cleanup_logs "$LOG_DIR" "$RETENTION_DAYS" "$DRY_RUN"

        log_info "PostgreSQL log cleanup completed successfully"
        ;;
    "status")
        show_status
        ;;
    "start")
        start_daemon "${START_INTERVAL:-86400}"
        ;;
    "stop")
        stop_daemon
        ;;
    "config")
        show_config
        ;;
    "activity")
        show_cleanup_activity
        ;;
    "help")
        show_help
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
