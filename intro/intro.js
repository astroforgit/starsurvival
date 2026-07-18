"use strict";

const scenes = [
  {
    image: new URL("./assets/00-mission-manifest.webp", import.meta.url).href,
    align: "left",
    kind: "crew",
    chapter: "Orpheus expedition // Mission manifest",
    title: "Beyond Known Space",
    copy: "Mission: enter the Cosmic Abyss, cross the final surveyed boundary, and chart the regions of space that no map has ever named.",
    crew: [
      ["Dr. Lyra Sen", "Xenocultural Anthropologist"],
      ["Dr. Elias Ward", "Psychotherapist"],
      ["Iona Vale", "Zero-G Yoga Instructor"],
      ["Cassian Rook", "Public Relations Officer"],
      ["Professor Oren Quill", "Space Philosopher"],
      ["TeeDeeCee", "Fifth-Generation Battle Cyborg // Security Guard"],
      ["Niko Ember", "Ship's Cook"],
      ["Captain Mara Venn", "Captain // Pilot // Chief Mechanic"]
    ],
    narration: "Mission file Orpheus. Objective: enter the Cosmic Abyss, cross the final surveyed boundary, and chart the regions of space that no map has ever named. Crew manifest. Doctor Lyra Sen, xenocultural anthropologist. Doctor Elias Ward, psychotherapist. Iona Vale, zero gravity yoga instructor. Cassian Rook, public relations officer. Professor Oren Quill, space philosopher. Tee Dee Cee, fifth-generation battle cyborg and security guard. Niko Ember, ship's cook. Captain Mara Venn, pilot and chief mechanic.",
    signal: "Expedition status // Cleared for departure"
  },
  {
    image: new URL("./assets/00-arcade.webp", import.meta.url).href,
    align: "right",
    kind: "title",
    chapter: "Personnel archive // Captain Mara Venn",
    title: "Cosmic Abyss",
    copy: "Mara Venn carried the whole ship in her head—reactor, life support, navigation, flight control. Command had entrusted her with one more impossible discipline: alien-defence strategy.",
    narration: "Mara Venn was the Orpheus's captain, pilot, and chief mechanic. Reactor, life support, navigation, flight control—she carried the whole ship in her head. Command had entrusted her with one more impossible discipline: alien-defence strategy.",
    signal: "Alien-defence simulation // Strategic training active"
  },
  {
    image: new URL("./assets/00-shower.webp", import.meta.url).href,
    align: "left",
    chapter: "Crew deck // Personal interval",
    title: "A Moment Alone",
    copy: "Sometimes Mara needed silence more than sleep: steam, a locked cabin, one breath with no alarms. Yet aboard a ship crossing the cosmic abyss, solitude was only another system waiting to fail.",
    narration: "Sometimes Mara needed silence more than sleep. Steam. A locked cabin. One breath with no alarms. Yet aboard a ship crossing the cosmic abyss, solitude was only another system waiting to fail.",
    signal: "Privacy cycle active // Command station unattended"
  },
  {
    image: new URL("./assets/01-impact.webp", import.meta.url).href,
    align: "right",
    chapter: "Navigation incident // 03:17 ship time",
    title: "Impact",
    copy: "The advanced alien-defence system overloaded the ship's power grid. Autopilot and collision detection slipped into standby. Beyond the glass, the asteroid field moved like a living tide; one fragment crossed the shields before the warning could finish.",
    narration: "The advanced alien-defence system overloaded the ship's power grid. Autopilot and collision detection were temporarily offline. Beyond the glass, the asteroid field moved like a living tide. One fragment crossed the shields before the warning could finish.",
    signal: "Hull breach // Processing spine // Decks 04–07"
  },
  {
    image: new URL("./assets/02-aftermath.webp", import.meta.url).href,
    align: "right",
    chapter: "Emergency record // 11 seconds after impact",
    title: "Aftermath",
    copy: "Gravity failed. Power folded into darkness. Across the command deck, seven systems began counting down toward silence.",
    narration: "Gravity failed. Power folded into darkness. Across the command deck, seven systems began counting down toward silence.",
    signal: "Power critical // Life support degraded // Main systems offline"
  },
  {
    image: new URL("./assets/03-containment.webp", import.meta.url).href,
    align: "left",
    chapter: "Containment alert // Processing passage",
    title: "Containment",
    copy: "The strike opened a radioactive seam beside the processing core. Engineer Mara Venn was the only systems officer still moving.",
    narration: "The strike opened a radioactive seam beside the processing core. Engineer Mara Venn was the only systems officer still moving.",
    signal: "Radiation rising // Manual containment required"
  },
  {
    image: new URL("./assets/04-console.webp", import.meta.url).href,
    align: "left",
    chapter: "Last command channel // Connection restored",
    title: "Last Command",
    copy: "One console answered. Keep power, air, and processing alive. Repair the ship. Find a course out of the abyss.",
    narration: "One console answered. Keep power, air, and processing alive. Repair the ship. Find a course out of the abyss.",
    signal: "System control transferred to you"
  }
];

