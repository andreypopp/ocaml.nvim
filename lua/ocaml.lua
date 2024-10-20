local uv = vim.loop

local function can_require(module_name)
  local ok,_ = pcall(require, module_name)
  return ok
end

local function get_ocamllsp()
  local cs = vim.lsp.get_clients {name='ocamllsp'}
  for _, c in ipairs(cs) do if c.name == 'ocamllsp' then return c end end
end

local function with_ocamllsp(f)
  local c = get_ocamllsp()
  if c then return f(c)
  else return vim.api.nvim_err_writeln('ocamllsp is not running') end
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

local function merlinRequest(command, args, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return with_ocamllsp(function(lsp)
    local params = {
      uri = vim.uri_from_bufnr(0),
      command = command,
      args = args or {},
      resultAsSexp = false
    }
    local res = lsp.request_sync('ocamllsp/merlinCallCompatible', params, 1000, bufnr)
    if res.error then return vim.api.nvim_err_writeln('ERROR: ' .. vim.inspect(res.error)) end
    return vim.json.decode(res.result.result).value
  end)
end

local function co_merlinRequest(command, args, bufnr)
  return with_ocamllsp(function(lsp)
    local params = {
      uri = vim.uri_from_bufnr(bufnr),
      command = command,
      args = args or {},
      resultAsSexp = false
    }
    local me = coroutine.running()
    local handler = function(err, res) 
      local value
      if res ~= nil then value = vim.json.decode(res.result).value end
      coroutine.resume(me, err, value) end
    lsp.request('ocamllsp/merlinCallCompatible', params, handler, bufnr)
    return coroutine.yield()
  end)
end

local function documentSymbols()
  local bufnr = vim.api.nvim_get_current_buf()
  local value = merlinRequest('outline')
  if not value then return end
  
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

  for _, item in ipairs(value) do
    handle({}, item)
  end

  local rev_data = {}
  for i = #data, 1, -1 do
    table.insert(rev_data, data[i])
  end
  return rev_data
end

local function get_merlin_pos(winnr)
  winnr = winnr or 0
  local pos = vim.api.nvim_win_get_cursor(winnr)
  return string.format('%d:%d', pos[1], pos[2])
end

local function searchByType(query, bufnr, winnr)
  local pos = get_merlin_pos(winnr)
  return co_merlinRequest('search-by-type', { query = query, position = pos }, bufnr)
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
  local raw_async_action = require("fzf.actions").raw_async_action

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
      local args = {
        "--prompt='DocumentSymbols> '",
        "--delimiter=,",
        "--with-nth=3..",
        "--layout=reverse-list",
        "--preview=" .. preview,
      }
      local cmd = table.concat(args, ' ')
      local lines = fzf.fzf(lines, cmd, {title='DocumentSymbols'})
      vim.schedule(function()
        if not lines or #lines < 1 then return end
        local item = line_to_item(lines[1])
        vim.api.nvim_win_set_cursor(0, {item.line, item.col})
        vim.cmd('normal! zz')
      end)
    end)()
  end

  vim.api.nvim_create_user_command('OCamlDocumentSymbols', fzf_documentSymbols, {})


  local function insert_at_position(text)
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_text(0, pos[1] - 1, pos[2] - 1, pos[1] - 1, pos[2] - 1, {text})
  end

  local function fzf_searchByType(opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local winnr = vim.api.nvim_get_current_win()
    local last_value = {}

    local function search(query, with_newline)
      if not query or query == '' then return nil, {} end
      local newline = with_newline and '\n' or ''
      local err, value = searchByType(query, bufnr, winnr)
      if err then return err end
      last_value = value
      local lines = {}
      for idx, item in ipairs(value) do
        local line = string.format('%d,%s : %s%s', idx,item.name, item.type, newline)
        table.insert(lines, line)
      end
      return nil, lines
    end

    local on_change = raw_async_action(function (oc, args)
      coroutine.wrap(function()
        local query = args[2]
        local err, lines = search(query, true)
        if err then
          uv.close(oc)
          return vim.api.nvim_err_writeln('ERROR: ' .. vim.inspect(err))
        end
        for _, line in ipairs(lines) do uv.write(oc, line) end uv.close(oc)
      end)()
    end)

    local query = opts.fargs[1]
    local args = {
      "--prompt='SearchByType> '",
      "--delimiter=,",
      "--with-nth=2..",
      "--layout=reverse-list",
      "--disabled",
      vim.fn.shellescape(string.format('--bind=change:reload:%s {q}', on_change))
    }
    if query then table.insert(args, string.format('--query=%s', vim.fn.shellescape(query))) end
    local cmd = table.concat(args, ' ')

    coroutine.wrap(function()
      local err, lines = search(query, false)
      if err then return vim.api.nvim_err_writeln('ERROR: ' .. vim.inspect(err)) end
      local res = fzf.fzf(lines, cmd)
      vim.schedule(function()
        if not res or #res < 1 then return end
        local parts = vim.split(res[1], ',')
        local idx = tonumber(parts[1])
        local item = last_value[idx]
        if not item then return end
        insert_at_position('('..item.constructible..')')
      end)
    end)()
  end

  vim.api.nvim_create_user_command('OCamlSearchByType', fzf_searchByType, {nargs='?'})
end


return {
  switchImplIntf = switchImplIntf,
  documentSymbols = documentSymbols,
  searchByType = searchByType,
}
