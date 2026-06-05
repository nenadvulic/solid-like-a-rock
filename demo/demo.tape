# Demo tape for solid-like-a-rock — renders demo.gif with vhs.
#
# Requirements:
#   brew install vhs
#   brew install solid-like-a-rock   (or have it on PATH)
#
# Render (from the demo/ directory):
#   vhs demo.tape
#
# The tape is fully reproducible: a hidden setup step re-plants the
# architecture violation in the fixture before each recording.

Output demo.gif

Set Shell bash
Set FontSize 20
Set Width 1200
Set Height 650
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- Hidden setup: enter the fixture and (re)plant the violation ----------
Hide
Type "cd fixture"
Enter
Type "sed -i '' 's|^import Domain.*$|import Data  // ❌ UI reaching straight into the data layer|' Sources/Presentation/HomeView.swift"
Enter
Type "clear"
Enter
Show

# --- Scene 1: the rules ----------------------------------------------------
Type "# Clean Architecture rule: Presentation must not import Data"
Enter
Sleep 1.5s
Type "cat .solid.yml"
Enter
Sleep 4s
Type "clear"
Enter

# --- Scene 2: a violation slipped into the code -----------------------------
Type "cat Sources/Presentation/HomeView.swift"
Enter
Sleep 3.5s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 4s

# --- Scene 3: fix the import, lint goes green --------------------------------
Type "# Fix: depend on the Domain layer instead"
Enter
Sleep 1s
Type "sed -i '' 's|^import Data.*$|import Domain|' Sources/Presentation/HomeView.swift"
Enter
Sleep 1s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 4s

# --- Outro -------------------------------------------------------------------
Type "# brew tap nenadvulic/solid-like-a-rock && brew install solid-like-a-rock"
Enter
Sleep 4s

# --- Hidden teardown: restore the violation for the next recording ----------
Hide
Type "sed -i '' 's|^import Domain.*$|import Data  // ❌ UI reaching straight into the data layer|' Sources/Presentation/HomeView.swift"
Enter
