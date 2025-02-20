#!/bin/bash

#!/bin/bash

# Directory pattern to find README.md files
README_FILES=$(find examples -mindepth 2 -maxdepth 2 -name "README.md")

for README in $README_FILES; do
    echo "Processing: $README"
    
    # Temporary output file
    OUTPUT_FILE="${README}.tmp"
    > "$OUTPUT_FILE"  # Clear output file

    # 读取输入文本并处理
    inside_code_block=false
    code_block_content=""

    while IFS= read -r line; do
        # 识别代码块起点
        if [[ "$line" == '```bash' ]]; then
            inside_code_block=true
            code_block_content="$line"
            continue
        fi

        # 识别代码块终点
        if [[ "$line" == '```' && "$inside_code_block" == true ]]; then
            inside_code_block=false
            code_block_content+=$'\n'"$line"

            # 匹配 `kubectl apply -f` 命令
            if [[ "$code_block_content" =~ kubectl\ apply\ -f\ ([^[:space:]]+\.yaml) ]]; then
                YAML_FILE="${BASH_REMATCH[1]}"  # 提取 YAML 文件路径

                # 如果 YAML 文件存在，则插入内容
                if [[ -f "$YAML_FILE" ]]; then
                    echo '```yaml' >> "$OUTPUT_FILE"
                    echo '# cat '"$YAML_FILE" >> "$OUTPUT_FILE"
                    cat "$YAML_FILE" >> "$OUTPUT_FILE"
                    # 插入空行
                    echo >> "$OUTPUT_FILE"
                    echo '```' >> "$OUTPUT_FILE"
                    # 插入空行
                    echo >> "$OUTPUT_FILE"
                else
                    echo "⚠️ 文件未找到: $YAML_FILE" >> "$OUTPUT_FILE"
                fi
            fi

            # 输出原始代码块
            echo "$code_block_content" >> "$OUTPUT_FILE"
            continue
        fi

        # 处理代码块内部
        if [[ "$inside_code_block" == true ]]; then
            code_block_content+=$'\n'"$line"
        else
            echo "$line" >> "$OUTPUT_FILE"
        fi

    done < "$README"

    # Replace original README with the updated content
    mv "$OUTPUT_FILE" "$README"

    echo "Updated: $README"
done

echo "All README.md files processed!"