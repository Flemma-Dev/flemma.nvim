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
Type "GA"
Sleep 200ms
Type@40ms "Is that more or less than the GB of RAM I have?"
Sleep 200ms
Ctrl+[
Sleep 1000ms
Ctrl+]
Sleep 1000ms
Wait+Line /@You:/
Sleep 2000ms
Type "GA"
Sleep 200ms
Type@40ms "Great stuff, all done."
Sleep 10000ms
