# RPM for the Fedora build. This is a BINARY REPACK spec: it does not
# compile anything, it wraps the self-contained binary that
# tools/build_releases.sh already produced with Godot's export.
#
# THE PACKAGE CONTAINS THE ORIGINAL BITMAP BROTHERS ART AND SOUND,
# embedded in the binary by the export. Build and install it locally;
# do not put it in a repository or attach it to a release.

%global godot_ver 4.7.2
# no debuginfo to extract from a Godot export, and no ELF hardening to check
%global debug_package %{nil}
%undefine _missing_build_ids_terminate_build
%global __brp_strip %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_strip_comment_note %{nil}
%global __requires_exclude_from ^%{_bindir}/z-remake$

Name:           z-remake
Version:        0.2.10
# BUILD STAMP. Without it every rebuild is the same NEVRA
# (z-remake-0.1.0-1.fc44) with different contents, so dnf sees no reason
# to replace what is installed and you cannot tell two builds apart --
# which is exactly how a stale binary with broken texture loading stayed
# installed. tools/build_rpm.sh passes `buildstamp` as .YYYYmmddHHMM, so
# a fresh package always sorts newer and `dnf install` upgrades in place.
Release:        1%{?buildstamp}%{?dist}
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
* Fri Sep 04 2026 sha5b <ned.tabulov@gmail.com> - 0.2.10-1
- Restore the retail production selector's tall bevel-edged metal carriers
  behind its up/down arrows and use the dedicated up-arrow pressed states.
- Keep the pause menu's original 384x256 panel at native aspect, fit all five
  controls inside it, and dim the complete HUD behind the overlay.
- Add regression checks for the production controls and pause-panel dimensions,
  plus a pause-screen screenshot lane for visual release validation.

* Fri Sep 04 2026 sha5b <ned.tabulov@gmail.com> - 0.2.9-1
- UI parity sweep: selected units and buildings appear as clickable portrait
  medallions above the command bar, and factory products use the original
  up/down arrow selector beside the portrait.
- Army gauges now count controlled zones and show each side's share of the
  battlefield instead of counting units.
- Original explosion, debris, smoke, oil, spark, track and crater effects now
  get proximity-scaled world-camera shake without moving the HUD.
- The title splash, generated-map settings, multiplayer lobby and pause menu
  now stay inside the original 640x480 frame and scale cleanly at modern
  resolutions.
- Tutorial-focused regression checks cover the production arrows, selection
  ribbon and territory gauges.

* Tue Sep 01 2026 sha5b <ned.tabulov@gmail.com> - 0.2.8-1
- Generated skirmish maps: the skirmish list leads with RANDOM MAP -
  players (2-8), starting money, size and theme, with a live preview of
  the exact map the seed builds. START plays what is previewed.
- Fort tower guns sit on the measured tower platforms (two of four
  floated beside the fort), forts start with ONE manned gun instead of
  four, and mounted guns get 1.8x range - a stock gatling could not
  cover its own fort's gate.
- Units fight back: a hit unit retaliates and raises idle friends within
  120px (the AI's squads too), and holds a weapon-up stance. The AI's
  first think fires on frame one instead of after a 4-6s dead interval.
- Hitscan fire reads the original way: muzzle flash on the shooter and
  an impact spark where the shot LANDS (ground ricochet on a miss) -
  the invented tracer line is gone. Reload timers carry +/-10% jitter,
  so battle lines no longer volley in lockstep.
- The jeep "spasm" is fixed (firing pins the facing; the chase has a
  hysteresis band), the dotted route no longer redraws while chasing a
  moving target, and stuck units re-route AROUND parked units.
- Game over lingers 3s so the HQ's collapse plays before the verdict.
- Production panel rebuilt on its own art: the name tag uses the 45x13
  plate cut for the slot (no more red bands), the health gauge is a real
  bar, and the window sits on whole pixels. The sidebar health bar and
  the army gauges can shrink again (both were stuck at full width).
- Review sweep: the in-world health bar was dead code, the death
  animation variant was frozen per army, box-select silently dropped
  units past 256 bodies, tower guns came back from a save unlinked, and
  the scene-map build tool called a deleted function.

* Sun Aug 23 2026 sha5b <ned.tabulov@gmail.com> - 0.2.7-1
- Production is a LINE, not a queue: point a factory at one unit type and
  it turns that out indefinitely. Cancel stops it; switching keeps the
  build clock. Z has no build queue and never did.
- Nothing enters a building any more. The fort garrison is gone; a fort
  defends itself with its four tower guns, which can be shot off it.
- Every explosive weapon can finally hurt a building. Tanks, cannons and
  missiles had no anti-structure damage scale at all, so a heavy tank
  needed 341s to raze a fort that a pyro robot razed in 14s. Crewed
  vehicles and cannons also could not fire on a fort AT ALL: their range
  gate measured to the fort's middle, ~80px inside its own wall.
- Cannons are no longer treated as manoeuvre units. A turret has speed 0,
  so drafting it into a squad dragged the squad's rally point onto an
  immobile gun and parked the army around it on one bridge.
- The CPU brain got a strategic layer (zone graph, per-sector strength and
  value, four stances) and squads that muster before they commit and
  withdraw when beaten. Its cadences run on GAME time, so pausing no
  longer fires every timer at once on unpause.
- Units path AROUND buildings: cells next to a wall now cost more, so a
  route prefers open ground instead of grinding along a factory wall.
- A captured factory no longer inherits the previous owner's rally point.
- Unit shadows are rasterised on the pixel grid instead of being smooth
  antialiased ellipses under 16px sprites.

* Fri Aug 21 2026 sha5b <ned.tabulov@gmail.com> - 0.2.0-1
- Fix an exported build loading none of its content: Godot packs an
  imported file as a .import sidecar, and every directory scan filtered
  on the source extension. PackFiles folds packed names back.
- Run the test suite inside the exported binary. The title screen hands
  over to the match scene on a test flag, so a build is testable.
- Carry a build stamp in Release, so a rebuild always upgrades in place.

* Thu Aug 20 2026 sha5b <ned.tabulov@gmail.com> - 0.1.0-1
- First packaged build: retail campaign, original HUD, tactical CPU
  opponent, adaptive AI posture ported from the Zod Engine bot.
