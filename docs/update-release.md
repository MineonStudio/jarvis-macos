# Jarvis macOS update releases

Jarvis updates are signed with an Ed25519 key independent of GitHub. The public
key is embedded in `Resources/Info.plist`; the private key is kept in the
release Mac's login Keychain and must never be committed or uploaded as a
GitHub Actions secret.

## Signing key

The release key has already been initialized in the current Mac's login
Keychain. `swift script/JarvisUpdateSigning.swift public-key` prints the public
key only. `generate` is for first-time setup on a new release machine; do not
run it to recover a missing key. A replacement key cannot update installed
copies that trust the old public key. If the Keychain item is lost, users must
install a new signed DMG manually to establish trust in a replacement key.

Keep an encrypted offline backup of the login Keychain before relying on this
key for future releases. GitHub stores only the signed manifest and public
artifacts, never the private key.

## Build release assets

Set a new, strictly increasing app version and build number, then run:

```sh
JARVIS_VERSION=1.4.8 JARVIS_BUILD=346 ./package_release.sh
```

Upload every emitted asset to the matching non-prerelease GitHub Release:

- `Jarvis-<version>-macos.zip`: direct download installation
- `Jarvis-<version>-macos.dmg`: DMG installation
- `Jarvis-update.zip`: the exact archive used by in-app updates
- `Jarvis-update-manifest.json`
- `Jarvis-update-manifest.sig`

The update manifest is signed over its exact file bytes and includes the
archive's SHA-256, bundle identifier, version, build number, and stable
channel. The app selects the update archive by the exact `archiveName` in that
verified manifest. Do not rename the update archive or edit either manifest
file after signing.

New direct-download and DMG installs record their source once in the user's
Jarvis preferences. The in-app update archive carries a neutral `unknown`
bundle marker: an existing preference wins, while installations made before
source tracking was added stay honestly unknown instead of being mislabeled as
direct downloads. Updates use the same stable release channel.

## Legacy bridge

Only the already-published unsigned release `1.4.5` is eligible for the
one-time GitHub digest bridge. It exists so older installed versions can reach
the first build that trusts the embedded Ed25519 key. Every newer release must
include both signed manifest assets; missing or invalid signatures fail
closed.
