"use strict";

const titleImageUrl = new URL("../pic/girl1.png", import.meta.url).href;
const powerFailureImageUrl = new URL("../pic/gameover-power-web.png", import.meta.url).href;
const repairImageUrl = new URL("../pic/repair-web.png", import.meta.url).href;
const successImageUrl = new URL("../pic/success-web.png", import.meta.url).href;

// Browser equivalents of the Atari data tables. Keep ordering synchronized
// with health/cooldown/unlocked/clicks in atari/cosmic-abyss.asm.
const SCR_W = 320;
const SCR_H = 200;
const INITIAL_HEALTH = [2, 7, 9, 2, 2, 1, 3];
const BASE_GAIN = [2, 1, 3, 2, 2, 3, 2];
const COST_PWR = [0, 1, 1, 2, 1, 3, 1];
const COST_LIF = [0, 0, 0, 0, 0, 1, 0];
const COST_PRC = [1, 0, 0, 2, 0, 0, 1];
const NAMES = ["POWER", "LIFE SUPPORT", "PROCESSING", "ENGINEERING", "GUIDANCE", "ENGINES", "SENSORS"];
const ACTION_KEYS = ["P", "L", "O", "E", "G", "I", "S"];
const EVENT_TEST_MODE = true;
const TRADE_PROMPTS = ["OPPORTUNITY", "DO YOU WANT", "HAVE OPTION", "ROBOT OFFER"];
const SALVAGE_DESCRIPTIONS = ["ALPHA MACHINE", "HELP RESEARCH", "REPAIR DRONE", "RESTORE RELAY"];
const HAZARD_DESCRIPTIONS = ["COOLANT LEAK", "RESEARCH FIRE", "POWER SURGE", "CORE FAILURE"];
const RADIOACTIVE_ICON = 7;
const RADIOACTIVE_ROW_Y = 60;
// Match the Atari layout: resources stay compact, Radioactive occupies the
// separator, and every main-system row is shifted down together.
const ROW_Y = [18, 32, 46, 80, 94, 108, 122];
const ICONS = [
  [0x18, 0x18, 0x30, 0x7c, 0x18, 0x30, 0x20, 0x00], // power: bolt
  [0x66, 0xff, 0xff, 0x7e, 0x3c, 0x18, 0x00, 0x00], // life support: heart
  [0x5a, 0x5a, 0x5a, 0x99, 0x99, 0x99, 0x99, 0x00], // processing: Atari Fuji
  [0xc3, 0x66, 0x3c, 0x18, 0x38, 0x60, 0xc0, 0x00], // engineering: wrench
  [0x18, 0x7e, 0xdb, 0xff, 0xbd, 0x7e, 0x42, 0x00], // guidance: robot
  [0x18, 0x3c, 0x7e, 0x5a, 0x5a, 0x3c, 0x66, 0x00], // engines: rocket
  [0x06, 0x0c, 0x58, 0x30, 0x30, 0x7e, 0x18, 0x00], // sensors: dish
  [0x3c, 0x7e, 0xa5, 0x99, 0xdb, 0xe7, 0x66, 0x3c]  // radioactive: circular ☢ trefoil
];
const ICON_COLORS = ["#e8b84c", "#d76a45", "#d89c4a", "#a8aa8d", "#62a881", "#cb7f35", "#778f76", "#d7df42"];
const TINY_FONT = {
  A: [2, 5, 7, 5, 5], B: [6, 5, 6, 5, 6], C: [3, 4, 4, 4, 3], D: [6, 5, 5, 5, 6],
  E: [7, 4, 6, 4, 7], F: [7, 4, 6, 4, 4], G: [3, 4, 5, 5, 3], H: [5, 5, 7, 5, 5],
  I: [7, 2, 2, 2, 7], J: [1, 1, 1, 5, 2], K: [5, 5, 6, 5, 5], L: [4, 4, 4, 4, 7],
  M: [5, 7, 7, 5, 5], N: [5, 7, 7, 7, 5], O: [2, 5, 5, 5, 2], P: [6, 5, 6, 4, 4],
  Q: [2, 5, 5, 3, 1], R: [6, 5, 6, 5, 5], S: [3, 4, 2, 1, 6], T: [7, 2, 2, 2, 2],
  U: [5, 5, 5, 5, 7], V: [5, 5, 5, 5, 2], W: [5, 5, 7, 7, 5], X: [5, 5, 2, 5, 5],
  Y: [5, 5, 2, 2, 2], Z: [7, 1, 2, 4, 7]
};

const C = {
  bg: "#010704", border: "#1fb861", win: "#03130b", text: "#82f5a7",
  title: "#b7ffca", value: "#8dffae", hint: "#378d59", online: "#50ff86",
  degraded: "#b7d94a", offline: "#ff6e55", selected: "#0d3b23",
  cooldown: "#14522f", loadProgress: "#0d3e25"
};

const canvas = document.querySelector("#screen");
const ctx = canvas.getContext("2d", { alpha: false });
const announcement = document.querySelector("#announcement");
const titleScreen = document.querySelector("#title-screen");
const titleArt = document.querySelector("#title-art");
titleArt.src = titleImageUrl;
ctx.imageSmoothingEnabled = false;

