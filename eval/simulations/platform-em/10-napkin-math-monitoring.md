# Day 16 — Build vs buy: monitoring modernization

After the Pipeline Monitor incident, I'm more serious about the OTel migration. But I need to make the case to Jordan with numbers, not just vibes. Help me do some napkin math.

Current state: custom Python exporters that Marcus built and maintains. They work but they've had 2 OOM incidents in 6 months, they only cover metrics (no tracing), and Marcus is essentially the only person who can maintain them.

Option A: Fix the current exporters — add auto-restart, fix the memory leak, document them so others can maintain them. Probably 2-3 weeks of David's time.

Option B: Migrate to OpenTelemetry — replace the custom exporters with OTel SDK, get tracing for free, use the standard ecosystem. Probably bigger effort but reduces long-term maintenance.

What does each option actually cost? And what's the risk of doing nothing?
