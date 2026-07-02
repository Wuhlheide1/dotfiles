#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Dotfiles bare-repo management (~/.config/hypr, ~/.config/quickshell)
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
export PATH="$HOME/.local/bin:$PATH"
