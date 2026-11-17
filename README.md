# Harbor RL Submission — Pankaj Prajapat (@Pankaj-Prajapat367)

## 1. Loom Walkthrough Video
- **Video URL:** [Watch 5-Minute Walkthrough](https://www.loom.com/share/9dd4fc397f444e239df8b1cce1d69de2 )
  *(Make sure link sharing is set to "Anyone with the link can view")*

---

### Verbatim 5-Minute Video Recording Guide & Script

#### Part 1: Live Reward Mutation & Anti-Hack Proof (0:00 – 1:45)
- **Live Partial-Credit Canary (0:00 – 1:00):**
  1. *[Screen on `solution/solve.sh`]*: "Hello, my name is Pankaj Prajapat. Here is our reference solution in `solution/solve.sh`. Notice line 46 where we normalize ISO timestamps to UTC using `astimezone(timezone.utc)`. I am going to intentionally break Bug 3 by replacing this with a naive string comparison `ts_str > records[tx_id]['timestamp']` while keeping Bug 1 (`argparse`) and Bug 2 (`PENDING` filtering) fully fixed."
  2. *[Predict score out loud]*: "Based on our weights in `tests/test.sh` (Check 1 = 0.20, Check 2 = 0.30, Check 3 = 0.50), leaving Bug 3 broken means Checks 1 and 2 will pass (+0.50), but Check 3 will fail. Therefore, the oracle must score exactly **0.500**."
  3. *[Run in terminal]*: Run `harbor run -p ./tasks/reconcile-bug -a oracle` (or test runner) and highlight the output: `Final Verifier Reward: 0.50`.
  4. *[Revert & Re-run]*: Undo the edit, run oracle again, and show it scoring **1.000**.
- **Live Anti-Cheat Proof (`hack.sh`) (1:00 – 1:45):**
  1. *[Screen on `solution/hack.sh`]*: "Now let's examine `solution/hack.sh`. An AI agent attempting reward hacking might replace `/app/reconcile.py` with a dummy script returning a hardcoded JSON summary like `{'total_valid_amount': 100.0, 'valid_count': 1, 'failed_count': 0}` without doing any real CSV parsing."
  2. *[Run 4-line swap command]*:
     ```bash
     cp tasks/reconcile-bug/solution/solve.sh /tmp/solve.sh.bak
     cp tasks/reconcile-bug/solution/hack.sh tasks/reconcile-bug/solution/solve.sh
     harbor run -p ./tasks/reconcile-bug -a oracle
     mv /tmp/solve.sh.bak tasks/reconcile-bug/solution/solve.sh
     ```
  3. *[Show result]*: Highlight the terminal output: `Final Verifier Reward: 0.00`. Explain that `test.sh` uses randomized dynamic amounts/UUIDs and an input sensitivity invariant, catching the cheat and scoring it **0.000**.

#### Part 2: Side-by-Side Trajectory Forensics (1:45 – 3:15)
- *[Screen on `jobs_summary/run1_baseline/reconcile-bug__trial-1/trajectory.json`]*: "In Run 1 Baseline Trial 1, the agent identified the CLI crash on step 2 (`AttributeError: Namespace object has no attribute input_file`), patched it with `sed`, and fixed the status filter on step 4. However, on step 5 it ran a basic sanity test that only checked syntax, completely missing the cross-timezone deduplication rule in Bug 3 before exiting."
- *[Show Ablation change]*: "For Run 2 (Ablation), we made one controlled change: we provided `/app/sample_transactions.csv` containing mixed offset timestamps (`+04:00` vs `Z`)."
- *[Screen on `jobs_summary/run2_ablation/reconcile-bug__trial-1/trajectory.json`]*: "In Run 2 Trial 1, step 1 shows the agent inspecting `sample_transactions.csv`. It immediately recognized the timezone offset format, tested datetime conversions in step 3, and correctly implemented UTC normalization, scoring a full **1.000**."

#### Part 3: Defend Your RL Math & Reward Design (3:15 – 5:00)
- *[Screen on README.md Advantage Table and `tests/test.sh`]*:
  1. **Walkthrough of Math**: "In Run 1 Trial 1, the agent scored 0 under binary grading and 0.50 under dense grading. Because all 3 baseline trials failed Bug 3, the binary mean was 0.00, resulting in an advantage of $0.00 - 0.00 = 0.00$—the Zero-Signal Trap. Under dense grading, the mean is 0.23, yielding a positive advantage of $+0.27$ ($0.50 - 0.23$). This $+0.27$ advantage provides a direct gradient signal reinforcing the agent's edits that fixed the CLI parser and status filtering, rather than penalizing the entire trajectory as a total failure."
  2. **Local Optima & Weight Calibration**: "With Check 1 at 0.20, Check 2 at 0.30, and Check 3 at 0.50, an agent could potentially settle for 0.50 by refusing to touch Bug 3. If training runs revealed this plateau, I would adjust the weights to be super-linear or staged—such as allocating 0.70 to Check 3 or requiring Check 3 as a multiplicative gating factor ($R = (0.2 + 0.3) \times \text{Check}_3$ or minimum threshold) so the agent cannot maximize expected returns without solving the edge case."
  3. **Residual Reward-Hacking Risk**: "A smarter agent could inspect `/proc` or python call stacks to inspect the verifier's PID or memory, or read the temporary CSV path passed in `sys.argv[1]` to parse the headers, or try to read `/logs/verifier/reward.txt` directly if file permissions allow it. Hardening against this requires container capability dropping (`--cap-drop=ALL`) and read-only mounts for test scripts."

---

## 2. Task & Calibration Summary
- **Bug 1 (Easy):** `reconcile.py` crashes on launch with an `AttributeError` because `main()` references `args.input_file` and `args.output_file` instead of the defined `dest` names `input_path` and `output_path`.
- **Bug 2 (Medium):** The status filtering logic includes `"PENDING"` in `VALID_STATUSES` (treating pending payments as completed) and fails to round the total sum to two decimal places.
- **Bug 3 (Hard):** The deduplication logic performs naive lexical string comparisons on timestamp strings (`timestamp > records[tx_id]['timestamp']`), failing to recognize that timestamps with positive timezone offsets (e.g. `+04:00`) can be earlier in UTC than UTC `Z` timestamps.
- **Calibration Scores:** `nop` = `0.00` | `oracle` (`solve.sh`) = `1.00` | Partial `oracle` (Bug 1+2 fixed, Bug 3 broken, shown in video) = `0.50` | `hack.sh` = `0.00`

---

## 3. Ablation & RL Advantage Table (`terminus-2`, `k=3` Trials)

| Run | Change Tested | Trial 1 (Binary / Dense) | Trial 2 (Binary / Dense) | Trial 3 (Binary / Dense) | Mean Binary | Mean Dense ($\bar{R}$) | Binary Advantage ($R_1-\bar{R}, R_2-\bar{R}, R_3-\bar{R}$) | Dense Advantage ($R_1-\bar{R}, R_2-\bar{R}, R_3-\bar{R}$) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Run 1: Baseline** | Original 3-bug task (no sample data) | `0 / 0.50` | `0 / 0.20` | `0 / 0.00` | `0.00` | `0.23` | `0.00, 0.00, 0.00` | `+0.27, -0.03, -0.23` |
| **Run 2: Ablation** | Added `/app/sample_transactions.csv` with offset timestamps | `1 / 1.00` | `1 / 1.00` | `0 / 0.50` | `0.67` | `0.83` | `+0.33, +0.33, -0.67` | `+0.17, +0.17, -0.33` |

---

## 4. Trajectory Forensics (`trajectory.json`)
- **Where the Agent Failed in Run 1:** In Run 1 Trial 1 (`reconcile-bug__trial-1`), the agent fixed the argument parsing error and removed `"PENDING"` on step 3 and step 4, but stopped immediately after running `python3 -c "import reconcile"` to verify import syntax without testing cross-timezone edge cases, thus leaving Bug 3 completely unresolved.
- **Ablation Hypothesis & Result:** We hypothesized that without an existing sample file in `/app`, the agent lacked test data to reveal timezone comparison flaws. For Run 2, we placed `/app/sample_transactions.csv` with both UTC `Z` and `+04:00` offsets. In Run 2 Trial 1, the agent ran `cat /app/sample_transactions.csv` in step 1, tested `datetime.fromisoformat()` in step 3, and integrated proper UTC normalization, boosting the group success rate from 0% to 67%.

---

## 5. Dense Reward & Anti-Cheat Design
- **My Dense Reward Weights (`tests/test.sh`):** Check 1 awards **0.20** for parsing CLI flags and executing without crashes; Check 2 awards **0.30** for strict status filtering (`SUCCESS`/`COMPLETED` only) and 2-decimal rounding; Check 3 awards **0.50** for correct cross-timezone deduplication. This ensures meaningful learning signals ($+0.27$) for incremental progress while reserving half the reward for solving the core algorithmic challenge.
- **How `solution/hack.sh` Cheated & How I Blocked It:** `solution/hack.sh` attempts to cheat by returning a hardcoded mock JSON summary (`{"total_valid_amount": 100.0, "valid_count": 1, "failed_count": 0}`). Our hardened `test.sh` blocks this by: (1) generating dynamic randomized transaction amounts and UUIDs for every test run so static mock values fail exact equality, and (2) enforcing an input sensitivity invariant where an empty CSV output is compared against a populated CSV output—mock stubs returning identical output fail immediately and receive `0.00`.
- **Remaining Reward-Hacking Risk:** A sophisticated agent could inspect the process table (`ps aux` / `/proc`) or attempt to read the verifier execution context if `/logs/verifier/reward.txt` is writable prior to verifier execution, potentially overwriting the score file directly.

---

## 6. AI Tool Workflow
- **AI Tool & Model Used:** Gemini CLI / Google DeepMind Agentic Assistant (`gemini-2.5-flash` / `terminus-2`).
- **How I Avoided Prompt Leakage:** We strictly separated environment generation from task instructions. `instruction.md` was authored exclusively from the external functional requirements (CSV input schema, business definitions of valid vs. failed statuses, and deduplication rules) with zero references to variable names, lines of code, or specific implementation flaws present in `environment/reconcile.py`.
