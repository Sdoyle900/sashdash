# SashDash 🪟💨

Job sheets for the Sean Doyle Windows service team. Same setup as RackTrack: one `index.html` on **GitHub Pages**, data and PDFs in **Supabase**.

- **Office (you):** dashboard of all service men → open a man's portal → site tabs → upload order sheets (PDF or photos) → chat about each job → delete jobs (file is removed from the server).
- **Service men:** log in on their phone, see **only their own** sites and jobs, strike items off the sheet with their finger, comment, and tick **Complete**.

---

## Setup (about 20 minutes, once)

### 1. Create a new Supabase project
Use a **new project**, not the RackTrack one. (RackTrack treats every Supabase login as an admin, so service-man logins must not live there.)

1. supabase.com → **New project** → name it `sashdash`, region **West EU (Ireland)**.
2. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up" (only you add people) and turn **off** "Confirm email".
3. **SQL Editor → New query** → paste all of `supabase/schema.sql` → **Run**. This creates the tables, the who-sees-what rules, the private `job-files` storage bucket and live chat.

### 2. Add yourself and make yourself the office admin
1. **Authentication → Users → Add user → Create new user** → your email + a password, tick **Auto Confirm User**.
2. SQL Editor → run (with your email):
   ```sql
   update public.profiles set role = 'admin', full_name = 'Sean'
   where id = (select id from auth.users where email = 'seandoyle102@gmail.com');
   ```

### 3. Add the 5 service men
For each man: **Authentication → Users → Add user → Create new user**
- Email: `john@sashdash.app` (`paddy@sashdash.app`, etc. — these don't need to be real email addresses)
- A password · tick **Auto Confirm User**

He logs in with just **`john`** and his password. Then in SashDash click **👥 Manage team** to set his proper name, phone and card colour.

### 4. Connect the app
Supabase → **Project Settings → API**: copy the **Project URL** and the **anon public** key into the top of the script in `index.html`:
```js
const SUPABASE_URL  = "https://xxxx.supabase.co";
const SUPABASE_ANON = "eyJhbGciOi...";
```

### 5. Put it on GitHub Pages
1. GitHub → **New repository** → `sashdash` (public, like Rack-tracker).
2. **Add file → Upload files** → drag in everything from this folder (including the `.github` and `supabase` folders) → Commit.
3. **Settings → Pages** → Source: *Deploy from a branch*, `main`, `/ (root)` → Save.
4. In a minute it's live at **https://sdoyle900.github.io/sashdash/**

### 6. Keep Supabase awake (same as RackTrack)
Free Supabase projects pause after 7 days of no use. The included GitHub Action pings it every morning.
Repo → **Settings → Secrets and variables → Actions → New repository secret**:
- `SUPABASE_URL` = your project URL
- `SUPABASE_ANON_KEY` = your anon key

---

## Installing on the phones
Send each man the link **https://sdoyle900.github.io/sashdash/**
- **iPhone:** open in **Safari** → Share button → **Add to Home Screen**.
- **Android:** open in **Chrome** → ⋮ menu → **Install app** (or *Add to Home screen*).

It then opens full-screen from its own SashDash icon, stays logged in, and updates itself whenever you change `index.html` on GitHub. No App Store needed.

---

## How it works day to day
| You (office) | Service man |
|---|---|
| Dashboard shows each man: sites, open jobs, done, and a red **"new"** badge when he's commented, marked up or completed something | Opens app → his site tabs → jobs with a red **New** marker for anything you've sent |
| Open his portal → **＋ New site** (e.g. *Herons Lock*) → **⬆ Upload job** | Taps a job → sheet on one tab, chat on the other |
| Upload a PDF, or photos of the sheet (several photos become one PDF, shrunk to save space) | **✏️ Mark up** → *Line* tool snaps flat for striking items through; Pen, Highlighter, Eraser, Undo → **Save** |
| Chat beside each job; download the marked-up PDF from the ⋯ menu | Writes in the chat, ticks **Complete** (can re-open) |
| ⋯ → **Delete job** removes the PDF, marked copy and chat from the server. Deleting a site removes all its jobs' files too. | — |

The original PDF is never changed — marks are saved separately and burned into a `marked.pdf` copy, so they stay editable and you always keep the clean original.

**Storage:** the dashboard shows how much of the free 1 GB is used. A typical photographed sheet is 300–500 KB, so that's roughly 2,000+ jobs before you'd need to delete old ones or upgrade.

## Files
| File | What it is |
|---|---|
| `index.html` | The whole app (office + service man) |
| `supabase/schema.sql` | Database, security rules, storage bucket — run once |
| `manifest.json`, `sw.js`, `icon-*.png`, `apple-touch-icon.png` | Makes it installable on phones |
| `sdwindows-logo.png` | Company logo |
| `.github/workflows/keep-supabase-awake.yml` | Daily ping |
