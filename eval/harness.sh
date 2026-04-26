#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_FILE="$REPO_DIR/prompt.md"
RESULTS_DIR="$SCRIPT_DIR/results"
PERSONAS_DIR="$SCRIPT_DIR/personas"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
SIMULATIONS_DIR="$SCRIPT_DIR/simulations"
RUBRIC_FILE="$SCRIPT_DIR/rubric.md"

MODEL="${MODEL:-opus}"
BUDGET="${BUDGET:-3.00}"
SCENARIO_BUDGET="${SCENARIO_BUDGET:-1.50}"
ASSESS_BUDGET="${ASSESS_BUDGET:-2.00}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [persona-name|all] [--onboard-only|--simulate]"
    echo ""
    echo "Runs EM-OS onboarding + operational scenarios with test personas."
    echo ""
    echo "Personas:"
    for f in "$PERSONAS_DIR"/*.md; do
        local name desc
        name=$(basename "$f" .md)
        desc=$(head -1 "$f" | sed 's/^# //')
        echo "  $name — $desc"
    done
    echo "  all — run all personas"
    echo ""
    echo "Options:"
    echo "  --onboard-only   Skip scenarios, only run onboarding + assessment"
    echo "  --simulate       Run a deep multi-session simulation (requires specific persona)"
    echo ""
    echo "Simulations:"
    if [[ -d "$SIMULATIONS_DIR" ]]; then
        for d in "$SIMULATIONS_DIR"/*/; do
            local name
            name=$(basename "$d")
            local count
            count=$(find "$d" -name '*.md' -not -name '00-onboard.md' | wc -l | tr -d ' ')
            echo "  $name — $count sessions"
        done
    fi
    echo ""
    echo "Environment variables:"
    echo "  MODEL            Claude model to use (default: opus)"
    echo "  BUDGET           Max spend per onboarding run in USD (default: 1.00)"
    echo "  SCENARIO_BUDGET  Max spend per scenario/session in USD (default: 0.75)"
    echo "  ASSESS_BUDGET    Max spend per assessment in USD (default: 0.75)"
    echo ""
    echo "Results are saved to eval/results/"
}

check_file() {
    local dir="$1" file="$2"
    if [[ -f "$dir/$file" ]]; then
        echo -e "  ${GREEN}pass${NC}  $file"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}  $file (missing)"
        return 1
    fi
}

check_dir() {
    local dir="$1" subdir="$2"
    if [[ -d "$dir/$subdir" ]]; then
        local count
        count=$(find "$dir/$subdir" -type f | wc -l | tr -d ' ')
        echo -e "  ${GREEN}pass${NC}  $subdir/ ($count files)"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}  $subdir/ (missing)"
        return 1
    fi
}

snapshot_files() {
    local dir="$1"
    find "$dir" -type f -not -path '*/.harness-*' 2>/dev/null | sort | while read -r f; do
        local rel="${f#$dir/}"
        local mod
        mod=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null)
        echo "$rel|$mod"
    done
}

diff_snapshots() {
    local before="$1" after="$2"
    local new_files="" modified_files=""

    while IFS='|' read -r file mod; do
        local old_mod
        old_mod=$(echo "$before" | grep -F "${file}|" | cut -d'|' -f2 || true)
        if [[ -z "$old_mod" ]]; then
            new_files+="  + $file"$'\n'
        elif [[ "$old_mod" != "$mod" ]]; then
            modified_files+="  ~ $file"$'\n'
        fi
    done <<< "$after"

    if [[ -n "$new_files" || -n "$modified_files" ]]; then
        [[ -n "$new_files" ]] && echo -e "${GREEN}New files:${NC}" && echo "$new_files"
        [[ -n "$modified_files" ]] && echo -e "${YELLOW}Modified files:${NC}" && echo "$modified_files"
    else
        echo -e "${DIM}No file changes${NC}"
    fi
}

