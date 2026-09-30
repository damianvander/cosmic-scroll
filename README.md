# cosmic-scroll

Kinetic (smooth) scrolling for [COSMIC](https://github.com/pop-os), with per-app
scroll speed overrides. This repo carries patches for cosmic-comp and
cosmic-settings, an install script, and CI that publishes prebuilt binaries.

## Install

Installs prebuilt patched binaries (Arch/CachyOS), matched to your installed
COSMIC version:

```bash
curl -fsSL https://raw.githubusercontent.com/damianvander/cosmic-scroll/master/install-kinetic.sh | bash
```

Log out and back in. Existing binaries are backed up to `<binary>.bak`.

Other options:

```bash
./install-kinetic.sh cosmic-comp       # compositor only
./install-kinetic.sh cosmic-settings   # settings app only
./install-kinetic.sh epoch-1.2.0       # pin a specific COSMIC version
./install-kinetic.sh --latest          # skip version matching, newest release
```

On other distros, build from source with the patches applied (see below).

## Use

- Enable **Settings > Input Devices > Touchpad > Scrolling > Smooth scrolling**.
- Set per-app scroll speed under **Settings > Input Devices > Touchpad >
  Per-app scroll speed**: add the app's Wayland app ID (or X11 WM_CLASS) and a
  multiplier (1.0 = unchanged, lower = slower, higher = faster).

## Develop

Upstream sources are not vendored. Clone them into the gitignored working
dirs at the epoch tag the patches track (currently `epoch-1.9.0`) and apply
the patches:

```bash
git clone -b epoch-1.9.0 https://github.com/pop-os/cosmic-comp.git     cosmic-comp
git clone -b epoch-1.9.0 https://github.com/pop-os/cosmic-settings.git cosmic-settings
git -C cosmic-comp     apply ../cosmic-comp-kinetic.patch
git -C cosmic-settings apply ../cosmic-settings-kinetic.patch
```

Building cosmic-settings requires the patched cosmic-comp clone as a sibling
directory (its patch points the `cosmic-comp-config` dependency at
`../cosmic-comp/cosmic-comp-config`).

After editing, regenerate the patches:

```bash
git -C cosmic-comp     diff HEAD > cosmic-comp-kinetic.patch
git -C cosmic-settings diff HEAD > cosmic-settings-kinetic.patch
```

Pushing to master triggers CI (`.github/workflows/patch-and-build.yml`): it
applies the patches to the latest upstream `epoch-*` tag of each component,
builds in an `archlinux:latest` container, and publishes
`patched-<component>-<epoch>` releases. It also runs every 6 hours to pick up
new upstream tags.

Pull requests run the same patch-and-build checks without publishing releases.
The current patches target **epoch-1.9.0** for both components, including
Smithay's `InputTime` API. Older epochs may require patches from an earlier
commit of this repository. The settings build requires a matching cosmic-comp
epoch tag; CI fails explicitly if it is missing instead of using upstream master.

To check patch application before building (from clean upstream checkouts):

```bash
git -C cosmic-comp     apply --check ../cosmic-comp-kinetic.patch
git -C cosmic-settings apply --check ../cosmic-settings-kinetic.patch
```

Use `git diff HEAD` when regenerating patches after `git apply -3`, which stages
changes, and stage any newly added files first so they are included in the diff.
