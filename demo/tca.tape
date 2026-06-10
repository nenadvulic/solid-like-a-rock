# Demo tape for solid-like-a-rock — renders tca.gif with vhs.
#
# Requirements:
#   brew install vhs
#   solid-like-a-rock >= v0.7.0 on PATH   (the --tca / isolatePeers release)
#
# Render (from the demo/ directory):
#   vhs tca.tape
#
# The tape is fully reproducible: a hidden setup step re-plants the peer-import
# violation in the fixture before each recording, and a teardown restores it.

Output tca.gif

Set Shell bash
Set FontSize 20
Set Width 1200
Set Height 650
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

# --- Hidden setup: enter the fixture and (re)plant the peer import ----------
Hide
Type "cd fixture-tca"
Enter
Type "sed -i '' '/^import CounterFeature/d' Sources/LoginFeature/LoginFeature.swift"
Enter
Type "sed -i '' 's|^import Models$|import Models\nimport CounterFeature  // ❌ a feature reaching into a sibling feature|' Sources/LoginFeature/LoginFeature.swift"
Enter
Type "clear"
Enter
Show

# --- Scene 1: the rule ------------------------------------------------------
Type "# TCA rule: feature modules are peers — they must not import each other"
Enter
Sleep 1.5s
Type "cat .solid.yml"
Enter
Sleep 4.5s
Type "clear"
Enter

# --- Scene 2: a sibling import slipped into a feature ------------------------
Type "cat Sources/LoginFeature/LoginFeature.swift"
Enter
Sleep 3.5s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 4.5s

# --- Scene 3: fix — features compose through the root, not each other --------
Type "# Fix: drop the sibling import; AppFeature composes the features"
Enter
Sleep 1s
Type "sed -i '' '/^import CounterFeature/d' Sources/LoginFeature/LoginFeature.swift"
Enter
Sleep 1s
Type "solid-like-a-rock lint Sources"
Enter
Sleep 4s

# --- Outro -------------------------------------------------------------------
Type "# Generate this config automatically:  solid-like-a-rock init --tca ."
Enter
Sleep 4s

# --- Hidden teardown: restore the violation for the next recording -----------
Hide
Type "sed -i '' 's|^import Models$|import Models\nimport CounterFeature  // ❌ a feature reaching into a sibling feature|' Sources/LoginFeature/LoginFeature.swift"
Enter
