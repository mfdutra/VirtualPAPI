# Xcode Build Skill

When building the VirtualPAPI Xcode project, ALWAYS use the latest iPad mini simulator.

## Build Command

Use this command pattern for all test builds:

```bash
xcodebuild -scheme VirtualPAPI -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=latest' build
```

## Alternative: Find Latest iPad mini

If the above fails, use this to find the exact latest iPad mini:

```bash
xcodebuild -showdestinations -scheme VirtualPAPI 2>&1 | grep "iPad mini" | sort -t, -k3 -V | tail -1
```

Then extract the name and OS version from the output and use it in the build command.

## Simplified Approach

For most builds, just use:

```bash
xcodebuild -scheme VirtualPAPI -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' build
```

This will automatically select the latest available OS version for that device.

## Important Notes

- ALWAYS use iPad mini for test builds (not iPhone)
- The simulator name is "iPad mini (A17 Pro)"
- Don't specify OS version unless necessary - xcodebuild will use the latest
- This is the user's preferred testing device
