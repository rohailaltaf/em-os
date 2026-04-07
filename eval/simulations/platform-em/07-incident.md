# Day 10 — Incident: Pipeline Monitor down

Pipeline Monitor went down this morning for about 2 hours. We had no visibility into pipeline health during that time — no alerts, no dashboards. Luckily no pipelines actually failed, but we wouldn't have known if they did.

What happened: one of the custom Python exporters hit an OOM error and crashed. The exporter process doesn't have auto-restart configured (!!). David caught it because he happened to be looking at the Grafana dashboard and saw gaps in the data. He manually restarted the process.

Marcus was on Slack within minutes helping debug, which was great. But he also seemed stressed — I think he felt personally responsible since he built these exporters.

Priya actually stepped up in a way I didn't expect. She started documenting the timeline in a Slack thread while David and Marcus were debugging. She also found that this same exporter had a similar OOM 3 months ago (before she joined) — she dug through Slack history to find it. Nobody had filed a proper fix for the memory leak then either.

I need to:
1. Write up a proper postmortem
2. Figure out why we don't have auto-restart on these exporters
3. Think about whether this changes the OTel conversation
