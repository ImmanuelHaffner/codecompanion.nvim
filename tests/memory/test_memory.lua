local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_CWD = vim.fn.tempname()
        _G.MEMORY_DIR = vim.fs.joinpath(_G.TEST_CWD, "memories")
        vim.fn.mkdir(_G.MEMORY_DIR, "p")

        -- Set up while the tests directory is still on the package path
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()

        vim.uv.chdir(_G.TEST_CWD)
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, "rf")
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

local function add_memories()
  child.lua([[
    vim.fn.mkdir(vim.fs.joinpath(_G.MEMORY_DIR, "projects"), "p")
    vim.fn.writefile({ "Sub-agents" }, vim.fs.joinpath(_G.MEMORY_DIR, "parallel-sub-agents.md"))
    vim.fn.writefile({ "Zsh" }, vim.fs.joinpath(_G.MEMORY_DIR, "projects", "dotfiles-zsh-migration.md"))
  ]])
end

T["Memory"] = new_set()

T["Memory"]["indexes nested memories as paths the tool accepts back"] = function()
  add_memories()

  h.eq({
    "/memories/parallel-sub-agents.md",
    "/memories/projects/dotfiles-zsh-migration.md",
  }, child.lua([[return require("codecompanion.memory").get_index()]]))
end

T["Memory"]["prompt lists every memory"] = function()
  add_memories()

  local prompt = child.lua([[return require("codecompanion.memory").get_prompt()]])

  h.expect_match(prompt, "%- /memories/parallel%-sub%-agents%.md")
  h.expect_match(prompt, "%- /memories/projects/dotfiles%-zsh%-migration%.md")
  h.expect_match(prompt, "That index is complete")
end

T["Memory"]["prompt says the directory is empty when there are no memories"] = function()
  local prompt = child.lua([[return require("codecompanion.memory").get_prompt()]])

  -- FORK(memory-cwd): the prompt names the directory /memories stands for
  h.expect_match(prompt, "Your memory directory `/memories` %(`.*/memories`%) is empty")
  -- /FORK(memory-cwd)
  h.expect_match(prompt, "Name a memory so that the file name alone says what it holds")
end

T["Memory"]["refreshing picks up a memory created since the prompt was built"] = function()
  local contents = child.lua([[
    _G.chat.tool_registry:add("memory", { config = require("codecompanion.config").interactions.chat.tools })
    vim.fn.writefile({ "Sub-agents" }, vim.fs.joinpath(_G.MEMORY_DIR, "parallel-sub-agents.md"))

    require("codecompanion.memory").refresh_prompt(_G.chat)

    return table.concat(
      vim.tbl_map(function(message)
        return message.content
      end, _G.chat.messages),
      "\n"
    )
  ]])

  h.expect_match(contents, "%- /memories/parallel%-sub%-agents%.md")
end

T["Memory"]["shares the index when Anthropic defines the tool server-side"] = function()
  add_memories()

  local contents = child.lua([[
    local anthropic = require("codecompanion.adapters.http.anthropic")
    _G.chat.tools:refresh({ adapter = anthropic })
    _G.chat.tool_registry:add("memory", { config = _G.chat.tools.tools_config })

    return table.concat(
      vim.tbl_map(function(message)
        return message.content
      end, _G.chat.messages),
      "\n"
    )
  ]])

  h.expect_match(contents, "%- /memories/parallel%-sub%-agents%.md")
end

-- FORK(memory-cwd): the root belongs to a chat
T["Memory"]["root"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.OTHER_ROOT = vim.fs.joinpath(vim.fn.tempname(), "memories")
        vim.fn.mkdir(_G.OTHER_ROOT, "p")
        vim.fn.writefile({ "in other" }, vim.fs.joinpath(_G.OTHER_ROOT, "other.md"))
      ]])
    end,
    post_case = function()
      child.lua([[pcall(vim.fn.delete, vim.fs.dirname(_G.OTHER_ROOT), "rf")]])
    end,
  },
})

T["Memory"]["root"]["defaults to the cwd"] = function()
  local roots = child.lua([[
    local memory = require("codecompanion.memory")
    return { expected = vim.fs.joinpath(vim.fn.getcwd(), "memories"), bare = memory.get_root(), chat = memory.get_root(_G.chat) }
  ]])

  h.eq(roots.expected, roots.bare)
  h.eq(roots.expected, roots.chat)
end

T["Memory"]["root"]["is the chat's own once set"] = function()
  local res = child.lua([[
    local memory = require("codecompanion.memory")
    _G.chat._memory_root = _G.OTHER_ROOT
    return { root = memory.get_root(_G.chat), prompt = memory.get_prompt(_G.chat) }
  ]])

  h.eq(child.lua_get("_G.OTHER_ROOT"), res.root)
  h.expect_match(res.prompt, "%- /memories/other%.md")
end

T["Memory"]["root"]["is where a chat's tool call resolves"] = function()
  child.lua([[
    -- The case's chat, since a new one can't load the test config once the cwd has moved
    local chat, tools = _G.chat, _G.chat.tools
    require("codecompanion.interactions.chat.tools.approvals"):set_mode(chat.bufnr, { mode = "yolo" })
    chat._memory_root = _G.OTHER_ROOT
    _G.call_chat = chat

    local n = #chat.messages
    tools:execute(chat, {
      {
        id = "root_call",
        type = "function",
        ["function"] = {
          name = "memory",
          arguments = vim.json.encode({ command = "view", path = "/memories/other.md" }),
        },
      },
    })
    vim.wait(5000, function()
      return #chat.messages > n and chat.tool_orchestrator == nil
    end, 10)
  ]])

  h.expect_contains("in other", child.lua_get("_G.call_chat.messages[#_G.call_chat.messages].content"))
end
-- /FORK(memory-cwd)

return T
