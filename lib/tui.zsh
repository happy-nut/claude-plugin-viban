# lib/tui.zsh - Coprocess, TUI rendering, and interaction
# Python coprocess for TUI rendering (eliminates per-frame spawn overhead)
# Uses explicit file descriptors (fd 7/8) to avoid interfering with read -sk1
_COPROC_PID=""
_COPROC_RESULT=""

_start_coproc() {
    local _in_fifo _out_fifo
    _in_fifo=$(mktemp -u /tmp/viban_cp_in.XXXXXX)
    _out_fifo=$(mktemp -u /tmp/viban_cp_out.XXXXXX)
    mkfifo "$_in_fifo" "$_out_fifo"
    python3 "$VIBAN_SCRIPT_DIR/scripts/tui_coprocess.py" < "$_in_fifo" > "$_out_fifo" &
    _COPROC_PID=$!
    exec 7>"$_in_fifo" 8<"$_out_fifo"
    rm -f "$_in_fifo" "$_out_fifo"
}

_stop_coproc() {
    if [[ -n "$_COPROC_PID" ]] && kill -0 "$_COPROC_PID" 2>/dev/null; then
        echo "QUIT" >&7 2>/dev/null
        exec 7>&- 2>/dev/null
        wait "$_COPROC_PID" 2>/dev/null
    else
        exec 7>&- 2>/dev/null
    fi
    exec 8<&- 2>/dev/null
    _COPROC_PID=""
}

_coproc_batch_trunc() {
    echo "BATCH_TRUNC" >&7
    echo "$1" >&7
    echo "END" >&7
    _COPROC_RESULT=""
    local line
    while read -r line <&8; do
        [[ "$line" == "END" ]] && break
        [[ -n "$_COPROC_RESULT" ]] && _COPROC_RESULT+=$'\n'
        _COPROC_RESULT+="$line"
    done
}

_coproc_batch_width() {
    echo "BATCH_WIDTH" >&7
    echo "$1" >&7
    echo "END" >&7
    _COPROC_RESULT=""
    local line
    while read -r line <&8; do
        [[ "$line" == "END" ]] && break
        [[ -n "$_COPROC_RESULT" ]] && _COPROC_RESULT+=$'\n'
        _COPROC_RESULT+="$line"
    done
}

print_center() {
    local text=$1 color=${2:-$A_FG}
    local w=$CACHED_TERM_W
    (( w == 0 )) && w=$(get_term_width)
    local len=${#text}
    local pad=$(( (w - len) / 2 ))
    printf "%${pad}s${color}%s${A_RESET}\033[K\n" "" "$text"
}

# Draw header with pure ANSI
draw_header() {
    printf '\033[K\n'
    print_center "VIBAN" "${A_BOLD}${A_ACCENT}"
    local _ver repo_name subtitle="Vibe Kanban"
    _ver=$(grep '"version"' "$VIBAN_SCRIPT_DIR/package.json" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
    repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
    [[ -n "$repo_name" ]] && subtitle="Vibe Kanban · $repo_name"
    if [[ -n "$_ver" ]]; then
        subtitle="$subtitle · v$_ver"
        # Check for update availability from cache
        if [[ -f "$_VIBAN_UPDATE_CACHE" ]]; then
            local cached_latest
            cached_latest=$(sed -n '2p' "$_VIBAN_UPDATE_CACHE" 2>/dev/null)
            if [[ -n "$cached_latest" && "$cached_latest" != "$_ver" ]]; then
                local -a cv lv
                cv=("${(@s/./)_ver}")
                lv=("${(@s/./)cached_latest}")
                local _is_newer=false _c _l
                for i in 1 2 3; do
                    _c=${cv[$i]:-0}; _l=${lv[$i]:-0}
                    _c=${_c%%[^0-9]*}; _l=${_l%%[^0-9]*}
                    [[ -z "$_c" ]] && _c=0; [[ -z "$_l" ]] && _l=0
                    if (( _l > _c )); then
                        _is_newer=true
                        break
                    elif (( _l < _c )); then
                        break
                    fi
                done
                $_is_newer && subtitle="$subtitle → v$cached_latest"
            fi
        fi
    fi
    print_center "$subtitle" "${A_DIM}"
    if ! $VIBAN_IS_GIT_REPO; then
        print_center "⚠ Not a git repo · assign/PR unavailable" "${A_DIM}"
    fi
    printf '\033[K\n'
}

# Get status color code
get_status_color() {
    case "$1" in
        backlog) echo "$A_GRAY";;
        in_progress) echo "$A_ORANGE";;
        review) echo "$A_DEEP_ORANGE";;
    esac
}

