-- Rendered by ~/.config/caelestia/hooks/theme-post.py. Read by
-- ~/.config/nvim/colors/caelestia.lua, which watches this file and re-applies
-- itself in every running nvim when the wallpaper changes.
return {
  mode = "{{ mode }}",

  bg = "#{{ surface.hex }}",
  bg_low = "#{{ surfaceContainerLow.hex }}",
  bg_mid = "#{{ surfaceContainer.hex }}",
  bg_high = "#{{ surfaceContainerHigh.hex }}",
  bg_highest = "#{{ surfaceContainerHighest.hex }}",
  fg = "#{{ onSurface.hex }}",
  fg_dim = "#{{ onSurfaceVariant.hex }}",
  outline = "#{{ outline.hex }}",
  outline_dim = "#{{ outlineVariant.hex }}",

  primary = "#{{ primary.hex }}",
  on_primary = "#{{ onPrimary.hex }}",
  primary_container = "#{{ primaryContainer.hex }}",
  on_primary_container = "#{{ onPrimaryContainer.hex }}",
  secondary = "#{{ secondary.hex }}",
  secondary_container = "#{{ secondaryContainer.hex }}",
  on_secondary_container = "#{{ onSecondaryContainer.hex }}",
  tertiary = "#{{ tertiary.hex }}",
  tertiary_container = "#{{ tertiaryContainer.hex }}",
  on_tertiary_container = "#{{ onTertiaryContainer.hex }}",
  error = "#{{ error.hex }}",
  error_container = "#{{ errorContainer.hex }}",

  red = "#{{ ansiRed.hex }}",
  orange = "#{{ ansiOrange.hex }}",
  yellow = "#{{ ansiYellow.hex }}",
  green = "#{{ ansiGreen.hex }}",
  cyan = "#{{ ansiCyan.hex }}",
  blue = "#{{ ansiBlue.hex }}",
  magenta = "#{{ ansiMagenta.hex }}",

  terminal = {
    "#{{ ansi0.hex }}", "#{{ ansi1.hex }}", "#{{ ansi2.hex }}", "#{{ ansi3.hex }}",
    "#{{ ansi4.hex }}", "#{{ ansi5.hex }}", "#{{ ansi6.hex }}", "#{{ ansi7.hex }}",
    "#{{ ansi8.hex }}", "#{{ ansi9.hex }}", "#{{ ansi10.hex }}", "#{{ ansi11.hex }}",
    "#{{ ansi12.hex }}", "#{{ ansi13.hex }}", "#{{ ansi14.hex }}", "#{{ ansi15.hex }}",
  },
}
