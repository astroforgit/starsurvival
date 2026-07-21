#!/usr/bin/env node

// Accelerated, frame-based simulation of the gameplay rules in
// atari/cosmic-abyss.asm. One simulated frame is one Atari 50 Hz game tick.

import { setTimeout as delay } from "node:timers/promises";

const NAMES = ["POWER", "LIFE", "PROCESSING", "ENGINEERING", "GUIDANCE", "ENGINES", "SENSORS"];
const INITIAL = [2, 7, 9, 2, 2, 1, 3];
const BASE_GAIN = [2, 1, 3, 2, 2, 3, 2];
const BASE_POWER_COST = [0, 1, 1, 2, 1, 3, 1];
const LIFE_COST = [0, 0, 0, 0, 0, 1, 0];
const BASE_PROCESSING_COST = [1, 0, 0, 2, 0, 0, 1];
const BIT = [1, 2, 4, 8, 16, 32, 64];
const SPECIAL_NAME = { 3: "INSTALL SOURCE", 4: "PLOT COURSE", 5: "ACTIVATE JUMPDRIVE", 6: "SCAN SECTOR" };

function numberArg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((arg) => arg.startsWith(prefix));
  return found ? Number(found.slice(prefix.length)) : fallback;
}

function hasArg(name) {
  return process.argv.includes(`--${name}`);
}

function clampResource(value) {
  return Math.max(0, Math.min(10, value));
}

class AtariGame {
  constructor(seed, { events = true } = {}) {
    this.initialSeed = seed || 0xa7;
    this.seed = seed || 0xa7;
    this.eventsEnabled = events;
    this.frame = 0;
    this.health = [...INITIAL];
    this.minimum = [...INITIAL];
    this.cooldown = Array(7).fill(0);
    this.cooldownFull = Array(7).fill(500); // 10 seconds at 50 Hz
    this.unlocked = [true, false, false, false, false, false, false];
    this.clicks = Array(7).fill(0);
    this.gain = [...BASE_GAIN];
    this.powerCost = [...BASE_POWER_COST];
    this.processingCost = [...BASE_PROCESSING_COST];
    this.loadPower = 0;
    this.loadLife = 1;
    this.systemLoadPower = Array(7).fill(0);
    this.systemLoadLife = [0, 1, 0, 0, 0, 0, 0];
    this.loadFrames = 200; // The assembly's first deduction is after 4 seconds.
    this.amountMask = 0;
    this.autoMask = 0;
    this.speedMask = 0;
    this.amountOpened = false;
    this.specialAvailable = Array(7).fill(false);
    this.specialDone = Array(7).fill(false);
    this.specialFrames = Array(7).fill(0);
    this.storyOpen = false;
    this.radioactive = 0;
    this.sourceInstalled = false;
    this.mode = "playing";
    this.failure = null;
    this.actions = [];
    this.loadHistory = [];
    this.event = null;
    this.eventWait = this.eventsEnabled ? this.random(5) + 1 : Infinity;
    this.secondFrame = 50;
  }

  randomStep() {
    const carry = this.seed & 1;
    this.seed >>>= 1;
    if (carry) this.seed ^= 0xb8;
    return this.seed;
  }

  random(modulo) {
    return this.randomStep() % modulo;
  }

  seconds() {
    return this.frame / 50;
  }

  record(kind, detail = "") {
    this.actions.push({ time: this.seconds(), kind, detail, health: [...this.health] });
  }

  actionActive(system) {
    if (this.specialAvailable[system]) return this.specialFrames[system] === 0;
    return this.unlocked[system] && this.cooldown[system] === 0 && (system < 3 || this.clicks[system] < 3);
  }

  safeToPay(system) {
    return this.health[0] > this.powerCost[system]
      && this.health[1] > LIFE_COST[system]
      && this.health[2] > this.processingCost[system];
  }