# Build column lines into array (optimized - single jq call, cached borders)
# $1: status, $2: col_selected, $3: card_selected (-1 if none), $4: max_h, $5: col_w, $6: json_data
build_column_lines() {
    local st="$1"
    local is_col_selected="${2:-0}"
    local card_sel="${3:--1}"
    local max_h="${4:-20}"
    local col_w="${5:-30}"
    local json_data="$6"
    local label="${STATUS_LABEL[$st]:-Unknown}"
    local color=$(get_status_color "$st")

    # Single jq call to get all issues for this status (include description, priority, type)
    # Replace newlines/tabs in description to prevent parsing issues
    # Sort: review by updated_at desc, others by effective order (ordered cards first, then priority)
    local sort_expr='sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end)'
    [[ "$st" == "review" ]] && sort_expr='sort_by(.updated_at) | reverse'
    local done_ids_tui=$(printf '%s' "$json_data" | jq '[.issues[]|select(.status=="done")|.id]')
    local issues_data=$(printf '%s' "$json_data" | jq -r --arg s "$st" --argjson done "$done_ids_tui" "
        .issues | map(select(.status==\$s)) | $sort_expr |
        .[] | \"\\(.id)\t\\(.title)\t\\((.description // \"\") | gsub(\"[\\n\\t\\r]\"; \" \"))\t\\(.priority // \"P3\")\t\\(.type // \"\")\t\\(.external_id // \"\")\t\\(if ((.blocked_by // []) | length > 0 and any(. as \$b | \$done | index(\$b) == null)) then \"blocked\" else \"\" end)\"")
    local count=0
    # Count total issues (not capped) for overflow indicator
    if [[ -n "$issues_data" ]]; then
        local -a _count_arr=("${(f)issues_data}")
        count=${#_count_arr[@]}
    fi

    # Header centered in column
    local hdr_text="● $label"
    local hdr_w=$((${#label} + 2))
    local left_pad=$(( (col_w - hdr_w) / 2 ))
    local right_pad=$((col_w - hdr_w - left_pad))
    if (( is_col_selected )); then
        printf "%${left_pad}s${A_BOLD}${A_SELECTED}%s${A_RESET}%${right_pad}s\n" "" "$hdr_text" ""
        # Underline for selected column - use printf repeat pattern
        local underline=$(printf '─%.0s' {1..$hdr_w})
        printf "%${left_pad}s${A_SELECTED}%s${A_RESET}%${right_pad}s\n" "" "$underline" ""
    else
        printf "%${left_pad}s${color}%s${A_RESET}%${right_pad}s\n" "" "$hdr_text" ""
        # Empty line for non-selected columns
        printf "%${col_w}s\n" ""
    fi

    local lines_used=2
    local card_inner=$((col_w - 4))
    local border=$(gen_border $card_inner)

    # --- Pass 1: Collect card data into arrays ---
    local -a _ids _titles _descs _priorities _types _ext_ids _title_max_ws _title_pfxs
    local _has_nonascii=0
    local _desc_max_w=$((card_inner - 4))
    local _spinner_w=0
    [[ "$st" == "in_progress" ]] && _spinner_w=2
    local _cc _bc _pfx _did

    local -a _blocked_flags=()
    while IFS=$'\t' read -r _id _title _desc _priority _type _ext_id _blocked; do
        [[ -z "$_id" ]] && continue
        (( ${#_ids} >= CACHED_MAX_TASKS )) && break
        [[ -z "$_priority" || "$_priority" == "null" ]] && _priority="P3"
        [[ -z "$_type" || "$_type" == "null" ]] && _type=""
        [[ "$_desc" == "null" ]] && _desc=""

        _ids+=("$_id"); _titles+=("$_title"); _descs+=("$_desc")
        _priorities+=("$_priority"); _types+=("$_type"); _ext_ids+=("$_ext_id")
        _blocked_flags+=("$_blocked")

        # Per-card title width limit (use display ID length)
        _did=$(display_id "$_id" "$_ext_id")
        _title_max_ws+=($((card_inner - 4 - ${#_did} - _spinner_w)))
        # Prefix for width calc (X as spinner placeholder - same width 1 as braille chars)
        _pfx="  "
        (( _spinner_w )) && _pfx="  X "
        _title_pfxs+=("${_pfx}${_did} ")

        # Check for non-ASCII
        if (( ! _has_nonascii )); then
            _cc=${#_title}
            LC_ALL=C _bc=${#_title}; unset LC_ALL
            (( _bc != _cc )) && _has_nonascii=1
            if (( ! _has_nonascii && ${#_desc} > 0 )); then
                _cc=${#_desc}; LC_ALL=C _bc=${#_desc}; unset LC_ALL
                (( _bc != _cc )) && _has_nonascii=1
            fi
        fi
    done <<< "$issues_data"

    local _n=${#_ids}

    # --- Pass 2: Batch compute truncation + widths (single Python call) ---
    local -a _short_titles _title_cws _short_descs _desc_cws

    if (( _n > 0 )); then
        if (( _has_nonascii )); then
            # Build batch input: 2 lines per card (title, desc)
            # Format: max_w<TAB>prefix<TAB>string
            local _batch_input=""
            for (( _i=1; _i<=_n; _i++ )); do
                _batch_input+="${_title_max_ws[$_i]}"$'\t'"${_title_pfxs[$_i]}"$'\t'"${_titles[$_i]}"$'\n'
                _batch_input+="${_desc_max_w}"$'\t'"  "$'\t'"${_descs[$_i]}"$'\n'
            done

            # Single Python call: truncate each string and compute content width
            local _batch_output
            _coproc_batch_trunc "$_batch_input"
            _batch_output="$_COPROC_RESULT"

            local _li=0
            while IFS=$'\t' read -r _tr _cw; do
                ((_li++))
                if (( _li % 2 == 1 )); then
                    _short_titles+=("$_tr"); _title_cws+=($_cw)
                else
                    _short_descs+=("$_tr"); _desc_cws+=($_cw)
                fi
            done <<< "$_batch_output"
        else
            # All-ASCII fast path - no Python needed
            local _t _mw _fc _d
            for (( _i=1; _i<=_n; _i++ )); do
                _t="${_titles[$_i]}" _mw=${_title_max_ws[$_i]}
                (( ${#_t} > _mw )) && _t="${_t:0:$_mw}"
                _short_titles+=("$_t")
                _fc="${_title_pfxs[$_i]}${_t}"
                _title_cws+=(${#_fc})

                _d="${_descs[$_i]}"
                (( ${#_d} > _desc_max_w )) && _d="${_d:0:$_desc_max_w}"
                _short_descs+=("$_d")
                _desc_cws+=($((2 + ${#_d})))
            done
        fi
    fi

    # --- Pass 3: Render cards ---
    local shown=0
    local id priority issue_type ext_id did
    local spinner_prefix title_content title_pad
    local desc_content desc_pad
    local priority_tag priority_color type_tag type_color tags_w tags_pad
    local border_color text_color desc_color
    for (( _i=1; _i<=_n; _i++ )); do
        id="${_ids[$_i]}"
        priority="${_priorities[$_i]}"
        issue_type="${_types[$_i]}"
        ext_id="${_ext_ids[$_i]}"
        did=$(display_id "$id" "$ext_id")

        # Title line
        spinner_prefix=""
        [[ "$st" == "in_progress" ]] && spinner_prefix="${SPINNER_FRAMES[$((SPINNER_IDX % ${#SPINNER_FRAMES[@]} + 1))]} "
        title_content="  ${spinner_prefix}${did} ${_short_titles[$_i]}"
        title_pad=$((card_inner - ${_title_cws[$_i]}))
        (( title_pad < 0 )) && title_pad=0

        # Description line
        desc_content="  ${_short_descs[$_i]}"
        desc_pad=$((card_inner - ${_desc_cws[$_i]}))
        (( desc_pad < 0 )) && desc_pad=0

        # Priority, type, and blocked tags
        priority_tag="[$priority]"
        priority_color="${PRIORITY_COLOR[$priority]:-$A_DIM}"
        type_tag="" type_color="" tags_w=0
        local blocked_tag="" blocked_color=""
        if [[ -n "$issue_type" ]]; then
            type_tag="[${TYPE_LABEL[$issue_type]:-$issue_type}]"
            type_color="${TYPE_COLOR[$issue_type]:-$A_DIM}"
            tags_w=$((${#priority_tag} + 1 + ${#type_tag}))
        else
            tags_w=${#priority_tag}
        fi
        if [[ "${_blocked_flags[$_i]}" == "blocked" ]]; then
            blocked_tag=" BLOCKED"
            blocked_color="\033[38;2;255;69;58m"
            tags_w=$((tags_w + 8))
        fi
        tags_pad=$((card_inner - tags_w - 2))

        border_color="$A_DIM"
        text_color="$A_FG"
        desc_color="$A_DIM"
        if (( is_col_selected && shown == card_sel )); then
            border_color="${A_SELECTED}"
            text_color="${A_BOLD}${A_ACCENT}"
            desc_color="${A_ACCENT}"
        fi

        # 5-line card with priority+type tags on 4th line
        printf " ${border_color}╭%s╮${A_RESET} \n" "$border"
        printf " ${border_color}│${A_RESET}${text_color}%s${A_RESET}%${title_pad}s${border_color}│${A_RESET} \n" "$title_content" ""
        printf " ${border_color}│${A_RESET}${desc_color}%s${A_RESET}%${desc_pad}s${border_color}│${A_RESET} \n" "$desc_content" ""
        if [[ -n "$type_tag" ]]; then
            printf " ${border_color}│${A_RESET}  ${priority_color}%s${A_RESET} ${type_color}%s${A_RESET}${blocked_color}%s${A_RESET}%${tags_pad}s${border_color}│${A_RESET} \n" "$priority_tag" "$type_tag" "$blocked_tag" ""
        else
            printf " ${border_color}│${A_RESET}  ${priority_color}%s${A_RESET}${blocked_color}%s${A_RESET}%${tags_pad}s${border_color}│${A_RESET} \n" "$priority_tag" "$blocked_tag" ""
        fi
        printf " ${border_color}╰%s╯${A_RESET} \n" "$border"

        ((shown++))
        lines_used=$((lines_used + 5))
    done

    # Overflow indicator
    if (( count > _n )); then
        local more_text="  +$((count - _n)) more..."
        printf "${A_DIM}%s${A_RESET}%$((col_w - ${#more_text}))s\n" "$more_text" ""
        ((lines_used++))
    fi

    if (( count == 0 )); then
        local no_text="  No tasks"
        local no_w=${#no_text}
        printf "${A_DIM}%s${A_RESET}%$((col_w - no_w))s\n" "$no_text" ""
        ((lines_used++))
    fi

    while (( lines_used < max_h )); do
        printf "%${col_w}s\n" ""
        ((lines_used++))
    done
}

# ESC character for ANSI stripping (defined once at script level)
_ESC=$'\e'

# Pad line to exact width with spaces
# Optimized: use zsh parameter expansion to strip ANSI codes
pad_to_width() {
    local line="$1"
    local width="$2"
    local precomputed_w="${3:-}"
    # Strip ANSI codes: ESC [ followed by numbers/semicolons, ending with letter
    local plain="${line//${_ESC}\[[0-9;]#[a-zA-Z]/}"
    local display_w
    if [[ -n "$precomputed_w" ]]; then
        display_w=$precomputed_w
    else
        local char_count=${#plain} byte_count
        LC_ALL=C byte_count=${#plain}
        unset LC_ALL
        if [[ $byte_count -eq $char_count ]]; then
            display_w=$char_count
        else
            display_w=$(( char_count + (byte_count - char_count) / 2 ))
        fi
    fi
    local pad=$((width - display_w))
    printf '%s' "$line"
    (( pad > 0 )) && printf "%${pad}s" ""
}

# Draw the board (optimized - arrays instead of temp files)
# $1: col_sel, $2: card_sel, $3: json_data
draw_board() {
    local col_sel=${1:-0}
    local card_sel=${2:--1}
    local json_data="$3"
    local col_w=$CACHED_COL_W
    local max_h=$CACHED_MAX_H

    local c1=-1 c2=-1 c3=-1
    case $col_sel in
        0) c1=$card_sel;;
        1) c2=$card_sel;;
        2) c3=$card_sel;;
    esac

    # Build columns to arrays
    local -a col1 col2 col3
    col1=("${(@f)$(build_column_lines "backlog" $((col_sel == 0)) $c1 $max_h $col_w "$json_data")}")
    col2=("${(@f)$(build_column_lines "in_progress" $((col_sel == 1)) $c2 $max_h $col_w "$json_data")}")
    col3=("${(@f)$(build_column_lines "review" $((col_sel == 2)) $c3 $max_h $col_w "$json_data")}")

    # Batch compute display widths for all non-ASCII lines (single Python call)
    # Build input: all lines from all 3 columns, ANSI-stripped
    local -a all_plains
    local -a all_widths
    local _needs_python=0
    local i _plain _cc _bc
    for ((i=1; i<=max_h; i++)); do
        for _col_line in "${col1[$i]}" "${col2[$i]}" "${col3[$i]}"; do
            _plain="${_col_line//${_ESC}\[[0-9;]#[a-zA-Z]/}"
            all_plains+=("$_plain")
            _cc=${#_plain}
            LC_ALL=C _bc=${#_plain}
            unset LC_ALL
            if [[ $_bc -eq $_cc ]]; then
                all_widths+=($_cc)
            else
                all_widths+=(-1)  # marker: needs Python
                _needs_python=1
            fi
        done
    done

    if (( _needs_python )); then
        # Single Python call to compute all non-ASCII widths
        local _input="" _idx
        for ((_idx=1; _idx<=${#all_plains[@]}; _idx++)); do
            if [[ ${all_widths[$_idx]} -eq -1 ]]; then
                _input+="${all_plains[$_idx]}"$'\n'
            fi
        done
        local -a _py_results
        _coproc_batch_width "$_input"
        _py_results=("${(@f)_COPROC_RESULT}")
        # Map Python results back to width array
        local _pi=1
        for ((_idx=1; _idx<=${#all_widths[@]}; _idx++)); do
            if [[ ${all_widths[$_idx]} -eq -1 ]]; then
                all_widths[$_idx]=${_py_results[$_pi]}
                ((_pi++))
            fi
        done
    fi

    # Merge line by line using precomputed widths
    local _wi=1
    for ((i=1; i<=max_h; i++)); do
        pad_to_width "${col1[$i]}" $col_w "${all_widths[$_wi]}"
        ((_wi++))
        printf "${A_DIM}│${A_RESET}"
        pad_to_width "${col2[$i]}" $col_w "${all_widths[$_wi]}"
        ((_wi++))
        printf "${A_DIM}│${A_RESET}"
        pad_to_width "${col3[$i]}" $col_w "${all_widths[$_wi]}"
        ((_wi++))
        printf '\033[K\n'
    done
}

draw_footer() {
    printf '\033[K\n'
    print_center "←→ Column  │  ↑↓ Card  │  Shift+↑↓ Reorder  │  Shift+←→ Move  │  Enter Edit/PR  │  ⌫ Del  │  A Add  │  Q Quit" "${A_DIM}"
}

read_key() {
    local _rk_timeout="${1:-0.5}"
    local key result=""
    # Timeout for spinner animation refresh (default 0.5s)
    read -sk1 -t "$_rk_timeout" key 2>/dev/null || { echo "timeout"; return; }

    if [[ "$key" == $'\e' ]]; then
        read -sk1 -t 0.1 c2 2>/dev/null
        if [[ "$c2" == "[" ]]; then
            read -sk1 -t 0.1 c3 2>/dev/null
            case "$c3" in
                D) result="left";; C) result="right";;
                A) result="up";; B) result="down";;
                "1")
                    # Handle Shift+arrow sequences: ESC[1;2X where X is A/B/C/D
                    read -sk1 -t 0.1 c4 2>/dev/null
                    if [[ "$c4" == ";" ]]; then
                        read -sk1 -t 0.1 c5 2>/dev/null
                        read -sk1 -t 0.1 c6 2>/dev/null
                        if [[ "$c5" == "2" ]]; then
                            case "$c6" in
                                A) result="shift_up";;
                                B) result="shift_down";;
                                C) result="shift_right";;
                                D) result="shift_left";;
                            esac
                        fi
                    fi
                    ;;
            esac
        elif [[ "$c2" == "]" ]]; then
            # Drain OSC sequence
            while read -sk1 -t 0.01 _ 2>/dev/null; do :; done
        fi
    elif [[ "$key" == "" || "$key" == $'\n' ]]; then
        result="enter"
    elif [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
        result="backspace"
    else
        case "$key" in
            q|Q) result="quit";;
            a|A) result="add";;
        esac
    fi

    echo "$result"
}

# Move card order up or down within a status column (fractional indexing)
# $1: status, $2: current card index, $3: direction (-1 for up, 1 for down)
# When manually moved, the card gets an order value to pin its position
move_card_order() {
    local st="$1"
    local cur_idx="$2"
    local dir="$3"
    local new_idx=$((cur_idx + dir))

    # Get issues in current effective order (ordered cards first, then priority-sorted)
    local issues=$(jq -r --arg s "$st" '
        .issues | map(select(.status==$s)) | sort_by(
            if .order != null then [0, .order]
            else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id]
            end
        )
    ' "$VIBAN_JSON")
    local cnt=$(printf '%s' "$issues" | jq 'length')

    # Bounds check
    (( new_idx < 0 || new_idx >= cnt )) && return 1

    # Get ID of the card to move
    local cur_id=$(printf '%s' "$issues" | jq -r ".[$cur_idx].id")

    # Calculate effective order for a card (use actual order or virtual priority-based order)
    get_eff_order() {
        local idx=$1
        local order=$(printf '%s' "$issues" | jq -r ".[$idx].order // \"null\"")
        if [[ "$order" != "null" ]]; then
            echo "$order"
        else
            local priority=$(printf '%s' "$issues" | jq -r ".[$idx].priority // \"P3\"")
            local id=$(printf '%s' "$issues" | jq -r ".[$idx].id")
            case "$priority" in
                P0) echo $((1000000 + id));;
                P1) echo $((2000000 + id));;
                P2) echo $((3000000 + id));;
                *)  echo $((4000000 + id));;
            esac
        fi
    }

    # Calculate new order using fractional indexing
    # Place card between the target position and its neighbor
    local new_order
    if (( dir < 0 )); then
        # Moving up: place between target and the one above it
        local target_order=$(get_eff_order $new_idx)
        if (( new_idx == 0 )); then
            # Moving to top: use target_order - 1
            new_order=$(echo "$target_order - 1" | bc)
        else
            local above_order=$(get_eff_order $(($new_idx - 1)))
            new_order=$(echo "scale=6; ($above_order + $target_order) / 2" | bc)
        fi
    else
        # Moving down: place between target and the one below it
        local target_order=$(get_eff_order $new_idx)
        if (( new_idx == cnt - 1 )); then
            # Moving to bottom: use target_order + 1
            new_order=$(echo "$target_order + 1" | bc)
        else
            local below_order=$(get_eff_order $(($new_idx + 1)))
            new_order=$(echo "scale=6; ($target_order + $below_order) / 2" | bc)
        fi
    fi

    # Update the card's order (this pins it to the new position)
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson cur_id "$cur_id" --argjson new_order "$new_order" --arg now "$now" '
        (.issues[] | select(.id==$cur_id)) |= . + {order:$new_order,updated_at:$now}
    ' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    return 0
}

# Get issue ID by status and index (uses correct sort order per status)
get_issue_id_by_index() {
    local st=$1 idx=$2
    local sort_expr=$(get_sort_expr "$st")
    jq -r --arg s "$st" --argjson i "$idx" ".issues | map(select(.status==\$s)) | $sort_expr | .[\$i].id // empty" "$VIBAN_JSON"
}

# Delete issue by ID (with worktree cleanup)
delete_issue() {
    local id=$1
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    local wt_dir="$VIBAN_DATA_DIR/worktrees/$id"

    local branch="issue-$id"
    local _ext_id=$(get_ext_id "$id")
    if [[ -n "$_ext_id" && "$_ext_id" != "null" ]]; then
        local _issue_num="${_ext_id##*:}"
        if git -C "$repo_root" rev-parse --verify "issue-${_issue_num}" &>/dev/null 2>&1; then
            branch="issue-${_issue_num}"
        fi
    fi

    if [[ -d "$wt_dir" ]]; then
        git -C "$repo_root" worktree remove "$wt_dir" --force 2>/dev/null
        git -C "$repo_root" branch -D "$branch" 2>/dev/null
    fi
    jq --argjson id "$id" 'del(.issues[]|select((.id|tonumber)==$id))' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && \
    mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
}

level1_columns() {
    IN_TUI=true
    _start_coproc
    local col=0 card=0

    # Auto-sync state (120 iterations × 0.5s timeout = ~60s interval)
    local _sync_counter=0
    local _SYNC_INTERVAL=120
    local _sync_pid=""

    # Hide cursor and disable input echo
    stty -echo 2>/dev/null
    printf '\033[?25l\033[2J\033[H'

    # Initial cache update
    update_term_cache

    while true; do
        # Auto-sync: reap finished background sync
        if [[ -n "$_sync_pid" ]]; then
            if ! kill -0 "$_sync_pid" 2>/dev/null; then
                wait "$_sync_pid" 2>/dev/null
                _sync_pid=""
            fi
        fi

        # Auto-sync: trigger when interval reached and sync configured
        ((_sync_counter++)) || true
        if (( _sync_counter >= _SYNC_INTERVAL )) && [[ -z "$_sync_pid" && -f "$VIBAN_DATA_DIR/sync.json" ]]; then
            _sync_counter=0
            local _sync_provider
            _sync_provider=$(jq -r '.provider // ""' "$VIBAN_DATA_DIR/sync.json" 2>/dev/null)
            if [[ -n "$_sync_provider" && "$_sync_provider" != "null" ]]; then
                VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
                    VIBAN_PROVIDER="$_sync_provider" VIBAN_SCRIPT_DIR="$VIBAN_SCRIPT_DIR" \
                    bash "$VIBAN_SCRIPT_DIR/scripts/sync.sh" --auto &
                _sync_pid=$!
            fi
        fi
        # Cache JSON data once per frame
        local json_data=$(cat "$VIBAN_JSON")

        printf '\033[H\033[0m'
        draw_header
        draw_board $col $card "$json_data"
        draw_footer
        printf '\033[J'

        # Advance spinner
        ((SPINNER_IDX++))

        local st="${VIBAN_STATUSES[$((col + 1))]}"
        # Use cached json_data for count
        local cnt=$(printf '%s' "$json_data" | jq -r --arg s "$st" '[.issues[]|select(.status==$s)]|length')

        local key=$(read_key)
        case "$key" in
            left)
                local start_col=$col
                col=$(( (col - 1 + 3) % 3 ))
                # Skip empty columns (but stop if we return to start)
                while (( col != start_col )); do
                    local next_st="${VIBAN_STATUSES[$((col + 1))]}"
                    local next_cnt=$(printf '%s' "$json_data" | jq -r --arg s "$next_st" '[.issues[]|select(.status==$s)]|length')
                    (( next_cnt > 0 )) && break
                    col=$(( (col - 1 + 3) % 3 ))
                done
                card=0
                ;;
            right)
                local start_col=$col
                col=$(( (col + 1) % 3 ))
                # Skip empty columns (but stop if we return to start)
                while (( col != start_col )); do
                    local next_st="${VIBAN_STATUSES[$((col + 1))]}"
                    local next_cnt=$(printf '%s' "$json_data" | jq -r --arg s "$next_st" '[.issues[]|select(.status==$s)]|length')
                    (( next_cnt > 0 )) && break
                    col=$(( (col + 1) % 3 ))
                done
                card=0
                ;;
            up)
                (( cnt > 0 )) && card=$(( (card - 1 + cnt) % cnt ))
                ;;
            down)
                (( cnt > 0 )) && card=$(( (card + 1) % cnt ))
                ;;
            shift_up)
                if (( cnt > 0 && card > 0 )); then
                    local card_id=$(get_issue_id_at_index "$st" "$card" "$json_data")
                    if move_card_order "$st" $card -1; then
                        local new_json=$(cat "$VIBAN_JSON")
                        card=$(get_card_index_by_id "$st" "$card_id" "$new_json")
                    fi
                fi
                ;;
            shift_down)
                if (( cnt > 0 && card < cnt - 1 )); then
                    local card_id=$(get_issue_id_at_index "$st" "$card" "$json_data")
                    if move_card_order "$st" $card 1; then
                        local new_json=$(cat "$VIBAN_JSON")
                        card=$(get_card_index_by_id "$st" "$card_id" "$new_json")
                    fi
                fi
                ;;
            enter)
                if (( cnt > 0 )); then
                    local id=$(get_issue_id_at_index "$st" "$card" "$json_data")
                    [[ -n "$id" ]] && {
                        if [[ "$st" == "review" ]]; then
                            # Open associated PR in browser
                            local _branch="issue-${id}"
                            local _ext_id=$(get_ext_id "$id")
                            if [[ -n "$_ext_id" && "$_ext_id" != "null" ]]; then
                                local _num="${_ext_id##*:}"
                                gh pr view "$_num" --web 2>/dev/null || \
                                    gh pr list --head "$_branch" --web 2>/dev/null
                            else
                                gh pr list --head "$_branch" --web 2>/dev/null
                            fi
                        else
                            printf '\033[?25h'
                            stty echo 2>/dev/null
                            edit_issue "$id"
                            stty -echo 2>/dev/null
                            printf '\033[?25l\033[2J\033[H'
                        fi
                    }
                fi
                ;;
            shift_left)
                if (( cnt > 0 && col > 0 )); then
                    move_card_status "$st" $card -1 && { col=$((col - 1)); card=0; }
                fi
                ;;
            shift_right)
                if (( cnt > 0 && col < 2 )); then
                    move_card_status "$st" $card 1 && { col=$((col + 1)); card=0; }
                fi
                ;;
            add)
                printf '\033[?25h'
                stty echo 2>/dev/null
                add_issue
                stty -echo 2>/dev/null
                printf '\033[?25l\033[2J\033[H'
                ;;
            backspace)
                if (( cnt > 0 )); then
                    local id=$(get_issue_id_at_index "$st" "$card" "$json_data")
                    [[ -n "$id" ]] && {
                        # Move cursor to footer line and run gum there
                        printf '\033[?25h'
                        stty echo 2>/dev/null
                        # Clear footer line and show confirm
                        printf '\033[%d;1H\033[K' "$CACHED_TERM_H"
                        if gum confirm "Delete $(display_id "$id" "$(get_ext_id "$id")")?" --affirmative "Yes" --negative "No" \
                            --selected.foreground="#000000" --selected.background "${C[accent]}"; then
                            delete_issue "$id"
                            (( card > 0 )) && card=$((card - 1))
                        fi
                        stty -echo 2>/dev/null
                        printf '\033[?25l'
                        # Redraw footer only (cursor back to footer)
                        printf '\033[%d;1H\033[K' "$((CACHED_TERM_H - 1))"
                        draw_footer
                    }
                fi
                ;;
            quit)
                printf '\033[?25h\033[0m'
                stty echo 2>/dev/null
                clear
                exit 0
                ;;
        esac
    done
}

# Edit issue in editor (title + description + priority + type)
edit_issue() {
    local id=$1
    local issue=$(jq --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)' "$VIBAN_JSON")
    [[ -z "$issue" ]] && return 1

    local title=$(printf '%s' "$issue" | jq -r '.title')
    local desc=$(printf '%s' "$issue" | jq -r '.description // ""')
    local ist=$(printf '%s' "$issue" | jq -r '.status')
    local created=$(printf '%s' "$issue" | jq -r '.created_at')
    local priority=$(printf '%s' "$issue" | jq -r '.priority // "P3"')
    local issue_type=$(printf '%s' "$issue" | jq -r '.type // ""')
    local ext_id=$(printf '%s' "$issue" | jq -r '.external_id // ""')
    local parent_id=$(printf '%s' "$issue" | jq -r '.parent_id // ""')
    local blocked_by=$(printf '%s' "$issue" | jq -r '(.blocked_by // []) | if length > 0 then map(tostring) | join(", ") else "" end')
    local comment_count=$(printf '%s' "$issue" | jq -r '(.comments // []) | length')
    local did; did=$(display_id "$id" "$ext_id")

    local tmpfile=$(mktemp)
    local editor="${EDITOR:-${VISUAL:-vim}}"

    cat > "$tmpfile" <<TEMPLATE
# ─────────────────────────────────────────────
# VIBAN Issue $did
# ─────────────────────────────────────────────
# Status: ${STATUS_LABEL[$ist]}
# Created: ${created:0:10}
$([ -n "$blocked_by" ] && echo "# Blocked by: #$blocked_by")
$([ "$comment_count" -gt 0 ] 2>/dev/null && echo "# Comments: $comment_count (use 'viban comment' to add)")
# ─────────────────────────────────────────────

# ▼ Priority (P0=CRITICAL, P1=HIGH, P2=MEDIUM, P3=LOW)
$priority

# ▼ Type (bug, feat, chore, refactor) - leave empty for none
$issue_type

# ▼ Parent ID (number or empty for none)
$parent_id

# ▼ Title (single line)
$title

# ▼ Description (multiple lines allowed)
$desc
TEMPLATE

    $editor "$tmpfile"

    # Parse: priority -> type -> parent_id -> title -> description
    local new_priority="" new_type="" new_parent="" new_title="" new_desc="" parse_stage=0
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        case $parse_stage in
            0)  # Looking for priority
                [[ -z "$line" ]] && continue
                if [[ "$line" =~ ^P[0-3]$ ]]; then
                    new_priority="$line"
                else
                    new_priority="P3"
                fi
                parse_stage=1
                ;;
            1)  # Looking for type
                [[ -z "$line" ]] && continue
                if [[ "$line" =~ ^(bug|feat|chore|refactor)$ ]]; then
                    new_type="$line"
                fi
                parse_stage=2
                ;;
            2)  # Looking for parent_id
                [[ -z "$line" ]] && continue
                if [[ "$line" =~ ^[0-9]+$ ]]; then
                    new_parent="$line"
                fi
                parse_stage=3
                ;;
            3)  # Looking for title
                [[ -z "$line" ]] && continue
                new_title="$line"
                parse_stage=4
                ;;
            4)  # Collecting description
                if [[ -z "$new_desc" && -z "$line" ]]; then
                    continue
                fi
                new_desc+="$line"$'\n'
                ;;
        esac
    done < "$tmpfile"

    # Trim trailing newlines from description
    new_desc="${new_desc%$'\n'}"

    rm -f "$tmpfile"

    [[ -z "$new_title" ]] && return 1
    [[ -z "$new_priority" ]] && new_priority="P3"

    # Update issue
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmpjson=$(mktemp)
    printf '%s' "$new_desc" > "$tmpjson"
    jq --argjson id "$id" --arg title "$new_title" --rawfile desc "$tmpjson" --arg priority "$new_priority" --arg issue_type "$new_type" --arg parent "$new_parent" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {title:$title,description:$desc,priority:$priority,type:(if $issue_type == "" then null else $issue_type end),parent_id:(if $parent == "" then null else ($parent|tonumber) end),updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
    rm -f "$tmpjson"
}

# Move card to adjacent column (change status)
move_card_status() {
    local st="$1"
    local card_idx="$2"
    local dir="$3"  # -1 for left, 1 for right

    local sort_expr=$(get_sort_expr "$st")
    local id=$(jq -r --arg s "$st" --argjson i "$card_idx" \
        ".issues | map(select(.status==\$s)) | $sort_expr | .[\$i].id // empty" "$VIBAN_JSON")
    [[ -z "$id" ]] && return 1

    # Find current status index and calculate new status
    local cur_idx=0
    for i in {1..3}; do
        [[ "${VIBAN_STATUSES[$i]}" == "$st" ]] && { cur_idx=$i; break; }
    done

    local new_idx=$((cur_idx + dir))
    (( new_idx < 1 || new_idx > 3 )) && return 1

    local new_st="${VIBAN_STATUSES[$new_idx]}"
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --argjson id "$id" --arg new_st "$new_st" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {status:$new_st,updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
}