let titleActive = true;
let briefingActive = false;
let briefingChars = 0;
let briefingStarted = 0;
let selected;
let loadSec;
let gameMode; // 0 playing, 1 won, 2 lost
let health;
let cooldown;
let cooldownMax;
let unlocked;
let clicks;
let loadPwr;
let loadLif;
let systemLoadPwr;
let systemLoadLif;
let gainTab;
let actionCostPwr;
let actionCostPrc;
let amountMask;
let autoMask;
let speedMask;
let modalType;
let amountOpened;
let specialAvailable;
let specialDone;
let specialTimer;
let storyType;
let failureSystem;
let radioactive;
let deniedUntil;
let eventType;
let eventMode;
let eventNextSec;
let eventWindow;
let eventSource;
let eventDest;
let eventGain;
let eventCode;
let eventEntered;
let eventResult;
let eventDescription;
let eventRadioactiveOffer;
let lastTime = performance.now();

const failureImage = new Image();
failureImage.addEventListener("load", () => {
  if (!titleActive && gameMode === 2) drawScreen();
});
failureImage.src = powerFailureImageUrl;

const successImage = new Image();
successImage.addEventListener("load", () => {
  if (!titleActive && gameMode === 1) drawScreen();
});
successImage.src = successImageUrl;

const FAILURE_TEXT = {
  0: ["POWER SYSTEM FAILURE", "THE REACTOR FALLS SILENT.", "THE LAST LIGHT FADES OUT."],
  1: ["LIFE SUPPORT FAILURE", "OXYGEN FALLS BELOW SURVIVAL.", "NO HEARTBEATS REMAIN."],
  2: ["PROCESSING CORE FAILURE", "SHIP CONTROL LOOPS COLLAPSE.", "THE CORE BURNS IN SILENCE."],
  3: ["ENGINEERING SYSTEM FAILURE", "THE HULL CANNOT BE STABILIZED.", "THE SHIP BREAKS APART."],
  4: ["GUIDANCE SYSTEM FAILURE", "THE ORPHEUS LOSES ITS COURSE.", "THE ABYSS HAS NO HORIZON."],
  5: ["ENGINE SYSTEM FAILURE", "THE JUMP DRIVE FALLS SILENT.", "THE SHIP DRIFTS FOREVER."],
  6: ["SENSOR SYSTEM FAILURE", "THE DARKNESS BECOMES ABSOLUTE.", "NOTHING ANSWERS THE VOID."],
  7: ["RADIATION LEVEL CRITICAL", "NO LIFE SIGNS DETECTED.", "THE ORPHEUS DRIFTS ON."]
};

const BRIEFING_LINES = [
  "AN ASTEROID STRIKE HAS LEFT",
  "YOUR SHIP DRIFTING IN DARKNESS.",
  "KEEP POWER, AIR, AND PROCESSING",
  "ALIVE WHILE YOU REPAIR THE SHIP.",
  "RESTORE MAIN SYSTEMS AND ESCAPE."
];
const BRIEFING_LENGTH = BRIEFING_LINES.reduce((total, line) => total + line.length, 0);
const repairImage = new Image();
repairImage.addEventListener("load", () => {
  if (briefingActive) drawBriefing();
});
repairImage.src = repairImageUrl;

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value));
}

function isActionActive(index) {
  if (specialAvailable[index]) return specialTimer[index] === 0;
  return Boolean(unlocked[index]) && cooldown[index] === 0 && !(index >= 3 && clicks[index] >= 3);
}

function gameInit() {
  selected = 0;
  loadSec = 4;
  gameMode = 0;
  health = [...INITIAL_HEALTH];
  cooldown = [0, 0, 0, 0, 0, 0, 0];
  cooldownMax = [10, 10, 10, 10, 10, 10, 10];
  unlocked = [1, 0, 0, 0, 0, 0, 0];
  clicks = [0, 0, 0, 0, 0, 0, 0];
  loadPwr = 0;
  loadLif = 1;
  systemLoadPwr = [0, 0, 0, 0, 0, 0, 0];
  systemLoadLif = [0, 1, 0, 0, 0, 0, 0];
  gainTab = [...BASE_GAIN];
  actionCostPwr = [...COST_PWR];
  actionCostPrc = [...COST_PRC];
  amountMask = 0;
  autoMask = 0;
  speedMask = 0;
  modalType = null;
  amountOpened = false;
  specialAvailable = [0, 0, 0, 0, 0, 0, 0];
  specialDone = [0, 0, 0, 0, 0, 0, 0];
  specialTimer = [0, 0, 0, 0, 0, 0, 0];
  storyType = null;
  failureSystem = -1;
  radioactive = 0;
  deniedUntil = 0;
  initEvents();
  announce("New game. Power selected.");
  drawScreen();
}

function randomInt(max) {
  return Math.floor(Math.random() * max);
}

function scheduleNextEvent() {
  eventNextSec = 1 + randomInt(5);
}

function initEvents() {
  eventType = null;
  eventMode = null;
  eventWindow = 0;
  eventSource = 0;
  eventDest = 0;
  eventGain = 0;
  eventCode = [];
  eventEntered = "";
  eventResult = "";
  eventDescription = "";
  eventRadioactiveOffer = false;
  scheduleNextEvent();
  updateEventControls();
}

