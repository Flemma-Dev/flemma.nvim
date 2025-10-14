" Add the project root to the runtime path to find the 'lua' directory
let s:project_root = $PROJECT_ROOT
if empty(s:project_root)
  echom "Error: PROJECT_ROOT must be set."
  echom "Please run this from within the 'nix develop' shell."
  cquit
endif
execute 'set rtp+=' . s:project_root

" Add plenary to the runtime path
let s:plenary_path = $PLENARY_PATH
if empty(s:plenary_path)
  echom "Error: PLENARY_PATH must be set."
  echom "Please run this from within the 'nix develop' shell."
  cquit
endif
execute 'set rtp+=' . s:plenary_path

" Load plenary plugin, which is now in the runtime path
runtime plugin/plenary.vim
