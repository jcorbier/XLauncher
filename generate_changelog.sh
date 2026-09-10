#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_FILE="RELEASE_CHANGELOG.md"
PRO_CHANGELOG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pro-changelog)
            PRO_CHANGELOG="$2"
            shift 2
            ;;
        *)
            if [[ "$1" != -* && "$OUTPUT_FILE" == "RELEASE_CHANGELOG.md" ]]; then
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

if [ "$IS_PRERELEASE" = "true" ]; then
    # Pre-release: get immediately previous tag
    PREVIOUS_TAG=$(git tag --sort=-version:refname | grep -v "^${TAG_NAME}$" | head -n 1 || true)
    CURRENT_TAG=${TAG_NAME:-"HEAD"}

    echo "# Changes in $CURRENT_TAG" > "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
else
    # Stable release: get previous non-prerelease tag (e.g. vX.Y.Z)
    PREVIOUS_TAG=$(git tag --sort=-version:refname | grep -v "^${TAG_NAME}$" | grep -E '^v[0-9]+(\.[0-9]+)*$' | head -n 1 || true)
    CURRENT_TAG=${TAG_NAME:-"HEAD"}

    echo "# Changes in $CURRENT_TAG" > "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

if [ -z "$PREVIOUS_TAG" ]; then
    echo "No previous tag found, using initial commit"
    PREVIOUS_TAG=$(git rev-list --max-parents=0 HEAD)
fi

echo "Generating changelog from $PREVIOUS_TAG to $CURRENT_TAG into $OUTPUT_FILE"

RAW_LOGS=$(git log --pretty=format:"%s (%h)" "$PREVIOUS_TAG..$CURRENT_TAG" 2>/dev/null || true)

if [ -z "$RAW_LOGS" ]; then
    echo "No changes recorded." >> "$OUTPUT_FILE"
    exit 0
fi

HAS_SECTIONS=false

# 1. Features
FEATS=$(echo "$RAW_LOGS" | grep -iE "^feat(\([^)]+\))?:" || true)
if [ -n "$FEATS" ]; then
    echo "### Features" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$FEATS" | sed "s/^/- /" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    HAS_SECTIONS=true
fi

# 2. Bug Fixes
FIXES=$(echo "$RAW_LOGS" | grep -iE "^fix(\([^)]+\))?:" || true)
if [ -n "$FIXES" ]; then
    echo "### Bug Fixes" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$FIXES" | sed "s/^/- /" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    HAS_SECTIONS=true
fi

# 3. Documentation
DOCS=$(echo "$RAW_LOGS" | grep -iE "^docs?(\([^)]+\))?:" || true)
if [ -n "$DOCS" ]; then
    echo "### Documentation" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$DOCS" | sed "s/^/- /" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    HAS_SECTIONS=true
fi

# 4. Chores
CHORES=$(echo "$RAW_LOGS" | grep -iE "^chore(\([^)]+\))?:" || true)
if [ -n "$CHORES" ]; then
    echo "### Chores" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$CHORES" | sed "s/^/- /" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    HAS_SECTIONS=true
fi

# 5. Other Changes
OTHERS=$(echo "$RAW_LOGS" | grep -ivE "^(feat|fix|docs?|chore)(\([^)]+\))?:" || true)
if [ -n "$OTHERS" ]; then
    echo "### Other Changes" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$OTHERS" | sed "s/^/- /" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    HAS_SECTIONS=true
fi

if [ "$HAS_SECTIONS" = "false" ]; then
    echo "$RAW_LOGS" | sed "s/^/- /" >> "$OUTPUT_FILE"
fi

if [ -n "$PRO_CHANGELOG" ] && [ -f "$PRO_CHANGELOG" ]; then
    PRO_CONTENT=$(sed '/^[[:space:]]*$/d' "$PRO_CHANGELOG" 2>/dev/null || true)
    if [ -n "$PRO_CONTENT" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "## 🚀 Pro Features & Updates" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        cat "$PRO_CHANGELOG" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
fi