const cinematic = document.querySelector(".cinematic");
const layers = [document.querySelector(".scene-a"), document.querySelector(".scene-b")];
const story = document.querySelector(".story");
const chapter = document.querySelector(".chapter");
const title = document.querySelector(".scene-title");
const copy = document.querySelector(".scene-copy");
const crewManifest = document.querySelector(".crew-manifest");
const signal = document.querySelector(".scene-signal");
const transition = document.querySelector(".transition");
const musicButton = document.querySelector("[data-music]");
const musicLabel = document.querySelector("[data-music-label]");

let sceneIndex = 0;
let activeLayer = 0;
let typeTimer = 0;
let fullCopy = "";
let isTyping = false;
let leaving = false;
let sceneChangeTimer = 0;
const musicUrl = new URL("./assets/Static in the Void.mp3", import.meta.url).href;

class CinematicAudio {
  constructor() {
    this.track = new Audio(musicUrl);
    this.track.loop = true;
    this.track.autoplay = true;
    this.track.preload = "auto";
    this.track.volume = .42;
    this.context = null;
    this.musicMaster = null;
    this.music = null;
    this.effects = null;
    this.narratorFx = null;
    this.filter = null;
    this.drone = [];
    this.musicTimers = new Set();
    this.sceneToken = 0;
    this.musicEnabled = true;
    this.narrating = false;
    this.carrier = [];
  }

  armMusic() {
    musicButton.setAttribute("aria-pressed", "true");
    musicLabel.textContent = "MUSIC ON";
    this.track.play().catch(() => {});
  }

  async unlock() {
    if (this.musicEnabled && this.track.paused) await this.track.play().catch(() => {});
  }

  toggleMusic() {
    if (this.musicEnabled && this.track.paused) {
      this.track.play().catch(() => {});
      return;
    }
    this.musicEnabled = !this.musicEnabled;
    musicButton.setAttribute("aria-pressed", String(this.musicEnabled));
    musicLabel.textContent = this.musicEnabled ? "MUSIC ON" : "MUSIC OFF";
    if (this.musicEnabled) {
      this.unlock();
    } else {
      this.track.pause();
    }
  }

  createEngine() {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) {
      return false;
    }

    try {
      this.context = new AudioContext();
    } catch {
      return false;
    }
    this.narratorFx = this.context.createGain();
    const compressor = this.context.createDynamicsCompressor();

    this.narratorFx.gain.value = .22;
    compressor.threshold.value = -20;
    compressor.knee.value = 14;
    compressor.ratio.value = 5;
    compressor.attack.value = .02;
    compressor.release.value = .7;

