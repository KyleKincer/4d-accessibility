# Releases

CI builds the native plugin and component from the same checkout. A passing build produces development artifacts, not a production-readiness claim. Production releases require Developer ID signing and Apple notarization.

The signed release workflow runs on `vMAJOR.MINOR.PATCH` or prerelease tags such as `v0.19.5-rc.1`. The numeric portion must match `VERSION`. Allocate a permanent 4D plugin ID before production distribution. Coverage remains defined by [status](skills/4d-accessibility/references/STATUS.md), independently of signing.

## Development release candidates

Run the **Build and test** workflow on `main` with `preview_tag` set to `vVERSION-rc.N`. It builds and checks the kit, verifies the artifact checksums, then prepares a draft GitHub prerelease. Leaving the input empty runs checks only. This path cannot publish a stable tag or mark a release as latest.

Download that draft's kit, verify `SHA256SUMS`, and run the live host checks with its packages. Record the exact results, then publish the same assets with `gh release edit vVERSION-rc.N --draft=false --prerelease --latest=false`. This final check covers the downloadable binaries, including their component/plugin pairing; CI itself has no licensed graphical 4D host. A preview with a known failure must name it in the release notes and attach the failing result alongside the successful checks. Stable publication requires all selected acceptance checks to pass.

These candidates are ad hoc signed and not notarized. They are for local integration and evaluation on the documented test platform. The plugin ID is provisional. State both facts in the release notes, along with unresolved runtime limitations. A candidate is not a claim that every 4D form is accessible.

Use this workflow to publish a candidate; pushing a tag directly invokes the signed workflow and requires its credentials. Production signing gates remain in that separate workflow.

## Maintainer setup

Configure these repository secrets for release jobs:

| Secret | Contents |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that certificate |
| `APPLE_SIGNING_IDENTITY` | Exact Developer ID Application signing identity |
| `APPLE_ID` | Apple account used by notarization |
| `APPLE_TEAM_ID` | Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

Set repository variable `PLUGIN_ID_REGISTERED` to `true` after registering the ID with 4D and updating both `manifest.json` and the lookup in `host/OptionalMethods/AXB_Host.4dm`. The workflow checks these prerequisites before building a release. Credentials are used only in a temporary runner keychain and removed in an unconditional cleanup step. Pull-request jobs have no signing credentials and cannot publish releases.

## Artifacts

`package_release.py` verifies the component, versions, native architecture, binary checksums and source hashes against the build reports before staging. It includes the installer, canonical host helpers, integration reference, examples, skill and license notices. It omits fixtures, vendor plugins, local licenses, application data and machine reports.

- `4d-accessibility-VERSION-macos.zip` contains the complete integration kit.
- `4d-accessibility.zip` contains only the compiled component and its licenses. Its name follows 4D's GitHub Dependency Manager convention. Installing it alone does not install the native plugin or host methods.
- `4d-accessibility-VERSION-macos.dmg` contains the complete kit, signed contents and a stapled notarization ticket.
- `SHA256SUMS` covers the final download files.

Release signing processes the compiled ARM library and native plugin explicitly, then notarizes the ZIP and DMG and staples the DMG. The component ZIP contains the same signed component. A release is published only after those steps succeed. Prerelease tags publish a GitHub prerelease; stable tags publish a normal release.

## Before tagging

Run the documented tests and update support/validation records for the exact source and package hashes. Compile and test the generated host helpers in a real host. Verify ordinary forms, complex grids, repeated/generated children, native interoperability, editing and required assistive technologies in each claimed execution mode. Validate a download in a clean host, including restart and optional-package absence. Client/server delivery needs its own test.

The version is maintained in `VERSION`; CI does not modify source or manufacture version bumps. Never replace assets of an existing release. Correct the source and publish a new version.

## References behind this design

[Miyako's component workflow](https://github.com/miyako/buildapp/blob/main/.github/workflows/publish.yml) demonstrates headless compilation followed by signing and release assets. [Miyako's native plugin workflow](https://github.com/miyako/4d-plugin-ica/blob/master/.github/workflows/release.yml) demonstrates universal plugin builds, signing and notarization. This repository builds the plugin and component together and limits write permissions to publication.

The [official tool4d action](https://developer.4d.com/tool4d-action/) documents the public download layout. Our compiler archive is checksum-pinned. [4D's GitHub component documentation](https://developer.4d.com/docs/21/Project/components#components-stored-on-github) defines the component ZIP name. [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) describes signing, submission and ticket handling.
