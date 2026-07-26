#!/bin/bash

# Print the first binlog that must be retained. PURGE BINARY LOGS TO that file
# deletes only the contiguous synced+uploaded prefix before it.
select_mysql_binlog_purge_target() {
    local synced_files="$1"
    local uploaded_files="$2"
    local keep_count="$3"
    shift 3

    local files=("$@")
    local total_files=${#files[@]}
    local keep_tail_start=$((total_files - keep_count))
    local i file

    if [ "$total_files" -le "$keep_count" ]; then
        return 1
    fi

    for ((i = 0; i < total_files; i++)); do
        file="${files[$i]}"
        if ((i >= keep_tail_start)); then
            if [ "$i" -eq 0 ]; then
                return 1
            fi
            printf '%s\n' "$file"
            return 0
        fi
        if ! (printf '%s\n' "$synced_files" | tr ' ' '\n' | grep -Fxq "$file" &&
              printf '%s\n' "$uploaded_files" | tr ' ' '\n' | grep -Fxq "$file"); then
            if [ "$i" -eq 0 ]; then
                return 1
            fi
            printf '%s\n' "$file"
            return 0
        fi
    done

    return 1
}
