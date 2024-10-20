# ocaml.nvim

This is a neovim plugin for OCaml development. It builds on top of neovim's LSP
support and provides methods/handlers for ocamllsp specific features.

## features

- `:OCamlSwitchImplIntf` command swicthes between `.ml` and `.mli` files.
- `:OCamlDocumentSymbols` command lists all symbols in the current buffer. This
  is similar to standard `:LspDocumentSymbols` formats symbols nicely for OCaml
  and also includes type information. Requires [nvim-fzf][].
- `:OCamlSearchByType` seaches by values by type. Requires [nvim-fzf][].

[nvim-fzf]: https://github.com/vijaymarupudi/nvim-fzf
