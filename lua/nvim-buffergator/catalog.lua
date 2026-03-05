local M = {}

local config = require("nvim-buffergator.config")

local function is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
end

-- Run git status --porcelain once and return a map: abs_path -> status_char
local function get_git_statuses()
  local cwd = vim.fn.getcwd()
  local output = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(cwd) .. " status --porcelain 2>/dev/null"
  )
  if vim.v.shell_error ~= 0 then return {} end
  local result = {}
  for _, line in ipairs(output) do
    if #line >= 4 then
      local xy   = line:sub(1, 2)
      local path = line:sub(4):gsub("%s+$", "")
      -- Renames: "old -> new" — take the destination
      path = path:match("^.* %-> (.+)$") or path
      local abs = cwd .. "/" .. path
      -- Prefer working-tree char (col 2), fall back to index char (col 1)
      local s = xy:sub(2, 2)
      if s == " " then s = xy:sub(1, 1) end
      result[abs] = s
    end
  end
  return result
end

function M.get_git_branch()
  local branch = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  branch = branch:gsub("%s+$", "")
  if vim.v.shell_error ~= 0 or branch == "" or branch == "HEAD" then
    return nil
  end
  return branch
end

local function make_entry(bufnr, current, alternate, git_st)
  local name     = vim.api.nvim_buf_get_name(bufnr)
  local basename = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
  local parent   = name ~= "" and vim.fn.fnamemodify(name, ":h:~:.") or ""
  if parent == "." then parent = "" end

  return {
    bufnr      = bufnr,
    name       = name,
    basename   = basename,
    parent     = parent,
    modified   = vim.bo[bufnr].modified,
    current    = (bufnr == current),
    alternate  = (bufnr == alternate),
    git_status = (name ~= "" and git_st[name]) or " ",
  }
end

local sorters = {
  filepath = function(a, b)
    local pa = a.parent .. "/" .. a.basename
    local pb = b.parent .. "/" .. b.basename
    return pa < pb
  end,
  bufnum   = function(a, b) return a.bufnr < b.bufnr end,
  basename = function(a, b)
    if a.basename ~= b.basename then return a.basename < b.basename end
    return a.parent < b.parent
  end,
}

-- context_win: the user's working window (not the sidebar).
-- If nil, falls back to the current window (fine for refresh from BufEnter etc.).
function M.get_buffers(context_win)
  local current, alternate
  if context_win and vim.api.nvim_win_is_valid(context_win) then
    current   = vim.api.nvim_win_get_buf(context_win)
    alternate = vim.api.nvim_win_call(context_win, function()
      return vim.fn.bufnr("#")
    end)
  else
    current   = vim.api.nvim_get_current_buf()
    alternate = vim.fn.bufnr("#")
  end

  local git_st = get_git_statuses()
  local entries = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      entries[#entries + 1] = make_entry(bufnr, current, alternate, git_st)
    end
  end

  local sort_fn = sorters[config.options.sort] or sorters.filepath
  table.sort(entries, sort_fn)
  return entries
end

return M
