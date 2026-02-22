Output assets/flemma_cast.mp4

Set Shell bash
Set Width 1920
Set Height 1080
Set Padding 8
Set Theme "Catppuccin Frappe"
Set FontFamily "Adwaita Mono"
Set FontSize 32
Set LetterSpacing 0
Set LineHeight 1

# Start NeoVim, install treesitters, quit.
Hide
Type@10ms "nvim"
Enter
Sleep 5000ms
Type ":q"
Enter
Type "clear"
Enter
Show

Sleep 1000ms
Type "nvim .vapor/scratch.chat"
Sleep 1000ms
Enter
Type "G"
Sleep 1000ms
Type "Gi"
Enter
Type@40ms "@You: "
Ctrl+[
Sleep 200ms
Type@40ms "aHello, My name's {{ name }}!"
Sleep 200ms
Enter
Sleep 500ms
Type@40ms "Calculate the expression embedded in "
Sleep 200ms
Type@40ms "@./math.png."
Sleep 200ms
Ctrl+[
Sleep 1000ms
Ctrl+]
Sleep 1000ms
Wait+Line /@You:/
Sleep 3000ms
Type@40ms ":Okay, quick review of tool use…"
Sleep 2000ms
Type@40ms " looks okay to approve!"
Sleep 2000ms
Ctrl+[
Sleep 1000ms
Alt+Enter
Sleep 1000ms
Wait+Line /@You:/
Sleep 4000ms
Type@40ms "amath.png is not needed anymore, get rid of it."
Sleep 500ms
Ctrl+[
Type "mm"
Type@40ms "?math.png"
Enter
Sleep 1000ms
Type "n"
Sleep 2000ms
Type "dd"
Sleep 1000ms
Type "`m"
Sleep 1000ms
Type "a"
Enter
Type@40ms "(Got rid of the file reference so Flemma won't complain it's missing)"
Enter
Sleep 1000ms
Type@40ms "(Oh... and Bash is in auto-approve mode, YOLO!)"
Enter
Ctrl+[
Sleep 2000ms
Hide
Type ":nohlsearch"
Enter
Type ":call clearmatches()"
Enter
Show
Ctrl+]
Sleep 1000ms
Wait+Line /@You:/
Sleep 100ms
Wait+Line /@Assistant: Thinking…/
Sleep 100ms
Wait+Line /@You:/
Sleep 2000ms
Type@40ms "GAGreat stuff, all done."
Sleep 10000ms
