fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app for App Store distribution

### ios testflight_upload

```sh
[bundle exec] fastlane ios testflight_upload
```

Build and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit to App Store Review

### ios bump

```sh
[bundle exec] fastlane ios bump
```

Bump version number (e.g. bump type:minor)

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload metadata to App Store Connect

### ios status

```sh
[bundle exec] fastlane ios status
```

Check app status in App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
