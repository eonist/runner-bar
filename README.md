# RunnerBar

> Self-hosted GitHub Actions runners, at a glance in your macOS menu bar.

![RunnerBar screenshot](https://raw.githubusercontent.com/eonist/runner-bar/main/runner-bar.gif)

---

## The problem

1. Status - Knowing if your selfhosted github runner is online, offline, busy.
2. Mananging - Removing them. Adding them? Pausing them? Which repo or org runners do you have installed.
3. Activity - Easily look through active or past runs, figure out what worked and what failed
---

## The solution:

1. Easily see which runners are offline, online, or buzy
2. Easily add / remove or pause your runners
3. Easily look through sessions, individual jobs and action logs. 

## Install

```bash
curl -fsSL https://eonist.github.io/runner-bar/install.sh | bash
```

---

## Requirements

- macOS 13+
- [`gh` CLI](https://cli.github.com) installed and authenticated (`gh auth login`)

RunnerBar uses your existing `gh` CLI session for auth — no PAT, no OAuth setup.

---

## How it works

1. On first launch, enter one or more repo slugs (`owner/repo`) or org names to monitor
2. RunnerBar polls the GitHub API every 30 seconds via `gh api`
3. The menu bar icon updates based on aggregate runner state
4. Click the icon to see the full runner list and refresh manually

---

## Docs

- [DEVELOPMENT.md](DEVELOPMENT.md) — how to build and run locally
- [DEPLOYMENT.md](DEPLOYMENT.md) — how releases are built and deployed
- [AGENTS.md](AGENTS.md) — context for AI coding agents

---

## Quick deploy

1. Download and build. close current apps
2. Build and deploy
3. Test user-facing download

```bash
git pull && bash build.sh && pkill RunnerBar; sleep 1 && open dist/RunnerBar.app 2>&1
bash build.sh && bash deploy.sh
curl -fsSL https://eonist.github.io/runner-bar/install.sh | bash
```

**To test branches:**    
`git fetch && git checkout feature/actions-section && git pull`
and   
`bash build.sh && pkill RunnerBar; sleep 1 && open dist/RunnerBar.app`  

---

## Contributing

This project is built with SwiftPM and edited with AI assistance — no Xcode required or apple-dev account needed.

```bash
git clone https://github.com/eonist/runner-bar
cd runner-bar
swift run
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for the full dev setup.
