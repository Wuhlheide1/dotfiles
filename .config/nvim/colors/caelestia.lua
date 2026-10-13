-- Caelestia: colours come from the wallpaper. The theme engine
-- (~/.config/caelestia/hooks/theme-post.py) renders the palette to
-- ~/.local/state/caelestia/theme/nvim-colours.lua; this file maps it onto
-- highlight groups and watches it, so every open nvim re-themes live.
--
-- Normal has no background on purpose: the terminal's (slightly translucent,
-- blurred) background shows through, so nvim and the shell look like one
-- surface. Floats get a solid container colour so they read as layered.

local path = vim.fn.expand("~/.local/state/caelestia/theme/nvim-colours.lua")
local ok, c = pcall(dofile, path)
if not ok or type(c) ~= "table" then
  vim.notify("caelestia: palette missing (" .. path .. ")", vim.log.levels.WARN)
  return
end

vim.cmd("highlight clear")
vim.g.colors_name = "caelestia"
vim.o.background = c.mode

local hl = function(group, spec) vim.api.nvim_set_hl(0, group, spec) end
local NONE = "NONE"

-- Editor -------------------------------------------------------------------
hl("Normal", { fg = c.fg, bg = NONE })
hl("NormalNC", { link = "Normal" })
hl("NormalFloat", { fg = c.fg, bg = c.bg_mid })
hl("FloatBorder", { fg = c.outline_dim, bg = c.bg_mid })
hl("FloatTitle", { fg = c.primary, bg = c.bg_mid, bold = true })
hl("FloatFooter", { fg = c.outline, bg = c.bg_mid })
hl("Cursor", { fg = c.bg, bg = c.primary })
hl("CursorLine", { bg = c.bg_low })
hl("CursorColumn", { link = "CursorLine" })
hl("ColorColumn", { bg = c.bg_low })
hl("CursorLineNr", { fg = c.primary, bold = true })
hl("LineNr", { fg = c.outline_dim })
hl("SignColumn", { bg = NONE })
hl("FoldColumn", { fg = c.outline_dim })
hl("Folded", { fg = c.fg_dim, bg = c.bg_low, italic = true })
hl("WinSeparator", { fg = c.outline_dim })
hl("VertSplit", { link = "WinSeparator" })
hl("EndOfBuffer", { fg = c.bg_highest })
hl("NonText", { fg = c.outline_dim })
hl("Whitespace", { fg = c.bg_highest })
hl("SpecialKey", { fg = c.outline_dim })
hl("Conceal", { fg = c.outline })
hl("Directory", { fg = c.primary })
hl("Title", { fg = c.primary, bold = true })
hl("Visual", { bg = c.primary_container, fg = c.on_primary_container })
hl("VisualNOS", { link = "Visual" })
hl("Search", { bg = c.tertiary_container, fg = c.on_tertiary_container })
hl("CurSearch", { bg = c.primary, fg = c.on_primary, bold = true })
hl("IncSearch", { link = "CurSearch" })
hl("Substitute", { link = "CurSearch" })
hl("MatchParen", { fg = c.primary, bold = true, underline = true })
hl("QuickFixLine", { bg = c.bg_high, bold = true })

hl("StatusLine", { fg = c.fg, bg = c.bg_mid })
hl("StatusLineNC", { fg = c.outline, bg = c.bg_low })
hl("TabLine", { fg = c.outline, bg = c.bg_low })
hl("TabLineSel", { fg = c.fg, bg = c.bg_high, bold = true })
hl("TabLineFill", { bg = NONE })
hl("WinBar", { fg = c.fg_dim, bg = NONE })
hl("WinBarNC", { fg = c.outline, bg = NONE })

hl("Pmenu", { fg = c.fg, bg = c.bg_mid })
hl("PmenuSel", { fg = c.on_primary_container, bg = c.primary_container, bold = true })
hl("PmenuKind", { fg = c.tertiary, bg = c.bg_mid })
hl("PmenuExtra", { fg = c.outline, bg = c.bg_mid })
hl("PmenuSbar", { bg = c.bg_high })
hl("PmenuThumb", { bg = c.outline })
hl("PmenuMatch", { fg = c.primary, bold = true })
hl("WildMenu", { link = "PmenuSel" })

