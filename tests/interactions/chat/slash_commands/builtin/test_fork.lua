local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        fork = require("codecompanion.interactions.chat.slash_commands.builtin.fork")
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

---Config that preloads the given tools into every new chat buffer
---@param names string[]
---@return table
local function with_default_tools(names)
  return { interactions = { chat = { tools = { opts = { default_tools = names } } } } }
end

---Create the chat that gets forked
---@param config? table Config merged over the test config
local function setup_source(config)
  child.lua(string.format(
    [[
    _G.chat = h.setup_chat_buffer(%s)
    table.insert(_G.chat.messages, { role = "user", content = "Hello there" })
  ]],
    vim.inspect(config or {})
  ))
end

---Fork the source chat, leaving the fork in `_G.forked`
---@param opts? { context?: string } The fork slash command's options
local function fork_source(opts)
  child.lua(string.format(
    [[
    fork.new({ Chat = _G.chat, config = { opts = %s } }):output("A fork")
    _G.forked = require("codecompanion").last_chat()
  ]],
    vim.inspect(opts or {})
  ))
end

---Delete a context row from a chat buffer and reconcile, as a user would
---@param opts { chat: string, id: string } `chat` names the global holding the chat
local function delete_context_row(opts)
  child.lua(string.format(
    [[
    local chat = %s
    chat.ui:unlock_buf()
    for i, line in ipairs(h.get_buf_lines(chat.bufnr)) do
      if line:find("%s", 1, true) then
        vim.api.nvim_buf_set_lines(chat.bufnr, i - 1, i, false, {})
        break
      end
    end
    chat:check_context()
  ]],
    opts.chat,
    opts.id
  ))
end

---@return string[]
local function forked_context_ids()
  return child.lua_get([[vim.tbl_map(function(item) return item.id end, _G.forked.context_items)]])
end

---@return string[]
local function forked_context_block()
  return child.lua_get([[
    vim.tbl_filter(function(line)
      return line:find("^> ") ~= nil
    end, h.get_buf_lines(_G.forked.bufnr))
  ]])
end

---@param id string
---@return number
local function forked_messages_for(id)
  return child.lua_get(string.format(
    [[
    #vim.tbl_filter(function(message)
      return message.context ~= nil and message.context.id == "%s"
    end, _G.forked.messages)
  ]],
    id
  ))
end

T["Fork"] = new_set()

T["Fork"]["inherits the source's context when no mode is set"] = function()
  setup_source()
  child.lua([[_G.chat.context:add({ source = "test", name = "test", id = "testing" })]])

  fork_source()

  h.eq({ "testing" }, forked_context_ids())
end

T["Fork"]["warns and inherits when the context mode is unknown"] = function()
  setup_source()
  child.lua([[
    _G.warnings = {}
    require("codecompanion.utils.log").warn = function(_, message, ...)
      table.insert(_G.warnings, string.format(message, ...))
    end
    _G.chat.context:add({ source = "test", name = "test", id = "testing" })
  ]])

  fork_source({ context = "nonsense" })

  h.eq({ "testing" }, forked_context_ids())
  h.expect_contains("nonsense", child.lua_get("_G.warnings[1]"))
end

T["Fork"]["renders one context block when inheriting"] = function()
  setup_source(with_default_tools({ "tool_group" }))

  fork_source()

  h.eq({ "> Context:", "> - <group>tool_group</group>" }, forked_context_block())
end

T["Fork"]["inherits a group without duplicating its system prompt"] = function()
  setup_source(with_default_tools({ "tool_group" }))

  fork_source()

  h.eq(1, forked_messages_for("<group>tool_group</group>"))
end

T["Fork"]["DOES NOT re-add a default tool the source dropped"] = function()
  setup_source(with_default_tools({ "func" }))
  delete_context_row({ chat = "_G.chat", id = "<tool>func</tool>" })

  fork_source()

  h.eq({}, forked_context_ids())
  h.eq(true, child.lua_get([[_G.forked.tool_registry.in_use.func == nil]]))
end

T["Fork"]["revokes an inherited group when its row is deleted"] = function()
  setup_source(with_default_tools({ "tool_group" }))
  fork_source()

  delete_context_row({ chat = "_G.forked", id = "<group>tool_group</group>" })

  h.eq({}, forked_context_ids())
  h.eq({}, child.lua_get([[vim.tbl_keys(_G.forked.tool_registry.schemas)]]))
  h.eq({}, child.lua_get([[vim.tbl_keys(_G.forked.tool_registry.in_use)]]))
  h.eq(0, forked_messages_for("<group>tool_group</group>"))
end

return T
