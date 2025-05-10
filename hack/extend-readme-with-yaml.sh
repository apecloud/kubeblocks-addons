#!/bin/bash

# Directory pattern to find README.md files
README_FILES=$(find examples -mindepth 2 -maxdepth 2 -name "README.md" | sort)

# Group 1: one or more '#' characters.
# Group 2: characters inside the square brackets.
# Group 3: characters inside the parentheses.
regex='^(#+) \[([^]]+)\]\(([^)]+)\)$'

for README in $README_FILES; do
    echo "Processing: $README"

    # Temporary output file
    OUTPUT_FILE="${README}.tmp"
    > "$OUTPUT_FILE"  # Clear output file

    # read input text and process
    inside_code_block=false
    code_block_content=""

    while IFS= read -r line; do
        # identify code block start
        if [[ "$line" =~ ^[[:space:]]*\`\`\`bash ]]; then
            inside_code_block=true
            code_block_content="$line"
            continue
        fi

        # identify code block end
        if [[ "$line" =~  ^[[:space:]]*\`\`\` && "$inside_code_block" == true ]]; then
            inside_code_block=false
            code_block_content+=$'\n'"$line"
            # match `kubectl apply -f` command
            if [[ "$code_block_content" =~ kubectl\ apply\ -f\ ([^[:space:]]+\.yaml) ]]; then
                YAML_FILE="${BASH_REMATCH[1]}"  # extract yaml file name

                # insert yaml file content
                if [[ -f "$YAML_FILE" ]]; then
                    echo '```yaml' >> "$OUTPUT_FILE"
                    echo '# cat '"$YAML_FILE" >> "$OUTPUT_FILE"
                    cat "$YAML_FILE" >> "$OUTPUT_FILE"
                    # insert empty line
                    echo >> "$OUTPUT_FILE"
                    echo '```' >> "$OUTPUT_FILE"
                    # insert empty line
                    echo >> "$OUTPUT_FILE"
                else
                    echo "⚠️ File Not Found: $YAML_FILE in $README"
                    exit 1
                fi
            fi

            # echo original code block
            echo "$code_block_content" >> "$OUTPUT_FILE"
            continue
        fi

        # process code block content
        if [[ "$inside_code_block" == true ]]; then
            code_block_content+=$'\n'"$line"
        else
            if [[ "$line" =~ $regex ]]; then
                # Rewriting the line: combine Group 1 (hashes) and Group 2 (text inside [])
                line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
            fi
            echo "$line" >> "$OUTPUT_FILE"
        fi

    done < "$README"

    # parase addon name from path examples/addon-name/README.md
    ADDON_NAME=$(echo "$README" | awk -F'/' '{print $2}')
    # Replace original README with the updated content
    mv "$OUTPUT_FILE" "addons/${ADDON_NAME}/README.md"

    echo "Updated: $README"
done

echo "All README.md files processed!"