hl("ModeMsg", { fg = c.fg_dim })
hl("MoreMsg", { fg = c.primary })
hl("Question", { fg = c.primary })
hl("ErrorMsg", { fg = c.red })
hl("WarningMsg", { fg = c.yellow })
hl("SpellBad", { undercurl = true, sp = c.red })
hl("SpellCap", { undercurl = true, sp = c.yellow })
hl("SpellRare", { undercurl = true, sp = c.magenta })
hl("SpellLocal", { undercurl = true, sp = c.cyan })

-- Syntax -------------------------------------------------------------------
-- Roles: functions = accent, keywords = tertiary, strings = green,
-- numbers/constants = orange, types = cyan, special/macros = magenta.
-- Comments are italic, which kitty renders in Monaspace Radon (handwritten).
hl("Comment", { fg = c.outline, italic = true })
hl("Constant", { fg = c.orange })
hl("String", { fg = c.green })
hl("Character", { link = "String" })
hl("Number", { fg = c.orange })
hl("Boolean", { fg = c.orange })
hl("Float", { link = "Number" })
hl("Identifier", { fg = c.fg })
hl("Function", { fg = c.primary })
hl("Statement", { fg = c.tertiary })
hl("Keyword", { fg = c.tertiary })
hl("Conditional", { link = "Keyword" })
hl("Repeat", { link = "Keyword" })
hl("Label", { fg = c.tertiary })
hl("Exception", { fg = c.red })
hl("Operator", { fg = c.fg_dim })
hl("PreProc", { fg = c.magenta })
hl("Include", { link = "PreProc" })
hl("Define", { link = "PreProc" })
hl("Macro", { link = "PreProc" })
hl("Type", { fg = c.cyan })
hl("StorageClass", { link = "Keyword" })
hl("Structure", { link = "Type" })
hl("Typedef", { link = "Type" })
hl("Special", { fg = c.magenta })
hl("SpecialChar", { link = "Special" })
hl("Delimiter", { fg = c.outline })
hl("SpecialComment", { fg = c.outline, italic = true })
hl("Tag", { fg = c.primary })
hl("Underlined", { underline = true })
hl("Error", { fg = c.red })
hl("Todo", { fg = c.on_primary, bg = c.primary, bold = true })

-- Treesitter: most @groups link to the classic ones by default; only the
-- ones that would otherwise look wrong are set.
hl("@variable", { fg = c.fg })
hl("@variable.builtin", { fg = c.red, italic = true })
hl("@variable.parameter", { fg = c.fg, italic = true })
hl("@variable.member", { fg = c.fg_dim })
hl("@property", { fg = c.fg_dim })
hl("@constructor", { fg = c.cyan })
hl("@module", { fg = c.fg_dim })
hl("@punctuation", { link = "Delimiter" })
hl("@punctuation.special", { fg = c.magenta })
hl("@string.escape", { fg = c.magenta })
hl("@string.regexp", { fg = c.magenta })
hl("@keyword.return", { fg = c.tertiary, italic = true })
hl("@function.builtin", { fg = c.primary, italic = true })
hl("@tag.attribute", { fg = c.tertiary })
hl("@markup.heading", { fg = c.primary, bold = true })
hl("@markup.strong", { bold = true })
hl("@markup.italic", { italic = true })
hl("@markup.link", { fg = c.tertiary, underline = true })
hl("@markup.raw", { fg = c.green })
hl("@markup.list", { fg = c.primary })
hl("@markup.quote", { fg = c.fg_dim, italic = true })
hl("@diff.plus", { fg = c.green })
hl("@diff.minus", { fg = c.red })
hl("@diff.delta", { fg = c.yellow })
hl("@lsp.type.comment", {}) -- let treesitter keep comment styling

