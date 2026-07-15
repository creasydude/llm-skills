---
name: telegram-serverless
description: Build Telegram bots using serverless infrastructure - no servers to manage, deploy with a single command
tags: [telegram, serverless, bots, javascript]
---

# Telegram Serverless — Complete Documentation

**Source:** https://core.telegram.org/bots/serverless  
**Last Retrieved:** 2025-07-15  
**Status:** Official Telegram Bot Platform Documentation

---

## Overview

Telegram Serverless lets you run backend code for your bot and Mini App **directly on Telegram's infrastructure** — no servers to provision, no containers to keep alive, no scaling to think about. You write plain JavaScript modules, deploy them with a single command, and Telegram runs them in a fast, isolated V8 sandbox that sits right next to the Bot API and a built-in database.

If you have ever wired a bot to a VPS, a cloud function, or a hosting panel just to answer a `/start`, this is the part you no longer have to do.

---

## Table of Contents

1. [Why Serverless](#why-serverless)
2. [The Mental Model](#the-mental-model)
3. [Quick Demo](#quick-demo)
4. [Getting Started](#getting-started)
5. [Building with AI](#building-with-ai)
6. [On the Go with BotFather](#on-the-go-with-botfather)
7. [Projects and Modules](#projects-and-modules)
8. [The Database](#the-database)
9. [Migrations](#migrations)
10. [The SDK](#the-sdk)
11. [Command-Line Interface](#command-line-interface)
12. [Staying in Sync](#staying-in-sync)

---

## Why Serverless

A Telegram bot is, at heart, a program that reacts to updates. Traditionally you had to host that program somewhere that is always on, reachable, and secure — and then keep it that way. Telegram Serverless removes that layer entirely:

- **No infrastructure.** There is no machine to rent, patch, or monitor. Your code runs on demand and scales with your bot automatically.
- **Batteries included.** The Telegram Bot API, an SQLite-backed database, and outbound HTTP are available to every module out of the box — nothing to install, no credentials to wire up.
- **Fast, isolated execution.** Each invocation runs in a lightweight V8 isolate, close to Telegram's own systems, so calls to the Bot API and your database are quick and reliable.
- **A real developer workflow.** A project lives in a folder on your machine under version control. You edit files, see exactly what changed, deploy atomically, and roll your database schema forward with reviewed migrations — the way you already work with everything else.

### The Mental Model

You work in **three places**, and they map cleanly onto each other:

| Where | What lives there |
|-------|------------------|
| Your project folder | JavaScript modules — schema, shared code, update handlers |
| The cloud | The deployed copy of those modules, plus your bot's database |
| The `tgcloud` CLI | The bridge — it shows you differences and syncs them |

You never SSH into anything. You edit files locally, run `npx tgcloud push`, and the platform takes it from there. Your bot's traffic is handled by the deployed modules; your database persists between invocations.

A project has just three kinds of code:

```
handlers/      # entry points — one file per Telegram update type
lib/           # shared code you import from anywhere
schema.js      # your database tables
```

When an update arrives — a message, a button press, an inline query — Telegram routes it to the matching handler (`handlers/message.js`, `handlers/callback_query.js`, …) and calls its default export. That function talks to the Bot API and the database through the SDK, and returns. That is the whole loop. An update with no matching handler is simply ignored, so you add only the handlers you need.

### Quick Demo

Here is a complete, working demo bot. It replies to every message and remembers how many it has seen from each chat.

**schema.js**
```javascript
import { table, integer } from 'sdk/db';

export const counters = table('counters', {
  chatId: integer('chat_id').primaryKey(),
  seen:   integer('seen').notNull().default(0),
});
```

**handlers/message.js**
```javascript
import { api, db } from 'sdk';
import { counters } from 'schema';
import { sql } from 'sdk/db';

export default async function (message) {
  const chatId = message.chat.id;

  // Insert the counter, or bump it if this chat already has one — and get the
  // resulting row back in the same statement via .returning().
  const [row] = await db.insert(counters)
    .values({ chatId, seen: 1 })
    .onConflictDoUpdate({
      target: counters.chatId,
      set: { seen: sql`${counters.seen} + 1` },
    })
    .returning()
    .run();

  await api.sendMessage({
    chat_id: chatId,
    text: `Hello! I've seen ${row.seen} message(s) from you.`,
  });
}
```

Deploy it:
```bash
npx tgcloud push       # upload the modules
npx tgcloud migrate    # create the `counters` table
```

That's a live bot with persistent state and no server. Everything in it — `api`, `db`, the `table()` DSL — is described in the sections below.

Serverless is a general backend for Telegram bots and Mini Apps, not a template for one kind of app. It is ideal for:

- **Conversational AI Bots** that need to store per-user state in a database.
- **Mini App Backends** that store user data and serve dynamic content.
- **Games and Tools** — including leaderboards, quizzes and more.
- **Automations and Integrations** that call third-party HTTP APIs and push results into chats.

---

## Getting Started

This walkthrough takes you from an empty folder to a live bot that answers messages and stores data. It assumes you have Node.js 18 or newer installed and a bot registered with @BotFather. By the end you will have used every command you need day to day: `push`, `migrate`, `run`, and `status`.

> **Before anything else, switch Serverless on.** In @BotFather, open your bot → **Serverless** and turn it on. That turns the feature on for this bot and unlocks its CLI access token, handlers, library, and database.

### 1. Create a Project

The fastest way to start is the project creator, which scaffolds a project and installs the CLI into it:

```bash
npm create @tgcloud/bot example_bot
cd example_bot
```

The argument is the target folder: pass `.` to scaffold into the current folder, or any path. It works in an existing folder too and never overwrites files you already have.

This gives you a ready-to-edit project:

```
example_bot/
├─ docs/
│  └─ tgcloud-sdk.md    # SDK reference (for you and your AI tools)
├─ handlers/
│  └─ message.js        # a starter message handler (echoes text back)
├─ lib/                 # your shared modules go here (empty to start)
├─ AGENTS.md            # orientation for AI coding assistants
├─ package.json
└─ schema.js            # your database tables
```

The scaffolded files are self-documenting — each one contains commented examples of what you can do next.

The CLI installs into the project as a local dev-dependency, so you run it with `npx tgcloud <command>` (npx finds the copy in your project's `node_modules`), or through the `npm run` shortcuts the scaffold adds to `package.json` (`npm run deploy`, `npm run status`). By default there is no global `tgcloud` on your `PATH`.

You can also install it globally — `npm install -g @tgcloud/cli` — if you'd rather type a bare `tgcloud` from anywhere. That's handy for running `tgcloud init` in any empty folder, and it's what shell tab-completion needs. Either way you get the same project.

### 2. Link Your Bot

Every project is tied to one bot. Connect them with `login`, which asks for your CLI access token (@BotFather → your bot → Serverless → CLI Access → Access token — a separate token from your bot's API token) and stores it locally:

```bash
npx tgcloud login
```

The token has the form `app<id>:<secret>`. The CLI keeps it in `.tgcloud/`, which is git-ignored, and never prints the secret part. Login is the only time you are asked for it — see Authentication for how tokens are resolved in CI.

### 3. Look Around

Two commands tell you where things stand at any moment, both fully offline:

```bash
npx tgcloud status     # what has changed locally vs. the deployed copy
npx tgcloud diff       # the line-by-line changes
```

Right after `init` everything is new and nothing is deployed yet. `status` shows the starter files waiting to go up.

### 4. Deploy

Send your modules to the cloud:

```bash
npx tgcloud push
```

`push` uploads every changed module in one atomic batch and updates your local record of what the cloud now holds. Your bot is live: open it in Telegram and send it a message — the starter handler echoes it back.

> **Deploying never touches your database.** Pushing code and changing your database schema are deliberately separate steps, so a code deploy can never surprise you with a data migration. That is what the next step is for.

### 5. Add a Database Table

Let's make the bot remember something. Open `schema.js` and declare a table:

```javascript
import { table, integer, text, sql } from 'sdk/db';

export const messages = table('messages', {
  id:      integer('id').primaryKey({ autoIncrement: true }),
  chatId:  integer('chat_id').notNull(),
  text:    text('text'),
  created: integer('created_at', { mode: 'timestamp' }).default(sql`(unixepoch())`),
});
```

Deploy the schema, then apply it to the database:

```bash
npx tgcloud push       # uploads the new schema.js
npx tgcloud migrate    # creates the `messages` table
```

`push` reports that the schema is out of sync and shows you the pending change, but applies nothing. `migrate` walks you through the change and, on your confirmation, creates the table. This two-step model — and what happens with riskier changes like drops — is covered in Migrations.

### 6. Store and Read Data

Now use the table from your handler. Edit `handlers/message.js`:

```javascript
import { api, db } from 'sdk';
import { messages } from 'schema';
import { eq } from 'sdk/db';

export default async function (message) {
  // Save this message.
  await db.insert(messages)
    .values({ chatId: message.chat.id, text: message.text })
    .run();

  // Count how many we've stored for this chat.
  const count = await db.$count(messages, eq(messages.chatId, message.chat.id));

  await api.sendMessage({
    chat_id: message.chat.id,
    text: `Saved. That's ${count} message(s) from this chat so far.`,
  });
}
```

Deploy the updated handler with `npx tgcloud push`, then send your bot a few messages and watch the count climb. The database persists between invocations — that's your bot's memory.

### 7. Test Without Deploying

You don't have to deploy to try a change. `npx tgcloud run` executes a handler on the platform using your **local** files, without publishing them:

```bash
npx tgcloud run handlers/message '{ chat: { id: 1 }, text: "hello" }'
```

The argument is the payload your handler receives — for `handlers/message`, a Message — written in JSON5 (so you can skip quoting keys). The command prints anything the handler logged with `console.*`, the return value, and how long it took. This is the tightest loop for iterating on logic — no deploy, no waiting for a real message.

### 8. Keep in Sync

As you work, a handful of commands keep your local project and the cloud aligned: `npx tgcloud status` shows what changed, `npx tgcloud push` deploys, `npx tgcloud pull` brings your local project in line with the cloud, `npx tgcloud fetch` refreshes the reference copy without touching your files, and `npx tgcloud reset` discards local changes.

> If two people (or two machines) deploy to the same bot, the platform detects the conflict and `push` stops to let you `pull` first — you can never silently overwrite someone else's work. See Staying in Sync.

---

## Building with AI

Prefer to build with an AI assistant — or is the only coder on your team an AI? You can still ship a bot. We've taken a first step to make an AI agent feel at home in a project: every new one is scaffolded with an `AGENTS.md` and a `docs/tgcloud-sdk.md` reference that agentic coding tools read automatically.

Together with a small, self-contained runtime — one SDK, no npm packages to wrangle — that gives the assistant a running start on the conventions generic codegen tends to miss here: import by bare name, no foreign keys, every `db` call is async, one handler per update type, and the two-step `push`/`migrate` flow.

Try it:

```bash
npm create @tgcloud/bot my-bot
cd my-bot
opencode            # or Claude Code, Cursor, … — any agent that reads AGENTS.md
```

Then just ask, in plain language:

> Write a bot that remembers each person's to-do list — add an item when they send text, and show the whole list when they send /list.

The assistant edits `schema.js` and your handlers for you; you review, test a change instantly with `npx tgcloud run`, then go live with `npx tgcloud push` and `npx tgcloud migrate`. `AGENTS.md` is part of your project — edit it as the bot grows so the guidance stays accurate.

---

## On the Go with BotFather

Down to just your phone? The whole project lives in @BotFather too — open your bot → **Serverless** and you get everything the CLI manages, on a touchscreen:

- **Handlers** — create, edit, and test-run update handlers; BotFather keeps the webhook in sync with the handlers you have (the same *In sync* / *Out of sync* the CLI reports).
- **Library** — your shared `lib/` modules.
- **Database** — edit `schema.js` in the same Drizzle-like syntax, review pending changes, and apply them; **Save** deploys.
- **CLI Access** — grab the CLI access token here when you're back at a keyboard.

It's one and the same cloud project, so you can start a handler on your phone and `npx tgcloud pull` it to your laptop later.

---

## Projects and Modules

### Project Structure

A project is a folder on your machine with this layout:

```
project/
├─ .tgcloud/              # CLI state (git-ignored)
│  ├─ credentials         # login token (never committed)
│  ├─ deployed/           # reference copy of deployed modules
│  └─ revision            # last synced cloud revision
├─ handlers/              # update handlers (flat)
│  ├─ message.js
│  ├─ callback_query.js
│  └─ …
├─ lib/                   # shared modules (nestable)
│  ├─ utils.js
│  └─ payments/
│     └─ stripe.js
├─ schema.js              # database schema
├─ AGENTS.md              # AI agent guidance
├─ docs/
│  └─ tgcloud-sdk.md     # SDK reference
└─ package.json
```

### Handlers

A handler is a JavaScript module under `handlers/` whose filename matches a Telegram update type (`message`, `callback_query`, `inline_query`, `chat_member`, `my_chat_member`, `chat_join_request`, `poll`, `poll_answer`, `pre_checkout_query`, `shipping_query`, `business_connection`, `business_message`, `edited_business_message`, `deleted_business_messages`, `message_reaction`, `message_reaction_count`).

Each handler exports a **default async function** that receives the update object (e.g., a Message for `message`, a CallbackQuery for `callback_query`) and a context object as its second argument:

```javascript
// handlers/message.js
export default async function (message, ctx) {
  // message: Message (from Telegram Bot API)
  // ctx: { update: Update, botInfo: User }
}
```

The context object contains:
- `update` — the full Update object (includes `update_id`)
- `botInfo` — the bot's own User object (from `getMe`)

You only create handlers for the update types you actually handle. An incoming update with no matching handler is silently ignored.

### Library Modules

Any file under `lib/` is a shared module you can import by its bare path from anywhere:

```javascript
// lib/utils.js
export function formatCount(n) {
  return n === 1 ? '1 message' : `${n} messages`;
}
```

```javascript
// handlers/message.js
import { formatCount } from 'lib/utils';
// or from a nested path:
import { charge } from 'lib/payments/stripe';
```

### The Module System

- Import project modules by **bare name**: `from 'schema'`, `from 'lib/utils'`, `from 'handlers/message'`.
- Never use relative paths (`./`, `../`) or `.js` extensions for project imports.
- The SDK is always available as `sdk` (or `sdk/db`, `sdk/api`, `sdk/fetch`).
- No `node_modules`, no `package.json` dependencies (except the CLI itself). The runtime provides everything.

---

## The Database

The database is SQLite, accessed through a Drizzle-like query builder and schema DSL. It is **per-bot**, persists forever, and is included at no extra cost.

### Schema Definition (`schema.js`)

```javascript
import { table, integer, text, real, blob, sql } from 'sdk/db';

export const users = table('users', {
  id:        integer('id').primaryKey({ autoIncrement: true }),
  username:  text('username').unique(),
  balance:   real('balance').notNull().default(0),
  data:      blob('data'),                    // raw bytes
  createdAt: integer('created_at', { mode: 'timestamp' }).default(sql`(unixepoch())`),
});

export const items = table('items', {
  id:          integer('id').primaryKey({ autoIncrement: true }),
  userId:      integer('user_id').notNull().references(() => users.id),
  name:        text('name').notNull(),
  quantity:    integer('quantity').notNull().default(1),
  purchasedAt: integer('purchased_at', { mode: 'timestamp' }),
});
```

**Column Types:**
- `integer(name, { mode: 'timestamp' | 'number' })` — INT, optional timestamp mode
- `text(name)` — TEXT
- `real(name)` — REAL (floating point)
- `blob(name)` — BLOB (raw bytes)

**Column Modifiers:**
- `.primaryKey({ autoIncrement?: boolean })`
- `.notNull()`
- `.default(value | sql\`...\`)`
- `.unique()`
- `.references(() => otherTable.column)`
- `.deprecated('reason')` — marks for removal (see Migrations)

**Table Modifiers:**
- `.deprecated('reason')` — marks whole table for removal

### Query Builder (`db`)

```javascript
import { db } from 'sdk';
import { users, items } from 'schema';
import { eq, and, or, lt, gt, like, inArray, sql } from 'sdk/db';
```

**Insert:**
```javascript
await db.insert(users).values({ username: 'pavel', balance: 100 }).run();
const [row] = await db.insert(users).values({ username: 'pavel' }).returning().run();
```

**Upsert (ON CONFLICT):**
```javascript
await db.insert(users)
  .values({ username: 'pavel', balance: 50 })
  .onConflictDoUpdate({
    target: users.username,
    set: { balance: sql`${users.balance} + 50` },
  })
  .run();
```

**Select:**
```javascript
const all = await db.select().from(users).all();
const one = await db.select().from(users).where(eq(users.username, 'pavel')).get();
const page = await db.select().from(users).limit(20).offset(40).all();
```

**Where Helpers:**
```javascript
eq(col, val), ne(col, val), lt(col, val), lte(col, val), gt(col, val), gte(col, val)
like(col, pattern), ilike(col, pattern)
inArray(col, values), notInArray(col, values)
isNull(col), isNotNull(col)
and(...conditions), or(...conditions)
```

**Update:**
```javascript
await db.update(users)
  .set({ balance: sql`${users.balance} + 10` })
  .where(eq(users.username, 'pavel'))
  .run();
```

**Delete:**
```javascript
await db.delete(users).where(eq(users.username, 'pavel')).run();
```

**Count:**
```javascript
const n = await db.$count(users, eq(users.balance, 0));
```

**Transactions:**
```javascript
await db.transaction(async (tx) => {
  await tx.insert(users).values({ username: 'a' }).run();
  await tx.insert(users).values({ username: 'b' }).run();
});
```

**Raw SQL:**
```javascript
await db.run(sql`PRAGMA journal_mode = WAL`);
const rows = await db.all(sql`SELECT * FROM users WHERE balance > 100`);
```

---

## Migrations

Data outlives code. The platform keeps that safe by separating **deploying code** from **changing data**, and by classifying every schema change by how risky it is.

### Deploying Never Touches the Database

When you `npx tgcloud push` a changed `schema.js`, the platform records the new schema and tells you what the database *would* change — but applies nothing:

```bash
npx tgcloud push       # deploy schema.js; reports pending DB changes
npx tgcloud migrate    # review and apply them
```

`npx tgcloud migrate` computes the difference between your schema and the live database and walks you through it. You are always asked before anything is applied. This means a routine code deploy can never trigger a data migration by accident.

### Change Classification

Each pending change carries a status that determines how `migrate` treats it:

| Status | Meaning | In `migrate` |
|--------|---------|--------------|
| **safe** | Additive and non-blocking — a new table, column, or index | Applied together in one step, on confirmation |
| **warning** | Potentially destructive or slow — dropping something, or an index on a huge table | Presented one at a time, each confirmed separately |
| **manual** | Can't be done automatically — e.g. changing a column's type | Shown with guidance; you perform it by hand |
| **undocumented** | Exists in the database but not in your schema | Shown for awareness; not applied |

Safe changes are quick and reversible in spirit, so they go through together. Each warning is a deliberate, individual confirmation — there is no "apply all" for destructive changes.

Manual changes come with a reason and a suggested action. `migrate` ends with a summary: how many changes were applied, skipped, awaiting a manual fix, or not in your schema.

> See `migrate` for the flags (`--dry-run`, `--safe`, `--yes`, `--local`).

### Removing Things

Deleting a table or column from `schema.js` does **not** drop it — that would make an accidental deletion catastrophic. To remove something, mark it deprecated:

```javascript
// drop a column
text('email').deprecated('replaced by login')

// drop a whole table
export const oldSessions = table('old_sessions', { /* … */ }).deprecated('unused');
```

On the next `migrate`, the deprecated object shows up as a **warning**-status drop that you confirm individually. Once it's gone, remove the declaration.

### Changing a Column's Type

Type changes are **manual** — SQLite can't always do them in place, and coercing existing values is a judgment call. `migrate` will show the change and its reasoning; perform it yourself with raw SQL (`db.run(...)`), typically by creating a new column or table, copying data, and swapping.

---

## The SDK

At runtime a module has one library: `sdk`. It bundles the three things a bot backend needs — a database, the Telegram Bot API, and outbound HTTP — with nothing to install and no credentials to configure. The database (`db`) is covered in The Database; this section covers `api`, `fetch`, and the `console` global.

```javascript
import { db, api, fetch, BotApiError } from 'sdk';   // the whole surface
// or from submodules:
import { table, integer, text, eq, sql } from 'sdk/db';
import { api } from 'sdk/api';
import { fetch } from 'sdk/fetch';
```

| Import | What it is |
|--------|------------|
| `db` | Database — query builder and schema DSL → The Database |
| `api` | Telegram Bot API — `api.sendMessage(...)` → The Bot API |
| `fetch` | Outbound HTTP → HTTP |

Import your own project modules by their **bare name** (`from 'schema'`, `from 'lib/cart'`) — never a relative path or a `.js` extension. See The Module System.

### The Bot API

`api` gives you the entire Telegram Bot API. Call any method as `api.<method>(params)`. Every current — and future — Bot API method works with **no SDK update** required.

```javascript
import { api } from 'sdk';

const me = await api.getMe();                            // → the unwrapped result
await api.sendMessage({ chat_id: id, text: 'Hello!' });
await api.editMessageText({ chat_id, message_id, text: 'Updated' });
await api.answerCallbackQuery({ callback_query_id, text: 'Done' });
```

**The response envelope is unwrapped.** The Bot API normally wraps results in `{ ok: true, result: … }`. `api` returns the `result` directly — `getMe()` resolves to the user object, not to a wrapper. Parameters use the Bot API's own snake_case names (`chat_id`, `message_id`, `reply_markup`, …).

**Failures throw `BotApiError`.** When the Bot API returns `{ ok: false }`, the call throws a `BotApiError` instead of returning a falsy value, so you can't accidentally ignore it. The error carries `.code` (the Bot API `error_code`), `.description` (the human-readable message), `.method` (which method failed), and `.parameters` (extra data such as `retry_after` on a 429, or `migrate_to_chat_id`). Catch it to handle an expected failure and rethrow the rest:

```javascript
import { api, BotApiError } from 'sdk';

try {
  await api.deleteMessage({ chat_id, message_id });
} catch (e) {
  if (e instanceof BotApiError && e.code === 400) {
    // 400 = the message is already gone; that's fine here.
  } else {
    throw e;
  }
}
```

#### File Limitations

You can work with files already on Telegram's servers by their `file_id` — send, forward, or reuse them — but downloading a file's bytes (`getFile` plus fetching the content) or uploading a new file from a handler **isn't supported yet**.

> You can easily design around this temporary limitation by passing `file_id`s rather than raw bytes.

### HTTP

`fetch` is a `fetch`-like client for calling the outside world — third-party APIs, webhooks, anything over HTTP.

```javascript
import { fetch } from 'sdk';

const res = await fetch('https://api.example.com/users', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'Pavel' }),
});
if (!res.ok) throw new Error(res.statusText);
const data = await res.json();
```

The response mirrors the web platform: `res.status`, `res.statusText`, `res.ok` (true for 200–299), `res.url`, `res.headers` (`.get()`, `.has()`, `.keys()`, `.entries()`), and body readers `await res.json()` / `await res.text()`.

> You can also read the body incrementally as a **stream** — `for await (const chunk of res.body) { … }` — which is how you consume server-sent events or token-by-token output from **AI APIs**.

Body helpers set the matching `Content-Type` for you:

```javascript
await fetch(url, { method: 'POST', body: fetch.body.json({ a: 1 }) }); // application/json
await fetch(url, { method: 'POST', body: fetch.body.form({ a: 1 }) }); // x-www-form-urlencoded
await fetch(url, { method: 'POST', body: fetch.body.text('hi') });     // text/plain
```

It otherwise behaves like the standard `fetch` you already know, with **two constraints**:
- Response content is **textual** (binary payloads aren't supported).
- The **total response is capped at 32 MB**. That cap covers the whole response — streaming with `res.body` lets you process a large body incrementally, but it does not raise the limit.

### Logging

The standard global `console` is available — nothing to import, it's just there as in any JavaScript. Its output is captured and shown by `npx tgcloud run`, which makes it your primary debugging tool during development.

```javascript
console.log('processing', { chatId: id });   // log / debug — plain
console.info('started');                     // info  — blue
console.warn('rate limited');                // warn  — yellow
console.error(err);                          // error — red, with a stack trace
```

Each line is tagged with the `[file:line]` it came from. `console.error` and `console.trace` append a full stack, while `console.warn` does not. When you `npx tgcloud run` a module, these lines are printed with a colored prefix per level, the time since the run started, and the origin — see `run`.

---

## Command-Line Interface

`tgcloud` is the bridge between your project folder and the cloud. It scaffolds projects, shows you what changed, deploys, runs modules, and applies database migrations. It needs Node.js 18 or newer. Two ways to get it:

```bash
# Recommended — create a project with the CLI installed into it:
npm create @tgcloud/bot example_bot

# Or install the CLI globally and init an empty folder:
npm install -g @tgcloud/cli
tgcloud init
```

The npm package is `@tgcloud/cli`; the command it installs is `tgcloud`. The CLI finds your project by walking up from the current directory to the nearest `.tgcloud/`, so every command works from any subfolder.

### Command Reference

| Command | Purpose |
|---------|---------|
| `init` | Scaffold a new project in the current folder |
| `add` | Scaffold a new module (a handler or a lib module) |
| `login` | Link the project to a bot (saves the token) |
| `status` | Show what changed locally vs. the cloud |
| `diff` | Show the line-by-line changes |
| `push` | Deploy changed modules to the cloud |
| `migrate` | Apply schema changes to the database |
| `run` | Execute a module on the platform without deploying |
| `fetch` | Refresh the local reference copy from the cloud |
| `pull` | Bring local files in line with the cloud |
| `reset` | Discard local changes; restore from the cloud state |
| `webhook` | Inspect and re-sync the platform-managed webhook |
| `completion` | Print a shell completion script (bash/zsh/fish) |

### Authentication

A project is tied to one bot by its token, which has the form `app<id>:<secret>`. The `app<id>` part is public and may be printed; the secret never appears in logs or errors.

The token is resolved in this order:
1. **`TGCLOUD_TOKEN`** environment variable — for CI; never written to disk.
2. **`.tgcloud/credentials`** — written by `npx tgcloud login`.
3. Neither → an error pointing you at `npx tgcloud login`.

The CLI **never prompts for a token mid-command** — a surprise prompt would hang scripts and CI. Logging in is always the explicit `login` step, and if a saved token becomes invalid (401/403), the CLI clears it and asks you to `login` again rather than re-prompting in place.

### `init`

```bash
npx tgcloud init
```

Scaffolds a new project in the current directory: `schema.js`, `lib/`, `handlers/`, a starter handler, `AGENTS.md`, `docs/`, and the `.tgcloud/` state folder. The set of files it creates is provided by the platform, so new starter files and directories can appear without upgrading the CLI. Offline, it falls back to a built-in copy, so `init` always works.

`init` refuses to **nest** inside another project — an ancestor directory that already has a `.tgcloud/` — so you can't accidentally shadow one; re-running `init` in a project's own root is fine and just fills in anything missing.

### `add`

```bash
npx tgcloud add <target>
```

Scaffolds a single new module, wired up and ready to edit — a handler or a `lib/` module.

```bash
npx tgcloud add handlers/callback_query   # a new update handler
npx tgcloud add lib/cart                  # a new shared module
```

> Note that `add` never overwrites an existing file.

The `<target>` is the module's path (a trailing `.js` is optional). For `handlers/`, the name must be a Telegram update type; the platform advertises the valid set, so an invalid name is rejected up front. `handlers/` is flat; `lib/` may be nested (`lib/payments/stripe`).

The module name is required. Giving **just the directory** is an error — but a helpful one: for `handlers/` it lists the update types you don't already have, so you can copy one.

```bash
$ npx tgcloud add handlers
Error: Specify a name, e.g. "npx tgcloud add handlers/callback_query".
Available handlers/ types: callback_query, inline_query, chat_member, …
```

> `<Tab>` completion offers the same set — see `completion`.

The generated file has a live `export default`, so the handler is active as soon as you deploy — there's nothing to uncomment. Deploy the new module with `push`.

### `login`

```bash
npx tgcloud login
```

Prompts for your CLI access token — from @BotFather → your bot → Serverless → CLI Access → Access token, a separate token from your bot's API token — validates it against the platform, and saves it to `.tgcloud/credentials`.

> `login` is the **only** command that asks for a token. It requires a real terminal and will not run without one, so it never hangs in CI.

### `status`

```bash
npx tgcloud status
```

Shows, per file, what has changed between your working directory and the deployed copy: modified, new, deleted, unchanged. Fully offline — it compares against the local reference copy in `.tgcloud/`. A full run also warns about stray `.js` files at the project root.

### `diff`

```bash
npx tgcloud diff
```

Like `status`, but shows the actual line-by-line differences for changed modules. Also offline.

### `push`

```bash
npx tgcloud push [files...]
```

Deploys your project to the cloud in one atomic batch.

With **no arguments**, it deploys the whole project, and the deployed state is made to mirror your folder exactly — modules you deleted locally are removed in the cloud.

With **file or directory arguments** (`npx tgcloud push handlers/message.js`, `npx tgcloud push handlers/`), it narrows **which changes are sent**, but still sends the full manifest, so a targeted push never deletes untouched modules.

Its one option is `--force` — to skip the concurrency check and overwrite whatever is in the cloud. Only use it when you're sure (see Staying in Sync).

After a deploy, if `schema.js` changed and the database is out of sync, `push` prints a summary of the pending changes and suggests `npx tgcloud migrate`. It never applies them itself.

### `migrate`

```bash
npx tgcloud migrate
```

Applies your schema changes to the database. It computes the difference between `schema.js` and the live database, then walks you through it one step at a time with a running `[N/M]` counter:

- A brief summary of all pending changes.
- **Safe changes**, applied together in a single step on your confirmation.
- **Warnings** (drops, slow operations), one at a time, each confirmed separately.
- **Manual changes**, shown with a reason and suggested action, not applied automatically.
- **Undocumented objects** (in the database but not your schema), shown for awareness.

It ends with a summary: applied, skipped, awaiting manual fix, not in schema.

> See Migrations for the model.

Options: `--dry-run` (print everything, apply nothing), `--safe` (auto-apply safe changes, skip warnings), `--yes` (auto-apply safe changes and every warning, skip manual — use with care), `--local` (diff against your local `schema.js` instead of the deployed one). Without a flag, `migrate` requires a terminal and errors in a non-interactive environment rather than guessing.

### `run`

```bash
npx tgcloud run <module> [args] [--ctx <json5>]
```

Executes a handler on the platform **without deploying**, using your current local files. This is the fast inner loop for testing logic.

- `<module>` — a bare name (searched under `handlers/`) or a path like `handlers/message`.
- `[args]` — the payload passed to the handler, written in JSON5 so you can skip quoting keys. It's the update-type object your handler receives (e.g. a Message for `handlers/message`).
- `--ctx <json5>` — the handler's context object (its second argument), also JSON5. Use it to supply what your handler reads off `ctx` — e.g. the raw update: `--ctx '{ update: { update_id: 1 } }'`.

```bash
npx tgcloud run handlers/message '{ chat: { id: 1 }, text: "hi" }'
```

The platform runs the module against the module space assembled from your **local** project (so locally-changed `lib/` code is used too) and returns the return value, anything logged with `console.*`, and the elapsed time. Read big arguments from a file with `npx tgcloud run handlers/message "$(cat message.json5)"`.

### `fetch`

```bash
npx tgcloud fetch
```

Refreshes the local reference copy of the deployed state without touching your working files. Useful to re-check a conflict before deciding how to resolve it.

### `pull`

```bash
npx tgcloud pull
```

Brings your local project in line with the cloud — updates both the reference copy and your working files to the deployed state.

### `reset`

```bash
npx tgcloud reset
```

Discards your local changes and restores the working directory from the last known cloud state. Use it to throw away an experiment.

### `webhook`

```bash
npx tgcloud webhook
npx tgcloud webhook sync [--drop-pending]
```

Telegram delivers updates to your bot through a webhook, which the platform manages for you — you never point it anywhere by hand. `npx tgcloud webhook` shows its current state: the URL, the `allowed_updates` list, how many updates are pending, the last delivery error (if any), and whether it is **in sync** with your deployed handlers.

"In sync" means the webhook points at the platform and its `allowed_updates` match the handlers you've deployed — so Telegram delivers exactly the update types you handle, and nothing else. Deploying a new handler (or removing one) can leave the webhook out of sync until it's refreshed; `npx tgcloud status` flags this too.

`npx tgcloud webhook sync` fixes it — it re-points the webhook at the platform and rebuilds `allowed_updates` from your deployed handlers. Add `--drop-pending` to discard updates Telegram had already queued before the sync (otherwise they're delivered once the webhook is healthy again).

### `completion`

> **Note:** tab-completion works only when a bare `tgcloud` is on your `PATH` — so install it globally (`npm install -g @tgcloud/cli`) or otherwise put the binary on your `PATH`. It can't hook into `npx`.

```bash
tgcloud completion <bash|zsh|fish>
```

Prints a shell completion script to stdout. Enable it once, then `<Tab>` completes commands, flags, module directories, the handler update-types you don't have yet, and your local runnable modules — the suggestions are computed live, so they reflect the current project and the platform's advertised update-types.

```bash
# bash — needs the bash-completion package:
echo 'eval "$(tgcloud completion bash)"' >> ~/.bashrc

# zsh — ensure `autoload -U compinit && compinit` runs in your ~/.zshrc:
echo 'eval "$(tgcloud completion zsh)"' >> ~/.zshrc

# fish:
tgcloud completion fish > ~/.config/fish/completions/tgcloud.fish
```

Restart your shell (or re-source the file) afterwards. Running `tgcloud completion` with no shell prints these instructions again.

### Staying in Sync

Every project has a monotonically increasing **revision** in the cloud, bumped on each deploy. The CLI remembers the revision it last synced with and sends it on each `push`. If the cloud has moved ahead — because another machine or teammate deployed — the push is **rejected** instead of silently overwriting their work, and the CLI offers three ways forward:

```bash
npx tgcloud fetch           # pull the latest into the reference copy, then re-check
npx tgcloud pull            # pull the latest into both reference and working files
npx tgcloud push --force    # overwrite the cloud state (dangerous)
```

This optimistic-concurrency check is why you can share a bot across a team without a lockstep deploy process. Commands exit non-zero on failure — a rejected deploy, a failed migration, an authentication error, a module that threw during `run` — so they compose cleanly in scripts and CI pipelines.

---

## Key Differences from Traditional Hosting

| Aspect | Traditional (VPS/Cloud Functions) | Telegram Serverless |
|--------|-----------------------------------|---------------------|
| Infrastructure | You manage servers/containers | None — runs on Telegram's infra |
| Database | Separate (PostgreSQL, Redis, etc.) | Built-in SQLite, per-bot |
| Bot API Client | You install/maintain | Built-in, always current |
| Outbound HTTP | Your responsibility | Built-in `fetch` (32 MB cap) |
| Deploy | CI/CD, Docker, config | `npx tgcloud push` (atomic) |
| Migrations | Manual / separate tooling | `npx tgcloud migrate` (reviewed) |
| Local Testing | Mocks / local server | `npx tgcloud run` (runs on platform) |
| Secrets | Env vars, vaults | CLI token only (Bot API key managed) |
| Cost | Server + database + bandwidth | Free tier generous; pay for scale |
| Scaling | You configure | Automatic |

---

## Current Limitations (As of Documentation)

1. **File upload/download not supported** — Cannot download file bytes via `getFile` or upload new files from handlers. Workaround: use `file_id` to forward/reuse existing Telegram files.
2. **32 MB HTTP response limit** — Total response body capped at 32 MB. Streaming (`res.body`) processes incrementally but doesn't raise the cap.
3. **Binary payloads unsupported** — `fetch` only handles textual responses.
4. **Node.js 18+ required** — For the CLI and local development.
5. **No custom npm dependencies** — Runtime provides SDK only. All logic must be in your modules.

---

## Feedback & Support

- **Documentation:** https://core.telegram.org/bots/serverless
- **Feedback:** Send to @BotSupport using the `#serverless` hashtag
- **CLI Package:** `@tgcloud/cli` on npm
- **Project Template:** `npm create @tgcloud/bot <name>`

---

*This document was generated from the official Telegram Serverless documentation at core.telegram.org/bots/serverless. For the latest updates, always refer to the official source.*