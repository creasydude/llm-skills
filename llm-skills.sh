#!/usr/bin/env bash
#
# llm-skills — Install and manage AI coding assistant skills
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/creasydude/llm-skills/main/llm-skills.sh | bash
#   llm-skills                    # Interactive TUI
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
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
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

# Available skills (name:description)
declare -A SKILLS

# TUI state
declare -a MENU_ITEMS=()
declare -a MENU_LABELS=()
declare -a SELECTED=()
MENU_TITLE=""
MENUFOCUS=0

# ============================================================================
# TUI Functions
# ============================================================================

tui_clear() { printf '\033[2J\033[H'; }
tui_hide_cursor() { printf '\033[?25l'; }
tui_show_cursor() { printf '\033[?25h'; }

tui_box() {
    local title="$1"
    local width=60
    local border="${CYAN}"

    echo ""
    echo -e "  ${border}┌$(printf '─%.0s' $(seq 1 $((width-2))))┐${NC}"
    printf "  ${border}│${NC}%*s${BOLD}${WHITE}%s${NC}%*s${border}│${NC}\n" $(( (width-2-${#title})/2 )) "" "$title" $(( (width-1-${#title})/2 )) ""
    echo -e "  ${border}├$(printf '─%.0s' $(seq 1 $((width-2))))┤${NC}"
}

tui_box_end() {
    local border="${CYAN}"
    local width=60
    echo -e "  ${border}└$(printf '─%.0s' $(seq 1 $((width-2))))┘${NC}"
    echo ""
}

tui_menu() {
    local title="$1"
    shift
    local items=("$@")

    MENU_TITLE="$title"
    MENU_ITEMS=("${items[@]}")
    MENUFOCUS=0

    while true; do
        tui_clear
        tui_box "$title"

        local i=0
        for item in "${items[@]}"; do
            if [ $i -eq $MENUFOCUS ]; then
                echo -e "  ${CYAN}│${NC}  ${WHITE}${BOLD}▸ ${item}${NC}"
            else
                echo -e "  ${CYAN}│${NC}  ${DIM}  ${item}${NC}"
            fi
            i=$((i + 1))
        done

        tui_box_end
        echo -e "  ${DIM}↑↓ navigate  Enter select  q quit${NC}"

        # Read input
        tui_hide_cursor
        local key
        read -rsn1 key

        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') MENUFOCUS=$(( (MENUFOCUS - 1 + ${#items[@]} ) % ${#items[@]} )) ;;
                    '[B') MENUFOCUS=$(( (MENUFOCUS + 1) % ${#items[@]} )) ;;
                esac
                ;;
            '')
                tui_show_cursor
                return $MENUFOCUS
                ;;
            q|Q)
                tui_show_cursor
                return 255
                ;;
        esac
    done
}

tui_multi_select() {
    local title="$1"
    shift
    local items=("$@")

    SELECTED=()
    local -a checked=()
    for _ in "${items[@]}"; do checked+=(" "); done

    local focus=0

    while true; do
        tui_clear
        tui_box "$title"

        local i=0
        for item in "${items[@]}"; do
            local checkbox=" "
            if [ "${checked[$i]}" = "x" ]; then
                checkbox="${GREEN}✓${NC}"
            fi

            if [ $i -eq $focus ]; then
                echo -e "  ${CYAN}│${NC}  ${WHITE}${BOLD}▸ [${checkbox}] ${item}${NC}"
            else
                echo -e "  ${CYAN}│${NC}  ${DIM}  [${checkbox}] ${item}${NC}"
            fi
            i=$((i + 1))
        done

        tui_box_end
        echo -e "  ${DIM}↑↓ navigate  Space toggle  Enter confirm  q cancel${NC}"

        tui_hide_cursor
        local key
        read -rsn1 key

        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') focus=$(( (focus - 1 + ${#items[@]} ) % ${#items[@]} )) ;;
                    '[B') focus=$(( (focus + 1) % ${#items[@]} )) ;;
                esac
                ;;
            ' ')
                if [ "${checked[$focus]}" = "x" ]; then
                    checked[$focus]=" "
                else
                    checked[$focus]="x"
                fi
                ;;
            '')
                tui_show_cursor
                SELECTED=()
                i=0
                for item in "${items[@]}"; do
                    if [ "${checked[$i]}" = "x" ]; then
                        SELECTED+=("$item")
                    fi
                    i=$((i + 1))
                done
                return 0
                ;;
            q|Q)
                tui_show_cursor
                SELECTED=()
                return 255
                ;;
        esac
    done
}

tui_select_tool() {
    local tools=("$@")
    local labels=()
    for tool in "${tools[@]}"; do
        labels+=("${tool} (${TOOL_PATHS[$tool]})")
    done

    tui_menu "Select Target Tool" "${labels[@]}"
    local choice=$?

    if [ $choice -eq 255 ]; then
        return 255
    fi

    echo "${tools[$choice]}"
}

tui_show_installed() {
    tui_clear
    tui_box "Installed Skills"

    local found=0
    for tool in "${!TOOL_PATHS[@]}"; do
        local base="${TOOL_PATHS[$tool]}"
        if [ -d "$base" ]; then
            for skill_dir in "$base"/*/; do
                if [ -d "$skill_dir" ]; then
                    local name
                    name=$(basename "$skill_dir")
                    echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC} ${WHITE}${name}${NC} ${DIM}→ ${base}/${name}/${NC}"
                    found=1
                fi
            done
        fi
    done

    if [ $found -eq 0 ]; then
        echo -e "  ${CYAN}│${NC}  ${DIM}(no skills installed)${NC}"
    fi

    tui_box_end
    echo -e "  ${DIM}Press any key to continue${NC}"
    read -rsn1
}

tui_remove_skill() {
    # Collect installed skills
    local installed=()
    for tool in "${!TOOL_PATHS[@]}"; do
        local base="${TOOL_PATHS[$tool]}"
        if [ -d "$base" ]; then
            for skill_dir in "$base"/*/; do
                if [ -d "$skill_dir" ]; then
                    local name
                    name=$(basename "$skill_dir")
                    # Deduplicate
                    local found=0
                    for s in "${installed[@]}"; do
                        [ "$s" = "$name" ] && found=1
                    done
                    [ $found -eq 0 ] && installed+=("$name")
                fi
            done
        fi
    done

    if [ ${#installed[@]} -eq 0 ]; then
        tui_clear
        tui_box "Remove Skill"
        echo -e "  ${CYAN}│${NC}  ${DIM}No skills installed${NC}"
        tui_box_end
        echo -e "  ${DIM}Press any key to continue${NC}"
        read -rsn1
        return
    fi

    tui_multi_select "Select Skills to Remove" "${installed[@]}"
    local ret=$?

    if [ $ret -eq 255 ] || [ ${#SELECTED[@]} -eq 0 ]; then
        return
    fi

    for skill in "${SELECTED[@]}"; do
        for tool in "${!TOOL_PATHS[@]}"; do
            local target="${TOOL_PATHS[$tool]}/${skill}"
            if [ -d "$target" ]; then
                rm -rf "$target"
            fi
        done
    done

    tui_clear
    tui_box "Remove Skill"
    for skill in "${SELECTED[@]}"; do
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC} Removed ${WHITE}${skill}${NC}"
    done
    tui_box_end
    echo -e "  ${DIM}Press any key to continue${NC}"
    read -rsn1
}

# ============================================================================
# Core Functions
# ============================================================================

log_info()    { echo -e "${CYAN}[info]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
log_error()   { echo -e "${RED}[error]${NC} $*" >&2; }

usage() {
    cat << 'EOF'
llm-skills — manage AI coding assistant skills

Usage:
    llm-skills                         Interactive TUI
    llm-skills install [OPTIONS]       Install skills (CLI mode)
    llm-skills list                    List available/installed skills
    llm-skills remove <skill>          Remove an installed skill
    llm-skills help                    Show this help

Options:
    --tool <tool>    Install to specific tool
    --skill <name>   Install a specific skill

EOF
}

fetch_file() {
    local url="$1"
    local dest="$2"
    curl -fsSL "$url" -o "$dest" 2>/dev/null
}

auto_update() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Skip if running from local repo
    if [ -f "${script_dir}/.git/config" ]; then
        return 0
    fi

    # Skip if command doesn't exist yet
    if [ ! -f "$COMMAND_PATH" ]; then
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    if ! fetch_file "$SCRIPT_URL" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi

    if ! diff -q "$tmp" "$COMMAND_PATH" >/dev/null 2>&1; then
        log_info "Updating llm-skills..."
        cp "$tmp" "$COMMAND_PATH"
        chmod +x "$COMMAND_PATH"
        rm -f "$tmp"
        exec "$COMMAND_PATH" "$@"
    fi

    rm -f "$tmp"
}

fetch_skills() {
    local skills_list
    skills_list=$(curl -fsSL "https://api.github.com/repos/${REPO}/contents/skills" 2>/dev/null | \
                  grep -o '"name": *"[^"]*"' | \
                  sed 's/"name": *"\([^"]*\)"/\1/' 2>/dev/null) || skills_list=""

    if [ -n "$skills_list" ]; then
        while IFS= read -r skill; do
            [ -z "$skill" ] && continue
            local desc
            desc=$(curl -fsSL "${BASE_URL}/${skill}/SKILL.md" 2>/dev/null | \
                   sed -n '/^---$/,/^---$/p' | \
                   grep "^description:" | \
                   head -1 | \
                   sed 's/^description:[[:space:]]*//' 2>/dev/null) || desc=""
            desc="${desc#\"}"
            desc="${desc%\"}"
            if [ -n "$desc" ]; then
                SKILLS["$skill"]="$desc"
            else
                SKILLS["$skill"]="(no description)"
            fi
        done <<< "$skills_list"
    fi

    set +u
    if [ "${#SKILLS[@]}" -eq 0 ]; then
        SKILLS[telegram-serverless]="Build Telegram bots on Telegram's serverless infrastructure"
    fi
    set -u
}

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

install_skill_to_tool() {
    local skill="$1"
    local tool="$2"
    local target_base="${TOOL_PATHS[$tool]}"

    if [ -z "$target_base" ]; then
        return 1
    fi

    local target_dir="${target_base}/${skill}"
    mkdir -p "$target_dir"

    local target_file="${target_dir}/SKILL.md"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_skill="${script_dir}/skills/${skill}/SKILL.md"

    if [ -f "$local_skill" ]; then
        cp "$local_skill" "$target_file"
    else
        local skill_url="${BASE_URL}/${skill}/SKILL.md"
        if ! fetch_file "$skill_url" "$target_file"; then
            return 1
        fi
    fi

    log_ok "Installed ${skill} → ${target_dir}/"
}

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

    if [ ${#tools[@]} -eq 0 ]; then
        local detected
        detected=$(detect_tools)
        if [ -z "$detected" ]; then
            log_warn "No tools detected. Use --tool to specify."
            return 1
        fi
        tools=($detected)
    fi

    local skills_to_install=()
    if [ "$skill_pattern" = "*" ]; then
        set +u
        skills_to_install=(${!SKILLS[@]})
        set -u
    else
        set +u
        if [[ -v "SKILLS[$skill_pattern]" ]]; then
            skills_to_install=("$skill_pattern")
        else
            log_error "Unknown skill: $skill_pattern"
            return 1
        fi
        set -u
    fi

    for skill in "${skills_to_install[@]}"; do
        for tool in "${tools[@]}"; do
            install_skill_to_tool "$skill" "$tool"
        done
    done
}

cmd_list() {
    echo -e "${CYAN}Available skills:${NC}"
    set +u
    for skill in $(echo "${!SKILLS[@]}" | tr ' ' '\n' | sort); do
        echo -e "  ${GREEN}${skill}${NC} — ${SKILLS[$skill]}"
    done
    set -u

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
                    echo -e "  ${name} → ${skill_dir}"
                    found=1
                fi
            done
        fi
    done

    [ $found -eq 0 ] && echo "  (none)"
}

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

    [ $removed -eq 0 ] && log_warn "Skill '${skill}' not found"
}

self_install() {
    log_info "Installing llm-skills..."

    mkdir -p "$INSTALL_DIR" "$BIN_DIR"

    if ! fetch_file "$SCRIPT_URL" "$COMMAND_PATH"; then
        log_error "Failed to download llm-skills"
        return 1
    fi
    chmod +x "$COMMAND_PATH"

    log_ok "Installed to ${COMMAND_PATH}"

    # Check PATH
    local path_ok=0
    case ":$PATH:" in
        *":${BIN_DIR}:"*) path_ok=1 ;;
    esac

    if [ $path_ok -eq 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Add this to your shell profile:${NC}"
        echo ""
        echo -e "    ${BOLD}export PATH=\"${BIN_DIR}:\$PATH\"${NC}"
        echo ""
        echo -e "  Or run now: ${BOLD}export PATH=\"${BIN_DIR}:\$PATH\"${NC}"
        echo ""
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}✓ Done!${NC} Run ${BOLD}llm-skills${NC} to open the TUI."
    echo ""
}

# TUI main loop
tui_main() {
    fetch_skills

    while true; do
        tui_clear
        tui_box "llm-skills"
        echo -e "  ${CYAN}│${NC}"
        echo -e "  ${CYAN}│${NC}  ${DIM}Manage AI coding assistant skills${NC}"
        echo -e "  ${CYAN}│${NC}  ${DIM}github.com/${REPO}${NC}"
        echo -e "  ${CYAN}│${NC}"

        tui_box_end

        tui_menu "Main Menu" \
            "Install Skills" \
            "View Installed" \
            "Remove Skills" \
            "Update llm-skills" \
            "Exit"

        local choice=$?

        case $choice in
            0) # Install Skills
                local tools=()
                for tool in "${!TOOL_PATHS[@]}"; do tools+=("$tool"); done

                tui_multi_select "Select Skills to Install" "${!SKILLS[@]}"
                local ret=$?

                if [ $ret -eq 255 ] || [ ${#SELECTED[@]} -eq 0 ]; then
                    continue
                fi

                # Detect tools
                local detected
                detected=$(detect_tools)

                tui_clear
                tui_box "Installing Skills"

                for skill in "${SELECTED[@]}"; do
                    if [ -n "$detected" ]; then
                        for tool in $detected; do
                            install_skill_to_tool "$skill" "$tool" || true
                        done
                    else
                        # Install to all tools if none detected
                        for tool in "${!TOOL_PATHS[@]}"; do
                            install_skill_to_tool "$skill" "$tool" || true
                        done
                    fi
                done

                tui_box_end
                echo -e "  ${DIM}Press any key to continue${NC}"
                read -rsn1
                ;;
            1) # View Installed
                tui_show_installed
                ;;
            2) # Remove Skills
                tui_remove_skill
                ;;
            3) # Update
                tui_clear
                tui_box "Updating llm-skills"
                cmd_update 2>/dev/null && log_ok "Updated!" || log_warn "Already up to date"
                tui_box_end
                echo -e "  ${DIM}Press any key to continue${NC}"
                read -rsn1
                ;;
            255|4) # Exit
                tui_clear
                echo -e "${GREEN}Bye!${NC}"
                tui_show_cursor
                exit 0
                ;;
        esac
    done
}

cmd_update() {
    log_info "Checking for updates..."
    local tmp
    tmp=$(mktemp)
    if fetch_file "$SCRIPT_URL" "$tmp"; then
        if ! diff -q "$tmp" "$COMMAND_PATH" >/dev/null 2>&1; then
            cp "$tmp" "$COMMAND_PATH"
            chmod +x "$COMMAND_PATH"
            rm -f "$tmp"
            log_ok "Updated to latest version"
            return 0
        else
            rm -f "$tmp"
            log_info "Already up to date"
            return 1
        fi
    fi
    rm -f "$tmp"
    log_error "Failed to check for updates"
    return 1
}

# ============================================================================
# Main
# ============================================================================

main() {
    # If no arguments — either curl | bash install or interactive TUI
    if [ $# -eq 0 ]; then
        # Check if stdin is a terminal (interactive mode)
        if [ -t 0 ]; then
            # Interactive — show TUI
            auto_update "$@" || true
            fetch_skills
            tui_main
        else
            # Piped from curl — install only
            self_install
        fi
        return
    fi

    # CLI mode — auto-update on every run
    auto_update "$@" || true

    # Fetch latest skills
    fetch_skills

    local cmd="$1"
    shift

    case "$cmd" in
        install)  cmd_install "$@" ;;
        list)     cmd_list ;;
        remove)   cmd_remove "$@" ;;
        update)   cmd_update ;;
        help|-h|--help) usage ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            return 1
            ;;
    esac
}

main "$@"
