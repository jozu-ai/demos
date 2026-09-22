# Records ./mcp-trust.sh end to end, unattended.
#
#   ./setup.sh          # once: registry up, keys and bundled deps in place
#   vhs mcp-trust.tape  # -> mcp-trust-demo.mp4
#
# The typing animation is demo-magic's own (pv at TYPE_SPEED=70), not VHS's.
# `-w2` makes demo-magic auto-advance after 2s instead of waiting for ENTER,
# so nothing here has to press keys for it.

Output mcp-trust-demo.mp4

Require mcpb
Require kit
Require cosign
Require crane
Require jq
Require pv

Set Shell "bash"
Set Theme "Catppuccin Mocha"
Set FontFamily "Hack"
Set FontSize 19
# 2560x1440 at 19px Hack measures 207 cols x 63 rows. mcp-trust.sh disables
# line wrapping, so anything wider than the terminal is silently truncated
# rather than wrapped. Its widest line is now 188 columns - cosign tree's own
# referrer output, which cannot be reflowed - so 19px leaves 19 columns spare.
# Raising it past 20px (191 cols) starts clipping.
Set Width 2560
Set Height 1440
Set Padding 20
Set Framerate 30

# Clean slate off camera: no stale manifest, empty registry, untampered bundle.
Hide
Type "cd /Users/gorkem/workspaces/jozu/demos/cli-demos/mcpb-trust"
Enter
Type "./reset.sh >/dev/null 2>&1 && clear"
Enter
Sleep 3s
Show

Sleep 1500ms
Type "./mcp-trust.sh -w2"
Enter

# 29 steps x 2 pauses x 2s of demo-magic waits, plus ~55s of real work.
Sleep 170s

# Let the final verification sit on screen before the video ends.
Sleep 6s
