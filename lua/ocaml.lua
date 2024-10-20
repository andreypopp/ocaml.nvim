function can_require(module_name)
  local ok,_ = pcall(require, module_name)
  return ok
end

local function get_ocamllsp()
  local cs = vim.lsp.get_active_clients()
  for _, c in ipairs(cs) do
    if c.name == 'ocamllsp' then return c end
  end
end

local function with_ocamllsp(f)
  local c = get_ocamllsp()
  if c then f(c)
  else print('ERROR: ocamllsp is not running') end
end

--- switch between .ml and .mli

local function switchImplIntf()
  with_ocamllsp(function(client)
    local uri = vim.uri_from_bufnr(0)
    local res = client.request_sync(
      'ocamllsp/switchImplIntf', {vim.uri_from_bufnr(0)})
    if res.result then
      for _, uri in ipairs(res.result) do
        vim.api.nvim_command('edit ' .. vim.uri_to_fname(uri))
        return
      end
    end
  end)
end

function documentSymbols()
  local bufnr = vim.api.nvim_get_current_buf()

  local params = {
    uri = vim.uri_from_bufnr(0),
    command = 'outline',
    args = {},
    resultAsSexp = false
  }
  local res = vim.lsp.buf_request_sync(bufnr, 'ocamllsp/merlinCallCompatible', params, 1000)

  local found
  for _, item in ipairs(res) do
    if item.result then
      found = vim.json.decode(item.result.result).value
      break
    end
  end
  if not found then return end
  
  local function format_item(parents, item)
    local prefix = ''
    if item.kind == 'Module' then
      prefix = 'module '
    elseif item.kind == 'Type' then
      prefix = 'type '
    elseif item.kind == 'Value' then
      prefix = 'val '
    elseif item.kind == 'Constructor' then
      prefix = 'constructor '
    elseif item.kind == 'Label' then
      prefix = 'field '
    else
      prefix = item.kind .. ' '
    end
    local padding = string.rep(' ', #parents)
    local name = item.name
    if #parents > 0 then
      name = table.concat(parents, '.') .. '.' .. name
    end
    if item.kind == 'Value' then
      local type = item.type:gsub('\n', ' ')
      name = name .. ' : ' .. type
    end
    return string.format('%s%s%s', padding, prefix, name)
  end

  local data = {}

  local function handle(parents, item)
    local text = format_item(parents, item)
    if item.children and #item.children > 0 then
      local next_parents = vim.list_extend(parents, {item.name})
      for _, child in ipairs(item.children) do
        handle(next_parents, child)
      end
    end
    table.insert(data, {text=text, col=item.start.col, line=item.start.line})
  end

  for _, item in ipairs(found) do
    handle({}, item)
  end

  local rev_data = {}
  for i = #data, 1, -1 do
    table.insert(rev_data, data[i])
  end
  return rev_data
end

---
--- SETUP
---

vim.filetype.add {
  extension = { 
    mli = "ocaml.interface",
    mly = "ocaml.menhir",
    mll = "ocaml.ocamllex",
    t   = "ocaml.cram",
  },
}

vim.treesitter.language.register("ocaml_interface", "ocaml.interface")
vim.treesitter.language.register("menhir", "ocaml.menhir")
vim.treesitter.language.register("ocaml_interface", "ocaml.interface")
vim.treesitter.language.register("cram", "ocaml.cram")
vim.treesitter.language.register("ocamllex", "ocaml.ocamllex")

vim.api.nvim_create_user_command('OCamlSwitchImplIntf', switchImplIntf, {})

if can_require 'lspconfig' then
  local lspconfig = require 'lspconfig'
  lspconfig.util.on_setup = lspconfig.util.add_hook_before(lspconfig.util.on_setup, function(config)
    if config.name == 'ocamllsp' then
      local filetypes = vim.deepcopy(config.filetypes)
      table.insert(filetypes, 'ocaml.interface')
      config.filetypes = filetypes

      local get_language_id = config.get_language_id
      function config.get_language_id(bufnr, ft)
        if ft == 'ocaml.interface' then return 'ocaml.interface'
        else return get_language_id(bufnr, ft) end
      end
    end
  end)
end

if can_require 'fzf' then
  local fzf = require 'fzf'
  local action = require("fzf.actions").action

  local function item_to_line(item)
    return string.format('%s,%s,%s', item.line, item.col, item.text)
  end
  local function line_to_item(line)
    local parts = vim.split(line, ',')
    return {line=tonumber(parts[1]), col=tonumber(parts[2]), text=parts[3]}
  end

  local c_bold = '\027[1m'
  local c_reset = '\027[0m'

  local function get_buffer_lines(bufnr, line, height)
    local s = math.max(math.floor(line - height / 2), 0)
    local e = math.floor(line + height / 2)
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local lines = vim.api.nvim_buf_get_lines(bufnr, s, e, false)
      lines[line - s] = c_bold .. lines[line - s] .. c_reset
      return lines
    end
  end

  local function fzf_documentSymbols()
    local bufnr = vim.api.nvim_get_current_buf()
    local symbols = documentSymbols()
    if not symbols then return vim.api.nvim_err_writeln('No symbols found') end
    local lines = {}
    for _, item in ipairs(symbols) do
      table.insert(lines, item_to_line(item))
    end
    local preview = action(function (lines, height, width)
      local item = line_to_item(lines[1])
      return get_buffer_lines(bufnr, item.line, height)
    end)
    coroutine.wrap(function()
      local lines = fzf.fzf(lines, string.format('--delimiter=, --with-nth=3.. --layout=reverse-list --preview=%s', preview))
      vim.schedule(function()
        if #lines < 1 then return end
        local item = line_to_item(lines[1])
        vim.api.nvim_win_set_cursor(0, {item.line, item.col})
        vim.cmd('normal! zz')
      end)
    end)()
  end

  vim.api.nvim_create_user_command('OCamlDocumentSymbols', fzf_documentSymbols, {})
end

return {
  switchImplIntf = switchImplIntf,
  documentSymbols = documentSymbols,
}
