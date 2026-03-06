# nvim-buffergator

A sidebar buffer list for Neovim, written in Lua.
Full rewrite of [vim-buffergator](https://github.com/jeetsukumaran/vim-buffergator) targeting a clean Lua API with no VimScript workarounds.

## Features

- Left vertical split sidebar, auto-sized to the filename column
- Four sort modes: `filepath`, `bufnum`, `basename`, `mru` — cycle with `S`
- Four filename display modes (mirrors lualine `path` option 0–3)
- Per-file git status flags with filename colouring by dirty state
- Git branch shown in the header; multi-repo git status support
- Asynchronous git operations — sidebar opens instantly
- `close_on_select`, configurable mouse open, full keymap customisation
- lualine statusline/winbar suppression built-in
- `g?` floating keymap reference

## Requirements

- Neovim ≥ 0.9 (0.10+ recommended for async `vim.system`)

## Installation (lazy.nvim)

```lua
{
    dir  = "~/path/to/nvim-buffergator",
    name = "nvim-buffergator",
    config = function()
        require("nvim-buffergator").setup({
            sort            = "filepath",
            path            = 1,       -- relative paths
            close_on_select = true,
        })
    end,
}
```

## Default Keymaps

| Key | Action |
|-----|--------|
| `<Leader>b` | Toggle sidebar |
| `<Leader>B` | Close sidebar |
| `<CR>` / `o` | Open buffer in previous window |
| `s` / `<C-v>` | Open in vertical split |
| `i` / `<C-s>` | Open in horizontal split |
| `t` / `<C-t>` | Open in new tab |
| `d` / `D` | Delete / wipe buffer |
| `S` | Cycle sort mode |
| `R` | Refresh |
| `q` / `<Esc>` | Close sidebar |
| `g?` | Show keymap reference |

## Commands

| Command | Description |
|---------|-------------|
| `:BuffergatorToggle` | Toggle sidebar |
| `:BuffergatorOpen` | Open sidebar |
| `:BuffergatorClose` | Close sidebar |
| `:BuffergatorPath {0-3}` | Set filename display mode |
| `:BuffergatorSort {mode}` | Set sort mode (tab-completable) |

## Configuration

See `:help nvim-buffergator-config` for the full options reference.
