local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared_ui = require("codecompanion.interactions.shared.ui")
local utils = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion.CLI.UI
---@field bufnr number
---@field winnr number|nil
local UI = {}

---Resolve the window config by inheriting from display.chat.window
---and overlaying display.cli.window if present
---@return table
function UI:resolve_window()
  local window = vim.deepcopy(config.display.chat.window)
  if config.display.cli and config.display.cli.window then
    window = vim.tbl_deep_extend("force", window, config.display.cli.window)
  end
  return window
end

---@param args { bufnr: number }
---@return CodeCompanion.CLI.UI
function UI.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    winnr = nil,
  }, { __index = UI }) ---@cast self CodeCompanion.CLI.UI

  return self
end

---Open the CLI window
---@param opts? { width?: number, height?: number }
---@return CodeCompanion.CLI.UI
function UI:open(opts)
  opts = opts or {}

  if self:is_visible() then
    return self
  end

  local window = self:resolve_window()
  if opts.width then
    window.width = opts.width
  end
  if opts.height then
    window.height = opts.height
  end

  self.winnr = shared_ui.open(self.bufnr, window, {
    title = " " .. config.display.input.title .. " ",
  })

  log:trace("CLI window opened")
  utils.fire("CLIOpened", { bufnr = self.bufnr })

  return self
end

---Display the CLI buffer in a window that already exists, leaving that window's
---geometry and position exactly as the user left them
---@param winnr number The window to display the CLI buffer in
---@return CodeCompanion.CLI.UI|nil
function UI:show(winnr)
  if not winnr or not api.nvim_win_is_valid(winnr) then
    return
  end
  if self:is_visible() then
    return self
  end

  local window = self:resolve_window()

  api.nvim_win_set_buf(winnr, self.bufnr)
  self.winnr = winnr

  -- `open` leaves the cursor in the window it created, so match that
  if api.nvim_get_current_win() ~= winnr then
    api.nvim_set_current_win(winnr)
  end

  -- A window carries the options of whichever buffer it displayed before, and a
  -- buffer that has never been shown in it falls back to the global values, so
  -- the window options have to be applied again
  if window.opts and not vim.tbl_isempty(window.opts) then
    require("codecompanion.utils.ui").set_win_options(winnr, window.opts)
  end

  -- A float's border title belongs to the window, so it still names whatever we
  -- are replacing
  if window.layout == "float" then
    local win_config = api.nvim_win_get_config(winnr)
    win_config.title = " " .. config.display.input.title .. " "
    win_config.title_pos = window.title_pos or "center"
    pcall(api.nvim_win_set_config, winnr, win_config)
  end

  log:trace("CLI window reused")
  utils.fire("CLIOpened", { bufnr = self.bufnr })

  return self
end

---Hide the CLI window (does not kill the terminal process)
---@param opts? { window_reused?: boolean } Set `window_reused` when another
---  interaction has taken over our window, so the window is left alone
---@return nil
function UI:hide(opts)
  opts = opts or {}

  if opts.window_reused then
    -- Someone else displays their buffer in our window now, so all that is left
    -- to do is drop our claim on it
    self.winnr = nil
  else
    shared_ui.hide(self.winnr, self.bufnr, self:resolve_window().layout)
  end

  utils.fire("CLIHidden", { bufnr = self.bufnr })
end

---Determine if the CLI buffer is active
---@return boolean
function UI:is_active()
  return shared_ui.is_active(self.bufnr)
end

---Determine if the CLI window is visible
---@return boolean
function UI:is_visible()
  return shared_ui.is_visible(self.winnr, self.bufnr)
end

---CLI window is visible but not in the current tab
---@return boolean
function UI:is_visible_non_curtab()
  return shared_ui.is_visible_non_curtab(self.winnr, self.bufnr)
end

return UI
