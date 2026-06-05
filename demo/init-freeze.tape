# Demo tape: adopt solid-like-a-rock on an existing codebase with `init --freeze`.
# Renders init-freeze.gif with vhs.
#
# Render (from the demo/ directory):
#   vhs init-freeze.tape
#
# Reproducible: hidden setup removes any generated .solid.yml and the
# planted violation before each recording.

Output init-freeze.gif

Set Shell bash
Set FontSize 20
Set Width 1200
Set Height 650
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- Hidden setup: clean slate ---------------------------------------------
Hide
Type "cd fixture-init"
Enter
Type "rm -f .solid.yml && sed -i '' '/^import Data$/d' Sources/Presentation/HomeView.swift"
Enter
Type "clear"
Enter
Show

# --- Scene 1: generate the config from the real import graph ----------------
Type "# Existing codebase, no config? Freeze today's architecture:"
Enter
Sleep 1.5s
Type "solid-like-a-rock init --freeze ."
Enter
Sleep 2s
Type "cat .solid.yml"
Enter
Sleep 4s
Type "clear"
Enter

# --- Scene 2: zero violations today ------------------------------------------
Type "solid-like-a-rock lint Sources"
Enter
Sleep 3s

# --- Scene 3: it bites the moment a new cross-module dep appears -------------
Type "# Months later, a new cross-module dependency slips in..."
Enter
Sleep 1s
Type "echo 'import Data' >> Sources/Presentation/HomeView.swift"
Enter
Sleep 1s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 4.5s

# --- Hidden teardown: restore the clean fixture -------------------------------
Hide
Type "rm -f .solid.yml && sed -i '' '/^import Data$/d' Sources/Presentation/HomeView.swift"
Enter
