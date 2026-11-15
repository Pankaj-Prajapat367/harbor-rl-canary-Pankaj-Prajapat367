#!/usr/bin/env bash
set -uo pipefail

mkdir -p /logs/verifier
REWARD_FILE="/logs/verifier/reward.txt"
echo "0.00" > "$REWARD_FILE"

TEST_DIR=$(mktemp -d /tmp/reconcile_test_XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

python3 - << 'PYEOF'
import os
import sys
import json
import random
import string
import subprocess
from datetime import datetime, timezone, timedelta

reward_file = "/logs/verifier/reward.txt"

def write_reward(score):
    with open(reward_file, "w") as f:
        f.write(f"{score:.2f}\n")
    print(f"Final Verifier Reward: {score:.2f}")

def run_script(csv_path, json_path):
    cmd = ["python3", "/app/reconcile.py", "--input", csv_path, "--output", json_path]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
    return res

test_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp"
score = 0.0

try:
    # -------------------------------------------------------------
    # Anti-Cheat Invariant: Dynamic Sensitivity Check
    # A static mock stub that returns identical JSON regardless of input
    # will be penalized immediately.
    # -------------------------------------------------------------
    csv_null = os.path.join(test_dir, "input_null.csv")
    out_null = os.path.join(test_dir, "out_null.json")
    with open(csv_null, "w") as f:
        f.write("tx_id,timestamp,amount,status\n")
    
    r_null = run_script(csv_null, out_null)
    if r_null.returncode != 0 or not os.path.exists(out_null):
        # Even baseline failed to run
        write_reward(0.0)
        sys.exit(0)

    with open(out_null) as f:
        null_data = json.load(f)

    # -------------------------------------------------------------
    # Check 1: CLI Syntax & Basic Non-Crashing Execution (Weight: 0.20)
    # Tests that --input and --output arguments are parsed properly
    # and a basic valid transaction is summarized.
    # -------------------------------------------------------------
    rand_amt1 = round(random.uniform(50.0, 200.0), 2)
    tx_id1 = f"tx_c1_{random.randint(1000, 9999)}"
    csv_1 = os.path.join(test_dir, "input_1.csv")
    out_1 = os.path.join(test_dir, "out_1.json")

    with open(csv_1, "w") as f:
        f.write("tx_id,timestamp,amount,status\n")
        f.write(f"{tx_id1},2026-03-01T10:00:00Z,{rand_amt1},SUCCESS\n")

    r_1 = run_script(csv_1, out_1)
    if r_1.returncode == 0 and os.path.exists(out_1):
        with open(out_1) as f:
            data_1 = json.load(f)
        if (
            abs(data_1.get("total_valid_amount", 0.0) - rand_amt1) < 1e-4
            and data_1.get("valid_count") == 1
            and data_1.get("failed_count") == 0
        ):
            # Invariant check: Output for single transaction must differ from empty CSV
            if data_1 != null_data:
                score += 0.20
                print("[PASS] Check 1: CLI parsing and basic execution (+0.20)")
            else:
                print("[FAIL] Check 1: Output matched null invariant (Mock detected)")
        else:
            print("[FAIL] Check 1: Numerical summary mismatch")
    else:
        print("[FAIL] Check 1: Script crashed or output missing")

    # -------------------------------------------------------------
    # Check 2: Status Filtering & Decimals (Weight: 0.30)
    # Verifies PENDING is not counted as valid, FAILED/CANCELLED go to
    # failed_count, and total is rounded to 2 decimal places.
    # -------------------------------------------------------------
    amt_success = round(random.uniform(70.15, 140.85), 2)
    amt_completed = round(random.uniform(30.10, 90.40), 2)
    amt_pending = round(random.uniform(10.0, 50.0), 2)
    amt_failed = round(random.uniform(15.0, 45.0), 2)
    expected_valid_sum = round(amt_success + amt_completed, 2)

    csv_2 = os.path.join(test_dir, "input_2.csv")
    out_2 = os.path.join(test_dir, "out_2.json")

    with open(csv_2, "w") as f:
        f.write("tx_id,timestamp,amount,status\n")
        f.write(f"tx_s1,2026-03-01T08:00:00Z,{amt_success},SUCCESS\n")
        f.write(f"tx_c1,2026-03-01T09:00:00Z,{amt_completed},completed\n")
        f.write(f"tx_p1,2026-03-01T10:00:00Z,{amt_pending},PENDING\n")
        f.write(f"tx_f1,2026-03-01T11:00:00Z,{amt_failed},FAILED\n")

    r_2 = run_script(csv_2, out_2)
    if r_2.returncode == 0 and os.path.exists(out_2):
        with open(out_2) as f:
            data_2 = json.load(f)
        if (
            abs(data_2.get("total_valid_amount", 0.0) - expected_valid_sum) < 1e-4
            and data_2.get("valid_count") == 2
            and data_2.get("failed_count") == 2
        ):
            score += 0.30
            print("[PASS] Check 2: Status filtering and decimal precision (+0.30)")
        else:
            print(f"[FAIL] Check 2: Status filtering failed. Got {data_2}")
    else:
        print("[FAIL] Check 2: Script execution failed")

    # -------------------------------------------------------------
    # Check 3: Subtle Cross-Timezone Deduplication (Weight: 0.50)
    # Tests deduplication across differing timezone offsets.
    # Row A: 15:00:00+04:00 (which is 11:00:00 UTC) -> SUCCESS ($120.00)
    # Row B: 12:00:00Z       (which is 12:00:00 UTC) -> FAILED ($50.00)
    # Lexical compare thinks Row A > Row B, but UTC time of Row B is later!
    # Therefore, the latest record is FAILED -> Valid: 0, Failed: 1.
    # -------------------------------------------------------------
    amt_test3_success = round(random.uniform(110.0, 190.0), 2)
    amt_test3_failed = round(random.uniform(40.0, 80.0), 2)

    # Second transaction:
    # Row C: 09:00:00-05:00 (which is 14:00:00 UTC) -> SUCCESS ($95.00)
    # Row D: 13:00:00Z       (which is 13:00:00 UTC) -> FAILED ($30.00)
    # Here, Row C is 14:00 UTC, which is later than Row D (13:00 UTC).
    # Latest record is SUCCESS -> Valid: 1, Failed: 0.
    amt_test3_second = round(random.uniform(60.0, 130.0), 2)

    csv_3 = os.path.join(test_dir, "input_3.csv")
    out_3 = os.path.join(test_dir, "out_3.json")

    with open(csv_3, "w") as f:
        f.write("tx_id,timestamp,amount,status\n")
        # Transaction 1: Lexical trap
        f.write(f"tx_dup1,2026-03-01T15:00:00+04:00,{amt_test3_success},SUCCESS\n")
        f.write(f"tx_dup1,2026-03-01T12:00:00Z,{amt_test3_failed},FAILED\n")
        # Transaction 2: Timezone offset is later than UTC
        f.write(f"tx_dup2,2026-03-01T13:00:00Z,30.00,FAILED\n")
        f.write(f"tx_dup2,2026-03-01T09:00:00-05:00,{amt_test3_second},SUCCESS\n")

    r_3 = run_script(csv_3, out_3)
    if r_3.returncode == 0 and os.path.exists(out_3):
        with open(out_3) as f:
            data_3 = json.load(f)
        
        # Expected:
        # tx_dup1: latest is FAILED
        # tx_dup2: latest is SUCCESS (amount: amt_test3_second)
        if (
            abs(data_3.get("total_valid_amount", 0.0) - amt_test3_second) < 1e-4
            and data_3.get("valid_count") == 1
            and data_3.get("failed_count") == 1
        ):
            score += 0.50
            print("[PASS] Check 3: Cross-timezone deduplication logic (+0.50)")
        else:
            print(f"[FAIL] Check 3: Deduplication mismatch. Got {data_3}")
    else:
        print("[FAIL] Check 3: Script execution failed")

    write_reward(round(score, 2))

except Exception as e:
    print(f"Verifier encountered exception: {e}")
    write_reward(0.0)
PYEOF