function startRandomEvent() {
  const safeSources = [0, 1, 2].filter(index => health[index] >= 2);
  eventRadioactiveOffer = false;
  if (Math.random() < 0.75 && (safeSources.length || radioactive < 10)) {
    eventType = "decision";
    eventMode = "trade";
    eventRadioactiveOffer = radioactive < 10 && (!safeSources.length || Math.random() < 1 / 3);
    if (eventRadioactiveOffer) {
      eventSource = RADIOACTIVE_ICON;
      eventDest = randomInt(3);
    } else {
      eventSource = safeSources[randomInt(safeSources.length)];
      const destinations = [0, 1, 2].filter(index => index !== eventSource);
      eventDest = destinations[randomInt(destinations.length)];
    }
    eventGain = 2;
    eventDescription = TRADE_PROMPTS[randomInt(TRADE_PROMPTS.length)];
    eventWindow = 10;
  } else {
    eventType = "code";
    const modes = ["salvage", "hazard"];
    if (radioactive <= 8) modes.push("radioactiveLeak");
    if (radioactive >= 2) modes.push("clearRadioactiveLeak");
    eventMode = modes[randomInt(modes.length)];
    eventDest = eventMode === "salvage" || eventMode === "hazard" ? randomInt(3) : RADIOACTIVE_ICON;
    eventGain = eventMode === "radioactiveLeak" || eventMode === "clearRadioactiveLeak"
      ? 2
      : 1 + randomInt(2);
    eventCode = Array.from({ length: 4 }, () => randomInt(10));
    if (eventMode === "radioactiveLeak") eventDescription = "RADIOACTIVE LEAK";
    else if (eventMode === "clearRadioactiveLeak") eventDescription = "CLEAR RADIOACTIVE LEAK";
    else {
      const descriptions = eventMode === "salvage" ? SALVAGE_DESCRIPTIONS : HAZARD_DESCRIPTIONS;
      eventDescription = descriptions[randomInt(descriptions.length)];
    }
    eventEntered = "";
    eventWindow = 10;
  }
  updateEventControls();
  announce(eventType === "decision" ? "Robot trade offer. Press Y or N." : "Emergency code event. Enter four digits.");
}

function finishEvent(result, seconds = 3) {
  eventType = "result";
  eventResult = result;
  eventWindow = EVENT_TEST_MODE ? 1 : seconds;
  eventEntered = "";
  updateEventControls();
}

function applyEventResource(index, amount) {
  health[index] = clamp(health[index] + amount, 0, 10);
}

function acceptDecisionEvent() {
  if (eventType !== "decision") return false;
  if (eventRadioactiveOffer) radioactive = clamp(radioactive + 1, 0, 10);
  else applyEventResource(eventSource, -1);
  applyEventResource(eventDest, eventGain);
  finishEvent("trade");
  announce(eventRadioactiveOffer
    ? `Robot offer accepted: 1 Radioactive added for ${eventGain} ${NAMES[eventDest]}.`
    : `Robot trade accepted: 1 ${NAMES[eventSource]} for ${eventGain} ${NAMES[eventDest]}.`);
  checkEnd();
  return true;
}

function rejectDecisionEvent() {
  if (eventType !== "decision") return false;
  finishEvent("rejected", 2);
  announce("Robot trade rejected.");
  return true;
}

function completeCodeEvent() {
  if (eventMode === "salvage") {
    applyEventResource(eventDest, eventGain);
    finishEvent("salvage");
    announce(`Salvage secured: ${eventGain} ${NAMES[eventDest]}.`);
  } else if (eventMode === "clearRadioactiveLeak") {
    radioactive = clamp(radioactive - eventGain, 0, 10);
    finishEvent("radioactiveCleared");
    announce(`Radioactive leak cleared. Radioactive decreased to ${radioactive}.`);
  } else if (eventMode === "radioactiveLeak") {
    finishEvent("leakPrevented");
    announce("Radioactive leak prevented.");
  } else {
    finishEvent("prevented");
    announce(`Hazard prevented. ${NAMES[eventDest]} protected.`);
  }
  checkEnd();
}

function failCodeEvent() {
  if (eventMode === "hazard") {
    applyEventResource(eventDest, -eventGain);
    finishEvent("failed");
    announce(`Code failed: lost ${eventGain} ${NAMES[eventDest]}.`);
  } else if (eventMode === "radioactiveLeak") {
    radioactive = clamp(radioactive + eventGain, 0, 10);
    finishEvent("radioactiveIncreased");
    announce(`Radioactive leak. Radioactive increased to ${radioactive}.`);
  } else if (eventMode === "clearRadioactiveLeak") {
    finishEvent("cleanupFailed");
    announce("Radioactive cleanup failed.");
  } else {
    finishEvent("missed");
    announce("Salvage opportunity missed.");
  }
  checkEnd();
}

function enterEventDigit(digit) {
  if (eventType !== "code") return false;
  const expected = eventCode[eventEntered.length];
  if (digit === expected) eventEntered = `${eventEntered}${digit}`;
  if (eventEntered.length === 4) completeCodeEvent();
  updateEventControls();
  return true;
}

function tickEvents(deltaSeconds) {
  if (eventType === "decision") {
    eventWindow -= deltaSeconds;
    if (eventWindow <= 0) rejectDecisionEvent();
    return;
  }
  if (eventType === "code") {
    eventWindow -= deltaSeconds;
    if (eventWindow <= 0) failCodeEvent();
    return;
  }
  if (eventType === "result") {
    eventWindow -= deltaSeconds;
    if (eventWindow <= 0) {
      eventType = null;
      eventResult = "";
      scheduleNextEvent();
      updateEventControls();
    }
    return;
  }
  eventNextSec -= deltaSeconds;
  if (eventNextSec <= 0) startRandomEvent();
}

function updateEventControls() {
  document.querySelector(".decision-keys")?.toggleAttribute("hidden", eventType !== "decision");
  document.querySelector(".code-keys")?.toggleAttribute("hidden", eventType !== "code");
}

