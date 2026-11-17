# Harbor RL Submission — Pankaj Prajapat (@Pankaj-Prajapat367)

## 1. Loom Walkthrough Video
- **Video URL:** [Watch 5-Minute Walkthrough](https://www.loom.com/share/9dd4fc397f444e239df8b1cce1d69de2 )
  
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
