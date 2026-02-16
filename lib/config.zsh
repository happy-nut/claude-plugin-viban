# lib/config.zsh - Constants, colors, statuses, priorities
# Colors - Sunset Orange Theme
typeset -A C
C=(
    fg        "#FFE5D9"
    fg_dim    "#B89685"
    backlog   "#8B7B6B"
    progress  "#FF6B35"
    review    "#C44536"
    card_bg   "#2D2416"
    card_bd   "#5A4A3A"
    selected  "#FF8C42"
    accent    "#F7931E"
)

# 3 statuses only
typeset -A STATUS_LABEL STATUS_COLOR
STATUS_LABEL=(backlog "To-Do" in_progress "In Progress" review "Human Review")
STATUS_COLOR=(backlog "${C[backlog]}" in_progress "${C[progress]}" review "${C[review]}")

# Priority levels (P0=Critical, P3=Good to have)
typeset -A PRIORITY_LABEL PRIORITY_COLOR
PRIORITY_LABEL=(P0 "CRITICAL" P1 "HIGH" P2 "MEDIUM" P3 "LOW")
PRIORITY_COLOR=(P0 "\033[38;2;255;69;58m" P1 "\033[38;2;255;159;10m" P2 "\033[38;2;255;214;10m" P3 "\033[38;2;142;142;147m")

# Issue types (displayed as tags alongside priority)
typeset -A TYPE_LABEL TYPE_COLOR
TYPE_LABEL=(bug "BUG" feat "FEAT" chore "CHORE" refactor "REFAC")
TYPE_COLOR=(bug "\033[38;2;255;69;58m" feat "\033[38;2;50;215;75m" chore "\033[38;2;142;142;147m" refactor "\033[38;2;90;200;250m")

VIBAN_STATUSES=(backlog in_progress review)

# Pre-generate horizontal borders (cache) - optimized with printf repeat
typeset -A BORDER_CACHE
gen_border() {
    local w=$1
    [[ -n "${BORDER_CACHE[$w]}" ]] && { echo "${BORDER_CACHE[$w]}"; return; }
    # Use printf with dynamic width - single call instead of loop
    local b=$(printf '─%.0s' {1..$w})
    BORDER_CACHE[$w]="$b"
    echo "$b"
}

# Cached terminal dimensions (with sensible defaults)
CACHED_TERM_W=100
CACHED_TERM_H=30
CACHED_COL_W=32
CACHED_MAX_H=22
CACHED_MAX_TASKS=7

# Spinner for in_progress cards (Braille dots - consistent 1-char width)
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_IDX=0

update_term_cache() {
    if [[ -n "$COLUMNS" ]]; then
        CACHED_TERM_W=$COLUMNS
    elif command -v stty &>/dev/null; then
        CACHED_TERM_W=$(stty size 2>/dev/null | cut -d' ' -f2)
    else
        CACHED_TERM_W=$(tput cols 2>/dev/null || echo 100)
    fi
    if [[ -n "$LINES" ]]; then
        CACHED_TERM_H=$LINES
    elif command -v stty &>/dev/null; then
        CACHED_TERM_H=$(stty size 2>/dev/null | cut -d' ' -f1)
    else
        CACHED_TERM_H=$(tput lines 2>/dev/null || echo 30)
    fi
    CACHED_COL_W=$(( (CACHED_TERM_W - 2) / 3 ))
    local _header_extra=0
    $VIBAN_IS_GIT_REPO || _header_extra=1
    CACHED_MAX_H=$((CACHED_TERM_H - 8 - _header_extra))
    CACHED_MAX_TASKS=$((CACHED_MAX_H / 5))
    (( CACHED_MAX_TASKS < 2 )) && CACHED_MAX_TASKS=2
    (( CACHED_MAX_TASKS > 8 )) && CACHED_MAX_TASKS=8
}
# ANSI color codes - Orange Theme
A_RESET="\033[0m"
A_BOLD="\033[1m"
A_DIM="\033[2m"
A_FG="\033[38;2;255;229;217m"        # Warm cream text
A_GRAY="\033[38;2;139;123;107m"      # Warm gray for backlog
A_ORANGE="\033[38;2;255;107;53m"     # Vibrant orange for in_progress
A_DEEP_ORANGE="\033[38;2;196;69;54m" # Deep orange for review
A_ACCENT="\033[38;2;247;147;30m"     # Golden accent
A_SELECTED="\033[38;2;255;140;66m"   # Bright selection