    this.narratorFx.connect(compressor);
    compressor.connect(this.context.destination);
    return true;
  }

  fadeMusic(value) {
    if (!this.context) return;
    const now = this.context.currentTime;
    this.musicMaster.gain.cancelScheduledValues(now);
    this.musicMaster.gain.setValueAtTime(this.musicMaster.gain.value, now);
    this.musicMaster.gain.linearRampToValueAtTime(value, now + .7);
  }

  playScene(index) {
    return;
    /* The MP3 soundtrack now replaces the former synthesized scene score. */
    if (!this.musicEnabled || this.context?.state !== "running") return;
    this.clearMusicTimers();
    const token = ++this.sceneToken;
    const now = this.context.currentTime;
    const roots = [36.71, 41.2, 46.25, 55];
    const root = roots[index];
    const ratios = index === 3 ? [1, 1.2, 1.5] : [1, 1.5, 2];

    this.drone.forEach(({ oscillator, gain }, voice) => {
      oscillator.frequency.cancelScheduledValues(now);
      oscillator.frequency.exponentialRampToValueAtTime(root * ratios[voice], now + 2.2);
      gain.gain.cancelScheduledValues(now);
      gain.gain.linearRampToValueAtTime(index === 3 ? .04 : voice === 0 ? .055 : .025, now + 1.4);
    });
    this.filter.frequency.cancelScheduledValues(now);
    this.filter.frequency.exponentialRampToValueAtTime([330, 280, 480, 680][index], now + 1.8);

    if (index === 0) this.boom(.15);
    if (index === 1) this.heartbeat(token);
    if (index === 2) this.containmentClicks(token);
    if (index === 3) this.resolveChord();
    this.ambientPattern(index, token, 0);
  }

  ambientPattern(index, token, step) {
    if (!this.musicEnabled || token !== this.sceneToken) return;
    const patterns = [
      [36.71, 43.65, 55, 49],
      [41.2, 41.2, 49, 43.65],
      [46.25, 55, 69.3, 55],
      [55, 65.4, 82.4, 73.42]
    ];
    this.tone(patterns[index][step % 4], index === 3 ? 4.8 : 3.6, index === 2 ? .026 : .019, this.music);
    this.scheduleMusic(() => this.ambientPattern(index, token, step + 1), index === 3 ? 3200 : 2750);
  }

  tone(frequency, duration, volume, destination, type = "triangle") {
    const now = this.context.currentTime;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, now);
    gain.gain.setValueAtTime(.0001, now);
    gain.gain.exponentialRampToValueAtTime(volume, now + .12);
    gain.gain.exponentialRampToValueAtTime(.0001, now + duration);
    oscillator.connect(gain);
    gain.connect(destination);
    oscillator.start(now);
    oscillator.stop(now + duration + .05);
    return oscillator;
  }

  boom(delay = 0) {
    const start = this.context.currentTime + delay;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(72, start);
    oscillator.frequency.exponentialRampToValueAtTime(24, start + 2.1);
    gain.gain.setValueAtTime(.0001, start);
    gain.gain.exponentialRampToValueAtTime(.36, start + .03);
    gain.gain.exponentialRampToValueAtTime(.0001, start + 2.2);
    oscillator.connect(gain);
    gain.connect(this.effects);
    oscillator.start(start);
    oscillator.stop(start + 2.3);
  }

  heartbeat(token) {
    const beat = () => {
      if (!this.musicEnabled || token !== this.sceneToken) return;
      this.boom();
      this.scheduleMusic(() => this.boom(), 210);
      this.scheduleMusic(beat, 2400);
    };
    beat();
  }

  containmentClicks(token) {
    const click = () => {
      if (!this.musicEnabled || token !== this.sceneToken) return;
      this.tone(1900 + Math.random() * 2600, .04, .055, this.effects, "square");
      this.scheduleMusic(click, 260 + Math.random() * 840);
    };
    click();
  }

  resolveChord() {
    [55, 65.4, 82.4, 110].forEach((frequency, index) => {
      this.scheduleMusic(() => this.tone(frequency, 7, .035, this.music), index * 190);
    });
  }

  async narrateScene(index) {
    if (!window.speechSynthesis) return;
    this.stopNarration();
    if (!this.context) this.createEngine();
    if (this.context) await this.context.resume().catch(() => {});
    this.narrating = true;

    const utterance = new SpeechSynthesisUtterance(`System archive. ${scenes[index].narration}`);
    const voices = window.speechSynthesis.getVoices();
    utterance.voice = voices.find(voice => /Mark|David|Daniel|George|Male/i.test(voice.name) && /^en/i.test(voice.lang)) ||
      voices.find(voice => /^en/i.test(voice.lang)) || null;
    utterance.rate = .76;
    utterance.pitch = .38;
    utterance.volume = .92;

    if (this.context) {
      this.startCarrier();
      this.robotChime();
    }
    const finish = () => this.finishNarration();
    utterance.onend = finish;
    utterance.onerror = finish;
    window.setTimeout(() => {
      if (this.narrating) window.speechSynthesis.speak(utterance);
    }, 260);
  }

  startCarrier() {
    [62, 124].forEach((frequency, index) => {
      const oscillator = this.context.createOscillator();
      const gain = this.context.createGain();
      oscillator.type = index ? "square" : "sawtooth";
      oscillator.frequency.value = frequency;
      gain.gain.value = index ? .008 : .014;
      oscillator.connect(gain);
      gain.connect(this.narratorFx);
      oscillator.start();
      this.carrier.push(oscillator);
    });
  }

  robotChime() {
    [880, 660, 440].forEach((frequency, index) => {
      window.setTimeout(() => this.tone(frequency, .12, .06, this.narratorFx, "square"), index * 75);
    });
  }

  finishNarration() {
    this.carrier.forEach(oscillator => {
      try { oscillator.stop(); } catch {}
    });
    this.carrier = [];
    this.narrating = false;
  }

  stopNarration() {
    window.speechSynthesis?.cancel();
    if (this.narrating) this.finishNarration();
  }

  scheduleMusic(callback, delay) {
    const timer = window.setTimeout(() => {
      this.musicTimers.delete(timer);
      callback();
    }, delay);
    this.musicTimers.add(timer);
  }

  clearMusicTimers() {
    this.musicTimers.forEach(timer => window.clearTimeout(timer));
    this.musicTimers.clear();
  }

  stop() {
    this.track.pause();
    this.clearMusicTimers();
    this.stopNarration();
    this.context?.close();
  }
}

