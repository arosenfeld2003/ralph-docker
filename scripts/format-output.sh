#!/bin/bash
# Format stream-json output to human-readable format
# Filters Claude's verbose JSON output into colored, readable text
set -euo pipefail

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "[format-output] Warning: jq not installed, passing through raw output" >&2
    cat
    exit 0
fi

# Colors
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Maximum length for tool inputs/outputs before truncation
MAX_CONTENT_LENGTH=500

# Track state
LAST_ACTIVITY=$(date +%s)
TOOL_COUNT=0
SUBAGENT_COUNT=0

timestamp() {
    date "+%H:%M:%S"
}

truncate_text() {
    local text="$1"
    local max_len="${2:-$MAX_CONTENT_LENGTH}"
    if [ "${#text}" -gt "$max_len" ]; then
        echo "${text:0:$max_len}... (truncated)"
    else
        echo "$text"
    fi
}

# Show activity indicator
show_activity() {
    LAST_ACTIVITY=$(date +%s)
}

# Process each line of JSON
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Try to parse as JSON
    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
        # Not JSON, output as-is
        echo "$line"
        continue
    fi

    # Extract message type
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)

    case "$msg_type" in
        assistant)
            # Assistant text output
            content=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
            if [ -n "$content" ] && [ "$content" != "null" ]; then
                # Handle array of content blocks
                if echo "$content" | jq -e 'type == "array"' >/dev/null 2>&1; then
                    echo "$content" | jq -r '.[] | select(.type == "text") | .text // empty' 2>/dev/null | while IFS= read -r text; do
                        [ -n "$text" ] && echo -e "${CYAN}$text${NC}"
                    done
                else
                    echo -e "${CYAN}$content${NC}"
                fi
            fi
            ;;

        content_block_start)
            # Start of a content block (tool use, etc.)
            show_activity
            block_type=$(echo "$line" | jq -r '.content_block.type // empty' 2>/dev/null)
            if [ "$block_type" = "tool_use" ]; then
                tool_name=$(echo "$line" | jq -r '.content_block.name // "unknown"' 2>/dev/null)
                # Don't double-print if we handle it in tool_use
                if [ "$tool_name" != "Task" ] && [ "$tool_name" != "Read" ] && [ "$tool_name" != "Glob" ] && [ "$tool_name" != "Grep" ] && [ "$tool_name" != "Bash" ] && [ "$tool_name" != "Write" ] && [ "$tool_name" != "Edit" ]; then
                    echo -e "${YELLOW}$(timestamp) [tool]${NC} ${BOLD}$tool_name${NC} starting..."
                fi
            fi
            ;;

        content_block_delta)
            # Incremental content (streaming text)
            show_activity
            delta_type=$(echo "$line" | jq -r '.delta.type // empty' 2>/dev/null)
            if [ "$delta_type" = "text_delta" ]; then
                text=$(echo "$line" | jq -r '.delta.text // empty' 2>/dev/null)
                [ -n "$text" ] && echo -ne "${CYAN}$text${NC}"
            elif [ "$delta_type" = "input_json_delta" ]; then
                # Tool input streaming - show a dot for activity
                echo -ne "${DIM}.${NC}"
            fi
            ;;

        tool_use)
            # Tool invocation
            TOOL_COUNT=$((TOOL_COUNT + 1))
            show_activity
            tool_name=$(echo "$line" | jq -r '.name // "unknown"' 2>/dev/null)
            tool_input=$(echo "$line" | jq -r '.input // {} | tostring' 2>/dev/null)

            # Special handling for Task/subagent spawning
            if [ "$tool_name" = "Task" ]; then
                SUBAGENT_COUNT=$((SUBAGENT_COUNT + 1))
                subagent_type=$(echo "$line" | jq -r '.input.subagent_type // "unknown"' 2>/dev/null)
                description=$(echo "$line" | jq -r '.input.description // ""' 2>/dev/null)
                echo -e "${MAGENTA}$(timestamp) [subagent #$SUBAGENT_COUNT]${NC} ${BOLD}$subagent_type${NC} - $description"
            elif [ "$tool_name" = "Read" ]; then
                file_path=$(echo "$line" | jq -r '.input.file_path // ""' 2>/dev/null)
                echo -e "${BLUE}$(timestamp) [read]${NC} $file_path"
            elif [ "$tool_name" = "Glob" ]; then
                pattern=$(echo "$line" | jq -r '.input.pattern // ""' 2>/dev/null)
                echo -e "${BLUE}$(timestamp) [glob]${NC} $pattern"
            elif [ "$tool_name" = "Grep" ]; then
                pattern=$(echo "$line" | jq -r '.input.pattern // ""' 2>/dev/null)
                echo -e "${BLUE}$(timestamp) [grep]${NC} $pattern"
            elif [ "$tool_name" = "Bash" ]; then
                cmd=$(echo "$line" | jq -r '.input.command // ""' 2>/dev/null)
                truncated=$(truncate_text "$cmd" 100)
                echo -e "${YELLOW}$(timestamp) [bash]${NC} $truncated"
            elif [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ]; then
                file_path=$(echo "$line" | jq -r '.input.file_path // ""' 2>/dev/null)
                echo -e "${GREEN}$(timestamp) [$tool_name]${NC} $file_path"
            else
                echo -e "${YELLOW}$(timestamp) [tool #$TOOL_COUNT]${NC} ${BOLD}$tool_name${NC}"
                truncated=$(truncate_text "$tool_input" 200)
                echo -e "${DIM}  input: $truncated${NC}"
            fi
            ;;

        tool_result)
            # Tool execution result
            show_activity
            tool_id=$(echo "$line" | jq -r '.tool_use_id // "?"' 2>/dev/null)
            is_error=$(echo "$line" | jq -r '.is_error // false' 2>/dev/null)
            content=$(echo "$line" | jq -r '.content // empty' 2>/dev/null)

            if [ "$is_error" = "true" ]; then
                echo -e "${RED}$(timestamp) [error]${NC} Tool failed"
                [ -n "$content" ] && echo -e "${RED}  $(truncate_text "$content" 300)${NC}"
            else
                # Show brief result info
                content_len=${#content}
                echo -e "${DIM}$(timestamp) [done]${NC} ${DIM}(${content_len} chars)${NC}"
            fi
            ;;

        error)
            # Error message
            error_msg=$(echo "$line" | jq -r '.error.message // .message // "Unknown error"' 2>/dev/null)
            echo -e "${RED}[ERROR]${NC} $error_msg"
            ;;

        message_start)
            # New message starting
            model=$(echo "$line" | jq -r '.message.model // empty' 2>/dev/null)
            [ -n "$model" ] && echo -e "${DIM}[model: $model]${NC}"
            ;;

        message_stop)
            # Message complete
            echo ""
            ;;

        system)
            # System message
            text=$(echo "$line" | jq -r '.message // empty' 2>/dev/null)
            [ -n "$text" ] && echo -e "${MAGENTA}[system]${NC} $text"
            ;;

        result)
            # Final result
            cost=$(echo "$line" | jq -r '.total_cost_usd // .cost_usd // empty' 2>/dev/null)
            duration=$(echo "$line" | jq -r '.duration_ms // empty' 2>/dev/null)
            num_turns=$(echo "$line" | jq -r '.num_turns // empty' 2>/dev/null)
            echo ""
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  ITERATION SUMMARY${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            [ -n "$duration" ] && echo -e "  Duration:   ${duration}ms ($(( duration / 1000 ))s)"
            [ -n "$cost" ] && echo -e "  Cost:       \$$cost"
            [ -n "$num_turns" ] && echo -e "  API turns:  $num_turns"
            echo -e "  Tools used: $TOOL_COUNT"
            echo -e "  Subagents:  $SUBAGENT_COUNT"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            # Reset counters for next iteration
            TOOL_COUNT=0
            SUBAGENT_COUNT=0
            ;;

        *)
            # Unknown type - check for common patterns
            if echo "$line" | jq -e '.subagent' >/dev/null 2>&1; then
                subagent=$(echo "$line" | jq -r '.subagent // empty' 2>/dev/null)
                echo -e "${MAGENTA}[subagent]${NC} $subagent"
            fi
            ;;
    esac
done
