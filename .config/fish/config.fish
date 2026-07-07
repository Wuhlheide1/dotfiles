# Fish config — autosuggestions + syntax highlighting are built in, so this
# stays small: prompt via starship, no greeting, aliases + PATH ported from .bashrc.

set -g fish_greeting ""

# The Hyprland session env has no ~/.local/bin (only .bashrc exported it, and
# nothing sources .bashrc on the fish->kitty path). fish_add_path is idempotent.
fish_add_path -g ~/.local/bin ~/.npm-global/bin

if status is-interactive
    starship init fish | source
end

# aliases (kept in sync with .bashrc for the rare bash session)
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
