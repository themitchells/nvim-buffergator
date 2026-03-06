local M = {}

local config = require("nvim-buffergator.config")

local function is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
end

-- Find the git repo root for a given directory.
-- Uses a per-call cache (dir_cache) to avoid redundant git invocations
-- when multiple buffers live in the same directory.
local function find_repo_root(dir, dir_cache)
  if dir_cache[dir] ~= nil then return dir_cache[dir] end
  local root = vim.fn.system(
    "git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null"
  ):gsub("%s+$", "")
  local result = (vim.v.shell_error == 0 and root ~= "") and root or false
  dir_cache[dir] = result
  return result
end

-- Collect git statuses for every unique repo that contains open buffers.
-- Returns a map: abs_path -> status_char
local function get_git_statuses(buf_names)
  local dir_cache  = {}
  local repo_roots = {}   -- root -> true

  for _, name in ipairs(buf_names) do
    if name ~= "" then
      local dir  = vim.fn.fnamemodify(name, ":h")
      local root = find_repo_root(dir, dir_cache)
      if root then repo_roots[root] = true end
    end
  end

  local statuses = {}
  for root in pairs(repo_roots) do
    local lines = vim.fn.systemlist(
      "git -C " .. vim.fn.shellescape(root) .. " status --porcelain 2>/dev/null"
    )
    if vim.v.shell_error == 0 then
      for _, line in ipairs(lines) do
        if #line >= 4 then
          local xy   = line:sub(1, 2)
          local path = line:sub(4):gsub("%s+$", "")
          path = path:match("^.* %-> (.+)$") or path
          local abs = root .. "/" .. path
          local s   = xy:sub(2, 2)
          if s == " " then s = xy:sub(1, 1) end
          statuses[abs] = s
        end
      end
    end
  end

  return statuses
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

  local display_name, parent
  local path_opt = config.options.path or 0

  if name == "" then
    display_name = "[No Name]"
    parent       = ""
  elseif path_opt == 1 then
    display_name = vim.fn.fnamemodify(name, ":~:.")  -- relative to ~ then cwd
    parent       = ""
  elseif path_opt == 2 then
    display_name = name                              -- absolute
    parent       = ""
  elseif path_opt == 3 then
    display_name = vim.fn.fnamemodify(name, ":~")   -- tilde-relative
    parent       = ""
  else  -- path_opt == 0 (default)
    display_name = basename
    parent       = vim.fn.fnamemodify(name, ":h:~:.")
    if parent == "." then parent = "" end
  end

  return {
    bufnr        = bufnr,
    name         = name,
    basename     = basename,
    display_name = display_name,
    parent       = parent,
    modified     = vim.bo[bufnr].modified,
    current      = (bufnr == current),
    alternate    = (bufnr == alternate),
    git_status   = (name ~= "" and git_st[name]) or " ",
  }
end

local sorters = {
  -- Sort by full absolute path so the result is consistent across all
  -- path display modes (parent is "" when path > 0, so using it for
  -- sort would break ordering).
  filepath = function(a, b) return a.name < b.name end,
  bufnum   = function(a, b) return a.bufnr < b.bufnr end,
  basename = function(a, b)
    if a.basename ~= b.basename then return a.basename < b.basename end
    return a.name < b.name  -- full path as tiebreaker for same filename
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

  -- Collect names first so git status can batch by repo
  local valid_bufs = {}
  local buf_names  = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_valid(bufnr) then
      valid_bufs[#valid_bufs + 1] = bufnr
      buf_names[#buf_names + 1]   = vim.api.nvim_buf_get_name(bufnr)
    end
  end

  local git_st  = get_git_statuses(buf_names)
  local entries = {}
  for _, bufnr in ipairs(valid_bufs) do
    entries[#entries + 1] = make_entry(bufnr, current, alternate, git_st)
  end

  local sort_fn = sorters[config.options.sort] or sorters.filepath
  table.sort(entries, sort_fn)
  return entries
end

return M
