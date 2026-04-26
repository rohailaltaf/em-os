You are evaluating the output of an EM-OS test run. An LLM was given the EM-OS prompt as a system prompt, then:

1. A test persona provided their information and the LLM ran onboarding (setting up the directory)
2. Optionally, follow-up scenarios were run — each simulating a real operational use case (1:1 prep, review writing, research, hiring, escalations, etc.) against the onboarded workspace

Assess the output against these criteria. For each, score as PASS / PARTIAL / FAIL with a brief explanation.

## 1. Onboarding — structural completeness

Required files:
- config.md — EM profile, preferences, sync sources
- index.md — catalog of all files with summaries and links
- log.md — at least one onboarding entry
- todos.md — canonical action tracker, scaffolded with category sections matching the teams/projects the EM described (empty categories are fine on day 1)
- AGENTS.md or CLAUDE.md — a short orientation stub (~30 lines) identifying the workspace, giving a session-start read order, listing only the directories/files that were actually scaffolded, and linking to the full system prompt URL. **Must not be a copy of the full prompt.**

Required directories:
- people/ — one file per person mentioned (reports, manager, key stakeholders)
- products/ — files for owned products and key dependencies

Optional directories (should exist only if the persona mentioned them):
- projects/, one-on-ones/, meetings/, hiring/, escalations/, journal/, raw/

## 2. Onboarding — accuracy

- All names, roles, levels, and relationships correctly captured
- No hallucinated information
- Relationships correctly categorized (direct-report, manager, stakeholder, cross-functional)
- Products correctly marked as owned vs. dependency
- Tech stacks captured correctly

## 3. Onboarding — adaptiveness

- Directory structure matches what the persona described
- Things the persona DIDN'T mention are NOT scaffolded
- The system reflects the persona's actual workflow

## 4. Cross-references and linking

- Files use relative markdown links when referencing other files (people → projects, projects → products, etc.)
- Links are bidirectional where appropriate
- Index entries link correctly

## 5. Content quality

- Files use clean, consistent markdown
- Content is substantive — real information, not empty templates
- Useful for an actual EM to read

## 6. Scenarios (if present)

For each scenario that was run, assess:

**Did it use the existing system?** The LLM should have read relevant files (config, index, person files, project files) to inform its response. It should not have answered from scratch as if the wiki didn't exist.

**Did it produce the right kind of output?**
- 1:1 prep → should surface history, open items, and suggest topics
- Review drafts → should pull evidence from 1:1 history and person files, create a file in reviews/
- Research (bias check) → should identify specific biases with explanations, suggest reframing
- Research (technical) → should explain concepts clearly, give the EM enough to participate in discussions
- Research (management lit) → should reference specific books, frameworks, or authors — not generic advice
- Hiring → should create a role file in hiring/, potentially draft a JD
- Escalation → should produce a structured document in escalations/
- Career growth → should pull from person's file, suggest development paths
- Career growth (self) → should help the EM reflect on their own development

**Did it update the system?** Where appropriate, the LLM should have:
- Created new files (review drafts, escalation docs, hiring files, 1:1 notes)
- Updated existing files (person files with new context, index with new entries)
- Appended to the log

**Was the output grounded?** Responses should reference specific information from the persona's system — actual names, actual projects, actual context — not generic advice.

## 7. Overall

Summarize:
- What worked well across onboarding and scenarios
- What's missing or wrong
- Issues that suggest the PROMPT needs improvement (vs. the LLM making a one-off mistake)
- Specific recommendations for prompt changes

Be concise and direct.
