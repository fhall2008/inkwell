// Tiny IndexedDB key/value helper. Stores only ciphertext and a device-bound wrapping key.

let dbPromise;

function db() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open('inkwell', 1);
      req.onupgradeneeded = () => {
        req.result.createObjectStore('blobs');
        req.result.createObjectStore('vault');
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  return dbPromise;
}

async function run(store, mode, fn) {
  const database = await db();
  return new Promise((resolve, reject) => {
    const tx = database.transaction(store, mode);
    const request = fn(tx.objectStore(store));
    tx.oncomplete = () => resolve(request?.result);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

const safe = async (fn, fallback) => {
  try {
    return await fn();
  } catch {
    return fallback; // private browsing or storage disabled: carry on without a cache
  }
};

export const blobCache = {
  get: (id) => safe(() => run('blobs', 'readonly', (s) => s.get(id)), undefined),
  put: (id, value) => safe(() => run('blobs', 'readwrite', (s) => s.put(value, id)), undefined),
  clear: () => safe(() => run('blobs', 'readwrite', (s) => s.clear()), undefined),
};

// "Remember this device": the master key is wrapped by a non-extractable key kept only in this browser.
export const deviceVault = {
  async save(masterRaw) {
    const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const wrapped = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, masterRaw));
    await run('vault', 'readwrite', (s) => s.put({ key, iv, wrapped }, 'device'));
  },
  async load() {
    const rec = await safe(() => run('vault', 'readonly', (s) => s.get('device')), undefined);
    if (!rec) return null;
    try {
      return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: rec.iv }, rec.key, rec.wrapped));
    } catch {
      return null;
    }
  },
  clear: () => safe(() => run('vault', 'readwrite', (s) => s.delete('device')), undefined),
};
