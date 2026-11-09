import { openDB } from 'idb';
import { DATA_VERSION } from './version';

// How long initDb waits for IndexedDB before giving up. An open can stay
// pending indefinitely when another tab holds the database at an older
// version, and awaiting it forever is what held list spinners. Callers fall
// back to the authenticated network request on timeout; a late success is
// still kept for the next read and nothing local is deleted.
export const DATA_MANAGER_INIT_TIMEOUT_MS = 5000;

export class DataManager {
  constructor(accountId) {
    this.modelsToSync = ['inbox', 'label', 'team', 'canned_response'];
    this.accountId = accountId;
    this.db = null;
    this.initPromise = null;
  }

  async initDb() {
    if (this.db) return this.db;
    // Concurrent reads share one open so they settle together.
    if (this.initPromise) return this.initPromise;

    let timeoutId;
    const timeoutPromise = new Promise((_, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error('IndexedDB init timed out'));
      }, DATA_MANAGER_INIT_TIMEOUT_MS);
    });

    const openPromise = openDB(`cw-store-${this.accountId}`, DATA_VERSION, {
      upgrade(db) {
        // Existing databases already carry the stores added in earlier versions,
        // and createObjectStore throws on a name that is already taken.
        const createStore = (name, options) => {
          if (db.objectStoreNames.contains(name)) return;
          db.createObjectStore(name, options);
        };

        createStore('cache-keys');
        createStore('inbox', { keyPath: 'id' });
        createStore('label', { keyPath: 'id' });
        createStore('team', { keyPath: 'id' });
        createStore('canned_response', { keyPath: 'id' });
      },
    }).then(db => {
      this.db = db;

      // Store the database name in LocalStorage
      const dbName = `cw-store-${this.accountId}`;
      try {
        const dbNames = JSON.parse(
          localStorage.getItem('cw-idb-names') || '[]'
        );
        if (!dbNames.includes(dbName)) {
          dbNames.push(dbName);
          localStorage.setItem('cw-idb-names', JSON.stringify(dbNames));
        }
      } catch {
        // Storage unavailable (e.g. private mode): keep the open connection,
        // the database simply is not listed for later cleanup.
      }

      return db;
    });

    // A late settlement after the timeout already fell back to the network
    // must not surface as an unhandled rejection; a late success is still
    // kept via this.db for the next read.
    openPromise.then(
      () => clearTimeout(timeoutId),
      () => clearTimeout(timeoutId)
    );

    this.initPromise = Promise.race([openPromise, timeoutPromise]);

    try {
      return await this.initPromise;
    } finally {
      // Let the next read retry the open; a late success still assigns this.db.
      this.initPromise = null;
    }
  }

  validateModel(name) {
    if (!name) throw new Error('Model name is not defined');
    if (!this.modelsToSync.includes(name)) {
      throw new Error(`Model ${name} is not defined`);
    }
    return true;
  }

  async replace({ modelName, data }) {
    this.validateModel(modelName);

    await this.db.clear(modelName);
    return this.push({ modelName, data });
  }

  async push({ modelName, data }) {
    this.validateModel(modelName);

    if (Array.isArray(data)) {
      const tx = this.db.transaction(modelName, 'readwrite');
      data.forEach(item => {
        tx.store.add(item);
      });
      await tx.done;
    } else {
      await this.db.add(modelName, data);
    }
  }

  async get({ modelName }) {
    this.validateModel(modelName);
    return this.db.getAll(modelName);
  }

  // Patches a single cached record in place, without touching the cache key, so it
  // does not trigger a full refetch on the next cold load.
  async update({ modelName, id, data }) {
    this.validateModel(modelName);
    const record = await this.db.get(modelName, Number(id));
    if (!record) return;
    await this.db.put(modelName, { ...record, ...data });
  }

  async setCacheKeys(cacheKeys) {
    Object.keys(cacheKeys).forEach(async modelName => {
      this.db.put('cache-keys', cacheKeys[modelName], modelName);
    });
  }

  async getCacheKey(modelName) {
    this.validateModel(modelName);

    return this.db.get('cache-keys', modelName);
  }
}
