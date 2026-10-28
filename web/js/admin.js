// Administrator page: make invite and reset codes, see who has an account, disable or delete accounts.
// The admin token is held in memory only and is never stored.

import { h, $, clear, toast, formatBytes } from './dom.js';
import { Api } from './api.js';

const root = $('#app');
let api = null;
let token = '';

const get = (k) => {
  try {
    return localStorage.getItem(k) || '';
  } catch {
    return '';
  }
};

function connectScreen(message = '') {
  const server = h('input', { type: 'url', required: true, value: get('inkwell.api') || (window.INKWELL_API || ''), placeholder: 'https://inkwell-sync.example.workers.dev' });
  const tok = h('input', { type: 'password', required: true, autocomplete: 'off' });
  const error = h('p', { class: 'error', role: 'alert', text: message });
  const form = h('form', { class: 'stack' },
    h('label', { class: 'field' }, 'Server address', server),
    h('label', { class: 'field' }, 'Admin token', tok),
    error,
    h('button', { class: 'btn primary wide', type: 'submit', text: 'Connect' }));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    error.textContent = '';
    api = new Api(server.value.trim());
    token = tok.value.trim();
    try {
      await api.adminUsers(token);
      try {
        localStorage.setItem('inkwell.api', server.value.trim());
      } catch {
        /* ignore */
      }
      dashboard();
    } catch (err) {
      error.textContent = err.status === 401 ? 'That admin token was not accepted.' : err.message;
    }
  });
  clear(root).append(h('main', { class: 'auth' }, h('div', { class: 'auth-card' },
    h('h1', { class: 'brand', text: 'Administration' }),
    h('p', { class: 'tagline', text: 'The admin token is the SYNC_TOKEN secret. It stays in this tab only.' }),
    form, h('p', {}, h('a', { href: 'index.html', text: '← Back to Inkwell' })))));
}

async function dashboard() {
  const usersBox = h('div');
  const codeBox = h('div');

  const purpose = h('select', {}, h('option', { value: 'register', text: 'New account' }), h('option', { value: 'reset', text: 'Forgotten password (reset code)' }));
  const email = h('input', { type: 'email', placeholder: 'person@example.com (needed for a reset)' });
  const role = h('select', {}, h('option', { value: 'user', text: 'Normal user' }), h('option', { value: 'admin', text: 'Administrator' }));
  const days = h('input', { type: 'number', min: '1', max: '30', value: '7' });
  const field = (t, i) => h('label', { class: 'field' }, t, i);
  const form = h('form', { class: 'stack' },
    field('What is it for?', purpose), field('Email', email), field('Role (new accounts only)', role), field('Valid for (days)', days),
    h('button', { class: 'btn primary', type: 'submit', text: 'Make a code' }));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    clear(codeBox);
    try {
      const res = await api.adminInvite(token, { purpose: purpose.value, email: email.value.trim(), role: role.value, days: Number(days.value) });
      codeBox.append(h('div', { class: 'recovery' }, res.code),
        h('p', { class: 'hint', text: `Give this to ${res.email || 'the person'} privately. It works once and expires ${new Date(res.expires).toLocaleDateString()}.` }),
        h('button', { class: 'btn', text: 'Copy', onClick: () => navigator.clipboard.writeText(res.code).then(() => toast('Copied.')).catch(() => toast('Copy failed.')) }));
    } catch (err) {
      codeBox.append(h('p', { class: 'error', text: err.message }));
    }
  });

  async function refresh() {
    clear(usersBox);
    try {
      const { users } = await api.adminUsers(token);
      if (!users.length) return usersBox.append(h('p', { class: 'hint', text: 'No accounts yet.' }));
      usersBox.append(h('table', { class: 'users' },
        h('thead', {}, h('tr', {}, ['Email', 'Role', 'Status', 'Storage', 'Created', ''].map((t) => h('th', { text: t })))),
        h('tbody', {}, users.map((u) => h('tr', {},
          h('td', { text: u.email }), h('td', { text: u.role }), h('td', { text: u.status }),
          h('td', { text: formatBytes(u.bytes || 0) }), h('td', { text: new Date(u.created_at).toLocaleDateString() }),
          h('td', { class: 'actions' },
            u.status === 'active' ? h('button', { class: 'btn small', text: 'Disable', onClick: () => act(u, 'disable') }) : null,
            u.status === 'disabled' ? h('button', { class: 'btn small', text: 'Enable', onClick: () => act(u, 'enable') }) : null,
            h('button', { class: 'btn small danger', text: 'Delete…', onClick: () => remove(u) })))))));
    } catch (err) {
      usersBox.append(h('p', { class: 'error', text: err.message }));
    }
  }

  async function act(user, action) {
    try {
      await api.adminUserAction(token, user.id, action);
      toast(`${action === 'disable' ? 'Disabled' : 'Enabled'} ${user.email}.`);
    } catch (err) {
      toast(err.message);
    }
    refresh();
  }

  async function remove(user) {
    const typed = prompt(`This permanently deletes ${user.email} and every note they stored. It cannot be undone.\n\nType their email to confirm.`);
    if (typed === null) return;
    if (typed.trim().toLowerCase() !== user.email) return toast('That did not match, so nothing was deleted.');
    try {
      const res = await api.adminDeleteUser(token, user.id);
      toast(res.complete ? 'Account deleted.' : 'Deleting. The rest will finish overnight.');
    } catch (err) {
      toast(err.message);
    }
    refresh();
  }

  clear(root).append(h('div', { class: 'admin' },
    h('header', { class: 'lib-top' }, h('h1', { class: 'brand', text: 'Administration' }),
      h('span', { class: 'spacer' }), h('a', { class: 'btn', href: 'index.html', text: 'Back to Inkwell' }),
      h('button', { class: 'btn', text: 'Disconnect', onClick: () => { token = ''; api = null; connectScreen(); } })),
    h('main', { class: 'admin-body' },
      h('section', { class: 'panel' }, h('h2', { text: 'Make an invite or reset code' }), form, codeBox),
      h('section', { class: 'panel' }, h('h2', { text: 'Accounts' }), usersBox))));
  refresh();
}

connectScreen();
