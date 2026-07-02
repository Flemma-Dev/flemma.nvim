Output assets/flemma_cast.mp4
Output assets/flemma_cast.gif

Set Shell bash
Set Width 1920
Set Height 1080
Set Framerate 30
Set Padding 8
Set Theme "Catppuccin Mocha"
Set FontFamily "IBM Plex Mono"
Set FontSize 32
Set LetterSpacing 0
Set LineHeight 1
Set PlaybackSpeed 1.0
Set WaitTimeout 120s

Hide
Type@0ms "cd .vapor/northwind/"
Enter
Type@0ms "cat > weekly-status.chat"
Enter
Type@0ms "@You:"
Enter 2
Ctrl+D
Type@0ms "clear"
Enter
Show

Sleep 1000ms
Type "nvim weekly-status.chat"
Sleep 1000ms
Enter
Type "G"
Sleep 800ms
Type "i"
Type "Write a crisp weekly status update for the leadership channel."
Enter
Sleep 250ms
Type "Pull last Friday's standup with your tools, and cover what shipped, what's blocked,"
Enter
Sleep 50ms
Type "and the action items with owners."
Sleep 250ms
Type " Keep it tight."
Ctrl+[
Sleep 1200ms
Ctrl+]
Wait+Screen /Engineering Sync/
Sleep 2000ms
Wait+Screen /FlemmaBeacon1/
Sleep 2500ms

Type "zm"
Sleep 2500ms

Type ":Flemma switch $haiku"
Sleep 1000ms
Enter
Sleep 1800ms

Type "GA"
Type "Now pick out just the things that are on me, Stan."
Ctrl+[
Sleep 1200ms
Ctrl+]
Wait+Screen /FlemmaBeacon2/
Sleep 4000ms
