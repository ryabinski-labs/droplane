# Releasing Droplane

Droplane is a **macOS** app. It is distributed outside the Mac App Store as a Developer ID signed, notarized, stapled DMG. This is the distribution decision in [the PRD](prd/android-file-copier.md) (`DL-004`).

The iPhone App Store and TestFlight are not part of this pipeline: the app uses USB MTP and macOS APIs and does not run on iPhone or iPad.

## What the release produces

- `Droplane-vX.Y.Z-arm64.dmg` — signed with Developer ID, notarized by Apple, and stapled.
- `droplane-vX.Y.Z-source.tar.gz` — the tagged source.
- `SHA256SUMS.txt` and a Sigstore SLSA provenance bundle.

The DMG opens on a clean Mac with no “unidentified developer” warning. The app inside is drag-to-Applications ready.

## One-time setup

### 1. Create the Developer ID Application certificate

Only the **Account Holder** can create a Developer ID certificate. The App Store Connect API key used for notarization cannot create one (Apple returns `403: This operation can only be performed by the Account Holder`).

Either create it in Xcode:

> Xcode → Settings → Accounts → select the team → Manage Certificates → `+` → **Developer ID Application**

Or use the CSR generated on the signing Mac:

```bash
# If ~/.secrets/droplane-signing/developer-id.csr.pem does not exist:
mkdir -p ~/.secrets/droplane-signing
chmod 700 ~/.secrets/droplane-signing
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ~/.secrets/droplane-signing/developer-id.key.pem \
  -out ~/.secrets/droplane-signing/developer-id.csr.pem \
  -subj "/CN=Droplane Developer ID Application"
chmod 600 ~/.secrets/droplane-signing/developer-id.key.pem \
  ~/.secrets/droplane-signing/developer-id.csr.pem
```

Then in the Apple Developer portal:

1. Open **Certificates, Identifiers & Profiles → Certificates**.
2. Click `+` and choose **Developer ID Application**.
3. Upload `~/.secrets/droplane-signing/developer-id.csr.pem`.
4. Download the `.cer` file and save it as `~/.secrets/droplane-signing/developer-id.cer`.

If Xcode created the certificate, skip the CSR steps and export the identity from Keychain Access as a `.p12` instead.

### 2. Import the identity into the login keychain

Using the CSR route:

```bash
cd ~/.secrets/droplane-signing
openssl x509 -inform DER -in developer-id.cer -out developer-id.crt.pem
openssl pkcs12 -export \
  -inkey developer-id.key.pem \
  -in developer-id.crt.pem \
  -out developer-id.p12 \
  -passout pass:"$P12_PASSWORD"
security import developer-id.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign
```

Verify:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Create a notarytool profile (local builds)

This Mac already has the App Store Connect API key at `~/.ssh/AuthKey_J37SGR2QR5.p8`; `APPLE_KEY_ID` and `ASC_ISSUER_ID` are exported from `~/.zshrc`.

```bash
xcrun notarytool store-credentials "droplane-notary" \
  --key "$HOME/.ssh/AuthKey_J37SGR2QR5.p8" \
  --key-id "$APPLE_KEY_ID" \
  --issuer "$ASC_ISSUER_ID"
```

Do not commit the `.p8`, the `.pem`, the `.p12`, or the passwords.

### 4. Configure GitHub Actions secrets

The release workflow reads five repository secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64 of the Developer ID `.p12` containing the certificate and private key. |
| `DEVELOPER_ID_P12_PASSWORD` | The password used when exporting that `.p12`. |
| `APPLE_API_KEY_P8` | The raw contents of the App Store Connect `.p8` key. |
| `APPLE_KEY_ID` | The API key ID. |
| `ASC_ISSUER_ID` | The App Store Connect issuer ID. |

Set them from the files without printing the values:

```bash
base64 -i ~/.secrets/droplane-signing/developer-id.p12 | gh secret set DEVELOPER_ID_P12
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD
gh secret set APPLE_API_KEY_P8 < "$HOME/.ssh/AuthKey_J37SGR2QR5.p8"
printf '%s' "$APPLE_KEY_ID" | gh secret set APPLE_KEY_ID
printf '%s' "$ASC_ISSUER_ID" | gh secret set ASC_ISSUER_ID
gh secret list
```

## Local release dry run

First check the packaging and DMG layout without Apple's notary service:

```bash
./scripts/package-dmg.sh --no-notarize
```

Then run the real signing and notarization:

```bash
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="droplane-notary" \
VERSION=0.1.2 BUILD_NUMBER=3 \
./scripts/package-dmg.sh
```

The script builds the app, signs the app and every bundled dylib, creates a DMG with an Applications symlink, signs the DMG, submits it to `notarytool`, staples the ticket, and verifies the result.

## Publish a release

1. Update `CHANGELOG.md` and any user-facing download text.
2. Commit the changes through a pull request and merge to `main`.
3. Tag the merged commit and push the tag:

   ```bash
   git tag v0.1.2
   git push origin v0.1.2
   ```

4. The `Release` workflow builds the DMG, signs and notarizes it, creates `SHA256SUMS.txt`, attests provenance, and publishes the GitHub release. A tag containing a hyphen is published as a pre-release; a plain `vX.Y.Z` tag is published as a normal release.

## Verify the published download

```bash
spctl -a -vvv -t open --context context:primary-signature Droplane-v0.1.2-arm64.dmg
stapler validate Droplane-v0.1.2-arm64.dmg
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
gh attestation verify Droplane-v0.1.2-arm64.dmg --repo ryabinski-labs/droplane
```

`spctl` must report `source=Notarized Developer ID`. Then test on a clean Mac: download the DMG from the release, open it, drag Droplane to Applications, and launch it. No Gatekeeper approval should appear.

## If the workflow fails

- **No Developer ID Application identity in the imported p12** — the `DEVELOPER_ID_P12` secret does not contain the certificate and its private key. Re-export the identity from Keychain Access.
- **`403` from notarytool** — the API key ID, issuer ID, or key contents do not match, or the key was revoked.
- **`spctl` rejects the DMG** — the notarization or stapling step did not finish. Re-run the workflow; do not publish the asset.
- **The app still links against Homebrew paths** — `scripts/make-app.sh` did not bundle libmtp/libusb correctly. Fix the bundle before tagging.

## Not yet implemented

- Sparkle auto-updates and an appcast are in the PRD but not in the source. Publishing a notarized DMG does not add them.
- A Homebrew cask can be added after the first notarized release.
- Intel/universal builds are separate work; the current release asset is Apple Silicon only.