function startGame() {
  if (!titleActive) return false;
  titleActive = false;
  briefingActive = true;
  briefingChars = 0;
  briefingStarted = performance.now();
  titleScreen.classList.add("is-hidden");
  drawBriefing();
  canvas.focus({ preventScroll: true });
  return true;
}

function advanceBriefing() {
  if (!briefingActive) return false;
  briefingActive = false;
  lastTime = performance.now();
  gameInit();
  return true;
}

function performAction(actionIndex = selected) {
  if (gameMode) {
    gameInit();
    return;
  }
  if (!isActionActive(actionIndex)) return;
  selected = actionIndex;
  const i = selected;

  if (specialAvailable[i]) {
    specialTimer[i] = 20;
    announce(`${getSpecialName(i)} started.`);
    drawScreen();
    return;
  }

  health[2] = Math.max(-1, health[2] - actionCostPrc[i]);
  health[0] = Math.max(-1, health[0] - actionCostPwr[i]);
  health[1] = Math.max(-1, health[1] - COST_LIF[i]);
  health[i] = clamp(health[i] + gainTab[i], 0, 10);
  clicks[i]++;
  addSystemLoad(i);
  cooldownMax[i] = speedMask & (1 << i) ? 5 : 10;
  cooldown[i] = cooldownMax[i];
  updateProgress();
  updateSpecials();
  checkEnd();
  announce(`${NAMES[i]} action complete. Status ${health[i]} of 10.`);
  drawScreen();
}

function addSystemLoad(i) {
  if (i < 3) return;
  if (clicks[i] === 1) {
    loadPwr++;
    systemLoadPwr[i]++;
    if (i === 3 || i === 5) {
      loadLif++;
      systemLoadLif[i]++;
    }
  } else if (clicks[i] === 2) {
    if (i === 3) {
      loadLif++;
      systemLoadLif[i]++;
    }
    if (i === 5) {
      loadPwr++;
      systemLoadPwr[i]++;
    }
  } else if (clicks[i] === 3) {
    if (i === 3) {
      loadPwr++;
      loadLif += 3;
      systemLoadPwr[i]++;
      systemLoadLif[i] += 3;
    } else if (i === 4) {
      loadPwr++;
      systemLoadPwr[i]++;
    } else if (i === 5) {
      loadPwr += 3;
      systemLoadPwr[i] += 3;
    }
  }
}

function updateProgress() {
  if (clicks[0] >= 2) unlocked[1] = 1;
  if (clicks[1] >= 2) {
    unlocked[2] = 1;
    unlocked[3] = 1;
  }
  if (amountOpened) unlocked.fill(1, 4);
}

function getSpecialName(index) {
  return ({ 3: "INSTALL", 4: "PLOT", 5: "JUMP", 6: "SCAN" })[index] || "";
}

function updateSpecials() {
  if (clicks[6] >= 1 && !specialDone[6]) specialAvailable[6] = 1;
  if (clicks[4] >= 2 && specialDone[6] && !specialDone[4]) specialAvailable[4] = 1;
  if (clicks[5] >= 2 && specialDone[4] && !specialDone[5]) specialAvailable[5] = 1;
  if (clicks[3] >= 2 && specialDone[5] && !specialDone[3]) specialAvailable[3] = 1;
}

function completeSpecial(index) {
  specialTimer[index] = 0;
  specialAvailable[index] = 0;
  specialDone[index] = 1;
  if (index === 3) {
    gainTab[0] = 10;
    actionCostPrc[0] = 0;
  }
  updateSpecials();
  storyType = index;
  announce(`${getSpecialName(index)} complete.`);
}

function buyAmount() {
  openModification("amount");
}

function buyAuto() {
  openModification("auto");
}

function buySpeed() {
  openModification("speed");
}

const MOD_MAIN_SYSTEM = { amount: 3, auto: 4, speed: 5 };

function getMask(type) {
  return type === "amount" ? amountMask : type === "auto" ? autoMask : speedMask;
}

function countBits(value) {
  let count = 0;
  for (; value; value >>= 1) count += value & 1;
  return count;
}

function modificationAvailable(type) {
  const mask = getMask(type);
  return countBits(mask) < Math.min(clicks[MOD_MAIN_SYSTEM[type]], 3) && mask !== 7;
}

function openModification(type) {
  if (gameMode || modalType || !modificationAvailable(type)) return;
  modalType = type;
  if (type === "amount") {
    amountOpened = true;
    updateProgress();
  }
  announce(`${type} modification. Choose Power, Life Support, or Processing.`);
  drawScreen();
}

function closeModification() {
  modalType = null;
  drawScreen();
}

function selectModification(index) {
  if (!modalType || index < 0 || index > 2) return;
  const bit = 1 << index;
  if (getMask(modalType) & bit) return;
  const type = modalType;
  if (type === "amount") {
    amountMask |= bit;
    gainTab[index] = [5, 3, 7][index];
    if (index === 0) actionCostPrc[0] = 2;
    if (index === 2) actionCostPwr[2] = 2;
  } else if (type === "auto") {
    autoMask |= bit;
  } else {
    speedMask |= bit;
    cooldown[index] /= 2;
    cooldownMax[index] = 5;
  }
  modalType = null;
  announce(`${type} modification installed for ${NAMES[index]}.`);
  drawScreen();
}

function actionDenied() {
  deniedUntil = performance.now() + 1400;
  announce("Action locked, cooling, or too costly.");
  drawScreen();
}

