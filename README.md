# Soko — Backend

Django REST API for the Soko project. Three apps: `accounts` (users/JWT auth),
`catalog` (products/categories/reviews), `orders` (cart-to-order, with
server-side stock validation). Matches the schema and endpoint plan in the
project's architecture doc.

This has been tested end-to-end locally (register → login → create product →
place order → stock decrements → over-ordering is rejected) against sqlite.
Connecting it to Supabase is the next step, below.

---

## 1. Connect to Supabase

1. In Supabase: **Project Settings → Database → Connection string → URI tab**.
   Use the **Session pooler** connection, not the direct one.
2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
3. Open `.env` and paste your real Supabase URL into `DATABASE_URL`, replacing
   the placeholder password. Generate a real `SECRET_KEY`:
   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(50))"
   ```
4. **Never commit `.env`** — it's already in `.gitignore`. Only
   `.env.example` (with placeholder values) goes to GitHub.

## 2. Local setup

```bash
python -m venv venv
source venv/bin/activate        # venv\Scripts\activate on Windows
pip install -r requirements.txt
python manage.py dbcheck        # FIRST: confirms Django is really talking to Supabase
python manage.py migrate        # creates all tables in Supabase
python manage.py createsuperuser  # for Django admin access
python manage.py runserver
```

API will be at `http://localhost:8000/api/`. Django admin at `/admin/`.

Once `migrate` runs successfully, open the Supabase **Table Editor** — you
should see `accounts_user`, `catalog_product`, `catalog_category`,
`orders_order`, etc. appear there. That confirms the connection is real.

## 3. Add data

Load the same 7 categories and 16 products the frontend currently uses as
mock data (safe to run more than once):

```bash
python manage.py seed_demo
```

Then create your admin login (a superuser automatically becomes a Soko
admin, so the admin-only API endpoints work for it):

```bash
python manage.py createsuperuser
```

Open `http://localhost:8000/admin/`, log in, and you can add or edit
Categories, Products, Orders (including changing an order's status from
the list) and Users.

Pricing convention: `price` is the normal price and `discount_price`, when
set, is what the customer is actually charged. The API returns both plus
`selling_price` (the one to display and charge).

## 4. API quick reference

| Endpoint | Method | Auth |
|---|---|---|
| `/api/auth/register/` | POST | No |
| `/api/auth/login/` | POST | No |
| `/api/auth/me/` | GET | Yes |
| `/api/categories/` | GET / POST | GET: No · POST: Admin |
| `/api/products/` | GET / POST | GET: No · POST: Admin |
| `/api/products/:id/` | GET / PUT / DELETE | GET: No · others: Admin |
| `/api/products/:id/reviews/` | GET / POST | GET: No · POST: logged in |
| `/api/orders/` | GET / POST | Yes |
| `/api/orders/:id/` | GET | Yes (own orders only) |
| `/api/admin/orders/?status=` | GET | Admin |

Full request/response examples are in the architecture doc. The important
one to understand: `POST /api/orders/` takes `cart_items: [{product_id,
quantity}]` — **not** prices. Prices are looked up server-side so a
tampered request can't under-charge an order, and stock is checked and
decremented atomically inside a transaction.

## 5. Making a user an admin

There's no signup flow for admins — promote a user manually for now:

```bash
python manage.py shell -c "
from accounts.models import User
u = User.objects.get(email='someone@example.com')
u.role = 'admin'
u.save()
"
```

## 6. Connecting the frontend

In the React project, replace the mock data imports with `fetch()` calls to
this API, e.g.:

```js
const res = await fetch(`${import.meta.env.VITE_API_URL}/api/products/`);
const products = await res.json();
```

Add `VITE_API_URL=http://localhost:8000` to the frontend's own `.env` for
local dev, and the Render URL once deployed.

## 7. Deploy to Render

Render runs the Django server; Supabase keeps the data. Render only supports
IPv4 networking, and Supabase's *Direct* connection is IPv6-only — so the
**Session pooler** string (the same one you use locally) is the one to use.

1. Push this backend to its **own** GitHub repo. `manage.py` must be visible on
   the repo's first screen, not inside a subfolder (same nested-folder trap as
   the frontend).
2. On Render: **New → Web Service** → connect that repo.
3. Settings:
   - **Build Command:** `bash build.sh`
   - **Start Command:** `gunicorn soko_backend.wsgi`
4. Add these environment variables:

| Name | Value |
|---|---|
| `DATABASE_URL` | Your Supabase **Session pooler** string, with the real password |
| `SECRET_KEY` | A long random string (generate one, don't reuse your local one) |
| `DEBUG` | `False` |
| `CORS_ALLOWED_ORIGINS` | `https://storesoko.netlify.app` (exact, no trailing slash) |

   Render's own address is added to `ALLOWED_HOSTS` and the CSRF trusted
   origins automatically.
5. Deploy. `build.sh` installs packages, collects the admin's CSS, and runs
   `migrate` against Supabase.

**Admin user and demo data:** local and Render use the *same* Supabase
database, so create them from your laptop (with your local `.env` pointing at
Supabase): `python manage.py createsuperuser` and `python manage.py seed_demo`.
Render's free tier has no shell, and you don't need one. Remember: from this
point your laptop is editing the real, shared data.

The first request after the free server has been idle can take 30–60 seconds.
That's a cold start, not a bug.

## Not built yet

- Cart persistence in the database (cart currently lives in the frontend's
  `localStorage` only — the `cart_items` array is only ever sent at
  checkout, matching the original plan)
- Email notifications, image uploads, coupons — all in the "stretch" list
  from the project framework doc

## Troubleshooting

### Django won't connect to Supabase

Run this first — it shows exactly what Django is connected to and explains
the failure in plain English:

```bash
python manage.py dbcheck
```

Most common causes:
- **"using a LOCAL sqlite file"** — `.env` isn't being read. It must be named
  exactly `.env` and sit next to `manage.py`, with a `DATABASE_URL=` line.
- **Direct connection pasted** (host starts `db.` and ends `.supabase.co`) —
  it's IPv6-only. Use **Connect → Session pooler** instead.
- **`password authentication failed`** — wrong password, the `[YOUR-PASSWORD]`
  brackets left in, or special characters not URL-encoded. Easiest fix: reset
  the database password to letters and numbers only.
- **`Tenant or user not found`** — the pooler username must look like
  `postgres.<project-ref>`; copy the whole string again.

### `pg_config executable not found` during `pip install -r requirements.txt`

Cause: the older `psycopg2-binary` driver has no pre-built package for very
new Python versions (for example 3.14), so pip tries to compile it from
source, which needs PostgreSQL developer tools. This project now uses
`psycopg[binary]` (version 3), which Django supports natively and which
ships pre-built packages for Python 3.14. If you still see this error, your
`requirements.txt` is the old one — replace it with the updated file.
