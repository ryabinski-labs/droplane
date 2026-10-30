# Third-Party Notices

Droplane itself is released under the MIT License ([LICENSE](LICENSE)). Built app bundles also include the libraries below, each under its own license.

| Library | Version | License | Source |
| --- | --- | --- | --- |
| libmtp | 1.1.23 | LGPL-2.1-or-later | https://sourceforge.net/projects/libmtp/ |
| libusb | 1.0.30 | LGPL-2.1-or-later | https://github.com/libusb/libusb |

The full license texts are in [LICENSES/](LICENSES/) and are copied into `Droplane.app/Contents/Resources/` at build time.

## Your rights under the LGPL

libmtp and libusb are linked dynamically. They are separate `.dylib` files inside `Droplane.app/Contents/Frameworks/`, not compiled into the Droplane executable. You may replace them with your own build of the same libraries. To do that, build libmtp and libusb from the sources above, put the results in `Contents/Frameworks/` with the same file names, and re-sign the app (`codesign --force --sign - Droplane.app`). `scripts/make-app.sh` shows how the libraries are bundled and their install names rewritten.

The source for the exact versions shipped is available from the project links above and from the Homebrew formulae `libmtp` and `libusb`. If you cannot get it from there, open an issue and the maintainers will provide it.

Droplane does not modify libmtp or libusb.
