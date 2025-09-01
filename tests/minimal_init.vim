" Add the project root to the runtime path to find the 'lua' directory
let &rtp = &rtp . ',' . expand('$PROJECT_ROOT')

" Add plenary to the runtime path
let &rtp = &rtp . ',' . expand('$PLENARY_PATH')