run_scenario() {
    local work_dir="$1"
    local scenario_file="$2"
    local result_dir="$3"
    local scenario_num="$4"

    local scenario_name
    scenario_name=$(head -1 "$scenario_file" | sed 's/^# //')
    local scenario_slug
    scenario_slug=$(basename "$scenario_file" .md)
    local scenario_content
    scenario_content=$(tail -n +3 "$scenario_file")

    echo -e "${YELLOW}  Scenario ${scenario_num}: ${scenario_name}${NC}"

    # Snapshot before
    local before_snap
    before_snap=$(snapshot_files "$work_dir")

    local start_time
    start_time=$(date +%s)

    if cd "$work_dir" && echo "$scenario_content" | claude -p \
        --system-prompt "$(cat "$PROMPT_FILE")" \
        --dangerously-skip-permissions \
        --no-session-persistence \
        --no-chrome \
        --model "$MODEL" \
        --max-budget-usd "$SCENARIO_BUDGET" \
        > "$result_dir/scenario-${scenario_slug}-output.txt" 2>&1; then

        local end_time
        end_time=$(date +%s)
        local duration=$(( end_time - start_time ))
        echo -e "  ${GREEN}Complete (${duration}s)${NC}"
    else
        local end_time
        end_time=$(date +%s)
        local duration=$(( end_time - start_time ))
        echo -e "  ${RED}Error (${duration}s)${NC}"
    fi

    # Snapshot after and diff
    local after_snap
    after_snap=$(snapshot_files "$work_dir")
    diff_snapshots "$before_snap" "$after_snap"
    echo ""
}

collect_workspace() {
    local work_dir="$1"
    local out_file="$2"

    : > "$out_file"
    while IFS= read -r f; do
        local rel="${f#$work_dir/}"
        echo "--- FILE: $rel ---" >> "$out_file"
        cat "$f" >> "$out_file"
        echo "" >> "$out_file"
    done < <(find "$work_dir" -type f -name '*.md' \
        -not -path '*/.harness-*' \
        -not -name 'CLAUDE.md' \
        -not -name 'AGENTS.md' \
        | sort)
}

