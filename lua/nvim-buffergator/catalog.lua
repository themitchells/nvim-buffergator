local M = {}

local config = require("nvim-buffergator.config")

-- Returns true if bufnr is a valid, listed buffer worth showing
local function is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
end

-- Build metadata table for one buffer
local function make_entry(bufnr, current, alternate)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local basename = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
  local parent = name ~= "" and vim.fn.fnamemodify(name, ":h:~:.") or ""
  if parent == "." then parent = "" end

  return {
    bufnr    = bufnr,
    name     = name,
    basename = basename,
    parent   = parent,
    modified = vim.bo[bufnr].modified,
    current  = (bufnr == current),
    alternate = (bufnr == alternate),
  }
end

-- Sort comparators
local sorters = {
  filepath = function(a, b)
    local pa = a.parent .. "/" .. a.basename
    local pb = b.parent .. "/" .. b.basename
    return pa < pb
  end,
  bufnum = function(a, b)
    return a.bufnr < b.bufnr
  end,
  basename = function(a, b)
    if a.basename ~= b.basename then
      return a.basename < b.basename
    end
    return a.parent < b.parent
  end,
}

function M.get_buffers()
  local current  = vim.api.nvim_get_current_buf()
  local alternate = vim.fn.bufnr("#")

  local entries = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      entries[#entries + 1] = make_entry(bufnr, current, alternate)
    end
  end

  local sort_fn = sorters[config.options.sort] or sorters.filepath
  table.sort(entries, sort_fn)

  return entries
end

return M
