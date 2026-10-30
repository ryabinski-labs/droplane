# Contributing

Thanks for helping with Droplane. Bug reports, phone compatibility reports, docs, and code are all welcome.

## Before you start

- Check the [issues](https://github.com/ryabinski-labs/droplane/issues) for something similar.
- For a large change, open an issue first so we can agree on the approach.
- By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Set up

You need macOS 14 or later, Xcode 16 or later, and Homebrew.

```sh
brew install libmtp
git clone https://github.com/ryabinski-labs/droplane.git
cd droplane
swift build
swift test
./scripts/make-app.sh && open build/Droplane.app
```

You can develop without a phone: with nothing plugged in, choose **Try the Demo Phone**.

## Making a change

1. Create a branch from `main`. Changes reach `main` only through a pull request.
2. Keep the change focused. Match the surrounding code's style and naming.
3. Add or update tests. Behavior is specified in `docs/prd/android-file-copier.md`, and scenarios are tracked in `tdd/android-file-copier.tdd.yaml` with test names like `test_SC_003_a`. Cite the scenario ID a test covers.
4. Run `swift build` and `swift test` locally. CI runs the same checks.
5. Open a pull request and fill in the template.

## Licensing of contributions

Contributions are accepted under the project's [MIT License](LICENSE) (inbound equals outbound). There is no CLA. Do not submit code you do not have the right to license, and do not copy code from sources with incompatible licenses. Do not modify or vendor libmtp or libusb in this repository without discussing it first, because it changes the LGPL obligations.

## Privacy rules for contributors

Droplane has no telemetry and makes no network connections. Pull requests that add either will not be merged. Logs must not include file names.

## Reporting security issues

Do not open a public issue. See [SECURITY.md](SECURITY.md).
