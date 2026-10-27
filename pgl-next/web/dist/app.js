"use strict";

// --- state ---
let me = null;        // {email, admin}
let pc = null;        // RTCPeerConnection
let ws = null;        // signaling socket
let ch = {};          // data channels by label
let authed = false;
let remoteW = 0, remoteH = 0;

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");

// --- API helpers ---
async function api(path, opts) {
  const r = await fetch(path, Object.assign({ headers: { "Content-Type": "application/json" } }, opts));
  let body = null;
  try { body = await r.json(); } catch (_) {}
  if (!r.ok) throw new Error((body && body.error) || ("Ошибка " + r.status));
  return body;
}

// --- views ---
function showAuth() { hide($("devicesView")); hide($("viewerView")); hide($("who")); show($("authView")); }
function showDevices() { hide($("authView")); hide($("viewerView")); show($("who")); show($("devicesView")); loadDevices(); }

async function init() {
  try {
    me = await api("/api/me");
    $("whoEmail").textContent = me.email;
    showDevices();
  } catch (_) {
    showAuth();
  }
}

// --- auth form ---
let authMode = "login";
document.querySelectorAll(".tab").forEach((t) => {
  t.onclick = () => {
    document.querySelectorAll(".tab").forEach((x) => x.classList.remove("active"));
    t.classList.add("active");
    authMode = t.dataset.tab;
    $("authSubmit").textContent = authMode === "login" ? "Войти" : "Зарегистрироваться";
    $("authErr").textContent = "";
  };
});

$("authForm").onsubmit = async (e) => {
  e.preventDefault();
  $("authErr").textContent = "";
  const email = $("email").value.trim();
  const password = $("password").value;
  try {
    me = await api("/api/" + (authMode === "login" ? "login" : "register"), {
      method: "POST", body: JSON.stringify({ email, password }),
    });
    $("whoEmail").textContent = me.email;
    showDevices();
  } catch (err) {
    $("authErr").textContent = err.message;
  }
};

$("logoutBtn").onclick = async () => {
  try { await api("/api/logout", { method: "POST" }); } catch (_) {}
  me = null;
  showAuth();
};

// --- device list ---
async function loadDevices() {
  const list = $("devList");
  list.innerHTML = '<div class="empty">Загрузка…</div>';
  try {
    const devs = await api("/api/devices");
    if (!devs || devs.length === 0) {
      list.innerHTML = '<div class="empty">Пока нет устройств. Установите программу на компьютер и привяжите по ID.</div>';
      return;
    }
    list.innerHTML = "";
    devs.forEach((d) => {
      const el = document.createElement("div");
      el.className = "device";
      el.innerHTML =
        '<span class="dot ' + (d.online ? "on" : "") + '"></span>' +
        '<div class="info"><div class="name"></div><div class="sub"></div></div>';
      el.querySelector(".name").textContent = d.name || d.id;
      el.querySelector(".sub").textContent = (d.os || "") + " · ID " + d.id + " · " + (d.online ? "в сети" : "не в сети");
      const btn = document.createElement("button");
      btn.className = "btn sm";
      btn.textContent = "Подключиться";
      btn.disabled = !d.online;
      btn.onclick = () => connect(d.id, d.name);
      el.appendChild(btn);
      list.appendChild(el);
    });
  } catch (err) {
    list.innerHTML = '<div class="empty">' + err.message + "</div>";
  }
}
$("refreshBtn").onclick = loadDevices;
$("connBtn").onclick = () => {
  const id = $("connId").value.trim();
  if (id) connect(id, "ID " + id);
};

// --- viewer / WebRTC ---
function wsBase() {
  return (location.protocol === "https:" ? "wss://" : "ws://") + location.host;
}

function connect(id, title) {
  hide($("devicesView"));
  show($("viewerView"));
  $("vStatus").textContent = "Подключение к " + (title || id) + "…";
  authed = false;
  ws = new WebSocket(wsBase() + "/ws/viewer?id=" + encodeURIComponent(id));
  ws.onmessage = onSignal;
  ws.onclose = () => { if (!authed) $("vStatus").textContent = "Соединение закрыто."; };
  ws.onerror = () => { $("vStatus").textContent = "Ошибка соединения."; };
}

async function onSignal(ev) {
  const m = JSON.parse(ev.data);
  if (m.type === "hello") {
    const iceServers = (m.ice || []).map((s) => ({ urls: s.urls, username: s.username, credential: s.credential }));
    pc = new RTCPeerConnection({ iceServers });
    pc.onicecandidate = (e) => { if (e.candidate) sigSend({ type: "ice", candidate: e.candidate.toJSON() }); };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "failed" || pc.connectionState === "disconnected")
        $("vStatus").textContent = "Соединение потеряно.";
    };
    setupChannels();
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    sigSend({ type: "offer", sdp: offer.sdp });
  } else if (m.type === "answer") {
    await pc.setRemoteDescription({ type: "answer", sdp: m.sdp });
  } else if (m.type === "ice") {
    try { await pc.addIceCandidate(m.candidate); } catch (_) {}
  } else if (m.type === "error") {
    $("vStatus").textContent = m.message === "offline" ? "Компьютер не в сети." : ("Ошибка: " + m.message);
  }
}

