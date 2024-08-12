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

local function switchIntfImpl()
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

vim.api.nvim_create_user_command(
  'OCamlSwitchIntfImpl', switchIntfImpl, {})

--- treat .mli as separate ocaml_interface filetype

vim.filetype.add { extension = { mli = 'ocaml_interface' } }


if can_require 'lspconfig' then
  local lspconfig = require 'lspconfig'

  local ocamllsp_config = lspconfig.ocamllsp.document_config.default_config
  table.insert(ocamllsp_config.filetypes, 'ocaml_interface')

  local get_language_id = ocamllsp_config.get_language_id

  function ocamllsp_config.get_language_id(bufnr, ftype)
    if ftype == 'ocaml_interface' then return 'ocaml' 
    else return get_language_id(bufnr, ftype) end
  end
end
