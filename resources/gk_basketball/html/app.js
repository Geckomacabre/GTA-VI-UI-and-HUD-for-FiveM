const board = document.getElementById('board');
const el = {
    homeName: document.getElementById('home-name'),
    awayName: document.getElementById('away-name'),
    homeScore: document.getElementById('home-score'),
    awayScore: document.getElementById('away-score'),
    clock: document.getElementById('clock'),
    status: document.getElementById('status'),
    roster: document.getElementById('roster'),
    home: document.querySelector('.team.home'),
    away: document.querySelector('.team.away'),
};

function formatClock(seconds) {
    if (seconds === null || seconds === undefined) return '--:--';
    const s = Math.max(0, Math.floor(seconds));
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

function statusFor(data) {
    switch (data.state) {
        case 'lobby':
            return { text: 'Lobby', cls: '' };
        case 'countdown':
            return { text: `Tip-off ${data.countdown ?? ''}`.trim(), cls: '' };
        case 'live':
            return { text: 'Live', cls: 'live' };
        case 'ended':
            return { text: 'Final', cls: 'final' };
        default:
            return { text: 'Waiting', cls: '' };
    }
}

function render(data) {
    const teams = data.teams || {};
    const home = teams.home || { label: 'Home', colour: '#4a9eff' };
    const away = teams.away || { label: 'Away', colour: '#ff6b4a' };

    el.home.style.setProperty('--accent', home.colour);
    el.away.style.setProperty('--accent', away.colour);

    el.homeName.textContent = home.label;
    el.awayName.textContent = away.label;
    el.homeScore.textContent = data.score?.home ?? 0;
    el.awayScore.textContent = data.score?.away ?? 0;

    el.home.classList.toggle('mine', data.myTeam === 'home');
    el.away.classList.toggle('mine', data.myTeam === 'away');

    // With no clock configured, show progress toward the score limit instead of
    // an empty timer. A nil clock on the Lua side arrives as undefined rather than
    // null, so these checks are deliberately loose.
    if (data.state === 'live' && data.clock == null && data.scoreLimit > 0) {
        el.clock.textContent = `to ${data.scoreLimit}`;
        el.clock.classList.remove('urgent');
    } else {
        el.clock.textContent = formatClock(data.state === 'countdown' ? data.countdown : data.clock);
        el.clock.classList.toggle('urgent', data.state === 'live' && data.clock != null && data.clock <= 30);
    }

    const status = statusFor(data);
    el.status.textContent = status.text;
    el.status.className = `status ${status.cls}`;

    el.roster.replaceChildren();

    for (const player of data.players || []) {
        const colour = (teams[player.team] || {}).colour || '#666';

        const li = document.createElement('li');
        if (player.id === data.myId) li.classList.add('me');

        const dot = document.createElement('span');
        dot.className = 'dot';
        dot.style.setProperty('--accent', colour);

        const who = document.createElement('span');
        who.className = 'who';
        who.textContent = player.name;

        const pts = document.createElement('span');
        pts.className = 'pts';
        pts.textContent = player.points;

        li.append(dot, who, pts);
        el.roster.append(li);
    }
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};

    if (msg.action === 'update') {
        render(msg.data || {});
        board.classList.remove('hidden');
    } else if (msg.action === 'hide') {
        board.classList.add('hidden');
    }
});
