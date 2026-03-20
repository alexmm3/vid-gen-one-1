# VideoApp — AI Video Gen App

## Project

- **Bundle ID**: `com.alexm.videoeffects1`
- **Team ID**: `4CB8XNCYXB` (ODG SP. Z O.O.)
- **App Store Connect ID**: `6760908642`
- **SKU**: `videoeffects1`
- **Deployment Target**: iOS 18.0
- **Dependencies**: Swift Package Manager (Firebase, Supabase)

## Build & Release Automation (Fastlane)

All automation runs via Fastlane. Credentials are in `.keys/` (gitignored).

### Prerequisites

Fastlane must be available in PATH. Run commands from the project root:

```bash
export PATH="$HOME/.gem/ruby/3.4.0/bin:$PATH"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
```

### Commands

| Command | What it does |
|---|---|
| `fastlane ios build` | Archive + export IPA to `build_output/`. Auto-increments build number from TestFlight. |
| `fastlane ios testflight_upload` | Build + upload to TestFlight. Skips waiting for processing. |
| `fastlane ios release` | Build + upload to App Store Connect (does NOT auto-submit for review). |
| `fastlane ios release submit:true` | Build + upload + submit for App Store Review. |
| `fastlane ios bump type:patch` | Bump version (patch/minor/major) in .xcodeproj. |
| `fastlane ios status` | Show latest TestFlight build number. |
| `fastlane ios upload_metadata` | Push metadata/screenshots to ASC. |

### How it works

- **API Key auth** — no Apple ID password needed. Key: `.keys/AuthKey_4HDC79WA69.p8`, config: `.keys/appstore.env`
- **Build numbers** — auto-fetched from TestFlight and incremented. Set manually with `build_number:N`.
- **Signing** — manual export with provisioning profile "VideoApp AppStore Dist". Xcode project uses automatic signing for development.
- **Version numbers** — set via `MARKETING_VERSION` in xcodeproj build settings (project uses `GENERATE_INFOPLIST_FILE=YES`, so agvtool doesn't work).

### ASC API Script

`scripts/asc-api.sh` — direct App Store Connect API access for anything Fastlane can't do:

```bash
./scripts/asc-api.sh /v1/apps                              # list apps
./scripts/asc-api.sh /v1/apps/6760908642                    # get app details
./scripts/asc-api.sh /v1/apps/6760908642/builds             # list builds
./scripts/asc-api.sh /v1/profiles                           # list provisioning profiles
./scripts/asc-api.sh /v1/certificates                       # list certificates
```

### Key files

| File | Purpose |
|---|---|
| `.keys/appstore.env` | ASC API credentials (KEY_ID, ISSUER_ID, paths) |
| `.keys/AuthKey_4HDC79WA69.p8` | App Store Connect API private key |
| `fastlane/Fastfile` | All build/release lanes |
| `fastlane/Appfile` | App identifier and team config |
| `scripts/asc-api.sh` | Direct ASC REST API wrapper |
| `Gemfile` | Ruby dependencies (fastlane) |

### Certificates & Profiles

- **Distribution Certificate**: `5XHUJ7G696` — "iOS Distribution: ODG SP. Z O.O." (expires 2027-03-20). Private key is in the local Keychain.
- **Provisioning Profile**: `SG38MSG36Y` — "VideoApp AppStore Dist" (expires 2026-07-02). Installed at `~/Library/MobileDevice/Provisioning Profiles/`.
- **Development**: automatic signing via Xcode.

### Troubleshooting

- **"No profiles found"** — provisioning profile not installed. Re-download via `./scripts/asc-api.sh /v1/profiles/SG38MSG36Y` and install the base64-decoded content to `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`.
- **"No signing certificate found"** — distribution certificate private key missing from Keychain. Need to re-import the `.p12` or create a new certificate.
- **Build number conflict** — set explicitly: `fastlane ios build build_number:99`

## Backend

Supabase project. Edge Functions in `supabase/functions/`. Deploy scripts in `supabase/scripts/`.