function tickGame(deltaSeconds) {
  for (let i = 0; i < cooldown.length; i++) {
    cooldown[i] = Math.max(0, cooldown[i] - deltaSeconds);
    if (i < 3 && (autoMask & (1 << i)) && isActionActive(i)) performAction(i);
    if (specialTimer[i] > 0) {
      specialTimer[i] = Math.max(0, specialTimer[i] - deltaSeconds);
      if (specialTimer[i] === 0) completeSpecial(i);
    }
  }

  loadSec -= deltaSeconds;

  if (loadSec <= 0) {
    loadSec += 20;
    health[0] = clamp(health[0] - loadPwr, 0, 10);
    health[1] = clamp(health[1] - loadLif, 0, 10);
    announce(`Load cycle deducted ${loadPwr} power and ${loadLif} life support.`);
    checkEnd();
  }

  if (!gameMode) tickEvents(deltaSeconds);
}

function checkEnd() {
  if (radioactive >= 10) {
    failureSystem = RADIOACTIVE_ICON;
    gameMode = 2;
    return;
  }
  const failed = health.findIndex(value => value <= 0);
  if (failed >= 0) {
    failureSystem = failed;
    gameMode = 2;
  }
  else if (health.slice(3).every(value => value >= 8)) gameMode = 1;
}

function fillRect(x, y, width, height, color) {
  ctx.fillStyle = color;
  ctx.fillRect(x, y, width, height);
}

function fillRoundRect(x, y, width, height, radius, color) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(x, y, width, height, radius);
  ctx.fill();
}

function textAt(text, x, y, color = C.text, align = "left") {
  ctx.fillStyle = color;
  ctx.font = '700 8px "Arial Narrow", "Liberation Sans Narrow", "Lucida Console", monospace';
  ctx.textBaseline = "top";
  ctx.textAlign = align;
  ctx.fillText(text, x, y);
}

function tinyTextAt(text, x, y, color = C.text) {
  for (const character of text) {
    const rows = TINY_FONT[character];
    if (rows) {
      rows.forEach((bits, row) => {
        for (let column = 0; column < 3; column++) {
          if (bits & (4 >> column)) fillRect(x + column, y + row, 1, 1, color);
        }
      });
    }
    x += 4;
  }
}

function drawIcon(index, x, y) {
  if (index === RADIOACTIVE_ICON) {
    ctx.fillStyle = ICON_COLORS[index];
    ctx.font = '10px "DejaVu Sans", "Arial Unicode MS", sans-serif';
    ctx.textBaseline = "top";
    ctx.textAlign = "left";
    ctx.fillText("☢", x - 1, y - 2);
    return;
  }
  const rows = ICONS[index];
  for (let row = 0; row < 8; row++) {
    for (let column = 0; column < 8; column++) {
      if (rows[row] & (0x80 >> column)) fillRect(x + column, y + row, 1, 1, ICON_COLORS[index]);
    }
  }
}

function drawStatusBoxes(value, x, y, color, rowBackground) {
  for (let cell = 0; cell < 10; cell++) {
    const cellX = x + cell * 8;
    if (cell < value) {
      fillRoundRect(cellX, y, 7, 6, 2, color);
    } else {
      fillRoundRect(cellX, y, 7, 6, 2, C.hint);
      fillRoundRect(cellX + 1, y + 1, 5, 4, 1, rowBackground);
    }
  }
}

function drawScreen() {
  fillRect(0, 0, SCR_W, SCR_H, C.bg);
  fillRoundRect(4, 3, 312, 194, 5, C.border);
  fillRoundRect(6, 5, 308, 190, 4, C.win);
  textAt("KEY", 8, 8, C.hint);
  textAt("STATUS", 32, 8, C.hint);
  textAt("ACTION", 116, 8, C.hint);
  textAt("LOAD", 216, 8, C.hint);
  textAt("M", 288, 8, C.hint);
  drawRows();
  drawFooter();
  drawEventPanel();
  if (gameMode) drawEnd();
  else if (modalType) drawModificationModal();
  else if (storyType !== null) drawStoryModal();
}

function drawRows() {
  for (let i = 0; i < NAMES.length; i++) {
    const y = ROW_Y[i];
    const rowBackground = C.win;
    if ((unlocked[i] && cooldown[i] > 0) || specialTimer[i] > 0) {
      const progress = specialTimer[i] > 0 ? specialTimer[i] / 20 : cooldown[i] / cooldownMax[i];
      fillRoundRect(112, y, Math.round(100 * progress), 14, 3, C.cooldown);
    }
    if ((systemLoadPwr[i] || systemLoadLif[i]) && loadSec > 0) {
      fillRoundRect(212, y, Math.round(72 * loadSec / 20), 14, 3, C.loadProgress);
    }
    if (isActionActive(i)) textAt(ACTION_KEYS[i], 8, y + 3, C.value);
    drawIcon(i, 20, y + 3);
    const statusColor = health[i] >= 8 ? C.online : health[i] >= 4 ? C.degraded : C.offline;
    drawStatusBoxes(health[i], 32, y + 4, statusColor, rowBackground);
    if (specialAvailable[i]) textAt(getSpecialName(i), 116, y + 3, C.value);
    else if (unlocked[i] && !(i >= 3 && clicks[i] >= 3)) drawActionPrice(i, 116, y + 3);
    drawSystemLoad(i, 216, y + 3);

    const modification = getModificationState(i);
    if (modification) textAt(modification.text, 288, y + 3, modification.color);
  }
  drawRadioactiveRow();
}

