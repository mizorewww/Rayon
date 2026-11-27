# iCloud sync

Rayon syncs through CloudKit with `CKSyncEngine`, in the private database of
the container `iCloud.me.mizorewww.rayon`, in the zone `Rayon` (the code is
in `Foundation/RayonModule/Sources/RayonModule/Sync`). Record types are the
table names: `Machine`, `Identity`, `Snippet`, `PortForward`, `Folder`,
`TerminalSettings`, `AppSettings`. Every build and platform
uses that one container: the Mac app (`me.mizorewww.rayon`, Debug
`me.mizorewww.rayon.debug`) and the iOS app (`me.mizorewww.rayon`).

## Environments

A container has two separate environments, Development and Production, each
with its own schema and records. A build uses the one its signature names in
`com.apple.developer.icloud-container-environment`; without that key, a build
signed for development uses Development. Push (`aps-environment`, on the Mac
`com.apple.developer.aps-environment`) follows the provisioning profile.
`build-macos.sh` names Production for a Developer ID build, Xcode for a build
it exports for the App Store or TestFlight.

| Build | Signed with | Environment |
| --- | --- | --- |
| Mac Debug or Release from Xcode or `make build-macos` | Apple Development | Development |
| Mac release disk image (`release.sh mac`) | Developer ID | Production |
| iOS from Xcode or `install.sh` | Apple Development | Development |
| iOS TestFlight / App Store | Apple Distribution | Production |

So the Debug and Release builds on your own devices share data with each
other, and a shipped build shares data with other shipped builds; the two
never see each other's records.

## Schema

In Development, CloudKit creates the record types and fields the first time
a build saves a record with them. Production never does that: a shipped build
saving a record type that Production lacks fails with "Cannot create new type
... in production schema". Before shipping a build that adds a record type or
field:

1. Run a development build on a device signed in to iCloud, turn on
   **Settings > General > Sync with iCloud** and let it sync once with
   something of every kind it syncs (a server, a folder, an identity, a
   snippet, a port forward; terminal and app settings go by themselves), so
   every record type and its fields (`record` and `secrets`, encrypted, and
   `modified`) exist in Development.
2. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/),
   choose the container `iCloud.me.mizorewww.rayon`, then **Schema** (in the
   Development environment) and check the record types are there.
3. Click **Deploy Schema Changes...** (bottom of the sidebar), review the
   list of changes and click **Deploy**. Production gets the Development
   schema; records are not copied.

Schema deploys only add: a type or field once in Production stays there.

## Signing

The entitlements in `Application/Rayon/Resources/Entitlements` ask for the
container, CloudKit, push (CKSyncEngine hears of other devices' changes from
silent pushes) and the app's own keychain access group. The system grants
them only with a provisioning profile that lists the container:

- From Xcode, automatic signing fetches one.
- `make build-macos` signs with the profile `provisioning-profile.sh` finds
  for the bundle id and certificate; with none (ad hoc, CI) it signs without
  those entitlements, and the app says sync is not available in that build.
- `release.sh mac` needs the Developer ID profile for `me.mizorewww.rayon`
  ("Mac Team Direct Provisioning Profile"; Xcode downloads it when it
  exports a Developer ID build, or download it from the developer site).
  CI reads it from the `MAC_PROVISIONING_PROFILE` secret, base64: after the
  profile changes, update the secret, e.g.
  `base64 -i <profile>.provisionprofile | gh secret set MAC_PROVISIONING_PROFILE`.

A profile made before the App ID had the container lists none; Xcode makes a
new one when the build is signed with `-allowProvisioningUpdates` or from the
Signing & Capabilities tab.

## Trying it

1. Sign in to iCloud on the Mac and the iPhone or iPad with the same Apple
   Account, with iCloud Drive on.
2. Build the Mac app signed for development (`make build-macos`, which says
   "Signed for iCloud with ..."; or run the Rayon scheme from Xcode) and
   install the iOS app from Xcode or with `install.sh ios`.
3. Turn on **Sync with iCloud** on both. The status under the switch reads
   "Synced ..." once a round trip worked; "This build is not signed for
   iCloud." means the signature lacks the container, "Sign in to iCloud to
   sync." that no account is signed in.
4. Add a server on one device; it appears on the other within seconds
   (push), or at once with **Sync Now**.
5. The records are visible in CloudKit Console under **Records**, Development
   environment, private database, zone `Rayon` (query by record type; the
   console asks for a queryable `recordName` index for that, which only the
   console needs).
