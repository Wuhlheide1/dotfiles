-- Neovim 0.12, kept deliberately small: built-in plugin manager (vim.pack),
-- built-in LSP client + completion, and mini.nvim for the few UI pieces nvim
-- lacks. Colours follow the wallpaper (colors/caelestia.lua).
--
-- Plugins live in ~/.local/share/nvim/site/pack/core/opt; versions are pinned
-- in ~/.config/nvim/nvim-pack-lock.json. Update: :lua vim.pack.update()
-- (review, then :write to accept).
--
-- Keys: <Space> is leader; pause after it and a hint window lists what's next.
--   <Space>f files   <Space>g grep   <Space>b buffers   <Space>h help
--   <Space>e file browser (edit names/paths like text, = to apply)
--   <Space>r recent  <Space>d diagnostics  <Space>w save
--   LSP (when a server runs): K hover, grn rename, gra actions, grr refs,
--   gd definition, [d ]d prev/next diagnostic.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options --------------------------------------------------------------------
local o = vim.o
o.number = true
o.relativenumber = false
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 8
o.sidescrolloff = 8
o.wrap = false
o.breakindent = true
o.linebreak = true

o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true

o.ignorecase = true
o.smartcase = true
o.inccommand = "split"

o.splitright = true
o.splitbelow = true
o.mouse = "a"
o.clipboard = "unnamedplus" -- yank/paste use the Wayland clipboard (wl-copy)
o.undofile = true           -- undo survives closing the file
o.swapfile = false
o.confirm = true            -- ask instead of failing on :q with changes
o.updatetime = 250
o.timeoutlen = 400

o.termguicolors = true
o.winborder = "rounded"
o.pumheight = 12
o.showmode = false          -- the statusline shows the mode
o.laststatus = 3            -- one statusline for the whole window
o.cmdheight = 1
o.list = true
o.listchars = "tab:» ,trail:·,nbsp:␣"
o.fillchars = "eob: ,fold: ,foldopen:,foldclose:,foldsep: "
o.shortmess = o.shortmess .. "I" -- no intro screen

-- Plugins ------------------------------------------------------------------------
vim.pack.add({
  "https://github.com/nvim-mini/mini.nvim",
  "https://github.com/neovim/nvim-lspconfig",
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
}, { confirm = false })

vim.cmd.colorscheme("caelestia")

require("mini.icons").setup()
MiniIcons.mock_nvim_web_devicons()
require("mini.statusline").setup({ use_icons = true })
require("mini.pick").setup({ window = { config = { border = "rounded" } } })
require("mini.extra").setup()
require("mini.files").setup({ windows = { preview = true, width_preview = 50 } })
require("mini.pairs").setup()
require("mini.surround").setup()
require("mini.ai").setup()
require("mini.diff").setup({ view = { style = "sign" } })
require("mini.git").setup()
require("mini.cursorword").setup({ delay = 300 })
require("mini.indentscope").setup({ symbol = "│", draw = { delay = 50 } })
require("mini.notify").setup({ window = { config = { border = "rounded" } } })
vim.notify = MiniNotify.make_notify()

local clue = require("mini.clue")
clue.setup({
  window = { delay = 400, config = { width = "auto", border = "rounded" } },
  triggers = {
    { mode = "n", keys = "<Leader>" }, { mode = "x", keys = "<Leader>" },
    { mode = "n", keys = "g" }, { mode = "x", keys = "g" },
    { mode = "n", keys = "[" }, { mode = "n", keys = "]" },
    { mode = "n", keys = "<C-w>" },
    { mode = "n", keys = "z" },
    { mode = "n", keys = "'" }, { mode = "n", keys = "`" },
    { mode = "n", keys = '"' }, { mode = "i", keys = "<C-r>" },
  },
  clues = {
    clue.gen_clues.builtin_completion(), clue.gen_clues.g(), clue.gen_clues.marks(),
    clue.gen_clues.registers(), clue.gen_clues.windows(), clue.gen_clues.z(),
  },
})

