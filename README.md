# Cosmic Abyss

Cosmic Abyss is a real-time spaceship survival game with two maintained
implementations: an Atari 8-bit VBXE build and a browser version that mirrors
the Atari rules and 320x200 systems console.

Cosmic Abyss is heavily inspired by [Ravaged Space](https://straker.itch.io/ravaged-space),
the original text-based incremental survival game created by Steven Lambert.

## Project structure

```text
.
|-- index.html                    Vite HTML entry
|-- intro/                        Web-only cinematic prologue
|   |-- assets/                   Generated cinematic artwork
|   |-- index.html                Standalone intro entry
|   |-- intro.css                 Cinematic presentation
|   `-- intro.js                  Story playback and game handoff
|-- launch/                       Post-intro operations briefing
|   |-- index.html                Platform selection and instructions
|   |-- launch.css                Technical briefing presentation
|   `-- launch.js                 Atari build download link
|-- src/
|   |-- game.js                   Browser game logic and canvas renderer
|   `-- styles.css                Responsive console and controls
|-- atari/
|   |-- cosmic-abyss.asm         MADS/VBXE source
|   `-- cosmic-abyss.xex         Built Atari executable
|-- docs/
|   `-- vbxe-fx-1.26-pl.pdf       VBXE hardware reference
|-- legacy/
|   `-- original-browser/         Original browser implementation snapshot
|-- package.json                  Development and build scripts
`-- README.md
```

Generated web output is written to `dist/`; installed packages live in
`node_modules/`. Both directories are ignored by Git.

## Browser development

Requires Node.js and npm.

```sh
npm install
npm run dev
```

Open the URL printed by Vite, normally `http://localhost:5173/`.

Starting the browser game opens the cinematic prologue under `intro/`. Its start
screen waits for Space, Enter, or the Begin Transmission button so browsers can
unlock the soundtrack and first narration in sync. Space, Enter, click, or tap
then advances the story; Escape or the Skip Intro button opens the post-intro
operations briefing. From there the player can download the Atari VBXE
executable or enter the online game. The Atari build continues to use its compact
native briefing and does not include these web assets.

The seven-scene prologue opens with the Orpheus mission and crew manifest,
introduces Captain Mara Venn and her alien-defence training, then follows a rare
private moment before the unattended simulation starves the autopilot and
collision detector of power. The impact, containment, and last-command sequence
then carries the story into the game.

The prologue uses `intro/assets/Static in the Void.mp3` as its persistent,
looping dark-space soundtrack. Music is enabled by default when the browser
permits autoplay and otherwise begins with the first interaction. A separate
low robotic system voice with a retro transmission
carrier automatically narrates every scene as it appears; changing scenes stops
the previous line without interrupting the music. All spoken lines remain visible
as captions, and scenes advance only on keyboard, click, or tap input.

```sh
npm run build       # production build in dist/
npm run preview     # serve the production build locally
```

## GitHub Pages

Pushing `main` deploys the web game and cinematic intro automatically through
`.github/workflows/deploy-pages.yml`. The workflow builds Vite with the
`/starsurvival/` repository base path and publishes `dist/` to GitHub Pages.

The deployed routes are:

- Game: `https://astroforgit.github.io/starsurvival/`
- Intro: `https://astroforgit.github.io/starsurvival/intro/`
- Operations briefing: `https://astroforgit.github.io/starsurvival/launch/`

In the GitHub repository, select **Settings → Pages → Build and deployment →
GitHub Actions** once to enable workflow-based publishing.

Keyboard controls use the arrow keys and Space or Enter for the selected action. Matching
on-screen controls are available for touch devices.

Direct action keys are `P` Power, `L` Life Support, `O` Processing, `E`
Engineering, `G` Guidance, `N` Engines, and `S` Sensors. Modifications use `A`
Amount, `U` Auto, and `D` Speed. Random events reserve `Y/N` for decisions and
the number keys for four-digit challenges; matching touch buttons appear while
an event is active.

## Atari build

Requires MADS and a VBXE-equipped Atari or compatible emulator.

```sh
npm run build:atari
```

The command assembles `atari/cosmic-abyss.asm` into
`atari/cosmic-abyss.xex`.

Atari controls:

- joystick up/down selects a system
- Space performs the selected system action
- Space during the opening briefing skips directly to the game
- joystick left purchases the Amount modification
- joystick right purchases the speed modification
- keyboard `P/L/O/E/G/N/S` performs the corresponding action directly
- keyboard `A/U/D` purchases Amount, Auto, or Speed directly
- keyboard `Y/N` accepts or rejects a random robot trade
- number keys enter the displayed four-digit emergency code
- Space after game over starts a new game

## Game rules

Power, Life Support, and Processing support four main systems: Engineering,
Guidance, Engines, and Sensors. Actions repair one system while consuming other
resources and entering a cooldown. Main-system repairs can increase recurring
Power or Life Support load, deducted every 20 seconds.

New actions unlock as repairs progress. The three modifications improve resource
yield, add automatic production, and shorten cooldowns. The player wins when all
four main systems reach ONLINE status (8/10). Any system reaching zero destroys
the ship.

Guidance, Engines, and Sensors unlock when the first Amount modification window
is opened, matching the original progression trigger. Main systems have four
repair levels and become unavailable after the fourth repair; their final-level
Power and Life Support loads are included. Actions may be used even when their
cost will destroy a resource system, so resource shortages remain lethal.

The original special sequence is present: `Scan Sector`, `Plot Course`, `Activate
JumpDrive`, then `Install Source`. Each special replaces its normal system action
for a 20-second operation and opens a narrative popup on completion. Installing
the source changes Generate Power to `+10` Power with no Processing cost.

Victory has its own spaceport-jump popup. Power, Life Support, Processing, and a
fully radioactive meter each trigger a loss scenario and message.

Random events appear in the narrow panel below the system table. Robot events
appear more frequently and offer a one-point resource exchange for two points of
another resource.
Timed salvage and hazard events show a random four-digit code; entering it
within ten seconds collects the salvage or prevents the displayed resource loss.

## VBXE implementation

The Atari version disables ANTIC and uses a 320x200 VBXE overlay with one byte
per pixel. The framebuffer begins at VRAM `$000000`; the XDL and blitter control
block live in bank `$7F`.

Action cooldown bars are updated at the Atari frame rate. They shrink linearly
over 10 seconds, or 5 seconds after the speed modification. The recurring-load
bar uses the same frame-driven animation over its 20-second cycle.

At startup, the game expands the Atari ROM character set at `$E000` into an 8x8
mask font at VRAM `$038000`. Text, status bars, selection rows, windows, and
messages are drawn with the VBXE blitter. The browser Canvas implementation keeps
the same state-array ordering and closely matching game and drawing routines.

System condition is displayed as ten individually bordered boxes, following the
original browser interface. Eight custom 8x8 icons identify Power, Life Support,
Processing, Radioactive, Engineering, Guidance, Engines, and Sensors. The browser and Atari
versions share the same pixel masks; Atari expands them into coloured sprites at
VBXE VRAM `$039000` and draws each icon with one transparent blit.

Radioactive is an inverse resource displayed directly below Processing. It starts
at zero and has no keyboard action. A failed four-digit `RADIOACTIVE LEAK` event
adds exactly two points, while a successful `CLEAR RADIOACTIVE LEAK` event removes
exactly two points. These events only appear when the full change can be applied,
and show their signed change beside the radioactive trefoil icon. Some robot
offers also grant two points of a normal resource in exchange for adding one
Radioactive point; both effects are displayed before accepting. Reaching ten
Radioactive points immediately ends the mission.

The 320x200 console uses compact `STATUS`, `ACTION`, `LOAD`, and `MODS` columns.
System rows show icons only; the full icon names are collected in a two-line
legend at the bottom.

The first table column displays an action shortcut only while that action can be
performed immediately. Keys disappear while locked, unaffordable, or cooling
down. The narrow modification column similarly shows `A`, `U`, or `D` only while
another resource-system modification can currently be installed.

Pressing a modification key pauses the game and opens the original three-choice
workflow. `P` selects Power, `L` selects Life Support, and `O` selects Processing;
Escape cancels. Previously modified choices remain visible but disabled. Repair
progress in Engineering, Guidance, or Engines determines how many Amount, Auto,
or Speed choices may be installed, respectively.

Each option includes its before/after behavior. Amount lists the exact gain and
resource-cost changes, Auto shows manual production changing to automatic
production every cooldown, and Speed shows the cooldown changing from 10 to 5
seconds. Installed options retain this detail in a disabled style.

Amount uses the original per-resource values (`+5` Power for `-2` Processing,
`+3` Life Support for `-1` Power, or `+7` Processing for `-2` Power). Auto runs
only the selected resource action, including its costs. Speed halves only the
selected resource action's cooldown.

Like the original interface, each unlocked `ACTION` entry shows its icon-based
result and price. The positive term is the repaired or produced system, followed
by every resource cost as a negative term. For example, Generate Power displays
`+2` Power and `-1` Processing. These values update when production is modified.

The separate `LOAD` column shows recurring deductions owned by each running
system. Life Support begins at `-1` Life Support; repaired main systems add their
own Power and Life Support terms as their operating load increases. Those terms
are summed and deducted on a shared cycle. As in the original game, the first
Life Support deduction occurs after four seconds; later cycles take twenty
seconds. The countdown is shown as an animated overlay inside each active `LOAD`
cell rather than as a separate footer timer.

The original browser game is retained under `legacy/original-browser/` as a
rules and interface reference. It is not part of the Vite production build.
