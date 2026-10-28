// Talks to the Inkwell sync Worker. Everything uploaded here is already encrypted.

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export class Api {
  constructor(base, token = null) {
    this.base = base.replace(/\/+$/, '');
    this.token = token;
  }

  async request(path, { method = 'GET', json, body, headers = {}, bearer } = {}) {
    const h = { ...headers };
    const token = bearer ?? this.token;
    if (token) h.authorization = `Bearer ${token}`;
    let payload = body;
    if (json !== undefined) {
      payload = JSON.stringify(json);
      h['content-type'] = 'application/json';
    }
    let res;
    try {
      res = await fetch(this.base + path, { method, headers: h, body: payload });
    } catch {
      throw new ApiError(0, 'Could not reach the server. Check your connection and the server address.');
    }
    if (!res.ok) {
      let message = res.statusText || 'Request failed';
      try {
        message = (await res.json()).error || message;
      } catch {
        /* not JSON */
      }
      throw new ApiError(res.status, message);
    }
    return res;
  }

  async json(path, options) {
    return (await this.request(path, options)).json();
  }

  // ----- accounts -----
  prelogin(email) {
    return this.json('/auth/prelogin', { method: 'POST', json: { email } });
  }
  register(invite, email, salt, loginKey) {
    return this.json('/auth/register', { method: 'POST', json: { invite, email, salt, loginKey } });
  }
  reset(invite, email, salt, loginKey) {
    return this.json('/auth/reset', { method: 'POST', json: { invite, email, salt, loginKey } });
  }
  login(email, loginKey) {
    return this.json('/auth/login', { method: 'POST', json: { email, loginKey } });
  }
  me() {
    return this.json('/auth/me');
  }
  logout() {
    return this.json('/auth/logout', { method: 'POST' });
  }
  changePassword(currentLoginKey, newLoginKey, newSalt) {
    return this.json('/auth/password', { method: 'POST', json: { currentLoginKey, newLoginKey, newSalt } });
  }

  // ----- sync -----
  changes(since, limit = 500) {
    return this.json(`/api/changes?since=${since}&limit=${limit}`);
  }
  stats() {
    return this.json('/api/stats');
  }
  async getBlob(id, version) {
    const res = await this.request(`/api/blob/${encodeURIComponent(id)}${version ? `?version=${version}` : ''}`);
    return { bytes: new Uint8Array(await res.arrayBuffer()), version: Number(res.headers.get('x-version')) };
  }
  putBlob(id, kind, bytes, baseVersion) {
    const headers = { 'x-kind': kind, 'content-type': 'application/octet-stream' };
    if (baseVersion !== undefined && baseVersion !== null) headers['x-base-version'] = String(baseVersion);
    return this.json(`/api/blob/${encodeURIComponent(id)}`, { method: 'PUT', body: bytes, headers });
  }
  deleteBlob(id) {
    return this.json(`/api/blob/${encodeURIComponent(id)}`, { method: 'DELETE' });
  }
  versions(id) {
    return this.json(`/api/versions/${encodeURIComponent(id)}`);
  }

  // ----- admin (uses the admin token, not a session) -----
  adminInvite(adminToken, body) {
    return this.json('/admin/invites', { method: 'POST', json: body, bearer: adminToken });
  }
  adminUsers(adminToken) {
    return this.json('/admin/users', { bearer: adminToken });
  }
  adminUserAction(adminToken, id, action) {
    return this.json(`/admin/users/${encodeURIComponent(id)}/${action}`, { method: 'POST', bearer: adminToken });
  }
  adminDeleteUser(adminToken, id) {
    return this.json(`/admin/users/${encodeURIComponent(id)}`, { method: 'DELETE', bearer: adminToken });
  }
}
