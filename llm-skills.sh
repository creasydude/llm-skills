#!/usr/bin/env bash
#
# llm-skills — Install and manage AI coding assistant skills
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/creasydude/llm-skills/main/llm-skills.sh | bash
#   llm-skills install [--tool <tool>] [--skill <name>]
#   llm-skills list
#   llm-skills remove <name>
#

set -euo pipefail

REPO="creasydude/llm-skills"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/llm-skills.sh"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/skills"
INSTALL_DIR="${HOME}/.local/share/llm-skills"
BIN_DIR="${HOME}/.local/bin"
COMMAND_PATH="${BIN_DIR}/llm-skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Tool configurations
declare -A TOOL_PATHS
TOOL_PATHS[claude-code]=".claude/skills"
TOOL_PATHS[opencode]=".opencode/skills"
TOOL_PATHS[mimo-code]=".mimocode/skills"
TOOL_PATHS[codex]=".agents/skills"
TOOL_PATHS[cursor]=".cursor/rules"
TOOL_PATHS[windsurf]=".windsurf/skills"
TOOL_PATHS[cline]=".cline/skills"
TOOL_PATHS[copilot]=".github/instructions"

# Available skills (name:description) — fetched from GitHub on every run
declare -A SKILLS

log_info()    { echo -e "${CYAN}[info]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
log_error()   { echo -e "${RED}[error]${NC} $*" >&2; }

usage() {
    cat << 'EOF'
llm-skills — manage AI coding assistant skills

Usage:
    llm-skills install [OPTIONS]    Install skills
    llm-skills list                 List available/installed skills
    llm-skills remove <skill>       Remove an installed skill
    llm-skills help                 Show this help

Options:
    --tool <tool>    Install to specific tool (claude-code, opencode, mimo-code, codex, cursor, windsurf, cline, copilot)
    --skill <name>   Install a specific skill (default: all)

Examples:
    llm-skills install                        # Install all skills to all detected tools
    llm-skills install --tool claude-code     # Install all skills to Claude Code
    llm-skills install --skill telegram       # Install telegram skill to all tools
    llm-skills install --tool mimo-code --skill telegram
    llm-skills list                           # Show what's installed
    llm-skills remove telegram                # Remove telegram skill

EOF
}

# Fetch a file from GitHub
fetch_file() {
    local url="$1"
    local dest="$2"
    curl -fsSL "$url" -o "$dest" 2>/dev/null
}

# Auto-update: fetch latest script from GitHub, replace self if changed, re-exec
auto_update() {
    # Skip if running from local repo (dev mode)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${script_dir}/skills/telegram/SKILL.md" ] || [ -f "${script_dir}/.git/config" ]; then
        return 0
    fi

    # Skip if command doesn't exist yet (first install via curl)
    if [ ! -f "$COMMAND_PATH" ]; then
        return 0
    fi

    # Fetch latest script
    local tmp
    tmp=$(mktemp)
    if ! fetch_file "$SCRIPT_URL" "$tmp"; then
        rm -f "$tmp"
        return 0  # silent fail — run with current version
    fi

    # Compare with current
    if ! diff -q "$tmp" "$COMMAND_PATH" >/dev/null 2>&1; then
        log_info "Updating llm-skills..."
        cp "$tmp" "$COMMAND_PATH"
        chmod +x "$COMMAND_PATH"
        rm -f "$tmp"
        exec "$COMMAND_PATH" "$@"  # re-exec with same args
    fi

    rm -f "$tmp"
}

# Fetch available skills from GitHub
fetch_skills() {
    # Fetch skills directory listing from GitHub API
    local skills_list
    skills_list=$(curl -fsSL "https://api.github.com/repos/${REPO}/contents/skills" 2>/dev/null | \
                  grep -o '"name": *"[^"]*"' | \
                  sed 's/"name": *"\([^"]*\)"/\1/' 2>/dev/null) || skills_list=""

    if [ -n "$skills_list" ]; then
        while IFS= read -r skill; do
            [ -z "$skill" ] && continue
            # Fetch description from SKILL.md frontmatter
            local desc
            desc=$(curl -fsSL "${BASE_URL}/${skill}/SKILL.md" 2>/dev/null | \
                   sed -n '/^---$/,/^---$/p' | \
                   grep "^description:" | \
                   head -1 | \
                   sed 's/^description:[[:space:]]*//' 2>/dev/null) || desc=""
            # Clean up quotes
            desc="${desc#\"}"
            desc="${desc%\"}"
            if [ -n "$desc" ]; then
                SKILLS["$skill"]="$desc"
            else
                SKILLS["$skill"]="(no description)"
            fi
        done <<< "$skills_list"
    fi

    # Fallback: hardcoded list (for offline or if API fails)
    set +u
    if [ "${#SKILLS[@]}" -eq 0 ]; then
        SKILLS[telegram-serverless]="Build Telegram bots on Telegram's serverless infrastructure — no VPS, no containers, deploy with one command"
    fi
    set -u
}

# Detect installed tools
detect_tools() {
    local detected=()
    for tool in "${!TOOL_PATHS[@]}"; do
        case "$tool" in
            claude-code) command -v claude >/dev/null 2>&1 && detected+=("$tool") ;;
            opencode)    command -v opencode >/dev/null 2>&1 || [ -d .opencode ] && detected+=("$tool") ;;
            mimo-code)   command -v mimo >/dev/null 2>&1 || [ -d .mimocode ] && detected+=("$tool") ;;
            codex)       command -v codex >/dev/null 2>&1 || [ -d .codex ] && detected+=("$tool") ;;
            cursor)      command -v cursor >/dev/null 2>&1 || [ -d .cursor ] && detected+=("$tool") ;;
            windsurf)    command -v windsurf >/dev/null 2>&1 || [ -d .windsurf ] && detected+=("$tool") ;;
            cline)       command -v cline >/dev/null 2>&1 || [ -d .cline ] && detected+=("$tool") ;;
            copilot)     command -v gh >/dev/null 2>&1 || [ -d .github ] && detected+=("$tool") ;;
        esac
    done
    echo "${detected[@]}"
}

