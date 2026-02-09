#!/bin/bash

CONTENT_DIR="content"
EXIT_CODE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTENT_ROOT="$(cd "$REPO_ROOT/$CONTENT_DIR" && pwd)"

if [[ ! -d "$CONTENT_ROOT" ]]; then
    echo "Error: content directory not found. Run from repository root."
    exit 1
fi

normalize_link() {
    local link="$1"

    link="${link//%/\\x}"
    link="$(printf '%b' "$link")"

    link="${link%%#*}"
    link="${link%%\?*}"

    if [[ "$link" != "/" ]]; then
        link="${link%/}"
    fi

    printf "%s" "$link"
}

canonicalize_path() {
    local path="$1"
    local result=()
    local part

    IFS='/' read -r -a parts <<< "$path"

    for part in "${parts[@]}"; do
        if [[ -z "$part" || "$part" == "." ]]; then
            continue
        elif [[ "$part" == ".." ]]; then
            if [[ ${#result[@]} -gt 0 ]]; then
                unset 'result[-1]'
            fi
        else
            result+=("$part")
        fi
    done

    if [[ ${#result[@]} -eq 0 ]]; then
        printf "/"
    else
        ( IFS='/'; printf "/%s" "${result[*]}" )
    fi
}

resolve_real_path() {
    local path="$1"

    if command -v python3 >/dev/null 2>&1; then
        # Use python to compute realpath which is tolerant of non existing final target
        python3 - <<'PY' "$path"
import os
import sys
p = sys.argv[1]
# os.path.realpath resolves symlinks for existing components and otherwise returns a normalized path
print(os.path.realpath(p))
PY
    else
        # Fallback to the safe canonicalize_path output if python3 is not available
        canonicalize_path "$path"
    fi
}

check_internal_link() {
    local link="$1"
    local file="$2"
    local line_no="$3"
    local clean_link
    local target_path
    local location

    clean_link="$(normalize_link "$link")"

    [[ -z "$clean_link" || "$clean_link" == "#" ]] && return 0

    if [[ "$clean_link" == "{{"* ]]; then
        return 0
    fi

    local clean_lower="${clean_link,,}"

    if [[ "$clean_lower" == http://* || "$clean_lower" == https://* || "$clean_lower" == "//"* ]]; then
        return 0
    fi

    case "$clean_lower" in
        mailto:*|tel:*|javascript:*|data:*)
            return 0
            ;;
    esac

    if [[ "$clean_link" == /docs/* ]]; then
        target_path="$CONTENT_ROOT/en${clean_link}"
    elif [[ "$clean_link" == /cn/docs/* ]]; then
        target_path="$CONTENT_ROOT${clean_link}"
    elif [[ "$clean_link" == /* ]]; then
        target_path="$CONTENT_ROOT/en${clean_link}"
    else
        local file_dir
        file_dir="$(cd "$(dirname "$file")" && pwd)"
        target_path="$file_dir/$clean_link"
    fi

    target_path="$(canonicalize_path "$target_path")"
    target_path="$(resolve_real_path "$target_path")"

    case "$target_path" in
        "$CONTENT_ROOT"/*) ;;
        *)
            location="$file"
            [[ -n "$line_no" ]] && location="$file:$line_no"
            echo "Error: Link resolves outside content directory"
            echo "  File: $location"
            echo "  Link: $link"
            EXIT_CODE=1
            return
            ;;
    esac

    case "$clean_lower" in
        *.png|*.jpg|*.jpeg|*.svg|*.gif|*.xml|*.yaml|*.yml|*.json|*.css|*.js|*.pdf|*.zip|*.tar.gz)
            if [[ -f "$target_path" ]]; then
                return 0
            else
                location="$file"
                [[ -n "$line_no" ]] && location="$file:$line_no"
                echo "Error: Broken link"
                echo "  File: $location"
                echo "  Link: $link"
                echo "  Target: $target_path"
                EXIT_CODE=1
                return
            fi
            ;;
    esac

    if [[ -f "$target_path" || -f "$target_path.md" || -f "$target_path/_index.md" || -f "$target_path/README.md" ]]; then
        return 0
    fi

    location="$file"
    [[ -n "$line_no" ]] && location="$file:$line_no"

    echo "Error: Broken link"
    echo "  File: $location"
    echo "  Link: $link"
    echo "  Target: $target_path"
    EXIT_CODE=1
}

echo "Starting link validation..."

while read -r FILE; do
    declare -A CODE_LINES
    in_fence=false
    line_no=0

    while IFS= read -r line; do
        ((line_no++))

        if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
            if $in_fence; then
                in_fence=false
            else
                in_fence=true
            fi
            CODE_LINES[$line_no]=1
            continue
        fi

        if $in_fence; then
            CODE_LINES[$line_no]=1
            continue
        fi

        inline_count=$(grep -o "\`" <<< "$line" | wc -l)
        if (( inline_count % 2 == 1 )); then
            CODE_LINES[$line_no]=1
        fi
    done < "$FILE"

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
done < <(find "$CONTENT_ROOT" -type f -name "*.md")

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Link validation passed!"
else
    echo "Link validation failed!"
fi

exit $EXIT_CODE