run_persona() {
    local persona_file="$1"
    local onboard_only="${2:-false}"

    local persona_name
    persona_name=$(basename "$persona_file" .md)
    local persona_desc
    persona_desc=$(head -1 "$persona_file" | sed 's/^# //')
    local persona_content
    persona_content=$(cat "$persona_file")

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local result_dir="$RESULTS_DIR/${persona_name}-${timestamp}"
    local work_dir="$result_dir/workspace"
    mkdir -p "$work_dir"

    local scenario_dir="$SCENARIOS_DIR/$persona_name"
    local has_scenarios=false
    if [[ "$onboard_only" == "false" && -d "$scenario_dir" ]]; then
        local scenario_count
        scenario_count=$(find "$scenario_dir" -name '*.md' | wc -l | tr -d ' ')
        if [[ "$scenario_count" -gt 0 ]]; then
            has_scenarios=true
        fi
    fi

    local total_steps=3
    if [[ "$has_scenarios" == "true" ]]; then
        total_steps=4
    fi

    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Persona: ${persona_name}${NC}"
    echo -e "${BLUE}  ${persona_desc}${NC}"
    echo -e "${BLUE}  Model: ${MODEL} | Budget: \$${BUDGET}/onboard, \$${SCENARIO_BUDGET}/scenario${NC}"
    if [[ "$has_scenarios" == "true" ]]; then
        echo -e "${BLUE}  Scenarios: $(find "$scenario_dir" -name '*.md' | wc -l | tr -d ' ')${NC}"
    fi
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    echo "Workspace: $work_dir"
    echo "Results:   $result_dir"
    echo ""

    # --- Step 1: Onboarding ---
    echo -e "${YELLOW}[1/${total_steps}] Running onboarding...${NC}"

    local onboarding_start
    onboarding_start=$(date +%s)

    if cd "$work_dir" && echo "$persona_content" | claude -p \
        --system-prompt "$(cat "$PROMPT_FILE")" \
        --dangerously-skip-permissions \
        --no-session-persistence \
        --no-chrome \
        --model "$MODEL" \
        --max-budget-usd "$BUDGET" \
        > "$result_dir/onboarding-output.txt" 2>&1; then

        local onboarding_end
        onboarding_end=$(date +%s)
        local duration=$(( onboarding_end - onboarding_start ))
        echo -e "${GREEN}Onboarding complete (${duration}s)${NC}"
    else
        local onboarding_end
        onboarding_end=$(date +%s)
        local duration=$(( onboarding_end - onboarding_start ))
        echo -e "${RED}Onboarding exited with error (${duration}s)${NC}"
        echo "Check $result_dir/onboarding-output.txt for details"
    fi
    echo ""

    # --- Step 2: Structural checks ---
    echo -e "${YELLOW}[2/${total_steps}] Structural checks:${NC}"
    local pass_count=0
    local fail_count=0

    for f in config.md index.md log.md todos.md; do
        if check_file "$work_dir" "$f"; then
            ((pass_count++))
        else
            ((fail_count++))
        fi
    done

    for d in people products; do
        if check_dir "$work_dir" "$d"; then
            ((pass_count++))
        else
            ((fail_count++))
        fi
    done

    # Optional dirs
    for d in one-on-ones reviews projects meetings escalations hiring journal raw; do
        if [[ -d "$work_dir/$d" ]]; then
            local count
            count=$(find "$work_dir/$d" -type f | wc -l | tr -d ' ')
            echo -e "  ${GREEN} +  ${NC}  $d/ ($count files)"
        fi
    done

    # Check for CLAUDE.md
    if [[ -f "$work_dir/CLAUDE.md" ]]; then
        echo -e "  ${GREEN}pass${NC}  CLAUDE.md"
        ((pass_count++))
    elif [[ -f "$work_dir/AGENTS.md" ]]; then
        echo -e "  ${GREEN}pass${NC}  AGENTS.md"
        ((pass_count++))
    else
        echo -e "  ${RED}FAIL${NC}  CLAUDE.md / AGENTS.md (missing)"
        ((fail_count++))
    fi

    echo ""
    echo -e "  Required: ${GREEN}${pass_count} passed${NC}, ${RED}${fail_count} failed${NC}"
    echo ""

    # File listing
    echo -e "${YELLOW}Files created:${NC}"
    find "$work_dir" -type f -not -path '*/.harness-*' | sort | while read -r f; do
        echo "  ${f#$work_dir/}"
    done
    echo ""

    find "$work_dir" -type f -not -path '*/.harness-*' | sort | sed "s|$work_dir/||" > "$result_dir/file-list.txt"

    # --- Step 3: Scenarios (if any) ---
    if [[ "$has_scenarios" == "true" ]]; then
        echo -e "${YELLOW}[3/${total_steps}] Running scenarios...${NC}"
        echo ""

        local scenario_num=1
        for sf in "$scenario_dir"/*.md; do
            run_scenario "$work_dir" "$sf" "$result_dir" "$scenario_num"
            ((scenario_num++))
        done

        # Save post-scenario file list
        find "$work_dir" -type f -not -path '*/.harness-*' | sort | sed "s|$work_dir/||" > "$result_dir/file-list-post-scenarios.txt"
    fi

    # --- Final step: Assessment ---
    local assess_step=$total_steps
    echo -e "${YELLOW}[${assess_step}/${total_steps}] Running quality assessment...${NC}"

    local workspace_file="$result_dir/.workspace-content.txt"
    collect_workspace "$work_dir" "$workspace_file"

    local dir_tree
    dir_tree=$(cd "$work_dir" && find . -not -name '.' -not -path '*/.harness-*' | sort | sed 's|^\./||')

    # Build assessment input file
    local assess_file="$result_dir/.assess-input.txt"
    cat > "$assess_file" <<ASSESS_EOF
Assess this EM-OS test run.

PERSONA NAME: ${persona_name}
PERSONA DESCRIPTION: ${persona_desc}

PERSONA INPUT:
${persona_content}

DIRECTORY STRUCTURE (final state after all scenarios):
${dir_tree}

ALL FILES (final state, excluding CLAUDE.md/AGENTS.md):
ASSESS_EOF

    cat "$workspace_file" >> "$assess_file"

    # Append scenario outputs
    if [[ "$has_scenarios" == "true" ]]; then
        echo "" >> "$assess_file"
        echo "SCENARIO OUTPUTS:" >> "$assess_file"
        for sf in "$scenario_dir"/*.md; do
            local slug sname sout
            slug=$(basename "$sf" .md)
            sname=$(head -1 "$sf" | sed 's/^# //')
            sout="$result_dir/scenario-${slug}-output.txt"
            if [[ -f "$sout" ]]; then
                echo "" >> "$assess_file"
                echo "--- SCENARIO: ${sname} ---" >> "$assess_file"
                echo "USER MESSAGE: $(tail -n +3 "$sf")" >> "$assess_file"
                echo "" >> "$assess_file"
                echo "LLM RESPONSE:" >> "$assess_file"
                cat "$sout" >> "$assess_file"
                echo "" >> "$assess_file"
            fi
        done
    fi

    local assess_start
    assess_start=$(date +%s)

    if cat "$assess_file" | claude -p \
        --system-prompt "$(cat "$RUBRIC_FILE")" \
        --no-session-persistence \
        --no-chrome \
        --model "$MODEL" \
        --max-budget-usd "$ASSESS_BUDGET" \
        > "$result_dir/assessment.txt" 2>&1; then

        local assess_end
        assess_end=$(date +%s)
        local duration=$(( assess_end - assess_start ))
        echo -e "${GREEN}Assessment complete (${duration}s)${NC}"
    else
        local assess_end
        assess_end=$(date +%s)
        local duration=$(( assess_end - assess_start ))
        echo -e "${RED}Assessment exited with error (${duration}s)${NC}"
    fi
    echo ""

    echo -e "${YELLOW}Assessment:${NC}"
    echo "────────────────────────────────────────"
    cat "$result_dir/assessment.txt"
    echo "────────────────────────────────────────"
    echo ""
    echo -e "Results saved to: ${BLUE}${result_dir}${NC}"
    echo ""
}

run_simulation() {
    local persona_name="$1"
    local sim_dir="$SIMULATIONS_DIR/$persona_name"

    if [[ ! -d "$sim_dir" ]]; then
        echo "No simulation found for persona: $persona_name"
        echo "Available: $(ls "$SIMULATIONS_DIR"/ 2>/dev/null | tr '\n' ' ')"
        exit 1
    fi

    local onboard_file="$sim_dir/00-onboard.md"
    if [[ ! -f "$onboard_file" ]]; then
        echo "Error: $sim_dir/00-onboard.md not found"
        exit 1
    fi

    local sim_rubric="$SIMULATIONS_DIR/simulation-rubric.md"
    if [[ ! -f "$sim_rubric" ]]; then
        echo "Error: simulation-rubric.md not found"
        exit 1
    fi

    local session_files=()
    for f in "$sim_dir"/*.md; do
        [[ "$(basename "$f")" == "00-onboard.md" ]] && continue
        session_files+=("$f")
    done

    local total_sessions=${#session_files[@]}
    local total_steps=$(( total_sessions + 3 ))  # onboard + struct check + sessions + assess

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local result_dir="$RESULTS_DIR/sim-${persona_name}-${timestamp}"
    local work_dir="$result_dir/workspace"
    mkdir -p "$work_dir"

    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  SIMULATION: ${persona_name}${NC}"
    echo -e "${BLUE}  ${total_sessions} sessions after onboarding${NC}"
    echo -e "${BLUE}  Model: ${MODEL}${NC}"
    echo -e "${BLUE}  Budget: \$${BUDGET}/onboard, \$${SCENARIO_BUDGET}/session, \$${ASSESS_BUDGET}/assess${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    echo "Workspace: $work_dir"
    echo "Results:   $result_dir"
    echo ""

    # --- Step 1: Onboarding ---
    local step=1
    echo -e "${YELLOW}[${step}/${total_steps}] Session 0: Onboarding...${NC}"

    local start_time
    start_time=$(date +%s)

    if cd "$work_dir" && cat "$onboard_file" | claude -p \
        --system-prompt "$(cat "$PROMPT_FILE")" \
        --dangerously-skip-permissions \
        --no-session-persistence \
        --no-chrome \
        --model "$MODEL" \
        --max-budget-usd "$BUDGET" \
        > "$result_dir/session-00-onboard-output.txt" 2>&1; then

        local end_time
        end_time=$(date +%s)
        echo -e "  ${GREEN}Complete ($((end_time - start_time))s)${NC}"
    else
        local end_time
        end_time=$(date +%s)
        echo -e "  ${RED}Error ($((end_time - start_time))s)${NC}"
    fi
    echo ""

    # --- Step 2: Structural checks ---
    ((step++))
    echo -e "${YELLOW}[${step}/${total_steps}] Structural checks:${NC}"
    local pass_count=0
    local fail_count=0

    for f in config.md index.md log.md todos.md; do
        if check_file "$work_dir" "$f"; then ((pass_count++)); else ((fail_count++)); fi
    done
    for d in people products; do
        if check_dir "$work_dir" "$d"; then ((pass_count++)); else ((fail_count++)); fi
    done
    if [[ -f "$work_dir/CLAUDE.md" ]] || [[ -f "$work_dir/AGENTS.md" ]]; then
        echo -e "  ${GREEN}pass${NC}  CLAUDE.md / AGENTS.md"
        ((pass_count++))
    else
        echo -e "  ${RED}FAIL${NC}  CLAUDE.md / AGENTS.md (missing)"
        ((fail_count++))
    fi

    echo -e "  Required: ${GREEN}${pass_count} passed${NC}, ${RED}${fail_count} failed${NC}"
    echo ""

    if [[ "$fail_count" -gt 2 ]]; then
        echo -e "${RED}Onboarding failed too many checks. Aborting simulation.${NC}"
        return 1
    fi

    # --- Step 3: Run sessions ---
    ((step++))
    echo -e "${YELLOW}[${step}/${total_steps}] Running ${total_sessions} sessions...${NC}"
    echo ""

    local session_num=1
    for sf in "${session_files[@]}"; do
        local sname
        sname=$(head -1 "$sf" | sed 's/^# //')
        local slug
        slug=$(basename "$sf" .md)
        local scontent
        scontent=$(tail -n +3 "$sf")

        echo -e "  ${YELLOW}Session ${session_num}/${total_sessions}: ${sname}${NC}"

        # Check for fixtures to inject before this session
        local fixture_dir="$sim_dir/fixtures"
        local session_prefix
        session_prefix=$(basename "$sf" .md | grep -o '^[0-9]*')
        if [[ -d "$fixture_dir" && -n "$session_prefix" ]]; then
            # Fixtures named with session prefix (e.g., fixtures/12/) or generic (fixtures/raw/)
            # Copy generic fixtures if this session's slug matches a known pattern
            local slug_no_num
            slug_no_num=$(basename "$sf" .md | sed 's/^[0-9]*-//')
            if [[ "$slug_no_num" == *"sync"* && -d "$fixture_dir/raw" ]]; then
                echo -e "  ${DIM}Injecting fixtures into raw/...${NC}"
                mkdir -p "$work_dir/raw"
                cp "$fixture_dir/raw"/* "$work_dir/raw/" 2>/dev/null || true
            fi
        fi

        local before_snap
        before_snap=$(snapshot_files "$work_dir")

        local sstart
        sstart=$(date +%s)

        if cd "$work_dir" && echo "$scontent" | claude -p \
            --system-prompt "$(cat "$PROMPT_FILE")" \
            --dangerously-skip-permissions \
            --no-session-persistence \
            --no-chrome \
            --model "$MODEL" \
            --max-budget-usd "$SCENARIO_BUDGET" \
            > "$result_dir/session-${slug}-output.txt" 2>&1; then

            local send
            send=$(date +%s)
            echo -e "  ${GREEN}Complete ($((send - sstart))s)${NC}"
        else
            local send
            send=$(date +%s)
            echo -e "  ${RED}Error ($((send - sstart))s)${NC}"
        fi

        local after_snap
        after_snap=$(snapshot_files "$work_dir")
        diff_snapshots "$before_snap" "$after_snap"
        echo ""

        ((session_num++))
    done

    # Save final file list
    find "$work_dir" -type f -not -path '*/.harness-*' | sort | sed "s|$work_dir/||" > "$result_dir/file-list-final.txt"

    echo -e "${YELLOW}Final workspace ($(cat "$result_dir/file-list-final.txt" | wc -l | tr -d ' ') files):${NC}"
    cat "$result_dir/file-list-final.txt" | while read -r f; do echo "  $f"; done
    echo ""

    # --- Step 4: Assessment ---
    ((step++))
    echo -e "${YELLOW}[${step}/${total_steps}] Running deep assessment...${NC}"

    local workspace_file="$result_dir/.workspace-content.txt"
    collect_workspace "$work_dir" "$workspace_file"

    local dir_tree
    dir_tree=$(cd "$work_dir" && find . -not -name '.' -not -path '*/.harness-*' | sort | sed 's|^\./||')

    local assess_file="$result_dir/.assess-input.txt"
    cat > "$assess_file" <<ASSESS_EOF
Assess this EM-OS deep simulation.

PERSONA: ${persona_name}

DIRECTORY STRUCTURE (final state after all sessions):
${dir_tree}

ALL FILES (final state, excluding CLAUDE.md/AGENTS.md):
ASSESS_EOF

    cat "$workspace_file" >> "$assess_file"

    echo "" >> "$assess_file"
    echo "SESSION OUTPUTS (in chronological order):" >> "$assess_file"

    # Add onboarding output
    echo "" >> "$assess_file"
    echo "--- SESSION 0: Onboarding ---" >> "$assess_file"
    echo "USER MESSAGE: (see persona input above)" >> "$assess_file"
    echo "LLM RESPONSE:" >> "$assess_file"
    cat "$result_dir/session-00-onboard-output.txt" >> "$assess_file"
    echo "" >> "$assess_file"

    # Add all session outputs
    for sf in "${session_files[@]}"; do
        local slug sname sout
        slug=$(basename "$sf" .md)
        sname=$(head -1 "$sf" | sed 's/^# //')
        sout="$result_dir/session-${slug}-output.txt"
        if [[ -f "$sout" ]]; then
            echo "" >> "$assess_file"
            echo "--- SESSION: ${sname} ---" >> "$assess_file"
            echo "USER MESSAGE:" >> "$assess_file"
            tail -n +3 "$sf" >> "$assess_file"
            echo "" >> "$assess_file"
            echo "LLM RESPONSE:" >> "$assess_file"
            cat "$sout" >> "$assess_file"
            echo "" >> "$assess_file"
        fi
    done

    local assess_start
    assess_start=$(date +%s)

    if cat "$assess_file" | claude -p \
        --system-prompt "$(cat "$sim_rubric")" \
        --no-session-persistence \
        --no-chrome \
        --model "$MODEL" \
        --max-budget-usd "$ASSESS_BUDGET" \
        > "$result_dir/assessment.txt" 2>&1; then

        local assess_end
        assess_end=$(date +%s)
        echo -e "${GREEN}Assessment complete ($((assess_end - assess_start))s)${NC}"
    else
        local assess_end
        assess_end=$(date +%s)
        echo -e "${RED}Assessment error ($((assess_end - assess_start))s)${NC}"
    fi
    echo ""

    echo -e "${YELLOW}Assessment:${NC}"
    echo "────────────────────────────────────────"
    cat "$result_dir/assessment.txt"
    echo "────────────────────────────────────────"
    echo ""
    echo -e "Results saved to: ${BLUE}${result_dir}${NC}"
    echo ""
}