# Install a skill to a tool
install_skill_to_tool() {
    local skill="$1"
    local tool="$2"
    local target_base="${TOOL_PATHS[$tool]}"

    if [ -z "$target_base" ]; then
        log_warn "Unknown tool: $tool"
        return 1
    fi

    local target_dir="${target_base}/${skill}"
    mkdir -p "$target_dir"

    local target_file="${target_dir}/SKILL.md"

    # Try local file first (when running from repo), then GitHub
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_skill="${script_dir}/skills/${skill}/SKILL.md"

    if [ -f "$local_skill" ]; then
        cp "$local_skill" "$target_file"
    else
        # Fetch from GitHub
        local skill_url="${BASE_URL}/${skill}/SKILL.md"
        if ! fetch_file "$skill_url" "$target_file"; then
            log_error "Failed to fetch ${skill}/SKILL.md"
            return 1
        fi
    fi

    log_ok "Installed ${skill} to ${target_dir}/"
}

# Install skills
cmd_install() {
    local tools=()
    local skill_pattern="*"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tools+=("$2"); shift 2 ;;
            --skill) skill_pattern="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # If no tools specified, detect
    if [ ${#tools[@]} -eq 0 ]; then
        local detected
        detected=$(detect_tools)
        if [ -z "$detected" ]; then
            log_warn "No tools detected. Using --tool to specify."
            echo "Available tools: ${!TOOL_PATHS[*]}"
            return 1
        fi
        tools=($detected)
    fi

    # Get skills to install
    local skills_to_install=()
    if [ "$skill_pattern" = "*" ]; then
        skills_to_install=(${!SKILLS[@]})
    else
        # Check if specific skill exists
        if [[ -v "SKILLS[$skill_pattern]" ]]; then
            skills_to_install=("$skill_pattern")
        else
            log_error "Unknown skill: $skill_pattern"
            echo "Available skills: ${!SKILLS[*]}"
            return 1
        fi
    fi

    # Install
    for skill in "${skills_to_install[@]}"; do
        for tool in "${tools[@]}"; do
            install_skill_to_tool "$skill" "$tool"
        done
    done
}

# List skills
cmd_list() {
    echo -e "${CYAN}Available skills:${NC}"
    for skill in $(echo "${!SKILLS[@]}" | tr ' ' '\n' | sort); do
        echo "  ${GREEN}${skill}${NC} — ${SKILLS[$skill]}"
    done

    echo ""
    echo -e "${CYAN}Installed:${NC}"

    local found=0
    for tool in "${!TOOL_PATHS[@]}"; do
        local base="${TOOL_PATHS[$tool]}"
        if [ -d "$base" ]; then
            for skill_dir in "$base"/*/; do
                if [ -d "$skill_dir" ]; then
                    local name
                    name=$(basename "$skill_dir")
                    echo "  ${name} → ${skill_dir}"
                    found=1
                fi
            done
        fi
    done

    [ $found -eq 0 ] && echo "  (none)"
}

# Remove a skill
cmd_remove() {
    local skill="${1:-}"
    if [ -z "$skill" ]; then
        log_error "Usage: llm-skills remove <skill-name>"
        return 1
    fi

    local removed=0
    for tool in "${!TOOL_PATHS[@]}"; do
        local target="${TOOL_PATHS[$tool]}/${skill}"
        if [ -d "$target" ]; then
            rm -rf "$target"
            log_ok "Removed ${target}/"
            removed=$((removed + 1))
        fi
    done

    [ $removed -eq 0 ] && log_warn "Skill '${skill}' not found in any tool directory"
}

# Self-install (called by curl | bash)
self_install() {
    log_info "Installing llm-skills..."

    # Create directories
    mkdir -p "$INSTALL_DIR" "$BIN_DIR"

    # Download the script to ~/.local/bin/llm-skills
    if ! fetch_file "$SCRIPT_URL" "$COMMAND_PATH"; then
        log_error "Failed to download llm-skills"
        return 1
    fi
    chmod +x "$COMMAND_PATH"

    log_ok "Installed to ${COMMAND_PATH}"

    # Check if ~/.local/bin is in PATH
    case ":$PATH:" in
        *":${BIN_DIR}:"*) ;;
        *)
            log_warn "${BIN_DIR} is not in your PATH."
            echo "  Add this to your shell profile:"
            echo ""
            echo "    export PATH=\"${BIN_DIR}:\$PATH\""
            echo ""
            echo "  Or run: export PATH=\"${BIN_DIR}:\$PATH\""
            ;;
    esac

    # Auto-install skills if this is piped from curl
    echo ""
    log_info "Installing skills to detected tools..."
    cmd_install
}

# Main
main() {
    # If no arguments, this was likely called via curl | bash
    if [ $# -eq 0 ]; then
        self_install
        return
    fi

    # Auto-update on every run (unless running from local repo)
    auto_update "$@"

    # Fetch latest skills from GitHub
    fetch_skills

    local cmd="$1"
    shift

    case "$cmd" in
        install)  cmd_install "$@" ;;
        list)     cmd_list ;;
        remove)   cmd_remove "$@" ;;
        help|-h|--help) usage ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            return 1
            ;;
    esac
}

main "$@"
