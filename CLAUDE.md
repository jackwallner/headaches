# CLAUDE.md — HeadacheLogger

## Simulator — dedicated, headless (required)

This project owns the simulator device `agent-headaches`. Multiple agents work in
parallel on this machine: NEVER build/test against a shared named destination
(e.g. `name=iPhone 17 Pro`) and NEVER open Simulator.app — it steals Jack's
mouse/keyboard. Everything runs headless. Full guide: `~/docs/ios-agent-simulators.md`

```bash
UDID=$(agent-sim boot headaches)        # create if needed + boot headless; prints UDID
xcodebuild -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination "id=$UDID" build
xcodebuild test -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination "id=$UDID"
APP=$(find ~/Library/Developer/Xcode/DerivedData/HeadacheLogger-*/Build/Products -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
xcrun simctl install "$UDID" "$APP" && xcrun simctl launch "$UDID" "$(defaults read "$APP/Info" CFBundleIdentifier)"
axe describe-ui --udid "$UDID"        # inspect UI via accessibility tree
axe tap --label "Continue" --udid "$UDID"   # interact without mouse/keyboard
agent-sim screenshot headaches          # PNG at /tmp/agent-headaches.png
agent-sim shutdown headaches            # free resources when done
```

## TestFlight on every update

After finishing a change and pushing to git, ALWAYS upload a new TestFlight build by
running `./scripts/testflight.sh` — do this unprompted on every push that changes app
code. Jack tests every update on his device and shouldn't have to ask.
