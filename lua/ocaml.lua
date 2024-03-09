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
