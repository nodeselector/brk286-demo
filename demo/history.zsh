# Seed this shell's Ctrl-R history with the stage commands in history.txt:
#   . demo/history.zsh
# Swaps in a history list that holds only those commands and lives in memory:
# nothing is read from or written to ~/.zsh_history. `fc -P` brings yours back.
fc -p
fc -R "${${(%):-%x}:A:h}/history.txt"