  perform(system, source = "KEY") {
    if (this.mode !== "playing" || !this.actionActive(system)) return false;

    if (this.specialAvailable[system]) {
      this.specialFrames[system] = 1000;
      this.record(`${source} ${SPECIAL_NAME[system]}`, "20.00s operation started");
      return true;
    }

    // The assembly allows lethal costs; the bot calls safeToPay first.
    this.health[2] = Math.max(0, this.health[2] - this.processingCost[system]);
    this.health[0] = Math.max(0, this.health[0] - this.powerCost[system]);
    this.health[1] = Math.max(0, this.health[1] - LIFE_COST[system]);
    this.health[system] = Math.min(10, this.health[system] + this.gain[system]);
    this.clicks[system] += 1;
    this.addSystemLoad(system);
    this.cooldown[system] = this.cooldownFull[system];
    this.record(`${source} ${NAMES[system]}`);
    this.updateProgress();
    this.updateSpecials();
    this.checkEnd();
    return true;
  }

  addSystemLoad(system) {
    if (system < 3) return;
    const click = this.clicks[system];
    const addPower = (amount) => {
      this.loadPower += amount;
      this.systemLoadPower[system] += amount;
    };
    const addLife = (amount) => {
      this.loadLife += amount;
      this.systemLoadLife[system] += amount;
    };

    if (click === 1) {
      addPower(1);
      if (system === 3 || system === 5) addLife(1);
    } else if (click === 2) {
      if (system === 3) addLife(1);
      if (system === 5) addPower(1);
    } else if (click === 3) {
      if (system === 3) { addPower(1); addLife(3); }
      if (system === 4) addPower(1);
      if (system === 5) addPower(3);
    }
  }

  updateProgress() {
    if (this.clicks[0] >= 2) this.unlocked[1] = true;
    if (this.clicks[1] >= 2) {
      this.unlocked[2] = true;
      this.unlocked[3] = true;
    }
    if (this.amountOpened) this.unlocked[4] = this.unlocked[5] = this.unlocked[6] = true;
  }

  updateSpecials() {
    if (this.clicks[6] >= 1 && !this.specialDone[6]) this.specialAvailable[6] = true;
    if (this.clicks[4] >= 2 && this.specialDone[6] && !this.specialDone[4]) this.specialAvailable[4] = true;
    if (this.clicks[5] >= 2 && this.specialDone[4] && !this.specialDone[5]) this.specialAvailable[5] = true;
    if (this.clicks[3] >= 2 && this.specialDone[5] && !this.specialDone[3]) this.specialAvailable[3] = true;
  }

  modificationCapacity(type) {
    const owner = { amount: 3, auto: 4, speed: 5 }[type];
    return Math.min(3, this.clicks[owner]);
  }

  modificationMask(type) {
    return this[`${type}Mask`];
  }

  canModify(type, system) {
    const mask = this.modificationMask(type);
    const used = [1, 2, 4].filter((bit) => mask & bit).length;
    return system < 3 && !(mask & BIT[system]) && used < this.modificationCapacity(type);
  }

  modify(type, system) {
    if (!this.canModify(type, system)) return false;
    this[`${type}Mask`] |= BIT[system];
    if (type === "amount") {
      this.amountOpened = true;
      this.gain[system] = [5, 3, 7][system];
      if (system === 0) this.processingCost[0] = 2;
      if (system === 2) this.powerCost[2] = 2;
      this.updateProgress();
    } else if (type === "speed") {
      this.cooldownFull[system] = 250;
      this.cooldown[system] = Math.ceil(this.cooldown[system] / 2);
    }
    this.record(`MOD ${type.toUpperCase()} ${NAMES[system]}`);
    return true;
  }

  tickSpecials() {
    for (let system = 3; system <= 6; system += 1) {
      if (!this.specialFrames[system]) continue;
      this.specialFrames[system] -= 1;
      if (this.specialFrames[system]) continue;
      this.specialAvailable[system] = false;
      this.specialDone[system] = true;
      this.storyOpen = true;
      if (system === 3) {
        this.sourceInstalled = true;
        this.gain[0] = 10;
        this.processingCost[0] = 0;
      }
      this.record(`${SPECIAL_NAME[system]} COMPLETE`);
      this.updateSpecials();
    }
  }

  tickAutos() {
    for (let system = 0; system < 3 && this.mode === "playing"; system += 1) {
      if ((this.autoMask & BIT[system]) && this.actionActive(system)) {
        this.perform(system, "AUTO");
      }
    }
  }

