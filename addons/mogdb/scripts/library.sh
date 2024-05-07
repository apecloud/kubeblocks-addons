function home_directory() {
    local user=${1:=root}

    if [ "$user" == "root" ];then
        echo "/root"
    else
        echo "/home/$user"
    fi
}


function string_contain() {
    local src="$1"
    local sub="$2"

    if [[ "$src" == *"$2"* ]]; then
        return 0
    fi

    return 1
}


function add_path() {
    local path="$1"

    if ! string_contain "$PATH" "$path"; then
        echo "$path:$PATH"
    else
        echo "$PATH"
    fi
}

function human_format() {
    local b="$1"
    local f="$2"

    local cmd=(numfmt --to=iec-i --suffix=B)
    if [ -n "$b" ]; then
        if [ -n "$f" ]; then
            cmd+=(--format="$f")
        fi

        cmd+=($b)

        ${cmd[@]}
    fi
}