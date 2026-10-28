# Inkwell sync backend

A Cloudflare Worker + R2 bucket + D1 database. It stores **encrypted** notes for one person and lets
the iPad app and the web app stay in sync. The server cannot read the notes: encryption happens on
the devices.

## Set up (one time)

1. **Cloudflare account.** Sign up at cloudflare.com. In the dashboard, open **R2 Object Storage** and
   enable it (it may ask for a payment card, even if you stay inside the free allowance).
2. **Account ID.** Dashboard > Workers & Pages. The Account ID is shown on the right-hand side.
3. **API token.** Dashboard > My Profile > API Tokens > Create Token. Start from the
   **Edit Cloudflare Workers** template, then add two more permissions under Account:
   **D1: Edit** and **Workers R2 Storage: Edit**. Create it and copy the token (shown once).
4. **Sync token.** A long random password that the iPad and web app send to prove they're allowed.
   Generate one in PowerShell (run it once and keep the result private):

   ```powershell
   $b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)
   ```

5. **GitHub secrets** (repo > Settings > Secrets and variables > Actions):

   | Name | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token from step 3 |
   | `CLOUDFLARE_ACCOUNT_ID` | from step 2 |
   | `SYNC_TOKEN` | the random password from step 4 |

6. **Deploy.** Actions tab > **Deploy sync backend** > Run workflow. It creates the bucket and database,
   deploys the Worker, and sets the token. If it asks you to register a workers.dev subdomain, do that in
   the dashboard (Workers & Pages) and run it again.
7. **Find the address.** Dashboard > Workers & Pages > `inkwell-sync`. The URL looks like
   `https://inkwell-sync.<something>.workers.dev`. Open it in a browser: it should say
   "Inkwell sync is running."

Keep the sync token in a password manager. You enter it (and the URL) once on each device.

## Wire format (for the app and web client)

All blobs are opaque encrypted bytes. See the header comment in `src/index.ts` for the endpoints.

- `GET /api/changes?since=N` lists what changed. Remember the returned `cursor` and send it next time.
- `PUT /api/blob/<id>` with `X-Kind` and optionally `X-Base-Version` uploads a new version. If the
  response says `conflict: true`, someone else saved first: your version is now the newest and the
  other one is kept in history (`GET /api/versions/<id>`, `GET /api/blob/<id>?version=N`).
- The last 10 versions of each object are kept. Deleted objects are purged after 30 days.

## Planned encryption (client side)

- A random 256-bit master key encrypts everything with AES-256-GCM (a fresh random nonce per blob).
- The master key is stored in an `envelope` object, wrapped twice: once with a key derived from the
  passphrase (PBKDF2-SHA256, high iteration count) and once with a printed recovery key.
- Changing the passphrase only rewrites the envelope. The notes don't need re-encrypting.
