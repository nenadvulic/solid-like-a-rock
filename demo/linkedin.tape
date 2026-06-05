# LinkedIn-optimised demo: native MP4, square 1080x1080, large font,
# hook in the first seconds, ~35s total.
#
# Render (from the demo/ directory):
#   vhs linkedin.tape
#
# The output (linkedin.mp4) is a social asset — not committed; re-render on demand.

Output linkedin.mp4

Set Shell bash
Set FontSize 26
Set Width 1080
Set Height 1080
Set Padding 32
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms

# --- Hidden setup: enter the fixture and (re)plant the violation ----------
Hide
Type "cd fixture"
Enter
Type "sed -i '' 's|^import Domain.*$|import Data  // ❌ UI reaching straight into the data layer|' Sources/Presentation/HomeView.swift"
Enter
Type "clear"
Enter
Show

# --- Hook (first 3 seconds) -------------------------------------------------
Type "# AI writes code faster than you can review it."
Enter
Sleep 1.5s
Type "# Who is guarding your architecture?"
Enter
Sleep 2s

# --- Scene 1: the violation, caught -----------------------------------------
Type "solid-like-a-rock lint Sources"
Enter
Sleep 3.5s

# --- Scene 2: the offending code ---------------------------------------------
Type "cat Sources/Presentation/HomeView.swift"
Enter
Sleep 3.5s

# --- Scene 3: fix, green ------------------------------------------------------
Type "# Fix: depend on the Domain layer instead"
Enter
Sleep 1s
Type "sed -i '' 's|^import Data.*$|import Domain|' Sources/Presentation/HomeView.swift"
Enter
Sleep 1s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 3.5s

# --- Outro ---------------------------------------------------------------------
Type "clear"
Enter
Type "# SolidLikeARock — architectural guardrail for Swift"
Enter
Sleep 1s
Type "# brew tap nenadvulic/solid-like-a-rock"
Enter
Type "# brew install solid-like-a-rock"
Enter
Sleep 1s
Type "# github.com/nenadvulic/solid-like-a-rock"
Enter
Sleep 4s

# --- Hidden teardown: restore the violation for the next recording ------------
Hide
Type "sed -i '' 's|^import Domain.*$|import Data  // ❌ UI reaching straight into the data layer|' Sources/Presentation/HomeView.swift"
Enter
