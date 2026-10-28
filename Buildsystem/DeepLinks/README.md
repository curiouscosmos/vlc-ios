# Deep links (Universal Links)

The app accepts these website links and opens the matching screen:

- `https://rajneeshdiscourse.com/discourses/{DISCOURSE_ID}` → discourse detail
- `https://rajneeshdiscourse.com/discourses/{DISCOURSE_ID}/tracks/{DISCOURSE_AUDIO_ID}`
  → discourse detail, scrolled to that track

## App side (already configured)

- `com.apple.developer.associated-domains` contains
  `applinks:rajneeshdiscourse.com` in:
  - `Resources/iOS/VLC.entitlements`
  - `VLC-iOSDebug.entitlements`
  - `VLC-iOS-no-watchDebug.entitlements`
- `DiscourseDeepLink` parses the URL and `TabBarCoordinator` opens the
  Discourses tab, resolves the discourse and pushes the detail screen.
- The signed App ID must have the **Associated Domains** capability enabled.
  Xcode automatic signing does this; no Apple approval is required.

## Website side (required before links leave Safari)

Publish `apple-app-site-association` at:

```
https://rajneeshdiscourse.com/.well-known/apple-app-site-association
```

Requirements:

- No `.json` extension.
- `Content-Type: application/json`.
- HTTPS, HTTP 200, no redirects or authentication.
- The `appIDs` value must be the Team ID + bundle identifier actually signed.
  The current file uses `5TD3Z8LZ2H.com.oshodiscourse` (both iOS app targets
  currently use `com.oshodiscourse`). If the team or bundle id changes, update
  this file and regenerate the profile.
- The path components above cover both link shapes. If you later use `www`,
  add `applinks:www.rajneeshdiscourse.com` to the entitlements and serve the
  same file on the `www` host.

## Verify

1. Install a signed build on a physical device (the simulator does not reliably
   resolve Universal Links).
2. Delete and reinstall the app once if the AASA was previously 404.
3. Open both URLs in Safari or Messages; they should open the app.
4. On a device, use Console.app or `log stream` if a link still opens Safari;
   the AASA must return 200 with `Content-Type: application/json` and the signed
   app's Team ID + bundle ID must be listed.

The in-app parser tests are in
`Buildsystem/Testing/Unit/DiscourseDeepLinkTests.swift`. The routing was
verified in the simulator by delivering the https URL directly to the app's
`openURL` handler (discourse and track links both worked); Universal Links
themselves still depend on the deployed AASA.