function drawRadioactiveRow() {
  drawIcon(RADIOACTIVE_ICON, 20, RADIOACTIVE_ROW_Y + 3);
  drawStatusBoxes(radioactive, 32, RADIOACTIVE_ROW_Y + 4, C.offline, C.win);
}

function drawPriceTerm(value, icon, x, y) {
  textAt(`${value > 0 ? "+" : "-"}${Math.abs(value)}`, x, y, value > 0 ? C.online : C.offline);
  drawIcon(icon, x + 16, y);
}

function drawActionPrice(index, x, y) {
  const terms = [{ value: gainTab[index], icon: index }];
  if (actionCostPwr[index]) terms.push({ value: -actionCostPwr[index], icon: 0 });
  if (COST_LIF[index]) terms.push({ value: -COST_LIF[index], icon: 1 });
  if (actionCostPrc[index]) terms.push({ value: -actionCostPrc[index], icon: 2 });
  terms.forEach((term, position) => drawPriceTerm(term.value, term.icon, x + position * 24, y));
}

function drawSystemLoad(index, x, y) {
  const terms = [];
  if (systemLoadPwr[index]) terms.push({ value: -systemLoadPwr[index], icon: 0 });
  if (systemLoadLif[index]) terms.push({ value: -systemLoadLif[index], icon: 1 });
  terms.forEach((term, position) => drawPriceTerm(term.value, term.icon, x + position * 24, y));
}

function getModificationState(index) {
  if (index === 3) {
    return modificationAvailable("amount") ? { text: "A", color: C.value } : null;
  }
  if (index === 4) {
    return modificationAvailable("auto") ? { text: "U", color: C.value } : null;
  }
  if (index === 5) {
    return modificationAvailable("speed") ? { text: "D", color: C.value } : null;
  }
  return null;
}

function drawLegendItem(index, label, x, y) {
  drawIcon(index, x, y);
  textAt(label, x + 12, y, C.text);
}

function drawFooter() {
  const legend = [
    [0, "POWER", 12, 173], [1, "LIFE SUPPORT", 84, 173], [2, "PROCESSING", 164, 173],
    [RADIOACTIVE_ICON, "RADIOACTIVE", 244, 173],
    [3, "ENGINEERING", 12, 187], [4, "GUIDANCE", 84, 187],
    [5, "ENGINES", 164, 187], [6, "SENSORS", 244, 187]
  ];
  legend.forEach(([index, label, x, y]) => {
    drawIcon(index, x, y);
    tinyTextAt(label, x + 8, y + 2);
  });
  if (performance.now() < deniedUntil) {
    fillRect(10, 137, 300, 8, C.win);
    textAt("ACTION LOCKED, COOLING, OR TOO COSTLY", 12, 137, C.offline);
  }
}

function drawEventPanel() {
  fillRect(12, 145, 296, 24, C.win);
  if (!eventType) return;

  fillRoundRect(12, 151, 296, 18, 3, C.border);
  fillRoundRect(14, 153, 292, 14, 2, C.win);

  const category = eventType === "decision" || (eventType === "result" && eventMode === "trade")
    ? "OPPORTUNITY" : "CHALLENGE";
  tinyTextAt(category, 20, 146, C.value);

  if (eventType === "decision") {
    textAt(eventDescription, 20, 157, C.title);
    drawPriceTerm(eventRadioactiveOffer ? 1 : -1, eventSource, 124, 157);
    drawPriceTerm(eventGain, eventDest, 148, 157);
    textAt("Y/N", 268, 157, C.value);
    fillRect(20, 165, 276, 2, C.selected);
    fillRect(20, 165, Math.max(0, Math.round(276 * eventWindow / 10)), 2, C.cooldown);
    return;
  }

  if (eventType === "code") {
    textAt(eventDescription, 20, 157, C.title);
    const remainingCode = eventCode.map((digit, index) => index < eventEntered.length ? " " : digit).join("");
    textAt(remainingCode, 200, 157, C.value);
    drawEventEffect(240, 157);
    fillRect(20, 165, 276, 2, C.selected);
    fillRect(20, 165, Math.max(0, Math.round(276 * eventWindow / 10)), 2, C.cooldown);
    return;
  }

  const resultText = {
    trade: "ROBOT TRADE DONE",
    rejected: "ROBOT OFFER REJECTED",
    salvage: "SALVAGE SECURED",
    prevented: "HAZARD PREVENTED",
    failed: "CODE FAILED",
    missed: "SALVAGE MISSED",
    radioactiveCleared: "RADIOACTIVE CLEARED",
    leakPrevented: "LEAK PREVENTED",
    radioactiveIncreased: `RADIOACTIVE +${eventGain}`,
    cleanupFailed: "CLEANUP FAILED"
  }[eventResult];
  const color = ["failed", "radioactiveIncreased", "cleanupFailed"].includes(eventResult) ? C.offline :
    ["trade", "salvage", "radioactiveCleared", "leakPrevented"].includes(eventResult) ? C.online : C.text;
  textAt(resultText, 20, 157, color);
  if (eventResult === "trade") {
    if (eventRadioactiveOffer) {
      drawPriceTerm(1, RADIOACTIVE_ICON, 156, 157);
      drawPriceTerm(eventGain, eventDest, 180, 157);
    } else drawPriceTerm(eventGain, eventDest, 180, 157);
  } else if (["salvage", "prevented", "failed", "missed", "radioactiveCleared", "leakPrevented", "radioactiveIncreased", "cleanupFailed"].includes(eventResult)) {
    drawEventEffect(180, 157);
  }
}

