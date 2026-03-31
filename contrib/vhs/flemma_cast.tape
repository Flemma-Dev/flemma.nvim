Output assets/flemma_cast.mp4

Set Shell bash
Set Width 1920
Set Height 1080
Set Framerate 60
Set Padding 8
Set Theme "Catppuccin Mocha"
Set FontFamily "IBM Plex Mono"
Set FontSize 32
Set LetterSpacing 0
Set LineHeight 1

Hide
Type@0ms "cd .vapor/aurora/"
Enter
Type@0ms "cat > release.chat"
Enter
Type@0ms "```lua"
Enter
Type@0ms `version = "v0.4.0"`
Enter
Type@0ms "```"
Enter
Type@0ms "@System:"
Enter
Type@0ms `You are a release engineer for the Aurora project. Today is {{ os.date("%B %d, %Y") }}.`
Enter
Type@0ms "The current version being released is {{ version }}."
Enter
Type@0ms "Be very concise in your responses - answer the question in as few words as possible."
Enter 2
Type@0ms "@You:"
Enter 2
Ctrl+D
Type@0ms "clear"
Enter
Show

Sleep 1000ms
Type "nvim release.chat"
Sleep 1000ms
Enter
Type "G"
Sleep 1000ms
Type "i"
Type "We're cutting {{ version }} today."
Enter
Sleep 200ms
Type "Can you draft a short tagline announcement for the GitHub release page - just one sentence?"
Enter
Sleep 200ms
Type "Check the recent Git history for what changed."
Ctrl+[
Sleep 2000ms
Ctrl+]
Wait+Screen /╰/
Sleep 2500ms
Type "GA"
Type "Nice. One thing - we replaced the old thread-per-request model this cycle."
Enter
Sleep 200ms
Type "Can you check @./docs/architecture.pdf and confirm it no longer references the old approach?"
Ctrl+[
Sleep 2000ms
Ctrl+]
Wait+Screen /managed goroutine/
Sleep 3000ms
Type "GA"
Type "All done! Let's fold and review the conversation at a glance."
Ctrl+[
Sleep 3000ms
Type "zm"
Sleep 5000ms
