local M = {}

local catalog = require("nvim-buffergator.catalog")
local ns      = vim.api.nvim_create_namespace("nvim-buffergator")

local HEADER_LINES = 1
M.HEADER_LINES = HEADER_LINES

-- Prefix: [NNN]=5  ' '=1  C=1  M=1  G=1  "  "=2  → 11 chars, basename at col 11
local PREFIX = 11

local git_hl = {
  M = "DiagnosticWarn",
  A = "DiagnosticInfo",
  D = "DiagnosticError",
  R = "DiagnosticInfo",
  ["?"] = "Comment",
}

local function def_name_hls()
  local warn = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn",  link = false })
  local info = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo",  link = false })
  local err  = vim.api.nvim_get_hl(0, { name = "DiagnosticError", link = false })
  vim.api.nvim_set_hl(0, "NvimBuffergatorBufDirty",  { fg = warn.fg, bold = true })
  vim.api.nvim_set_hl(0, "NvimBuffergatorGitDirty",  { fg = info.fg })
  vim.api.nvim_set_hl(0, "NvimBuffergatorBothDirty", { fg = err.fg, bold = true, underline = true })
end
def_name_hls()
vim.api.nvim_create_autocmd("ColorScheme", { callback = def_name_hls })

local function build_line(entry, max_display)
  local num_str  = string.format("[%3d]", entry.bufnr)
  local cur_flag = entry.current  and ">" or (entry.alternate and "#" or " ")
  local mod_flag = entry.modified and "+" or " "
  local git_flag = (entry.git_status ~= " ") and entry.git_status or " "

  local display_name = entry.display_name
  local parent       = entry.parent

  local line = num_str .. " " .. cur_flag .. mod_flag .. git_flag .. "  " .. display_name

  -- Only pad + append parent when path=0 (parent column active)
  local parent_start
  if parent ~= "" then
    local parent_col = PREFIX + max_display + 2
    local pad = parent_col - #line
    line = line .. string.rep(" ", math.max(pad, 2))
    parent_start = #line
    line = line .. parent
  end

  -- Highlights
  local hl = {}
  hl[#hl+1] = { "Comment", 0, 5 }

  if entry.current then
    hl[#hl+1] = { "Statement", 6, 7 }
  elseif entry.alternate then
    hl[#hl+1] = { "Special", 6, 7 }
  end

  if entry.modified then
    hl[#hl+1] = { "DiagnosticWarn", 7, 8 }
  end

  local ghl = git_hl[entry.git_status]
  if ghl then
    hl[#hl+1] = { ghl, 8, 9 }
  end

  -- Dirty-state highlight group for the filename
  local buf_dirty = entry.modified
  local git_dirty = entry.git_status ~= " "
  local name_hl
  if buf_dirty and git_dirty then
    name_hl = "NvimBuffergatorBothDirty"
  elseif buf_dirty then
    name_hl = "NvimBuffergatorBufDirty"
  elseif git_dirty then
    name_hl = "NvimBuffergatorGitDirty"
  else
    name_hl = "Bold"
  end

  -- When display_name includes a path prefix (path > 0), dim the prefix
  -- and apply the dirty colour only to the basename at the end.
  local basename    = entry.basename
  local name_offset = #display_name - #basename
  if name_offset > 0 and display_name:sub(name_offset + 1) == basename then
    -- dim the path prefix portion
    hl[#hl+1] = { "Comment", PREFIX, PREFIX + name_offset }
    -- colour the basename
    hl[#hl+1] = { name_hl, PREFIX + name_offset, PREFIX + #display_name }
  else
    hl[#hl+1] = { name_hl, PREFIX, PREFIX + #display_name }
  end

  if parent_start then
    hl[#hl+1] = { "Comment", parent_start, parent_start + #parent }
  end

  return line, hl
end

function M.render(sidebar_bufnr, context_win)
  local branch  = catalog.get_git_branch()
  local entries = catalog.get_buffers(context_win)

  local max_display = 12
  for _, e in ipairs(entries) do
    if #e.display_name > max_display then max_display = #e.display_name end
  end

  local header = branch and ("  @ " .. branch) or "  [no git]"
  local lines  = { header }
  local all_hl = { {} }

  for _, entry in ipairs(entries) do
    local line, hl = build_line(entry, max_display)
    lines[#lines+1]   = line
    all_hl[#all_hl+1] = hl
  end

  vim.bo[sidebar_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_bufnr, 0, -1, false, lines)
  vim.bo[sidebar_bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(sidebar_bufnr, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, "Title", 0, 0, -1)

  for row, hl in ipairs(all_hl) do
    for _, h in ipairs(hl) do
      vim.api.nvim_buf_add_highlight(sidebar_bufnr, ns, h[1], row - 1, h[2], h[3])
    end
  end

  -- Width based on display_name (not full line with parent).
  -- path=0: parent is off-screen so we stop at PREFIX+max_display+1.
  -- path>0: display_name already includes the path, no separate parent column.
  local max_width = PREFIX + max_display + 1

  return max_width, entries
end

return M
