---@class CodeCompanion.Registry.Entry
---@field name string
---@field description string
---@field interaction string
---@field bufnr number
---@field open fun()
---@field hide fun(opts?: { window_reused?: boolean })
---@field show? fun(winnr: number) Display in a window that already exists
---@field window? fun(): table The resolved window configuration

local api = vim.api

local M = {}

---@type table<number, CodeCompanion.Registry.Entry>
local entries = {}

---Register an interaction
---@param bufnr number
---@param entry CodeCompanion.Registry.Entry
---@return nil
function M.add(bufnr, entry)
  entry.bufnr = bufnr
  entries[bufnr] = entry
end

---Deregister an interaction
---@param bufnr number
---@return nil
function M.remove(bufnr)
  entries[bufnr] = nil
end

---Partially update an entry
---@param bufnr number
---@param fields table
---@return nil
function M.update(bufnr, fields)
  if entries[bufnr] then
    for k, v in pairs(fields) do
      entries[bufnr][k] = v
    end
  end
end

---Return all entries
---@return CodeCompanion.Registry.Entry[]
function M.list()
  return vim
    .iter(pairs(entries))
    :map(function(_, v)
      return v
    end)
    :totable()
end

---Return a single entry
---@param bufnr number
---@return CodeCompanion.Registry.Entry|nil
function M.get(bufnr)
  return entries[bufnr]
end

---Layouts whose window can be handed from one interaction to another. `tab` and
---`buffer` are excluded because hiding those means leaving a tabpage or returning
---to the alternate buffer, not closing a window
local REUSABLE_LAYOUTS = { float = true, horizontal = true, vertical = true }

---Find the window in the current tabpage that displays a buffer, preferring the
---current window
---@param bufnr number
---@return number|nil
local function curtab_win(bufnr)
  local current = api.nvim_get_current_win()
  if api.nvim_win_get_buf(current) == bufnr then
    return current
  end
  for _, winnr in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(winnr) == bufnr then
      return winnr
    end
  end
end

---The window `current` occupies, if `next_entry` is able to take it over
---@param current CodeCompanion.Registry.Entry
---@param next_entry CodeCompanion.Registry.Entry
---@return number|nil
local function window_to_hand_over(current, next_entry)
  if not next_entry.show or not current.window or not next_entry.window then
    return
  end

  local layout = current.window().layout
  if not REUSABLE_LAYOUTS[layout] or layout ~= next_entry.window().layout then
    return
  end

  return curtab_win(current.bufnr)
end

---Navigate to the next or previous interaction
---@param current_bufnr number
---@param direction number 1 for next, -1 for previous
---@param opts? { filter?: fun(entry: CodeCompanion.Registry.Entry): boolean }
---@return CodeCompanion.Registry.Entry|nil moved_to The entry moved to, if any
function M.move(current_bufnr, direction, opts)
  opts = opts or {}

  local sorted = M.list()
  table.sort(sorted, function(a, b)
    return a.bufnr < b.bufnr
  end)

  if opts.filter then
    sorted = vim.tbl_filter(opts.filter, sorted)
  end

  local len = #sorted
  if len <= 1 then
    return nil
  end

  local idx
  for i, entry in ipairs(sorted) do
    if entry.bufnr == current_bufnr then
      idx = i
      break
    end
  end
  if not idx then
    return nil
  end

  local next_idx = direction > 0 and (idx % len) + 1 or ((idx - 2 + len) % len) + 1
  local current = sorted[idx]
  local next_entry = sorted[next_idx]

  -- Hand the window over when both interactions live in one, rather than closing
  -- it and building a new one: the replacement comes back at its configured size,
  -- discarding whatever the user resized it to along with everything else the
  -- window owned, such as a window-local cwd
  local winnr = window_to_hand_over(current, next_entry)
  if winnr then
    current.hide({ window_reused = true })
    next_entry.show(winnr)
  else
    current.hide()
    next_entry.open()
  end

  return next_entry
end

return M