function drawEventEffect(x, y) {
  if (eventMode === "radioactiveLeak") drawPriceTerm(eventGain, RADIOACTIVE_ICON, x, y);
  else if (eventMode === "clearRadioactiveLeak") drawPriceTerm(-eventGain, RADIOACTIVE_ICON, x, y);
  else drawPriceTerm(eventMode === "salvage" ? eventGain : -eventGain, eventDest, x, y);
}

function drawEnd() {
  if (gameMode === 2) {
    drawFailureImage();
    return;
  }

  drawSuccessImage();
}

function drawSuccessImage() {
  fillRoundRect(24, 0, 272, 200, 5, C.border);
  if (successImage.complete && successImage.naturalWidth) {
    ctx.drawImage(successImage, 28, 1, 264, 198);
  }
  fillRoundRect(32, 145, 256, 48, 3, "rgb(1 7 4 / 0.82)");
  textAt("ALL MAIN SYSTEMS ONLINE", 40, 151, "#f2fff5");
  textAt("JUMP COURSE LOCKED.", 40, 165, "#e5ffeb");
  textAt("THE CREW ESCAPES THE ABYSS.", 40, 177, "#e5ffeb");
}

function drawFailureImage() {
  fillRoundRect(24, 0, 272, 200, 5, C.border);
  if (failureImage.complete && failureImage.naturalWidth) {
    ctx.drawImage(failureImage, 28, 1, 264, 198);
  }
  fillRoundRect(32, 145, 256, 48, 3, "rgb(1 7 4 / 0.88)");
  const lines = FAILURE_TEXT[failureSystem] ||
    ["SYSTEM FAILURE", "THE SHIP CAN NO LONGER", "CONTINUE ITS JOURNEY."];
  textAt(lines[0], 40, 151, C.offline);
  textAt(lines[1], 40, 165, C.text);
  textAt(lines[2], 40, 177, C.text);
}

function drawBriefing() {
  fillRect(0, 0, SCR_W, SCR_H, C.bg);
  if (repairImage.complete && repairImage.naturalWidth) {
    ctx.drawImage(repairImage, 0, 0, SCR_W, SCR_H);
  }
  briefingTextAt("SHIP EMERGENCY LOG", 160, 12, "#f2fff5");

  let remaining = Math.floor(briefingChars);
  BRIEFING_LINES.forEach((line, index) => {
    const visible = line.slice(0, Math.max(0, remaining));
    briefingTextAt(visible, 160, 48 + index * 24, "#e5ffeb");
    remaining -= line.length;
  });
  if (briefingChars >= BRIEFING_LENGTH) {
    briefingTextAt("PRESS SPACE TO BEGIN", 160, 176, "#f2fff5");
  }
}

function briefingTextAt(text, x, y, color) {
  textAt(text, x - 1, y, "#010704", "center");
  textAt(text, x + 1, y, "#010704", "center");
  textAt(text, x, y - 1, "#010704", "center");
  textAt(text, x, y + 1, "#010704", "center");
  textAt(text, x, y, color, "center");
}

function drawStoryModal() {
  const stories = {
    6: ["SECTOR SCAN COMPLETE", "A RENEWABLE POWER SOURCE", "HAS BEEN FOUND NEARBY."],
    4: ["COURSE PLOTTED", "GUIDANCE HAS LOCKED ONTO", "THE NEW POWER SOURCE."],
    5: ["JUMPDRIVE ACTIVATED", "THE SHIP HAS ARRIVED.", "COLLECTION CAN BEGIN."],
    3: ["SOURCE INSTALLED", "POWER OUTPUT IS NOW ENOUGH", "TO COMPLETE ALL REPAIRS."]
  };
  const lines = stories[storyType];
  fillRoundRect(28, 54, 264, 94, 5, C.border);
  fillRoundRect(30, 56, 260, 90, 4, C.win);
  textAt(lines[0], 48, 68, C.title);
  textAt(lines[1], 48, 86, C.text);
  textAt(lines[2], 48, 98, C.text);
  textAt("PRESS SPACE TO CONTINUE", 160, 126, C.hint, "center");
}

function drawModificationModal() {
  const descriptions = {
    amount: "IMPROVES ONE RESOURCE ACTION",
    auto: "RUNS ONE RESOURCE AUTOMATICALLY",
    speed: "HALVES ONE RESOURCE COOLDOWN"
  };
  fillRoundRect(20, 32, 280, 136, 5, C.border);
  fillRoundRect(22, 34, 276, 132, 4, C.win);
  textAt(`${modalType.toUpperCase()} MODIFICATION`, 36, 42, C.title);
  textAt(descriptions[modalType], 36, 53, C.hint);
  const mask = getMask(modalType);
  [0, 1, 2].forEach((index, option) => {
    const y = 70 + option * 24;
    const installed = Boolean(mask & (1 << index));
    fillRoundRect(32, y - 2, 256, 22, 3, installed ? C.border : C.selected);
    if (!installed) textAt(ACTION_KEYS[index], 40, y, C.value);
    drawIcon(index, 56, y);
    textAt(NAMES[index], 70, y, installed ? C.hint : C.text);
    if (installed) textAt("INSTALLED", 210, y, C.online);
    if (modalType === "amount") drawAmountModificationDetail(index, y + 10, installed ? C.hint : C.text);
    else textAt(getModificationDetail(modalType, index), 70, y + 10, installed ? C.hint : C.text);
  });
  textAt("SPACE CLOSE", 204, 150, C.hint);
}

