# Pushing this to GitHub

Three commands, after creating an empty **private** repo on GitHub.

```bash
cd agentic-skills
git init
git add .
git commit -m "Initial commit: five agentic engineering skills"
git branch -M main
git remote add origin git@github.com:<you>/agentic-skills.git
git push -u origin main
```

Use `https://github.com/<you>/agentic-skills.git` if you aren't on SSH keys.

## Start private

Nothing here is sensitive today — it's generic Java and process tooling built
against a public demo app. But this is the repo that accumulates specifics over
time: build quirks, conventions, eventually architecture briefs of internal
systems. Private by default avoids the moment where something proprietary has
drifted into a public repo. Opening it up later is easy; un-publishing isn't.

## Before you add work-specific content

Once real architecture briefs, ticket keys, or internal service names start
landing in here, it stops being a personal toolbox and becomes something with
your employer's information in it. Worth deciding at that point whether it
belongs in a company repo instead.

## Prior inventions

This work predates employment. If onboarding paperwork includes a prior
inventions schedule, listing this repo keeps ownership unambiguous. Not legal
advice — just a two-minute entry that avoids a conversation later.