  startEvent() {
    if (this.random(4) !== 3) {
      const radiationOffer = this.random(4) === 0 && this.radioactive < 10;
      let source = radiationOffer ? 7 : this.random(3);
      if (!radiationOffer) {
        let tries = 3;
        while (this.health[source] < 2 && --tries) source = (source + 1) % 3;
        if (this.health[source] < 2) return this.startCodeEvent();
      }
      let destination = this.random(3);
      while (destination === source) destination = this.random(3);
      this.random(4); // Description selection affects the assembly RNG stream.
      this.event = { type: "trade", source, destination, radiationOffer, window: 10 };
      return;
    }
    this.startCodeEvent();
  }

  startCodeEvent() {
    let mode = this.random(4);
    if (mode === 2 && this.radioactive >= 9) mode = 0;
    if (mode === 3 && this.radioactive < 2) mode = 1;
    let destination = 7;
    let gain = 2;
    if (mode < 2) {
      destination = this.random(3);
      gain = this.random(2) + 1;
      this.random(4); // Description.
    }
    for (let i = 0; i < 4; i += 1) this.random(10); // Challenge digits.
    this.event = { type: "code", mode, destination, gain, entered: 0, window: 10 };
  }

  answerEvent() {
    if (!this.event) return;
    if (this.event.type === "trade") {
      const { source, destination } = this.event;
      // The reproducible survival strategy rejects robot trades. Although a
      // good offer can net one point, its cost can remove the exact reserve
      // needed at the next load boundary; radioactive offers are worse.
      const accept = false;
      if (accept) {
        this.health[source] -= 1;
        this.health[destination] = clampResource(this.health[destination] + 2);
        this.record("EVENT TRADE ACCEPTED", `${NAMES[source]} -> ${NAMES[destination]}`);
      }
      this.event = { type: "result", window: 1 };
      this.checkEnd();
      return;
    }

    this.event.entered += 1;
    if (this.event.entered < 4) return; // Atari accepts at most one digit/key press per loop.
    const { mode, destination, gain } = this.event;
    if (mode === 0) this.health[destination] = clampResource(this.health[destination] + gain);
    if (mode === 3) this.radioactive = Math.max(0, this.radioactive - gain);
    this.record("EVENT CODE SOLVED", ["salvage", "hazard", "radiation leak", "cleanup"][mode]);
    this.event = { type: "result", window: 1 };
    this.checkEnd();
  }

  tickEvents() {
    if (!this.eventsEnabled) return;
    if (this.event) {
      this.event.window -= 1;
      if (this.event.window <= 0) {
        this.event = null;
        this.eventWait = this.random(5) + 1;
      }
      return;
    }
    this.eventWait -= 1;
    if (this.eventWait <= 0) this.startEvent();
  }

  checkEnd() {
    this.minimum = this.minimum.map((value, i) => Math.min(value, this.health[i]));
    if (this.radioactive >= 10) {
      this.mode = "lost";
      this.failure = "RADIOACTIVE";
      return;
    }
    const failed = this.health.findIndex((value) => value === 0);
    if (failed >= 0) {
      this.mode = "lost";
      this.failure = NAMES[failed];
      return;
    }
    if (this.health.slice(3).every((value) => value >= 8)) this.mode = "won";
  }

  tick() {
    if (this.mode !== "playing") return;
    this.frame += 1;
    if (this.storyOpen) {
      this.storyOpen = false; // The bot presses Space on the next frame.
      return;
    }
    for (let i = 0; i < 7; i += 1) if (this.cooldown[i]) this.cooldown[i] -= 1;
    this.tickSpecials();
    this.tickAutos();
    this.loadFrames -= 1;
    this.secondFrame -= 1;
    if (this.secondFrame === 0) {
      this.secondFrame = 50;
      this.tickEvents();
    }
    if (this.loadFrames === 0 && this.mode === "playing") {
      this.loadFrames = 1000;
      this.health[0] = Math.max(0, this.health[0] - this.loadPower);
      this.health[1] = Math.max(0, this.health[1] - this.loadLife);
      this.loadHistory.push({ time: this.seconds(), power: this.loadPower, life: this.loadLife, health: [...this.health] });
      this.record("20s LOAD", `-${this.loadPower} Power, -${this.loadLife} Life`);
      this.checkEnd();
    }
  }
}

