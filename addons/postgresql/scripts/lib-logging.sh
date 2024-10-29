# shellcheck disable=SC2148
#
# Usage:
#     echo "some line content from stdout" | format_log_content STDOUT SOME_COMPONENT > /path/to/logfile
#     echo "some line content from stderr" | format_log_content STDERR SOME_COMPONENT > /path/to/logfile
# Result:
#     The formatted line will be printed to the stdout, in order to be saved into a log file.
# Example:
#     some_command > >( tee >( format_log_content STDOUT SOME_COMPONENT | stdbuf -oL cat >> "${log_file}" ) ) \
#                 2> >( tee >( format_log_content STDERR SOME_COMPONENT | stdbuf -oL cat >> "${log_file}" ) )
format_log_content() {
    local content_type #STDOUT or STDERR
    local component
    content_type=$1
    component=$2
    while IFS= read -r line; do
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [$content_type] [$component] $line"
    done
}

setup_logging() {
    local component
    local log_file
    component=$1
    log_file=$2

    # redirect all the stdout and stderr to files
    exec > >( tee >( format_log_content STDOUT "${component}" | stdbuf -oL cat >> "${log_file}" ) ) \
        2> >( tee >( format_log_content STDERR "${component}" | stdbuf -oL cat >> "${log_file}" ) >&2 )
}
