// whip_roulette: the panel while seated. Lua sends { type: 'show' | 'hud' | 'hide' } (client/play.lua).
// The server's hud says what's true; the timer counts down here from its endsIn.

const $ = (id) => document.getElementById(id);

function applyScale() {
    const s = Math.min(window.innerHeight / 1440, window.innerWidth / 2560);
    document.documentElement.style.setProperty('--ui-scale', s);
}
applyScale();
window.addEventListener('resize', applyScale);

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

function esc(t) {
    const d = document.createElement('div');
    d.textContent = t == null ? '' : String(t);
    return d.innerHTML;
}

const RED = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36].map(String));
const colourOf = (n) => (n === '0' || n === '00') ? 'green' : (RED.has(String(n)) ? 'red' : 'black');

let hud = {};
let endsAt = 0, span = 0;

function title() {
    const h = hud;
    if (h.phase === 'spinning') return ['No more bets', 'turn'];
    if (h.result && (h.phase === 'payout' || !h.total)) {
        const net = Number(h.net) || 0;
        if (h.result === 'won') return [`You won ${money(net)}`, 'won'];
        if (h.result === 'lost') return [`You lost ${money(-net)}`, 'lost'];
        if (h.result === 'some') return [`Down ${money(-net)}`, 'lost'];
        return ['Bets back', ''];
    }
    if (h.phase === 'payout') return ['Paying out', ''];
    return [h.total ? 'Bets down' : 'Place your bets', ''];
}

function render() {
    const [text, tone] = title();
    const t = $('title');
    t.textContent = text;
    t.className = 'rl-title ' + tone;
    $('total').textContent = money(hud.total || 0);
    $('history').innerHTML = (hud.history || []).map((n, i) =>
        `<div class="rl-num ${colourOf(n)}${i === 0 ? ' latest' : ''}">${esc(n)}</div>`).join('');
}

function tick() {
    const timer = $('timer');
    const left = endsAt - Date.now();
    if (!endsAt || left <= 0) { timer.classList.add('hidden'); return; }
    timer.classList.remove('hidden');
    $('timer-bar').style.width = Math.max(0, Math.min(100, (left / span) * 100)) + '%';
    timer.classList.toggle('low', left < 5000);
}
setInterval(tick, 250);

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.type === 'show') {
        hud = { phase: 'idle' };
        $('label').textContent = m.label;
        $('limits').textContent = `${money(m.min)} – ${money(m.max)} a bet`;
        $('panel').classList.remove('hidden');
        endsAt = 0;
        render();
    } else if (m.type === 'hud') {
        hud = m.hud || {};
        if (hud.endsIn > 0) {
            endsAt = Date.now() + hud.endsIn;
            span = Math.max(hud.span || hud.endsIn, 1);
        } else endsAt = 0;
        render();
        tick();
    } else if (m.type === 'hide') {
        $('panel').classList.add('hidden');
        hud = {};
        endsAt = 0;
    }
});
