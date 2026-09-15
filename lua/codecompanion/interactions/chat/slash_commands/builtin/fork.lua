local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

---Resolve how the fork populates its context
---@param opts? { context?: string }
---@return "inherit"
local function resolve_context_mode(opts)
  local mode = (opts or {}).context or "inherit"
  if mode ~= "inherit" then
    log:warn("Unknown `context` mode `%s` on the fork slash command, inheriting instead", mode)
  end

  return "inherit"
end

---Copy the source chat's messages, leaving the fork ready for user input
---@param source CodeCompanion.Chat
---@return CodeCompanion.Chat.Messages
local function build_messages(source)
  local messages = vim.deepcopy(source.messages or {})
  table.insert(messages, {
    content = "",
    role = config.constants.USER_ROLE,
  })

  return messages
end

---Give the fork the source chat's context and tools
---@param opts { source: CodeCompanion.Chat, forked: CodeCompanion.Chat }
---@return nil
local function inherit_context(opts)
  local source, forked = opts.source, opts.forked

  forked.context_items = vim.deepcopy(source.context_items or {})

  forked.tool_registry.groups = vim.deepcopy(source.tool_registry.groups)
  forked.tool_registry.in_use = vim.deepcopy(source.tool_registry.in_use)
  forked.tool_registry.schemas = vim.deepcopy(source.tool_registry.schemas)

  forked.context:render()
end

---@class CodeCompanion.SlashCommand.Fork
---@field Chat CodeCompanion.Chat
---@field config table
---@field context table
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

function SlashCommand:execute()
  if vim.tbl_isempty(self.Chat.messages) then
    return utils.notify("No messages to fork", vim.log.levels.WARN)
  end

  vim.ui.input({ default = self.Chat.title, prompt = " Fork Title " }, function(name)
    if name == nil then
      return
    end
    self:output(name)
  end)
end

---Fork the current chat into a new chat buffer
---@param name string The name for the forked chat
---@return nil
function SlashCommand:output(name)
  local source = self.Chat
  local context_mode = resolve_context_mode(self.config.opts)

  local title = (name ~= "") and name or ("Fork of: " .. (source.title or ("Chat " .. source.id)))

  local chat_args = {
    adapter = source.adapter,
    last_role = config.constants.USER_ROLE,
    messages = build_messages(source),
    settings = source.settings and vim.deepcopy(source.settings) or nil,
    stop_context_insertion = true,
    title = title,
  }

  -- The fork takes its context from the source, so loading the defaults here would render a second block
  if context_mode == "inherit" then
    chat_args.mcp_servers = "none"
    chat_args.skills = "none"
    chat_args.tools = "none"
  end

  local Chat = require("codecompanion.interactions.chat")
  local forked = Chat.new(chat_args)

  -- This ensures we respect any conditionals on the chat class
  if not forked then
    return
  end

  forked:set_title(forked.title) -- Needed for description as well

  if context_mode == "inherit" then
    inherit_context({ source = source, forked = forked })
  end

  if self.config.opts and self.config.opts.auto_save_session then
    require("codecompanion.interactions.chat.sessions").save(forked)
  end
end

return SlashCommand