function sigSend(o) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); }

function setupChannels() {
  const ctl = pc.createDataChannel("ctl");
  const video = pc.createDataChannel("video");
  const input = pc.createDataChannel("input");
  ch = { ctl, video, input };

  ctl.onopen = () => askPassword();
  ctl.onmessage = (e) => {
    const c = JSON.parse(e.data);
    if (c.t === "auth") {
      if (c.ok) {
        authed = true;
        remoteW = c.w; remoteH = c.h;
        hidePwModal();
        $("vStatus").textContent = (c.name || "Подключено") + " · " + c.w + "×" + c.h;
        const cv = $("screen");
        cv.width = c.w; cv.height = c.h;
        cv.focus();
        bindInput();
      } else {
        $("pwErr").textContent = "Неверный пароль.";
      }
    }
  };

  video.binaryType = "arraybuffer";
  const cv = $("screen");
  const ctx = cv.getContext("2d");
  let drawing = false;
  video.onmessage = async (e) => {
    if (drawing) return; // drop frames if we can't keep up
    drawing = true;
    try {
      const bmp = await createImageBitmap(new Blob([e.data], { type: "image/jpeg" }));
      if (cv.width !== bmp.width) cv.width = bmp.width;
      if (cv.height !== bmp.height) cv.height = bmp.height;
      ctx.drawImage(bmp, 0, 0);
      bmp.close();
    } catch (_) {} finally { drawing = false; }
  };
}

// --- password modal ---
function askPassword() {
  $("pwInput").value = "";
  $("pwErr").textContent = "";
  show($("pwModal"));
  $("pwInput").focus();
}
function hidePwModal() { hide($("pwModal")); }
function sendAuth() {
  sigCtl({ t: "auth", pw: $("pwInput").value });
}
function sigCtl(o) { if (ch.ctl && ch.ctl.readyState === "open") ch.ctl.send(JSON.stringify(o)); }
$("pwOk").onclick = sendAuth;
$("pwInput").addEventListener("keydown", (e) => { if (e.key === "Enter") sendAuth(); });
$("pwCancel").onclick = () => { hidePwModal(); disconnect(); };

// --- input forwarding ---
let inputBound = false;
function sendInput(o) { if (ch.input && ch.input.readyState === "open") ch.input.send(JSON.stringify(o)); }

function remoteCoords(cv, e) {
  const r = cv.getBoundingClientRect();
  // canvas is object-fit:contain — compute the drawn rect inside the element
  const scale = Math.min(r.width / cv.width, r.height / cv.height);
  const dw = cv.width * scale, dh = cv.height * scale;
  const ox = r.left + (r.width - dw) / 2, oy = r.top + (r.height - dh) / 2;
  let x = (e.clientX - ox) / scale, y = (e.clientY - oy) / scale;
  x = Math.max(0, Math.min(cv.width - 1, x));
  y = Math.max(0, Math.min(cv.height - 1, y));
  return { x: Math.round(x), y: Math.round(y) };
}

function bindInput() {
  if (inputBound) return;
  inputBound = true;
  const cv = $("screen");
  cv.addEventListener("mousemove", (e) => { const p = remoteCoords(cv, e); sendInput({ t: "mm", x: p.x, y: p.y }); });
  cv.addEventListener("mousedown", (e) => { e.preventDefault(); const p = remoteCoords(cv, e); sendInput({ t: "mm", x: p.x, y: p.y }); sendInput({ t: "md", b: e.button }); cv.focus(); });
  cv.addEventListener("mouseup", (e) => { e.preventDefault(); sendInput({ t: "mu", b: e.button }); });
  cv.addEventListener("contextmenu", (e) => e.preventDefault());
  cv.addEventListener("wheel", (e) => { e.preventDefault(); sendInput({ t: "wh", dx: Math.sign(e.deltaX), dy: Math.sign(e.deltaY) }); }, { passive: false });
  cv.addEventListener("keydown", (e) => { e.preventDefault(); sendInput({ t: "kd", code: e.code }); });
  cv.addEventListener("keyup", (e) => { e.preventDefault(); sendInput({ t: "ku", code: e.code }); });
}

// --- disconnect / nav ---
function disconnect() {
  if (ch.video) try { ch.video.close(); } catch (_) {}
  if (pc) try { pc.close(); } catch (_) {}
  if (ws) try { ws.close(); } catch (_) {}
  pc = null; ws = null; ch = {}; authed = false; inputBound = false;
}
$("backBtn").onclick = () => { disconnect(); hide($("viewerView")); showDevices(); };
$("fsBtn").onclick = () => {
  const st = $("stage");
  if (document.fullscreenElement) document.exitFullscreen();
  else st.requestFullscreen && st.requestFullscreen();
};

init();
