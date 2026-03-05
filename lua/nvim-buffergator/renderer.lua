local M = {}

local catalog = require("nvim-buffergator.catalog")
local ns      = vim.api.nvim_create_namespace("nvim-buffergator")

local HEADER_LINES = 2
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

-- Line format: [NNN] CMG  basename  parent/dir
-- Padding after basename ensures parent always starts at col PREFIX+max_name+2,
-- so the width formula can reliably hide it by stopping at PREFIX+max_name+1.
local function build_line(entry, max_name)
  local num_str  = string.format("[%3d]", entry.bufnr)
  local cur_flag = entry.current  and ">" or (entry.alternate and "#" or " ")
  local mod_flag = entry.modified and "+" or " "
  local git_flag = (entry.git_status ~= " ") and entry.git_status or " "
  local basename = entry.basename
  local parent   = entry.parent

  -- Build prefix+basename portion (exactly PREFIX + #basename chars)
  local line = num_str .. " " .. cur_flag .. mod_flag .. git_flag .. "  " .. basename

  -- Pad so parent always starts at the same column: PREFIX + max_name + 2
  local parent_col = PREFIX + max_name + 2
  local pad = parent_col - #line   -- always ≥ 2 since max_name ≥ #basename
  line = line .. string.rep(" ", pad)

  local parent_start = #line
  if parent ~= "" then
    line = line .. parent
  end

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

  hl[#hl+1] = { "Bold", PREFIX, PREFIX + #basename }

  if parent ~= "" then
    hl[#hl+1] = { "Comment", parent_start, parent_start + #parent }
  end

  return line, hl
end

function M.render(sidebar_bufnr, context_win)
  local branch  = catalog.get_git_branch()
  local entries = catalog.get_buffers(context_win)

  local max_name = 12
  for _, e in ipairs(entries) do
    if #e.basename > max_name then max_name = #e.basename end
  end

  local header = branch and ("  @ " .. branch) or "  [no git]"
  local lines  = { header, "" }
  local all_hl = { {}, {} }

  for _, entry in ipairs(entries) do
    local line, hl = build_line(entry, max_name)
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

  -- Width sized to filename column only. Parent always starts at PREFIX+max_name+2,
  -- so setting width = PREFIX+max_name+1 puts the parent one col past the window edge.
  -- Do NOT include header in the max — a long branch name must not widen the window
  -- past the filename column or it would expose the start of parent paths.
  local max_width = PREFIX + max_name + 1

  return max_width, entries
end

return M
