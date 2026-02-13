Output assets/flemma_cast.mp4

Set Shell bash
Set Width 1920
Set Height 1080
Set FontFamily "BerkeleyMono Nerd Font Mono"
Set FontSize 28
Set Theme "Dracula"

# Start Neovim.
Sleep 1000ms
Type "nvim .vapor/scratch.chat"
Sleep 500ms
Enter
# Move cursor to the end of the file.
Type "G"
Sleep 1000ms
# Type "@You:" and let Flemma refresh the UI.
Type "Gi@You: "
Ctrl+[
Sleep 200ms
# Type the user prompt.
Type@40ms "aHello, I'm {{ name }}! Help me OCR the following image, then solve the embedded expression."
Enter 2
Sleep 200ms
Type@40ms "@./math.png"
Enter
Sleep 1000ms
# Send the message and await Flemma's response.
Ctrl+[
Sleep 100ms
Ctrl+]
Wait+Line /@You:/
Sleep 2000ms
# Add pending tool results.
Type@40ms "a-- Okay, calculator use! I'll add the tool to my next message, pause, then execute and merge the  result."
Ctrl+[
Sleep 4000ms
Type u
Sleep 1000ms
Ctrl+]
# Note tool use will take 1s as per system prompt.
Sleep 4000ms
Ctrl+]
Sleep 2000ms
# Send the message with tool results and await Flemma's response.
Ctrl+]
Sleep 1000ms
Wait+Line /@You:/
Sleep 2000ms
# Clean up.
Type@40ms "aGreat! I don't need math.png anymore - delete it for me using `trash`."
Ctrl+[
Sleep 4000ms
Ctrl+]
Sleep 1000ms
Wait+Line /@You:/
Sleep 1000ms
# Tool Use: bash -c trash math.png
Ctrl+]
# Note tool use will take approx. 1s to complete.
Sleep 4000ms
Ctrl+]
Sleep 2000ms
# The End.
Type@40ms "GA"
Enter 2
Type "-- The End."
Sleep 5000ms
