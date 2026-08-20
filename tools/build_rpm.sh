#!/usr/bin/env bash
# Wrap the exported Linux binary into a Fedora RPM.
#
#   tools/build_releases.sh linux     # produces build/linux/z-remake.x86_64
#   tools/build_rpm.sh                # produces build/rpm/z-remake-*.rpm
#
# Needs: rpm-build, rpmdevtools, desktop-file-utils.
#
# THE RPM EMBEDS THE ORIGINAL BITMAP BROTHERS ART AND SOUND (the Godot
# export bakes the game data into the binary). Install it locally; never
# publish it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build/linux/z-remake.x86_64"
PKG="$ROOT/packaging/linux"
ICONS="$ROOT/project/assets/icon/hicolor"
OUT="$ROOT/build/rpm"
TOP="$ROOT/build/rpmbuild"

[[ -f "$BIN" ]] || { echo "!! missing $BIN — run tools/build_releases.sh linux" >&2; exit 1; }
[[ -d "$ICONS" ]] || { echo "!! missing $ICONS — run python3 tools/gog/make_icons.py" >&2; exit 1; }

rm -rf "$TOP"
mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$OUT"

cp "$BIN" "$TOP/SOURCES/z-remake.x86_64"
cp "$PKG/z-remake.desktop" "$TOP/SOURCES/"
# the spec unpacks this to pick up whichever sizes exist
tar -cf "$TOP/SOURCES/icons.tar" -C "$(dirname "$ICONS")" hicolor

rpmbuild --define "_topdir $TOP" -bb "$PKG/z-remake.spec"

find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT/" \;
echo
echo "built:"
ls -la "$OUT"/*.rpm
echo
echo "install with:  sudo dnf install $OUT/$(cd "$OUT" && ls *.rpm | head -1)"