class KeySpamBot {
  constructor(game) {
    this.game = game;
  }

  resourceTarget(system) {
    const g = this.game;
    const base = system === 0 ? 9 : system === 1 ? 8 : 8;
    if (g.sourceInstalled && system === 0) return 10;
    return base;
  }

  addedLoad(system) {
    const click = this.game.clicks[system] + 1;
    let power = 0;
    let life = 0;
    if (click === 1) {
      power = 1;
      if (system === 3 || system === 5) life = 1;
    } else if (click === 2) {
      if (system === 3) life = 1;
      if (system === 5) power = 1;
    } else if (click === 3) {
      if (system === 3) { power = 1; life = 3; }
      if (system === 4) power = 1;
      if (system === 5) power = 3;
    }
    return { power, life };
  }

  survivesNextLoad(system) {
    const g = this.game;
    let power = g.health[0] - g.powerCost[system];
    let life = g.health[1] - LIFE_COST[system];
    if (system === 0) power = Math.min(10, power + g.gain[0]);
    if (system === 1) life = Math.min(10, life + g.gain[1]);
    // If Generate Power/Cycle Air will be ready before the deduction, the bot
    // still has a chance to replenish; otherwise retain at least one point.
    const powerCanRecover = system !== 0 && g.cooldown[0] < g.loadFrames;
    const lifeCanRecover = system !== 1 && g.cooldown[1] < g.loadFrames;
    return (powerCanRecover || power > g.loadPower)
      && (lifeCanRecover || life > g.loadLife);
  }

  actionWouldWin(system) {
    const g = this.game;
    return system >= 3
      && Math.min(10, g.health[system] + g.gain[system]) >= 8
      && g.health.slice(3).every((value, index) => index === system - 3 || value >= 8);
  }

  pressOneKey() {
    const g = this.game;
    if (g.event?.type === "trade" || g.event?.type === "code") {
      g.answerEvent();
      return;
    }

    // Buy improvements as their Engineering/Guidance/Engines capacity grows.
    // Amount is useful immediately. Automation is delayed until the renewable
    // source is safe, avoiding an unattended action spending the last resource.
    for (const system of [0, 1, 2]) if (g.modify("amount", system)) return;
    for (const system of [0, 1, 2]) if (g.modify("speed", system)) return;
    if (g.sourceInstalled) {
      // Auto Power is free after Install Source and upgraded Auto Life is cheap.
      // Auto Processing still spends two Power, so leave that one manual.
      for (const system of [0, 1]) if (g.modify("auto", system)) return;
    }

    // Specials replace their corresponding repair key and are always advanced.
    for (const system of [6, 4, 5, 3]) {
      if (g.specialAvailable[system] && g.actionActive(system)) {
        g.perform(system);
        return;
      }
    }

    // Protect the three consumable resources. This is the equivalent of a
    // player repeatedly pressing whichever ready production key is most useful.
    const resourceOrder = [0, 2, 1].sort((a, b) => {
      const pressure = (system) => (this.resourceTarget(system) - g.health[system]) / g.gain[system];
      return pressure(b) - pressure(a);
    });
    for (const system of resourceOrder) {
      if (g.actionActive(system) && g.safeToPay(system) && this.survivesNextLoad(system)
          && g.health[system] < this.resourceTarget(system)) {
        g.perform(system);
        return;
      }
    }

    // Repair in story order where possible. Keep a larger Power/Life reserve
    // as permanent load accumulates and never intentionally pay a lethal cost.
    const repairOrder = g.sourceInstalled
      ? [6, 4, 3, 5] // cheapest final loads first; Engines completes the game
      : g.specialDone[6] ? [4, 5, 3, 6] : [6, 4, 5, 3];
    for (const system of repairOrder) {
      if (!g.actionActive(system) || !g.safeToPay(system)) continue;
      // Two repairs are enough to unlock every story operation. The third
      // repairs add the harshest permanent loads, so a real player can safely
      // postpone them until Install Source has completed.
      if (!g.sourceInstalled && g.clicks[system] >= 2) continue;
      const powerAfter = g.health[0] - g.powerCost[system];
      const lifeAfter = g.health[1] - LIFE_COST[system];
      const added = this.addedLoad(system);
      const reservePower = Math.min(10, Math.max(2, g.loadPower + added.power + 1));
      const reserveLife = Math.min(10, Math.max(2, g.loadLife + added.life + 1));
      if (this.actionWouldWin(system) || (powerAfter >= reservePower && lifeAfter >= reserveLife)) {
        g.perform(system);
        return;
      }
    }

    // Unlocking actions sometimes must happen below the normal reserve.
    for (const system of [0, 1, 2]) {
      if (g.actionActive(system) && g.safeToPay(system) && this.survivesNextLoad(system)) {
        g.perform(system);
        return;
      }
    }
    if (g.clicks[3] === 0 && g.actionActive(3) && g.safeToPay(3)) g.perform(3);
  }
}

