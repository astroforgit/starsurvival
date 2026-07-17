# Cosmic Abyss

Cosmic Abyss is a real-time spaceship survival game with two maintained
implementations: an Atari 8-bit VBXE build and a browser version that mirrors
the Atari rules and 320x200 systems console.

## Project structure

```text
.
|-- index.html                    Vite HTML entry
|-- src/
|   |-- game.js                   Browser game logic and canvas renderer
|   `-- styles.css                Responsive console and controls
|-- atari/
|   |-- ravaged-space.asm         MADS/VBXE source
|   `-- ravaged-space.xex         Built Atari executable
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

```sh
npm run build       # production build in dist/
npm run preview     # serve the production build locally
```

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

The command assembles `atari/ravaged-space.asm` into
`atari/ravaged-space.xex`.

Atari controls:

- joystick up/down selects a system
- Space performs the selected system action
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

Victory has its own spaceport-jump popup. Power, Life Support, and Processing
failures each use a separate loss scenario and message.

Random events appear in the narrow panel below the system table. Robot events
offer a one-point resource exchange for one or two points of another resource.
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
original browser interface. Seven custom 8x8 icons identify Power, Life Support,
Processing, Engineering, Guidance, Engines, and Sensors. The browser and Atari
versions share the same pixel masks; Atari expands them into coloured sprites at
VBXE VRAM `$039000` and draws each icon with one transparent blit.

The 320x200 console uses compact `STATUS`, `ACTION`, `LOAD`, and `MODS` columns.
System rows show icons only; the full icon names are collected in a three-line
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
