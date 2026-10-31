# Plasmarchy tmux helper functions, based on Omarchy Quattro.
# Sourced from ~/.bashrc by config/install-tmux.sh.
#
#   tdl  <ai> [<second_ai>]   editor + AI + terminal layout
#   tds                       editor + diff + terminal + opencode layout
#   tdlm <ai> [<second_ai>]   one tdl window per subdirectory
#   tsl  <count> <command>    the same command in N tiled panes
#
# These functions run inside tmux.  They are shell functions, not tmux
# keybindings; tmux itself gets its layout shortcuts from tmux.conf.

# Create a tmux dev layout with editor, AI, and terminal.
tdl() {
  [[ -z ${1:-} ]] && { echo "Usage: tdl <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z ${TMUX:-} ]] && { echo "You must start tmux to use tdl."; return 1; }

  local current_dir="${PWD}"
  local editor_pane ai_pane ai2_pane
  local ai="$1"
  local ai2="${2:-}"
  local editor="${EDITOR:-nvim}"

  # TMUX_PANE is stable even when the active window changes.
  editor_pane="$TMUX_PANE"

  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  # Top 85% editor, bottom 15% terminal.
  tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"

  # AI pane on the right, 30% of the editor width.
  ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

  if [[ -n $ai2 ]]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$ai2" C-m
  fi

  tmux send-keys -t "$ai_pane" "$ai" C-m
  tmux send-keys -t "$editor_pane" "$editor ." C-m

  # Omarchy 4.0 selected an undefined $opencode_pane here; focus the editor.
  tmux select-pane -t "$editor_pane"
}

# Create a tmux dev square layout: editor, diff watch, terminal, opencode.
# Requires hunk (diff --watch) and opencode unless you change the commands.
tds() {
  [[ -n ${1:-} ]] && { echo "Usage: tds"; return 1; }
  [[ -z ${TMUX:-} ]] && { echo "You must start tmux to use tds."; return 1; }

  local current_dir="${PWD}"
  local editor_pane diff_pane terminal_pane opencode_pane
  local editor="${EDITOR:-nvim}"

  editor_pane="$TMUX_PANE"

  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  terminal_pane=$(tmux split-window -v -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  diff_pane=$(tmux split-window -h -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  opencode_pane=$(tmux split-window -h -p 50 -t "$terminal_pane" -c "$current_dir" -P -F '#{pane_id}')

  tmux send-keys -t "$editor_pane" -l "$editor ."
  tmux send-keys -t "$editor_pane" C-m
  tmux send-keys -t "$diff_pane" -l "hunk diff --watch"
  tmux send-keys -t "$diff_pane" C-m
  tmux send-keys -t "$opencode_pane" -l "opencode"
  tmux send-keys -t "$opencode_pane" C-m

  tmux select-pane -t "$editor_pane"
}

# Create one tdl window per subdirectory of the current directory.
tdlm() {
  [[ -z ${1:-} ]] && { echo "Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z ${TMUX:-} ]] && { echo "You must start tmux to use tdlm."; return 1; }

  local ai="$1"
  local ai2="${2:-}"
  local base_dir="$PWD"
  local first=true
  local dir dirpath pane_id

  # tmux session names cannot contain dots or colons.
  tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"

  for dir in "$base_dir"/*/; do
    [[ -d $dir ]] || continue
    dirpath="${dir%/}"

    if $first; then
      tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
      first=false
    else
      pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
      tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
    fi
  done
}

# Create a multi-pane swarm layout with the same command in every pane.
tsl() {
  [[ -z ${1:-} || -z ${2:-} ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
  [[ -z ${TMUX:-} ]] && { echo "You must start tmux to use tsl."; return 1; }

  local count="$1"
  local cmd="$2"
  local current_dir="${PWD}"
  local -a panes
  local new_pane split_target pane

  tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"

  panes+=("$TMUX_PANE")

  while (( ${#panes[@]} < count )); do
    split_target="${panes[-1]}"
    new_pane=$(tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
    panes+=("$new_pane")
    tmux select-layout -t "${panes[0]}" tiled
  done

  for pane in "${panes[@]}"; do
    tmux send-keys -t "$pane" "$cmd" C-m
  done

  tmux select-pane -t "${panes[0]}"
}