async function simulate(seed, options) {
  const game = new AtariGame(seed, options);
  const bot = new KeySpamBot(game);
  const maxFrames = options.maxSeconds * 50;
  let wallSecond = 0;
  while (game.mode === "playing" && game.frame < maxFrames) {
    game.tick();
    if (game.mode === "playing") bot.pressOneKey();
    if (options.scale > 0 && Math.floor(game.seconds()) > wallSecond) {
      wallSecond = Math.floor(game.seconds());
      await delay(1000 * options.scale);
    }
  }
  if (game.mode === "playing") {
    game.mode = "timeout";
    game.failure = "time limit";
  }
  return game;
}

function printRun(game, verbose) {
  const status = game.mode.toUpperCase();
  console.log(`${status} seed=${game.initialSeed.toString(16).padStart(2, "0")} time=${game.seconds().toFixed(2)}s`);
  console.log(`  final: ${NAMES.map((name, i) => `${name}=${game.health[i]}`).join(" ")} RADIOACTIVE=${game.radioactive}`);
  console.log(`  minimum: ${NAMES.slice(0, 3).map((name, i) => `${name}=${game.minimum[i]}`).join(" ")}`);
  console.log(`  final recurring load: -${game.loadPower} Power / -${game.loadLife} Life every 20s`);
  console.log(`  repairs: E=${game.clicks[3]} G=${game.clicks[4]} N=${game.clicks[5]} S=${game.clicks[6]}; source=${game.sourceInstalled ? "installed" : "not installed"}`);
  if (game.failure) console.log(`  stopped: ${game.failure}`);
  if (verbose) {
    for (const action of game.actions) {
      const resources = action.health.slice(0, 3).join("/");
      console.log(`  ${action.time.toFixed(2).padStart(7)}s  ${action.kind.padEnd(28)} P/L/O=${resources}${action.detail ? `  ${action.detail}` : ""}`);
    }
  }
}

const runs = Math.max(1, numberArg("runs", 100));
const firstSeed = Math.max(1, numberArg("seed", 1)) & 0xff;
const options = {
  events: !hasArg("no-events"),
  maxSeconds: numberArg("max-seconds", 600),
  scale: numberArg("scale", 0),
};
const verbose = hasArg("verbose") || runs === 1;
const results = [];
for (let i = 0; i < runs; i += 1) {
  const seed = ((firstSeed + i - 1) % 255) + 1;
  results.push(await simulate(seed, options));
}

if (runs === 1) {
  printRun(results[0], verbose);
} else {
  const wins = results.filter((game) => game.mode === "won");
  const losses = results.filter((game) => game.mode === "lost");
  const timeouts = results.filter((game) => game.mode === "timeout");
  const times = wins.map((game) => game.seconds());
  console.log(`Atari accelerated simulation: ${runs} deterministic RNG seeds`);
  console.log(`  wins=${wins.length} losses=${losses.length} timeouts=${timeouts.length}`);
  if (wins.length) {
    console.log(`  win time: min=${Math.min(...times).toFixed(2)}s avg=${(times.reduce((a, b) => a + b, 0) / times.length).toFixed(2)}s max=${Math.max(...times).toFixed(2)}s`);
    const lowest = [0, 1, 2].map((system) => Math.min(...wins.map((game) => game.minimum[system])));
    console.log(`  lowest winning resources: Power=${lowest[0]} Life=${lowest[1]} Processing=${lowest[2]}`);
  }
  if (losses.length || timeouts.length) printRun(losses[0] || timeouts[0], false);
}
