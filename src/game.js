"use strict";

// Browser equivalents of the Atari data tables. Keep ordering synchronized
// with health/cooldown/unlocked/clicks in atari/ravaged-space.asm.
const SCR_W = 320;
const SCR_H = 200;
const INITIAL_HEALTH = [2, 7, 9, 2, 2, 1, 3];
const BASE_GAIN = [2, 1, 3, 2, 2, 3, 2];
const COST_PWR = [0, 1, 1, 2, 1, 3, 1];
const COST_LIF = [0, 0, 0, 0, 0, 1, 0];
const COST_PRC = [1, 0, 0, 2, 0, 1, 1];
const NAMES = ["POWER", "LIFE SUPPORT", "PROCESSING", "ENGINEERING", "GUIDANCE", "ENGINES", "SENSORS"];
const ACTION_KEYS = ["P", "L", "O", "E", "G", "N", "S"];
const ROW_Y = [18, 34, 50, 66, 82, 98, 114];
const ICONS = [
  [0x18, 0x18, 0x30, 0x7c, 0x18, 0x30, 0x20, 0x00], // power: bolt
  [0x66, 0xff, 0xff, 0x7e, 0x3c, 0x18, 0x00, 0x00], // life support: heart
  [0x7e, 0x42, 0x5a, 0x42, 0x5a, 0x42, 0x7e, 0x00], // processing: core
  [0xc3, 0x66, 0x3c, 0x18, 0x38, 0x60, 0xc0, 0x00], // engineering: wrench
  [0x18, 0x7e, 0xdb, 0xff, 0xbd, 0x7e, 0x42, 0x00], // guidance: robot
  [0x18, 0x3c, 0x7e, 0x5a, 0x5a, 0x3c, 0x66, 0x00], // engines: rocket
  [0x06, 0x0c, 0x58, 0x30, 0x30, 0x7e, 0x18, 0x00]  // sensors: dish
];
const ICON_COLORS = ["#e8b84c", "#d76a45", "#d89c4a", "#a8aa8d", "#62a881", "#cb7f35", "#778f76"];
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
ctx.imageSmoothingEnabled = false;

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
let deniedUntil;
let lastTime = performance.now();

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
  deniedUntil = 0;
  announce("New game. Power selected.");
  drawScreen();
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
}

function checkEnd() {
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
    [0, "POWER", 12], [1, "LIFE SUPPORT", 40], [2, "PROCESSING", 96],
    [3, "ENGINEERING", 144], [4, "GUIDANCE", 196], [5, "ENGINES", 236], [6, "SENSORS", 272]
  ];
  legend.forEach(([index, label, x]) => {
    drawIcon(index, x, 187);
    tinyTextAt(label, x + 8, 189);
  });
  if (performance.now() < deniedUntil) {
    fillRect(10, 176, 300, 9, C.win);
    textAt("ACTION LOCKED, COOLING, OR TOO COSTLY", 12, 176, C.offline);
  }
}

function drawEnd() {
  fillRoundRect(28, 54, 264, 94, 5, C.border);
  fillRoundRect(30, 56, 260, 90, 4, C.win);
  const won = gameMode === 1;
  if (won) {
    textAt("ALL MAIN SYSTEMS ONLINE", 48, 68, C.online);
    textAt("JUMP COURSE TO THE NEAREST", 48, 84, C.text);
    textAt("SPACEPORT IS READY. YOU WIN!", 48, 96, C.text);
  } else {
    const endings = {
      0: ["POWER SYSTEM FAILURE", "THE LIGHTS FAIL. AIR STALES.", "THE CREW FALLS SILENT."],
      1: ["LIFE SUPPORT FAILURE", "THE AIR TURNS STALE.", "THE CREW DRIFTS TO SLEEP."],
      2: ["PROCESSING FAILURE", "POWER CONTROL COLLAPSES.", "FIRE CONSUMES THE SHIP."]
    };
    const lines = endings[failureSystem] || ["SYSTEM FAILURE", "THE SHIP CAN NO LONGER", "CONTINUE ITS JOURNEY."];
    textAt(lines[0], 48, 68, C.offline);
    textAt(lines[1], 48, 84, C.text);
    textAt(lines[2], 48, 96, C.text);
  }
  textAt("PRESS FIRE TO RESTART", 76, 126, C.hint);
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
  textAt("ENTER CONTINUE", 168, 126, C.hint);
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
  textAt("ESC CANCEL", 204, 150, C.hint);
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
    if (key === "escape") closeModification();
    else {
      const option = ["p", "l", "o"].indexOf(key);
      if (option >= 0) selectModification(option);
    }
    event.preventDefault();
    return;
  }
  const actionIndex = ["p", "l", "o", "e", "g", "n", "s"].indexOf(key);
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
    handleControl(button.dataset.control);
    canvas.focus({ preventScroll: true });
  });
});

canvas.addEventListener("click", event => {
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

function loop(now) {
  const delta = Math.min(now - lastTime, 1000);
  lastTime = now;
  if (!gameMode && !modalType && storyType === null) {
    tickGame(delta / 1000);
  }
  drawScreen();
  requestAnimationFrame(loop);
}

gameInit();
requestAnimationFrame(loop);