-- Diagnostics, diff, LSP -------------------------------------------------------
for name, colour in pairs({ Error = c.red, Warn = c.yellow, Info = c.blue, Hint = c.cyan, Ok = c.green }) do
  hl("Diagnostic" .. name, { fg = colour })
  hl("DiagnosticVirtualText" .. name, { fg = colour, italic = true })
  hl("DiagnosticUnderline" .. name, { undercurl = true, sp = colour })
  hl("DiagnosticSign" .. name, { fg = colour })
end
hl("DiagnosticUnnecessary", { fg = c.outline })
hl("DiffAdd", { bg = c.mode == "dark" and "#1e3324" or "#dcf0e0" })
hl("DiffDelete", { bg = c.mode == "dark" and "#3a1e22" or "#f6dcdf" })
hl("DiffChange", { bg = c.bg_low })
hl("DiffText", { bg = c.bg_highest, bold = true })
hl("Added", { fg = c.green })
hl("Removed", { fg = c.red })
hl("Changed", { fg = c.yellow })
hl("LspReferenceText", { bg = c.bg_high })
hl("LspReferenceRead", { bg = c.bg_high })
hl("LspReferenceWrite", { bg = c.bg_high, underline = true })
hl("LspInlayHint", { fg = c.outline, italic = true })
hl("LspSignatureActiveParameter", { fg = c.primary, bold = true })

-- mini.nvim ------------------------------------------------------------------
hl("MiniStatuslineModeNormal", { fg = c.on_primary, bg = c.primary, bold = true })
hl("MiniStatuslineModeInsert", { fg = c.bg, bg = c.green, bold = true })
hl("MiniStatuslineModeVisual", { fg = c.bg, bg = c.tertiary, bold = true })
hl("MiniStatuslineModeReplace", { fg = c.bg, bg = c.red, bold = true })
hl("MiniStatuslineModeCommand", { fg = c.bg, bg = c.yellow, bold = true })
hl("MiniStatuslineModeOther", { fg = c.bg, bg = c.cyan, bold = true })
hl("MiniStatuslineDevinfo", { fg = c.fg_dim, bg = c.bg_high })
hl("MiniStatuslineFilename", { fg = c.fg_dim, bg = c.bg_mid })
hl("MiniStatuslineFileinfo", { fg = c.fg_dim, bg = c.bg_high })
hl("MiniStatuslineInactive", { fg = c.outline, bg = c.bg_low })
hl("MiniPickMatchCurrent", { bg = c.bg_high, bold = true })
hl("MiniPickMatchRanges", { fg = c.primary, bold = true })
hl("MiniPickPrompt", { fg = c.primary, bg = c.bg_mid })
hl("MiniPickBorderText", { fg = c.primary, bg = c.bg_mid })
hl("MiniFilesTitleFocused", { fg = c.primary, bg = c.bg_mid, bold = true })
hl("MiniFilesTitle", { fg = c.outline, bg = c.bg_mid })
hl("MiniClueTitle", { fg = c.primary, bg = c.bg_mid, bold = true })
hl("MiniClueDescGroup", { fg = c.tertiary })
hl("MiniClueNextKey", { fg = c.primary, bold = true })
hl("MiniDiffSignAdd", { fg = c.green })
hl("MiniDiffSignChange", { fg = c.yellow })
hl("MiniDiffSignDelete", { fg = c.red })
hl("MiniIndentscopeSymbol", { fg = c.outline_dim })
hl("MiniCursorword", { bg = c.bg_high })
hl("MiniCursorwordCurrent", { bg = c.bg_high })

-- :terminal uses the same 16 colours as kitty.
for i, colour in ipairs(c.terminal) do
  vim.g["terminal_color_" .. (i - 1)] = colour
end

-- Live reload: the engine replaces the file atomically (rename), so watch the
-- directory and re-run this colorscheme when our file is replaced.
if not vim.g.caelestia_watcher then
  local w = vim.uv.new_fs_event()
  if w then
    vim.g.caelestia_watcher = true
    local pending = false
    w:start(vim.fs.dirname(path), {}, function(_, fname)
      if fname ~= "nvim-colours.lua" or pending then return end
      pending = true
      vim.defer_fn(function()
        pending = false
        if vim.g.colors_name == "caelestia" then vim.cmd.colorscheme("caelestia") end
      end, 150)
    end)
  end
end
