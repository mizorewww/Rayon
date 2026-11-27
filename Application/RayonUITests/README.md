# Rayon UI tests

Smoke tests that drive the iOS app on a simulator: launch, the shared
Settings layout and font picker, and a Quick Connect session in the Ghostty
terminal (to a closed local port, so no server is contacted).

```sh
# 1. Build and install the app on a simulator
xcodebuild -workspace App.xcworkspace -scheme Rayon \
  -destination "id=$SIM" -derivedDataPath .build/DerivedData/iOS CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$SIM" .build/DerivedData/iOS/Build/Products/Debug-iphonesimulator/Rayon.app

# 2. Run the tests
cd Application/RayonUITests && xcodegen generate
xcodebuild test -project RayonUITests.xcodeproj -scheme RayonUITests -destination "id=$SIM"
```

Screenshots are attached to the result bundle.
