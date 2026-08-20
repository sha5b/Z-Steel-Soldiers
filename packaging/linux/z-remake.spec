# RPM for the Fedora build. This is a BINARY REPACK spec: it does not
# compile anything, it wraps the self-contained binary that
# tools/build_releases.sh already produced with Godot's export.
#
# THE PACKAGE CONTAINS THE ORIGINAL BITMAP BROTHERS ART AND SOUND,
# embedded in the binary by the export. Build and install it locally;
# do not put it in a repository or attach it to a release.

%global godot_ver 4.7.1
# no debuginfo to extract from a Godot export, and no ELF hardening to check
%global debug_package %{nil}
%undefine _missing_build_ids_terminate_build
%global __brp_strip %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_strip_comment_note %{nil}
%global __requires_exclude_from ^%{_bindir}/z-remake$

Name:           z-remake
Version:        0.1.0
Release:        1%{?dist}
Summary:        Fan remake of Z (The Bitmap Brothers, 1996)

# The CODE in this project is original. The embedded graphics and sound
# are not ours to license, which is what makes the built package
# non-redistributable.
License:        LicenseRef-Original-Code-Plus-Proprietary-Assets
URL:            https://github.com/sha5b/Z-Steel-Soldiers

Source0:        z-remake.x86_64
Source1:        z-remake.desktop
Source2:        icons.tar

ExclusiveArch:  x86_64
BuildRequires:  desktop-file-utils
Requires:       hicolor-icon-theme

%description
A fan remake of Z, the 1996 real-time strategy game by The Bitmap
Brothers, rebuilt in Godot %{godot_ver}. All 20 retail campaign levels
plus skirmish maps, the original HUD, and a tactical CPU opponent.

The binary is self-contained: it embeds the game data, which includes
graphics and sound (c) The Bitmap Brothers, extracted locally from the
Zod Engine asset pack and the GOG release. This package is therefore for
LOCAL USE ONLY and must not be redistributed.

%prep
# nothing to unpack for the binary; the icon tree comes out of Source2
%setup -q -c -T
tar -xf %{SOURCE2}

%build
# a Godot export is already linked

%install
install -Dpm 0755 %{SOURCE0} %{buildroot}%{_bindir}/%{name}
desktop-file-install --dir=%{buildroot}%{_datadir}/applications %{SOURCE1}
for size in 16 32 48 64 128 256 512; do
    if [ -f "hicolor/${size}x${size}/%{name}.png" ]; then
        install -Dpm 0644 "hicolor/${size}x${size}/%{name}.png" \
            "%{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{name}.png"
    fi
done

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%{_bindir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Thu Aug 20 2026 sha5b <cloud@fiber-elements.com> - 0.1.0-1
- First packaged build: retail campaign, original HUD, tactical CPU
  opponent, adaptive AI posture ported from the Zod Engine bot.