-- Keymaps --------------------------------------------------------------------------
local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { desc = desc }) end
local pick = MiniPick.builtin
local extra = MiniExtra.pickers

map("n", "<Leader>f", pick.files, "Find file")
map("n", "<Leader>g", pick.grep_live, "Grep")
map("n", "<Leader>b", pick.buffers, "Buffers")
map("n", "<Leader>h", pick.help, "Help")
map("n", "<Leader>r", extra.oldfiles, "Recent files")
map("n", "<Leader>d", extra.diagnostic, "Diagnostics")
map("n", "<Leader>s", function() extra.lsp({ scope = "document_symbol" }) end, "Symbols")
map("n", "<Leader>e", function() MiniFiles.open(vim.api.nvim_buf_get_name(0)) end, "File browser")
map("n", "<Leader>w", "<Cmd>write<CR>", "Save")
map("n", "<Leader>q", "<Cmd>quit<CR>", "Quit window")
map("n", "<Esc>", "<Cmd>nohlsearch<CR>", "Clear search highlight")
map("n", "gd", vim.lsp.buf.definition, "Go to definition")
-- Move by display line when wrapping, so long lines don't jump.
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })
-- Keep the selection when indenting.
map("x", "<", "<gv", "Indent left")
map("x", ">", ">gv", "Indent right")

-- Treesitter -------------------------------------------------------------------------
-- Highlighting for every language that has a parser. Parsers for c, lua,
-- markdown, vim and vimdoc ship with nvim; the rest are compiled by
-- nvim-treesitter, which needs the `tree-sitter` CLI (pacman -S tree-sitter-cli).
local want = { "bash", "fish", "python", "json", "jsonc", "toml", "yaml", "css", "html",
  "javascript", "typescript", "rust", "qmljs", "hyprlang", "ini", "diff", "git_config",
  "gitcommit", "regex" }
if vim.fn.executable("tree-sitter") == 1 then
  local ok, ts = pcall(require, "nvim-treesitter")
  if ok then
    local have = ts.get_installed and ts.get_installed() or {}
    local missing = vim.tbl_filter(function(l) return not vim.tbl_contains(have, l) end, want)
    if #missing > 0 then ts.install(missing) end
  end
end
vim.api.nvim_create_autocmd("FileType", {
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
    if pcall(vim.treesitter.start, ev.buf, lang) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})
vim.filetype.add({ pattern = { [".*/hypr/.*%.conf"] = "hyprlang" } })

-- LSP ----------------------------------------------------------------------------------
-- nvim-lspconfig only supplies server definitions; a server is enabled when
-- its binary is installed, so adding one is just `pacman -S <server>`.
local servers = {
  clangd = "clangd",
  lua_ls = "lua-language-server",
  bashls = "bash-language-server",
  basedpyright = "basedpyright-langserver",
  rust_analyzer = "rust-analyzer",
  qmlls = "qmlls6",
  taplo = "taplo",
  jsonls = "vscode-json-language-server",
}
for name, bin in pairs(servers) do
  if vim.fn.executable(bin) == 1 then vim.lsp.enable(name) end
end
vim.lsp.config("lua_ls", {
  settings = { Lua = { runtime = { version = "LuaJIT" }, workspace = { library = { vim.env.VIMRUNTIME } } } },
})
vim.lsp.config("qmlls", { cmd = { "qmlls6" } })

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})
o.completeopt = "menuone,noselect,popup,fuzzy"

vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●" },
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
  signs = { text = {
    [vim.diagnostic.severity.ERROR] = "", [vim.diagnostic.severity.WARN] = "",
    [vim.diagnostic.severity.INFO] = "", [vim.diagnostic.severity.HINT] = "󰌵",
  } },
})

-- Small comforts ------------------------------------------------------------------------
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Flash what was yanked",
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})
vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Reopen files where you left off",
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 1 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
vim.api.nvim_create_autocmd("VimResized", { command = "wincmd =" })
