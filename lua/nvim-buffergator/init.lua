local M = {}

local config = require("nvim-buffergator.config")
local view   = require("nvim-buffergator.view")

-- Debounce timers
local display_timer = nil
local git_timer     = nil
local DEBOUNCE_MS   = 80

-- Re-render from cache only (no git I/O) — used for BufEnter / cursor moves.
local function debounced_display_refresh()
  if display_timer then display_timer:stop(); display_timer:close() end
  display_timer = vim.uv.new_timer()
  display_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if view.is_open() then view.refresh() end
    display_timer = nil
  end))
end

-- Async git refresh + re-render — used when files actually change.
local function debounced_git_refresh()
  if git_timer then git_timer:stop(); git_timer:close() end
  git_timer = vim.uv.new_timer()
  git_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if view.is_open() then
      require("nvim-buffergator.catalog").refresh_git_async(function()
        if view.is_open() then view.refresh() end
      end)
    end
    git_timer = nil
  end))
end

-- Inject our filetype into lualine's disabled_filetypes so lualine
-- skips rendering its statusline for the sidebar window.
-- lualine.config.get_config() returns the live internal table by reference,
-- so a table.insert here is picked up immediately without re-calling setup().
local function register_lualine_compat()
  local ok, lc = pcall(require, "lualine.config")
  if not ok then return end
  local cfg = lc.get_config()
  if not (cfg and cfg.options and cfg.options.disabled_filetypes) then return end
  local df = cfg.options.disabled_filetypes
  df.statusline = df.statusline or {}
  for _, ft in ipairs(df.statusline) do
    if ft == "nvim-buffergator" then return end  -- already registered
  end
  table.insert(df.statusline, "nvim-buffergator")
end

function M.setup(user_opts)
  config.setup(user_opts)

  -- Register now if lualine is already loaded; also on VimEnter in case it
  -- loads lazily after us.
  register_lualine_compat()
  vim.api.nvim_create_autocmd("VimEnter", {
    once     = true,
    callback = register_lualine_compat,
  })

  -- Global keymaps
  local gk = config.options.global_keymaps
  if gk.toggle then
    vim.keymap.set("n", gk.toggle, view.toggle, { noremap = true, silent = true, desc = "Toggle buffergator" })
  end
  if gk.close then
    vim.keymap.set("n", gk.close, view.close, { noremap = true, silent = true, desc = "Close buffergator" })
  end

  -- Autocommands
  local grp = vim.api.nvim_create_augroup("NvimBuffergator", { clear = true })

  -- File-change events: need a full git refresh
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWritePost", "BufFilePost" }, {
    group    = grp,
    callback = debounced_git_refresh,
  })
  -- Window/buffer focus events: re-render from cache (no git I/O)
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = grp,
    callback = debounced_display_refresh,
  })

  -- Track which editing window the user is in so <CR> always opens
  -- in the window they most recently focused, not the one from sidebar open.
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = grp,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if view.is_open() and win ~= view.get_win() then
        view.set_prev_win(win)
      end
    end,
  })

  -- Close sidebar if it becomes the last window
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = grp,
    callback = function()
      if view.is_open() and #vim.api.nvim_list_wins() == 1 then
        -- Only the sidebar is open; close it to avoid being stranded
        view.close()
        vim.cmd("enew")
      end
    end,
  })
end

-- Public API
M.open   = view.open
M.close  = view.close
M.toggle = view.toggle
M.is_open = view.is_open

return M
