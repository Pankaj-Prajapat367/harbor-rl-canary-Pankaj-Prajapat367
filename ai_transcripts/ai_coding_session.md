# AI Coding Session Transcript: Harbor RL Task Calibration & Engineering

**Date:** 2026-11-15  
**Tool:** Gemini CLI / AI Assistant  
**User:** Pankaj Prajapat (@Pankaj-Prajapat367)  
**Task:** Engineering Internship Take-Home - Harbor RL Canary Sprint

---

### [Session 1: Task Engineering & Bug Calibration]

**User:**  
I need to build a Harbor RL task named `reconcile-bug` inside `tasks/reconcile-bug/`. It should feature a Python CLI script `/app/reconcile.py` (under 90 lines of code) that parses a payment transaction CSV and outputs a JSON summary with `total_valid_amount`, `valid_count`, and `failed_count`.  
We must calibrate 3 bugs of increasing difficulty:
1. Bug 1 (Easy / Surface): CLI argument parsing crash.
2. Bug 2 (Medium / Logic): Calculation or status-filtering bug (e.g. including PENDING transactions).
3. Bug 3 (Hard / Subtle Edge Case): Deduplication rule on repeat `tx_id` records comparing timestamps across mixed ISO 8601 timezones where lexical comparisons fail.

*Crucial constraint:* Do NOT put spoilers about code locations or bug lines into `instruction.md`. Keep instructions strictly focused on the input/output specification and business rules.

**AI:**  
Understood. Let's design `environment/reconcile.py` under 70 lines:
- **Bug 1**: `argparse` defines `--input` with `dest="input_path"`, but `main()` references `args.input_file`, causing an immediate `AttributeError` on invocation.
- **Bug 2**: `VALID_STATUSES` includes `"PENDING"`, and sum lacks 2-decimal rounding.
- **Bug 3**: In deduplicating repeat `tx_id` records, it performs a naive string comparison `timestamp > records[tx_id]['timestamp']`. When timestamps use different timezone offsets (e.g., `+04:00` vs `Z`), lexical comparison fails.

We will write `instruction.md` explaining the CSV format, the CLI arguments `--input` and `--output`, the business rule that only `SUCCESS` and `COMPLETED` are valid, and the deduplication requirement that the latest record in normalized UTC time determines the final state.

---

### [Session 2: Dense Reward & Anti-Cheat Verifier]

**User:**  
Now let's build `tests/test.sh`. It must not be a naive binary 0/1 verifier. It should provide dense reward feedback (0.00 to 1.00) so that an RL algorithm like GRPO receives an advantage learning signal even when Bug 3 is not solved.  
Also, write `solution/hack.sh` that tries to cheat with a hardcoded mock stub, and harden `tests/test.sh` so `hack.sh` scores 0.00 while `solve.sh` scores 1.00.

**AI:**  
We will assign independent weights:
- Check 1 (Bug 1 - CLI argument parsing & clean exit): **0.20**
- Check 2 (Bug 2 - Status filtering excluding PENDING & 2-decimal rounding): **0.30**
- Check 3 (Bug 3 - Cross-timezone deduplication edge case): **0.50**
- Total: **1.00**

To prevent reward hacking:
1. `tests/test.sh` generates **randomized dynamic transaction IDs and amounts** on each test run. A static stub in `hack.sh` returning fixed numbers will fail equality checks against random ground truth.
2. We enforce an **input sensitivity invariant**: evaluating an empty CSV vs a populated CSV must produce different JSON outputs. `hack.sh` returns the identical mock JSON for both and gets penalized immediately with `0.00`.

Verification results:
- `nop` (buggy initial code): `0.00`
- `hack.sh` (adversarial mock): `0.00`
- Partial fix (Bug 1+2 resolved, Bug 3 broken): `0.50`
- `solve.sh` (complete fix): `1.00`

---

### [Session 3: Trajectory Forensics & RL Advantage Analysis]

**User:**  
Let's analyze the Baseline vs Ablation runs:
- In Baseline Run 1 ($k=3$), Trial 1 got 0.50 (dense) / 0 (binary), Trial 2 got 0.20 (dense) / 0 (binary), Trial 3 got 0.00 (dense) / 0 (binary).
- Notice that under binary evaluation, all 3 trials score 0.00, meaning Mean = 0.00 and Advantage = 0.00 for all trials—the Zero-Signal Trap!
- Under dense evaluation, Mean = 0.23, giving Trial 1 an Advantage of +0.27.

**AI:**  
Exactly. Under dense grading, Trial 1's actions (fixing `argparse` and excluding `PENDING`) receive a positive policy gradient ($+0.27$), which reinforces those correct actions. Under binary grading, those actions received zero gradient signal because the trial ultimately failed Bug 3.

In the Ablation run, we introduced `sample_transactions.csv` containing mixed offset timestamps (`+04:00` vs `Z`). The agent inspected this file, tested with `datetime.fromisoformat()`, and achieved 1.00 in Trial 1 and Trial 2.