function drawAmountModificationDetail(index, y, arrowColor) {
  const oldGain = [2, 1, 3][index];
  const costIcon = [2, 0, 0][index];
  const oldCost = [1, 1, 1][index];
  const newGain = [5, 3, 7][index];
  const newCost = [2, 1, 2][index];
  drawPriceTerm(oldGain, index, 70, y);
  drawPriceTerm(-oldCost, costIcon, 94, y);
  textAt(">", 120, y, arrowColor);
  drawPriceTerm(newGain, index, 132, y);
  drawPriceTerm(-newCost, costIcon, 156, y);
}

function getModificationDetail(type, index) {
  if (type === "amount") {
    return "";
  }
  if (type === "auto") return "MANUAL > AUTO EVERY COOLDOWN";
  return "10 SEC COOLDOWN > 5 SEC COOLDOWN";
}

function moveSelection(delta) {
  if (gameMode) return;
  selected = clamp(selected + delta, 0, 6);
  announce(`${NAMES[selected]} selected.`);
  drawScreen();
}

function handleControl(control) {
  if (control === "up") moveSelection(-1);
  else if (control === "down") moveSelection(1);
  else if (control === "left" || control === "amount") buyAmount();
  else if (control === "auto") buyAuto();
  else if (control === "right" || control === "speed") buySpeed();
  else if (control === "fire") performAction();
}

function announce(message) {
  announcement.textContent = "";
  requestAnimationFrame(() => { announcement.textContent = message; });
}

document.addEventListener("keydown", event => {
  if (titleActive) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      startGame();
    }
    return;
  }
  if (briefingActive) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      advanceBriefing();
    }
    return;
  }
  const controls = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", " ": "fire", Enter: "fire" };
  const key = event.key.toLowerCase();
  if (storyType !== null) {
    if (key === "escape" || key === "enter" || key === " ") {
      storyType = null;
      drawScreen();
    }
    event.preventDefault();
    return;
  }
  if (modalType) {
    if (key === "escape" || key === " ") closeModification();
    else {
      const option = ["p", "l", "o"].indexOf(key);
      if (option >= 0) selectModification(option);
    }
    event.preventDefault();
    return;
  }
  if (eventType === "decision" && (key === "y" || key === "n")) {
    event.preventDefault();
    if (!event.repeat) (key === "y" ? acceptDecisionEvent : rejectDecisionEvent)();
    return;
  }
  if (eventType === "code" && /^[0-9]$/.test(key)) {
    event.preventDefault();
    if (!event.repeat) enterEventDigit(Number(key));
    return;
  }
  const actionIndex = ACTION_KEYS.indexOf(key.toUpperCase());
  if (actionIndex >= 0 && !event.repeat) {
    event.preventDefault();
    performAction(actionIndex);
    return;
  }
  if ({ a: buyAmount, u: buyAuto, d: buySpeed }[key] && !event.repeat) {
    event.preventDefault();
    ({ a: buyAmount, u: buyAuto, d: buySpeed })[key]();
    return;
  }
  const control = controls[event.key];
  if (!control || event.repeat) return;
  event.preventDefault();
  handleControl(control);
  document.querySelector(`[data-control="${control}"]`)?.classList.add("is-pressed");
});

document.addEventListener("keyup", event => {
  const controls = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", " ": "fire", Enter: "fire" };
  document.querySelector(`[data-control="${controls[event.key]}"]`)?.classList.remove("is-pressed");
});

document.querySelectorAll("[data-control]").forEach(button => {
  button.addEventListener("click", () => {
    if (titleActive) {
      if (button.dataset.control === "fire") startGame();
      return;
    }
    if (briefingActive) {
      if (button.dataset.control === "fire") advanceBriefing();
      return;
    }
    handleControl(button.dataset.control);
    canvas.focus({ preventScroll: true });
  });
});

document.querySelectorAll("[data-event-decision]").forEach(button => {
  button.addEventListener("click", () => {
    (button.dataset.eventDecision === "yes" ? acceptDecisionEvent : rejectDecisionEvent)();
    canvas.focus({ preventScroll: true });
  });
});

document.querySelectorAll("[data-event-digit]").forEach(button => {
  button.addEventListener("click", () => {
    enterEventDigit(Number(button.dataset.eventDigit));
    canvas.focus({ preventScroll: true });
  });
});

canvas.addEventListener("click", event => {
  if (startGame()) return;
  if (advanceBriefing()) return;
  if (storyType !== null) {
    storyType = null;
    drawScreen();
    return;
  }
  if (!modalType) return;
  const bounds = canvas.getBoundingClientRect();
  const x = (event.clientX - bounds.left) * SCR_W / bounds.width;
  const y = (event.clientY - bounds.top) * SCR_H / bounds.height;
  if (x >= 32 && x <= 288 && y >= 68 && y < 140) selectModification(Math.floor((y - 68) / 24));
});

titleScreen.addEventListener("click", startGame);

function loop(now) {
  const delta = Math.min(now - lastTime, 1000);
  lastTime = now;
  if (briefingActive) {
    briefingChars = Math.min(BRIEFING_LENGTH, (now - briefingStarted) * 0.018);
    drawBriefing();
  } else if (!titleActive && !gameMode && !modalType && storyType === null) {
    tickGame(delta / 1000);
  }
  if (!titleActive && !briefingActive) drawScreen();
  requestAnimationFrame(loop);
}

requestAnimationFrame(loop);
