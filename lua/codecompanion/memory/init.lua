local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local tags = require("codecompanion.interactions.shared.tags")

local fmt = string.format

local M = {}

M.DIR = "memories"
M.PREFIX = "/" .. M.DIR

-- FORK(memory-cwd): the root follows the chat's own window, and is fixed once per request
---The window showing the chat, preferring the chat's own
---@param chat CodeCompanion.Chat
---@return number|nil
local function chat_win(chat)
  local winnr = chat.ui and chat.ui.winnr
  if winnr and vim.api.nvim_win_is_valid(winnr) and vim.api.nvim_win_get_buf(winnr) == chat.bufnr then
    return winnr
  end
  return require("codecompanion.utils.ui").buf_get_win(chat.bufnr)
end

---The working directory a chat's memory follows: its window's effective cwd, the one it had when last
---shown while it is hidden, and the global cwd for a chat that has never had a window
---@param chat CodeCompanion.Chat
---@return string
function M.chat_cwd(chat)
  local winnr = chat_win(chat)
  if winnr then
    -- Without the tab, getcwd resolves the window in the current tab
    local tabnr = vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(winnr))
    chat._memory_cwd = vim.fn.getcwd(winnr, tabnr)
    return chat._memory_cwd
  end
  return chat._memory_cwd or vim.fn.getcwd(-1, -1)
end

---The absolute path to the memory directory
---@param chat? CodeCompanion.Chat
---@return string
function M.get_root(chat)
  if not chat then
    return vim.fs.joinpath(vim.fn.getcwd(), M.DIR)
  end
  return chat._memory_root or vim.fs.joinpath(M.chat_cwd(chat), M.DIR)
end

---Fix a chat's root for the request about to be sent, and bring its index in line if the root moved
---@param chat CodeCompanion.Chat
---@return nil
function M.sync_root(chat)
  local root = vim.fs.joinpath(M.chat_cwd(chat), M.DIR)
  if root ~= chat._memory_root then
    chat._memory_root = root
    M.refresh_prompt(chat)
  end
end
-- /FORK(memory-cwd)

-- FORK(memory-cwd): index the chat's own root
---Every memory, addressed the way the LLM must pass it back to the memory tool
---@param chat? CodeCompanion.Chat
---@return string[]
function M.get_index(chat)
  local root = M.get_root(chat)
  -- /FORK(memory-cwd)
  if not files.is_dir(root) then
    return {}
  end

  local paths = vim
    .iter(files.scan_directory(root))
    :map(function(path)
      return M.PREFIX .. path:sub(#root + 1)
    end)
    :totable()
  table.sort(paths)

  return paths
end

---@return string[]
local function get_whitelisted_paths()
  local tool_config = config.interactions.chat.tools["memory"]
  local whitelist = tool_config and tool_config.opts and tool_config.opts.whitelist or {}

  local paths = {}
  for _, entry in ipairs(whitelist) do
    if entry.path and entry.as then
      local prefix = vim.startswith(entry.as, "/") and entry.as or ("/" .. entry.as)
      table.insert(paths, fmt("  - %s (mounted at %s)", entry.path, prefix))
    end
  end

  return paths
end

-- FORK(memory-cwd): describe the chat's own root
---Tell the LLM what it has stored, and how to name what it stores next
---@param chat? CodeCompanion.Chat
---@return string
function M.get_prompt(chat)
  local index = M.get_index(chat)
  -- /FORK(memory-cwd)

  -- FORK(memory-cwd): name the directory /memories stands for, so the model can tell when it moves
  local where = fmt("`%s` (`%s`)", M.PREFIX, vim.fn.fnamemodify(M.get_root(chat), ":~"))
  local lines = {}
  if vim.tbl_isempty(index) then
    table.insert(lines, fmt("Your memory directory %s is empty.", where))
  else
    table.insert(lines, fmt("Below is everything in your memory directory %s:", where))
    -- /FORK(memory-cwd)
    table.insert(lines, "")
    vim.list_extend(
      lines,
      vim.tbl_map(function(path)
        return "- " .. path
      end, index)
    )
    table.insert(lines, "")
    table.insert(
      lines,
      "- That index is complete, so you never need to list the directory to see what you have stored."
    )
  end

  vim.list_extend(lines, {
    "- Read a memory only when its name matches what you have been asked about, and read one rather than several.",
    "- If no name matches, say that you have no memory on that topic instead of opening files to find out.",
    "- Save important decisions, summaries and insights from the conversation as new memories.",
    "- Name a memory so that the file name alone says what it holds: `parallel-sub-agents.md`, not `notes.md`. Rename any memory whose name fails that test.",
    "- Prefer updating an existing memory over creating a new one, unless the topic is new.",
    "- Say which memory you drew on when you continue or summarise an earlier conversation.",
  })

  local whitelisted = get_whitelisted_paths()
  if #whitelisted > 0 then
    table.insert(lines, fmt("- Alongside %s, you can also read and write to these paths:", M.PREFIX))
    vim.list_extend(lines, whitelisted)
  end

  return table.concat(lines, "\n")
end

---Bring a chat's index back in line with what is on disk, after the tool has changed it
---@param chat CodeCompanion.Chat
---@return nil
function M.refresh_prompt(chat)
  local id = require("codecompanion.interactions.chat.tool_registry").tool_id("memory")

  for _, message in ipairs(chat.messages) do
    if message.context and message.context.id == id and message._meta and message._meta.tag == tags.TOOL then
      -- FORK(memory-cwd): refresh against the chat's own root
      message.content = M.get_prompt(chat)
      -- /FORK(memory-cwd)
      return
    end
  end
end

return M
