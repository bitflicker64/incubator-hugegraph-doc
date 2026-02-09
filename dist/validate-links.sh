#!/bin/bash

CONTENT_DIR="content"
EXIT_CODE=0

normalize_link() {
    local link="$1"

    link="${link%%#*}"
    link="${link%%\?*}"

    if [[ "$link" != "/" ]]; then
        link="${link%/}"
    fi

    printf "%s" "$link"
}

check_internal_link() {
    local link="$1"
    local file="$2"
    local line_no="$3"
    local clean_link
    local target_path

    clean_link=$(normalize_link "$link")

    [[ -z "$clean_link" || "$clean_link" == "#" ]] && return 0

    if [[ "$clean_link" == "{{<"* || "$clean_link" == "{{%"* || "$clean_link" == "{{"* ]]; then
        return 0
    fi

    local clean_link_lower="${clean_link,,}"

    if [[ "$clean_link_lower" == http://* || "$clean_link_lower" == https://* || "$clean_link_lower" == "//"* ]]; then
        return 0
    fi

    case "$clean_link_lower" in
        mailto:*|tel:*|javascript:*|data:*)
            return 0
            ;;
    esac

    if [[ "$clean_link" == /docs/* ]]; then
        target_path="content/en${clean_link}"
    elif [[ "$clean_link" == /cn/docs/* ]]; then
        target_path="content${clean_link}"
    elif [[ "$clean_link" == /* ]]; then
        target_path="content/en${clean_link}"
    else
        local file_dir
        file_dir=$(dirname "$file")
        target_path="${file_dir}/${clean_link}"

        while [[ "$target_path" == *"/./"* ]]; do
            target_path="${target_path//\/.\//\/}"
        done

        while [[ "$target_path" =~ ([^/]+/\.\./?) ]]; do
            target_path="${target_path/${BASH_REMATCH[0]}/}"
        done
    fi

    case "$clean_link_lower" in
        *.png|*.jpg|*.jpeg|*.svg|*.gif|*.xml|*.yaml|*.yml|*.json|*.css|*.js|*.pdf|*.zip|*.tar.gz)
            [[ -f "$target_path" ]] && return 0
            ;;
    esac

    if [[ -f "${target_path}.md" ]]; then
        return 0
    elif [[ -f "$target_path" ]]; then
        return 0
    elif [[ -f "${target_path}/_index.md" ]]; then
        return 0
    elif [[ -f "${target_path}/README.md" ]]; then
        return 0
    fi

    echo "Error: Broken link"
    echo "  File: $file:$line_no"
    echo "  Link: $link"
    echo "  Target: $target_path (and variants)"
    EXIT_CODE=1
}

echo "Starting link validation..."

while read -r FILE; do
    declare -A CODE_LINES
    in_code=false
    line_no=0

    # Pass 1: mark fenced code block lines
    while IFS= read -r line; do
        ((line_no++))
        if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
            if $in_code; then
                in_code=false
            else
                in_code=true
            fi
            CODE_LINES[$line_no]=1
        elif $in_code; then
            CODE_LINES[$line_no]=1
        fi
    done < "$FILE"

    # Pass 2: extract links with original line numbers
    while read -r MATCH; do
        [[ -z "$MATCH" ]] && continue

        LINE_NO="${MATCH%%:*}"
        LINK_PART="${MATCH#*:}"

        [[ ${CODE_LINES[$LINE_NO]} ]] && continue

        LINK="${LINK_PART#*](}"
        LINK="${LINK%)}"

        check_internal_link "$LINK" "$FILE" "$LINE_NO"
    done < <(grep -n -oE '\]\([^)]+\)' "$FILE")

    unset CODE_LINES
done < <(find "$CONTENT_DIR" -type f -name "*.md")

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Link validation passed!"
else
    echo "Link validation failed!"
fi

exit $EXIT_CODE