const soundtrack = new CinematicAudio();

scenes.forEach(scene => {
  const image = new Image();
  image.src = scene.image;
});

function typeCopy(text) {
  clearInterval(typeTimer);
  fullCopy = text;
  copy.textContent = "";
  copy.classList.add("is-typing");
  isTyping = true;
  let position = 0;
  typeTimer = window.setInterval(() => {
    position += 1;
    copy.textContent = text.slice(0, position);
    if (position >= text.length) finishTyping();
  }, 24);
}

function finishTyping() {
  clearInterval(typeTimer);
  copy.textContent = fullCopy;
  copy.classList.remove("is-typing");
  isTyping = false;
}

function showCrewManifest(crew = []) {
  crewManifest.replaceChildren(...crew.map(([name, role]) => {
    const item = document.createElement("li");
    const memberName = document.createElement("strong");
    const memberRole = document.createElement("span");
    memberName.textContent = name;
    memberRole.textContent = role;
    item.append(memberName, memberRole);
    return item;
  }));
  crewManifest.hidden = crew.length === 0;
}

function showScene(index) {
  if (leaving || index < 0 || index >= scenes.length) return;
  clearTimeout(sceneChangeTimer);
  soundtrack.stopNarration();
  sceneIndex = index;
  const scene = scenes[index];
  story.classList.add("is-changing");

  sceneChangeTimer = window.setTimeout(() => {
    activeLayer = 1 - activeLayer;
    layers[activeLayer].style.backgroundImage = `url("${scene.image}")`;
    layers[activeLayer].classList.add("is-visible");
    layers[1 - activeLayer].classList.remove("is-visible");
    cinematic.dataset.align = scene.align;
    cinematic.dataset.scene = String(index);
    cinematic.dataset.kind = scene.kind || "story";
    chapter.textContent = scene.chapter;
    title.textContent = scene.title;
    signal.textContent = scene.signal;
    showCrewManifest(scene.crew);
    typeCopy(scene.copy);
    soundtrack.playScene(index);
    soundtrack.narrateScene(index);
    story.classList.remove("is-changing");
  }, 280);
}

function advance() {
  if (leaving) return;
  soundtrack.unlock();
  if (isTyping) {
    finishTyping();
    return;
  }
  if (sceneIndex < scenes.length - 1) showScene(sceneIndex + 1);
  else enterGame();
}

function enterGame() {
  if (leaving) return;
  leaving = true;
  clearTimeout(sceneChangeTimer);
  clearInterval(typeTimer);
  soundtrack.stopNarration();
  transition.classList.add("is-active");
  window.setTimeout(() => {
    window.location.assign(new URL("../launch/", window.location.href));
  }, 900);
}

document.querySelector("[data-skip]").addEventListener("click", enterGame);
document.querySelector("[data-continue]").addEventListener("click", advance);
musicButton.addEventListener("click", () => soundtrack.toggleMusic());
cinematic.addEventListener("click", event => {
  if (!event.target.closest("button, a")) advance();
});

document.addEventListener("keydown", event => {
  if ([" ", "Enter", "ArrowRight"].includes(event.key)) {
    event.preventDefault();
    if (!event.repeat) advance();
  } else if (["Escape", "s", "S"].includes(event.key)) {
    event.preventDefault();
    enterGame();
  } else if (event.key === "ArrowLeft") {
    event.preventDefault();
    soundtrack.unlock();
    showScene(Math.max(0, sceneIndex - 1));
  }
});

window.addEventListener("pagehide", () => soundtrack.stop(), { once: true });

layers[0].style.backgroundImage = `url("${scenes[0].image}")`;
cinematic.dataset.scene = "0";
showScene(0);
soundtrack.armMusic();
