#!/bin/bash

# Configuration
CONTENT_DIR="content"
EXIT_CODE=0

strip_fenced_code_blocks() {
    awk '
        BEGIN { code = 0 }
        /^[[:space:]]*```/ { code = !code; next }
        /^[[:space:]]*~~~/ { code = !code; next }
        { if (!code) print }
    ' "$1"
}

normalize_link() {
    local link="$1"

    # Remove anchor and query parameters
    link="${link%%#*}"
    link="${link%%\?*}"

    # Remove trailing slash
    if [[ "$link" != "/" ]]; then
        link="${link%/}"
    fi

    printf "%s" "$link"
}

check_internal_link() {
    local link="$1"
    local file="$2"
    local clean_link
    local target_path

    clean_link=$(normalize_link "$link")

    # Skip empty or anchor-only links
    if [[ -z "$clean_link" || "$clean_link" == "#" ]]; then
        return 0
    fi

    # Skip Hugo shortcodes
    if [[ "$clean_link" == "{{<"* || "$clean_link" == "{{%"* || "$clean_link" == "{{"* ]]; then
        return 0
    fi

    # Convert to lowercase for protocol checking (case-insensitive)
    local clean_link_lower="${clean_link,,}"

    # Skip external links (case-insensitive)
    if [[ "$clean_link_lower" == http://* || "$clean_link_lower" == https://* || "$clean_link_lower" == "//"* ]]; then
        return 0
    fi

    # Skip mailto, tel, javascript, data links
    case "$clean_link_lower" in
        mailto:*|tel:*|javascript:*|data:*)
            return 0
            ;;
    esac

    # Resolve target path based on link type
    if [[ "$clean_link" == /docs/* ]]; then
        # Hugo path: /docs/* → content/en/docs/*
        target_path="content/en${clean_link}"
    elif [[ "$clean_link" == /cn/docs/* ]]; then
        # Hugo path: /cn/docs/* → content/cn/docs/*
        target_path="content${clean_link}"
    elif [[ "$clean_link" == /* ]]; then
        # Absolute root path: /* → content/en/*
        target_path="content/en${clean_link}"
    else
        # Relative link: resolve against file directory
        local file_dir=$(dirname "$file")
        target_path="${file_dir}/${clean_link}"
        
        # Normalize path (remove redundant ./ and resolve ../)
        while [[ "$target_path" == *"/./"* ]]; do
            target_path="${target_path//\/.\//\/}"
        done
        
        # Basic .. resolution
        while [[ "$target_path" =~ ([^/]+/\.\./?) ]]; do
            target_path="${target_path/${BASH_REMATCH[0]}/}"
        done
    fi

    # Check asset files first (non-markdown extensions)
    case "$clean_link_lower" in
        *.png|*.jpg|*.jpeg|*.svg|*.gif|*.xml|*.yaml|*.yml|*.json|*.css|*.js|*.pdf|*.zip|*.tar.gz)
            [[ -f "$target_path" ]] && return 0
            ;;
    esac

    # Check for markdown file existence variations
    if [[ -f "${target_path}.md" ]]; then
        return 0
    elif [[ -f "$target_path" ]]; then
        return 0
    elif [[ -f "${target_path}/_index.md" ]]; then
        return 0
    elif [[ -f "${target_path}/README.md" ]]; then
        return 0
    fi

    echo "Error: Broken link in $file"
    echo "  Link: $link"
    echo "  Target: $target_path (and variants)"
    EXIT_CODE=1
}

echo "Starting link validation..."

# Find all markdown files and verify links
while read -r FILE; do
    # Extract inline links [text](url) and check internal doc links
    while read -r MATCH; do
        if [[ -z "$MATCH" ]]; then continue; fi

        # Extract URL from ](url)
        LINK="${MATCH#*](}"
        LINK="${LINK%)}"

        check_internal_link "$LINK" "$FILE"
    done < <(strip_fenced_code_blocks "$FILE" | grep -oE '\]\([^)]+\)')
done < <(find "$CONTENT_DIR" -type f -name "*.md")

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Link validation passed!"
else
    echo "Link validation failed!"
fi

exit $EXIT_CODE
