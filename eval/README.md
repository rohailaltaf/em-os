# Eval

Automated evaluation for the EM-OS prompt. Runs test personas through onboarding, operational scenarios, and deep simulations.

## How it works

1. Creates a temporary workspace directory
2. Runs `claude -p` with `prompt.md` as system prompt and a test persona as user input
3. Checks that required files and directories were created
4. Runs a second `claude -p` pass to assess content quality against `rubric.md`
5. Saves all results to `eval/results/` (gitignored)

## Usage

```bash
# Run all personas
./eval/harness.sh all

# Run a specific persona
./eval/harness.sh platform-em

# Use a different model
MODEL=opus ./eval/harness.sh all

# Adjust budgets
BUDGET=2.00 ASSESS_BUDGET=1.00 ./eval/harness.sh all
```

## Personas

Test personas live in `personas/`. Each is a markdown file where the first line is `# Description` and the rest is the user's onboarding message.

| Persona | Tests |
|---------|-------|
| `platform-em` | Full team (5 reports), formal processes, multiple products + dependencies |
| `startup-em` | Small team (3 reports), minimal process, single product, no formal reviews |
| `new-director` | Manages 3 EMs, 3 products across teams, skip-level 1:1s, coaching-heavy |

To add a new persona, create a markdown file in `personas/` following the same format.

## Assessment rubric

`rubric.md` defines what the assessor checks:
- Structural completeness (required files, directories)
- Accuracy (names, roles, relationships, no hallucinations)
- Adaptiveness (only scaffold what was requested)
- Cross-references and linking
- Content quality

## Results

Results are saved to `results/<persona>-<timestamp>/` and contain:
- `workspace/` — the full directory the LLM created
- `onboarding-output.txt` — the LLM's text output during onboarding
- `file-list.txt` — list of all files created
- `assessment.txt` — the quality assessment

Results are gitignored.
