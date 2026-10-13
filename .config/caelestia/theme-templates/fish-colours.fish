# Rendered by ~/.config/caelestia/hooks/theme-post.py, then sourced by it
# with `fish -c`. Universal variables reach every running fish at its next
# prompt, so the command line re-themes live with the wallpaper.
set -U fish_color_normal {{ onSurface.hex }}
set -U fish_color_command {{ primary.hex }}
set -U fish_color_keyword {{ tertiary.hex }}
set -U fish_color_param {{ onSurface.hex }}
set -U fish_color_option {{ secondary.hex }}
set -U fish_color_quote {{ ansiGreen.hex }}
set -U fish_color_redirection {{ ansiCyan.hex }}
set -U fish_color_operator {{ ansiCyan.hex }}
set -U fish_color_escape {{ ansiMagenta.hex }}
set -U fish_color_end {{ tertiary.hex }}
set -U fish_color_error {{ ansiRed.hex }}
set -U fish_color_comment {{ outline.hex }} --italics
set -U fish_color_autosuggestion {{ outline.hex }}
set -U fish_color_valid_path --underline
set -U fish_color_selection --background={{ primaryContainer.hex }} {{ onPrimaryContainer.hex }}
set -U fish_color_search_match --background={{ surfaceContainerHighest.hex }}
set -U fish_color_history_current --bold
set -U fish_color_cancel {{ outline.hex }} --reverse
set -U fish_color_cwd {{ primary.hex }}
set -U fish_color_cwd_root {{ ansiRed.hex }}
set -U fish_color_user {{ ansiGreen.hex }}
set -U fish_color_host {{ onSurface.hex }}
set -U fish_color_host_remote {{ ansiYellow.hex }}
set -U fish_color_status {{ ansiRed.hex }}

set -U fish_pager_color_progress {{ outline.hex }}
set -U fish_pager_color_prefix {{ primary.hex }} --bold
set -U fish_pager_color_completion {{ onSurface.hex }}
set -U fish_pager_color_description {{ outline.hex }}
set -U fish_pager_color_selected_background --background={{ surfaceContainerHigh.hex }}
set -U fish_pager_color_selected_prefix {{ primary.hex }} --bold

# fzf (Ctrl+R history, Ctrl+T files, Alt+C directories) in the same palette.
set -Ux FZF_DEFAULT_OPTS "--height=40% --layout=reverse --border=rounded --info=inline-right --pointer=▌ --marker=▌ --color=fg:-1,bg:-1,hl:#{{ primary.hex }},fg+:#{{ onSurface.hex }},bg+:#{{ surfaceContainerHigh.hex }},hl+:#{{ primary.hex }},info:#{{ outline.hex }},prompt:#{{ primary.hex }},pointer:#{{ primary.hex }},marker:#{{ ansiGreen.hex }},spinner:#{{ tertiary.hex }},header:#{{ tertiary.hex }},border:#{{ outlineVariant.hex }},gutter:-1,query:#{{ onSurface.hex }}"
