# The farmer app on iOS (M8, SPEC 0.3 and 14)

The spec puts iOS in P2 and only for the farmer app: "Android first (min SDK 26), iOS later
for farmer app only" (SPEC 0.3), "Public Play Store; iOS in P2" (SPEC 1.4). The field officer
app stays Android-only — it is issued hardware and the location and duty features are built
against Android's foreground-service model.

This change adds the iOS target so the farmer app is a two-platform project. It does **not**
produce a build: Xcode is not installed on the build machine used here (only the Command Line
Tools) and CocoaPods is absent, so nothing on iOS has been compiled or run. Treat every claim
below as "configured", never as "verified".

## What is in the repository

`apps/mobile/apps/farmer/ios/` — the standard Flutter runner, generated with
`flutter create --platforms=ios --org in.farmerapp --project-name farmerapp_farmer`, then
edited in three ways:

| Setting | Value | Why |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `in.farmerapp.kisan` | Matches the Android `applicationId`, so the two stores describe one app |
| `CFBundleDisplayName` / `CFBundleName` | `Kisan` | Matches the Android `android:label`. Not tenant-branded, for the same reason the Android label is not: one binary serves every tenant and a store listing cannot vary per tenant (docs/branding.md) |
| `CFBundleLocalizations` | en, hi, te, kn, mr | The five languages of FA-004. Without this the iOS system locale never resolves to Telugu, Kannada or Marathi and every device would open in English |
| `NSCameraUsageDescription` | crop photography only | DX-002. iOS refuses to launch a camera without it |
| `NSPhotoLibraryUsageDescription` | picking an existing crop photo | Same |
| `NSMicrophoneUsageDescription` | spoken questions | FA-024 voice input |
| `ITSAppUsesNonExemptEncryption` | `false` | The app uses only HTTPS, which is exempt. Without the key every upload stops for an export-compliance questionnaire |

There is no location permission key, deliberately. FA-010 collects location only on duty and
only in the officer app; the farmer app must never ask, and no code in `apps/farmer/lib` does.

One thing a reviewer will nevertheless raise: the shared `packages/core` declares the location
plugin because the officer app needs it, so the farmer binary links the location framework it
never calls. Without a usage-description key the app cannot ask for location at run time,
which is the behaviour we want, but Apple's privacy questionnaire asks about linked
frameworks, not calls. The clean answer is to move the duty and location code behind a
conditional dependency so the farmer app does not link it at all. That is a refactor of the
shared package, not an iOS setting, and it should happen before the first submission.

## What a human has to do before an iOS build exists

None of this can be automated from here, and all of it needs an Apple account.

1. **A Mac with Xcode** (not just the Command Line Tools) and CocoaPods:
   `sudo xcode-select -s /Applications/Xcode.app` then `sudo gem install cocoapods`.
2. **An Apple Developer Program membership** in the operating entity's name, and a bundle
   identifier `in.farmerapp.kisan` registered against it.
3. **Signing**: a distribution certificate and provisioning profile, set on the Runner target.
   Per CLAUDE.md, creating real credentials is human-only.
4. **The first `flutter build ios`**, which resolves the plugin pods. Every plugin the farmer
   app uses declares iOS support, but the resolution has never been run. Expect this step to
   surface work, particularly around `share_plus` (FM-013) and the camera and audio plugins.
5. **Push notifications** (FA-007) need an APNs key and the Firebase iOS app; the Android and
   iOS senders are configured separately.
6. **App Store review**, including the privacy nutrition labels. The answers are the DPDP
   disclosures already written in docs/dpdp.md; the phrasing is a legal review (TODO-LEGAL).
7. **Device testing.** NF-001's device matrix is Android-only today. iOS needs its own list;
   the cheapest supported iPhone in the target market is the sensible floor.

## What is already portable

The app itself is Flutter and shares `packages/core` with the officer app, so the features,
the offline outbox, the five languages, the design tokens and every widget test are already
platform-neutral. The accessibility work (NF-009) targets WCAG contrast and touch-target
sizes, which carry over; VoiceOver has never been exercised, and TalkBack passing does not
imply VoiceOver passing.