# --- Main ---

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt.md not found at $PROMPT_FILE"
    exit 1
fi

if [[ ! -f "$RUBRIC_FILE" ]]; then
    echo "Error: rubric.md not found at $RUBRIC_FILE"
    exit 1
fi

mkdir -p "$RESULTS_DIR"

ONBOARD_ONLY=false
SIMULATE=false
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --onboard-only) ONBOARD_ONLY=true ;;
        --simulate) SIMULATE=true ;;
        --help|-h) usage; exit 0 ;;
        *) TARGET="$arg" ;;
    esac
done
TARGET="${TARGET:-all}"

echo ""
echo -e "${BLUE}EM-OS Test Harness${NC}"
echo ""

if [[ "$SIMULATE" == "true" ]]; then
    if [[ -z "$TARGET" || "$TARGET" == "all" ]]; then
        echo "Simulation requires a specific persona. Usage: $0 --simulate <persona>"
        exit 1
    fi
    run_simulation "$TARGET"
elif [[ "$TARGET" == "all" ]]; then
    for f in "$PERSONAS_DIR"/*.md; do
        run_persona "$f" "$ONBOARD_ONLY"
    done
elif [[ -f "$PERSONAS_DIR/${TARGET}.md" ]]; then
    run_persona "$PERSONAS_DIR/${TARGET}.md" "$ONBOARD_ONLY"
else
    echo "Unknown persona: $TARGET"
    echo "Available: $(ls "$PERSONAS_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ' ')"
    exit 1
fi

echo -e "${GREEN}Done.${NC}"
