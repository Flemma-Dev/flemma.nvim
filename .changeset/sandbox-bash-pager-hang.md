---
"@flemma-dev/flemma.nvim": patch
---

Fixed the sandboxed `bash` tool hanging on Neovim 0.12+ when a command invokes an interactive pager. The 0.12+ terminal (PTY) backend gives commands a tty on stdout, so `git` (and `less`/`man`) launch the user's pager; the window-less terminal buffer's PTY is only a few rows tall, so any multi-line output (such as `git log`) pages and blocks until the tool times out. The terminal backend now sets `GIT_PAGER=cat` and `PAGER=cat`, matching the non-PTY backend's behavior (piped stdout never triggers a pager). This also resolves the earlier "Error: missing file" symptom, which was the same pager failing fast under bubblewrap's `--new-session`.
