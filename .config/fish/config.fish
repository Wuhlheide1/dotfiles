# Fish config — autosuggestions + syntax highlighting are built in, so this
# stays small: prompt via starship, no greeting, a few modern-tool shortcuts.
# Colours (syntax, pager, fzf) are universal variables set by the Caelestia
# theme engine on every wallpaper change — see
# ~/.config/caelestia/theme-templates/fish-colours.fish, don't set them here.

set -g fish_greeting ""

# The Hyprland session env has no ~/.local/bin (only .bashrc exported it, and
# nothing sources .bashrc on the fish->kitty path). fish_add_path is idempotent.
fish_add_path -g ~/.local/bin ~/.npm-global/bin

# bat and man pages use the terminal's own 16 colours, i.e. the scheme.
set -gx BAT_THEME ansi
set -gx MANPAGER "sh -c 'col -bx | bat --language=man --plain'"
set -gx MANROFFOPT -c

if status is-interactive
    starship init fish | source
    # Past prompts collapse to a bare ❯, so scrollback is just commands + output.
    function starship_transient_prompt_func
        starship module character
    end
    enable_transience

    # z <part of a path> jumps to the best match from your history; zi picks
    # interactively.
    zoxide init fish | source
    # Ctrl+R history, Ctrl+T insert a file path, Alt+C cd into a directory.
    fzf --fish | source

    # ls with icons and git-aware listing (eza). `command ls` is the real one.
    alias ls 'eza --group-directories-first --icons=auto'
    alias ll 'eza --group-directories-first --icons=auto -l --git --time-style=relative'
    alias la 'eza --group-directories-first --icons=auto -la --git --time-style=relative'
    alias lt 'eza --group-directories-first --icons=auto --tree --level=2'

    # Abbreviations expand in place, so the history keeps the full command.
    abbr -a g git
    abbr -a gs 'git status -sb'
    abbr -a gd 'git diff'
    abbr -a gl 'git log --oneline --graph -20'
    abbr -a v nvim
    abbr -a ff fastfetch
    # ... -> cd ../.. (any number of dots)
    function multicd
        echo cd (string repeat -n (math (string length -- $argv[1]) - 1) ../)
    end
    abbr -a dotdot --regex '^\.\.+$' --function multicd
end

alias grep='grep --color=auto'
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
