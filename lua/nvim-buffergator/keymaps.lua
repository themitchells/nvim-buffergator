local M = {}

local config = require("nvim-buffergator.config")

-- Open buffer in target window using the specified command
local function open_buf(bufnr, cmd)
  local view = require("nvim-buffergator.view")
  local target = view.get_prev_win()
  if not target then return end

  vim.api.nvim_set_current_win(target)

  if cmd == "edit" then
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "split" then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  elseif cmd == "tabedit" then
    vim.cmd("tabedit")
    vim.api.nvim_set_current_buf(bufnr)
  end
end

-- Get bufnr for the line currently under cursor in the sidebar
local function current_bufnr(sidebar_bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  -- Re-derive from catalog so we stay in sync
  local catalog = require("nvim-buffergator.catalog")
  local entries  = catalog.get_buffers()
  local e = entries[line]
  return e and e.bufnr or nil
end

local function delete_buf(wipe)
  local view       = require("nvim-buffergator.view")
  local sidebar_buf = view.get_bufnr()
  local bufnr       = current_bufnr(sidebar_buf)
  if not bufnr then return end

  local cmd = wipe and "bwipeout" or "bdelete"
  local ok, err = pcall(vim.cmd, cmd .. " " .. bufnr)
  if not ok then
    vim.notify("nvim-buffergator: " .. err, vim.log.levels.WARN)
  end
  view.refresh()
end

local function map(bufnr, keys, fn, desc)
  if type(keys) == "string" then keys = { keys } end
  for _, k in ipairs(keys) do
    vim.keymap.set("n", k, fn, { buffer = bufnr, noremap = true, silent = true, desc = desc })
  end
end

function M.setup(bufnr)
  local km = config.options.keymaps
  local view = require("nvim-buffergator.view")

  map(bufnr, km.open, function()
    local b = current_bufnr(bufnr)
    if b then open_buf(b, "edit") end
  end, "Open buffer")

  map(bufnr, km.open_vsplit, function()
    local b = current_bufnr(bufnr)
    if b then open_buf(b, "vsplit") end
  end, "Open buffer in vsplit")

  map(bufnr, km.open_split, function()
    local b = current_bufnr(bufnr)
    if b then open_buf(b, "split") end
  end, "Open buffer in split")

  map(bufnr, km.open_tab, function()
    local b = current_bufnr(bufnr)
    if b then open_buf(b, "tabedit") end
  end, "Open buffer in tab")

  map(bufnr, km.delete, function() delete_buf(false) end, "Delete buffer")
  map(bufnr, km.wipe,   function() delete_buf(true)  end, "Wipe buffer")

  map(bufnr, km.close, function() view.close() end, "Close sidebar")

  map(bufnr, km.next, function()
    local win  = view.get_win()
    if not win then return end
    local cur  = vim.api.nvim_win_get_cursor(win)
    local last = vim.api.nvim_buf_line_count(bufnr)
    if cur[1] < last then
      vim.api.nvim_win_set_cursor(win, { cur[1] + 1, cur[2] })
    end
  end, "Next buffer")

  map(bufnr, km.prev, function()
    local win  = view.get_win()
    if not win then return end
    local cur  = vim.api.nvim_win_get_cursor(win)
    if cur[1] > 1 then
      vim.api.nvim_win_set_cursor(win, { cur[1] - 1, cur[2] })
    end
  end, "Previous buffer")

  map(bufnr, km.refresh, function() view.refresh() end, "Refresh list")
end

return M
