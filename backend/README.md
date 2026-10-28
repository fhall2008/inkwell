# Inkwell sync backend

A Cloudflare Worker + R2 bucket + D1 database. It stores **encrypted** notes for a small number of
people, each with their own account, so the iPad app and the web portal stay in sync. The server
cannot read the notes: encryption happens on the devices.

## Set up (one time)

1. **Cloudflare account.** Sign up at cloudflare.com. In the dashboard, open **R2 Object Storage** and
   enable it (it may ask for a payment card, even if you stay inside the free allowance).
2. **Account ID.** Dashboard > Workers & Pages. The Account ID is shown on the right-hand side.
3. **API token.** Dashboard > My Profile > API Tokens > Create Token. Start from the
   **Edit Cloudflare Workers** template, then add two more permissions under Account:
   **D1: Edit** and **Workers R2 Storage: Edit**. Create it and copy the token (shown once).
4. **Admin token.** A long random password that only you hold. It lets you create invites and manage
   accounts. Generate one in PowerShell (run it once and keep the result private):

   ```powershell
   $b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)
   ```

5. **GitHub secrets** (repo > Settings > Secrets and variables > Actions):

   | Name | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token from step 3 |
   | `CLOUDFLARE_ACCOUNT_ID` | from step 2 |
   | `SYNC_TOKEN` | the admin token from step 4 (the name stays `SYNC_TOKEN`) |

6. **Deploy.** Actions tab > **Deploy sync backend** > Run workflow. It creates the bucket and database,
   deploys the Worker, and sets the admin token. If it asks you to register a workers.dev subdomain, do that
   in the dashboard (Workers & Pages) and run it again.
7. **Find the address.** Dashboard > Workers & Pages > `inkwell-sync`. The URL looks like
   `https://inkwell-sync.<something>.workers.dev`. Open it in a browser: it should say
   "Inkwell sync is running."

## Adding someone (you, as admin)

Make a one-time invite code (valid 7 days by default). Replace the two placeholders:

```powershell
Invoke-RestMethod -Method Post -Uri "https://YOUR-WORKER-ADDRESS/admin/invites" -Headers @{ Authorization = "Bearer YOUR-ADMIN-TOKEN" } -ContentType "application/json" -Body '{"email":"mum@example.com","role":"user","days":7}'
```

It returns a `code` like `ABCD-EFGH-JKLM-NPQR`. Give it to the person. They enter the code, their email
and a password in the app or web portal to create their account. Use `"role":"admin"` for another admin.
Leave out `email` to let the code work for any address.

Other admin calls: `GET /admin/users` (who has an account and how much space they use),
`POST /admin/users/<id>/disable` or `/enable`, `DELETE /admin/users/<id>` (permanently deletes the
account and all of its stored notes).

Keep the admin token in a password manager and never paste it into a chat or a file in the repo.

## Passwords and encryption (how the clients must do it)

- The person's password is stretched on the device: `PBKDF2-SHA256(password, salt, 600000 rounds)`
  producing 64 bytes. The salt comes from `POST /auth/prelogin` (or a fresh random 16 bytes when registering).
- The **first 32 bytes** encrypt the person's key envelope and never leave the device. The **last 32 bytes**
  (base64) are the `loginKey` sent to the server, which stores only a hash of it.
- A random 256-bit master key encrypts every note, image and the folder list with AES-256-GCM (a fresh
  random nonce per blob). The master key is stored in an `envelope` object, wrapped twice: once by the
  password-derived key and once by a printed **recovery key**.
- Forgetting the password does not lose notes if the recovery key exists. Losing both means the notes
  cannot be recovered by anyone, including the admin.
- Changing the password re-wraps the envelope and calls `POST /auth/password`. Notes aren't re-encrypted.

## Sync protocol

All blobs are opaque encrypted bytes. See the header comment in `src/index.ts` for the endpoints.

- `GET /api/changes?since=N` lists what changed. Remember the returned `cursor` and send it next time.
- `PUT /api/blob/<id>` with `X-Kind` and optionally `X-Base-Version` uploads a new version. If the
  response says `conflict: true`, another device saved first: your version is now the newest and the
  other one is kept in history (`GET /api/versions/<id>`, `GET /api/blob/<id>?version=N`).
- The last 10 versions of each object are kept. Deleted objects are purged after 30 days.
- Each person has a 2 GB storage limit (change `MAX_USER_BYTES` in `src/sync.ts`).

## Limits to know about

- Sign-in attempts are rate-limited (8 per 15 minutes per email).
- The old single-user tables (`objects`, `versions`, `counter`) from the first version are unused and can be
  deleted in the Cloudflare dashboard (D1) when you like.
- Sessions last 30 days, then the person signs in again.
