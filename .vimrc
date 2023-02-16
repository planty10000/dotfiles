" VIM config
syntax on                               "Syntax highlighting
set number                              "Line numbers
set softtabstop=4 tabstop=4
set shiftwidth=4
set expandtab                           "convert tabs to space
set smartindent                         "try to indent for me
set nowrap                              "don't screen wrap
set smartcase
set incsearch                           "display search results as you type
set ruler
set showcmd                             "Show commmand
"set cursorline                         "highlight the cursor location
filetype indent on                      "Filetype detection
set showmatch                           "Highlight matching brackets
set wildmenu                            "Better command-line completion
set wildmode=longest,list,full

" Highlight searches (use <C-L> to temporarily turn off highlighting; see the
" mapping of <C-L> below)
"set hlsearch
set encoding=utf8                       "set encoding so glyphs can be displayed in VIM

" +------------------+
" |  Key bindings    |
" +------------------+
let mapleader = " "                     "map leader to Space

inoremap jj <Esc> 

" enable copy/paste using system clipboard
vnoremap <C-c> "+y
map <C-p> "+p

" Map <C-L> (redraw screen) to also turn off search highlighting until the next search
"nnoremap <C-L> :nohl<CR><C-L>

" split: moving between windows
nmap <C-h> <C-w>h
nmap <C-j> <C-w>j
nmap <C-k> <C-w>k
nmap <C-l> <C-w>l

" +-------------------------+
" | Leader Key bindings  	|
" +-------------------------+
" turn off highlighting
map <leader>h :noh<CR>
nnoremap <Leader>+ :vertical resize +5<CR>
nnoremap <Leader>- :vertical resize -5<CR>
nnoremap <leader>u :UndotreeShow<CR>
