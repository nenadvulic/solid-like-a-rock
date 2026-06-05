# Demo tape: adopt solid-like-a-rock on a codebase with existing violations
# using a baseline — only NEW violations fail. Renders baseline.gif with vhs.
#
# Render (from the demo/ directory):
#   vhs baseline.tape
#
# Uses the same fixture as demo.tape (its resting state has one violation).
# Reproducible: hidden teardown removes the generated baseline file.

Output baseline.gif

Set Shell bash
Set FontSize 20
Set Width 1200
Set Height 650
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- Hidden setup -------------------------------------------------------------
Hide
Type "cd fixture"
Enter
Type "rm -f .solid-baseline.json && sed -i '' 's|^import Domain.*$|import Data  // ❌ UI reaching straight into the data layer|' Sources/Presentation/HomeView.swift"
Enter
Type "clear"
Enter
Show

# --- Scene 1: a legacy project with existing violations ------------------------
Type "# Legacy codebase: existing violations you can't fix today"
Enter
Sleep 1.5s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 3.5s

# --- Scene 2: record them in a baseline -----------------------------------------
Type "solid-like-a-rock lint --write-baseline .solid-baseline.json Sources"
Enter
Sleep 3s

# --- Scene 3: lint passes — only NEW violations will fail ------------------------
Type "solid-like-a-rock lint --baseline .solid-baseline.json Sources"
Enter
Sleep 3s
Type "# Ship it. The linter only fails on NEW violations."
Enter
Sleep 4s

# --- Hidden teardown --------------------------------------------------------------
Hide
Type "rm -f .solid-baseline.json"
Enter
