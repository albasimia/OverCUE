# Branch and release policy

## Branches

- `develop` is the integration and day-to-day development branch.
- Every push to `develop` builds and checks both the macOS and Windows applications.
- Pull requests targeting `develop` or `main` run the same cross-platform CI.
- `main` contains release-ready code and is the source of release version numbers.

## Versioning and releases

- Change release versions only in a pull request targeting `main`.
- `VERSION` is the shared macOS and Windows release version source.
- `Packaging/Info.plist` must contain the same `CFBundleShortVersionString`.
- Development CI uploads short-lived build artifacts but does not create GitHub Releases.
- A `vX.Y.Z` tag on a `main` commit packages both platforms, generates SHA-256 checksums,
  and publishes a GitHub Release.
- Windows releases are distributed directly as self-contained `win-x64` ZIP archives. They
  include the XPPen ACK05 driver profile, the rekordbox keyboard mapping, three localization
  JSON files, and Japanese/English/Simplified Chinese setup guides.
- Microsoft Store packaging is not part of the release process. The macOS app is ad-hoc signed
  during packaging but is not Developer ID signed or notarized. The Windows archive is currently
  unsigned.
- The Windows ZIP can be published unsigned during development and early public testing. Keep
  the SmartScreen warning documented, publish `SHA256SUMS.txt`, and do not use a self-signed
  certificate for public trust. SignPath Foundation is the preferred future signing route if
  the project qualifies.

## Recommended branch protection

Configure `develop` and `main` on GitHub to require the following status checks before merge:

- `GitHub Actions / actionlint`
- `macOS / Swift 6`
- `Windows / .NET 10`

Disallow direct pushes to `main`; merge release pull requests from `develop` after both checks pass.

After `develop` exists on GitHub and GitHub CLI authentication is available, configure both
branches automatically:

```powershell
.\Scripts\configure-github-protection.ps1
```

Dependabot checks GitHub Actions and Windows NuGet dependencies every Monday and opens grouped
pull requests against `develop`. Dependency pull requests are never merged automatically.
