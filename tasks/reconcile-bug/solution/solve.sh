#!/usr/bin/env bash
set -euo pipefail

cat << 'EOF' > /app/reconcile.py
#!/usr/bin/env python3
import argparse
import csv
import json
import sys
from datetime import datetime, timezone


def parse_iso_timestamp(ts_str):
    # Parse ISO 8601 string and normalize to UTC datetime
    # Handles both 'Z' suffix and numeric timezone offsets (+02:00, -05:00)
    cleaned = ts_str.strip()
    if cleaned.endswith("Z"):
        cleaned = cleaned[:-1] + "+00:00"
    dt = datetime.fromisoformat(cleaned)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt


def parse_args():
    parser = argparse.ArgumentParser(description="Payment Reconciler CLI")
    parser.add_argument("--input", required=True, dest="input_path", help="Path to input CSV")
    parser.add_argument("--output", required=True, dest="output_path", help="Path to output JSON")
    return parser.parse_args()


def reconcile(input_file, output_file):
    records = {}

    with open(input_file, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = row["tx_id"].strip()
            ts_str = row["timestamp"].strip()
            amount = float(row["amount"].strip())
            status = row["status"].strip().upper()
            dt = parse_iso_timestamp(ts_str)

            # Deduplication: Keep the transaction with the latest UTC timestamp
            if tx_id not in records:
                records[tx_id] = {"dt": dt, "amount": amount, "status": status}
            else:
                if dt > records[tx_id]["dt"]:
                    records[tx_id] = {"dt": dt, "amount": amount, "status": status}

    total_valid = 0.0
    valid_count = 0
    failed_count = 0

    VALID_STATUSES = {"SUCCESS", "COMPLETED"}

    for tx_id, data in records.items():
        if data["status"] in VALID_STATUSES:
            total_valid += data["amount"]
            valid_count += 1
        else:
            failed_count += 1

    summary = {
        "total_valid_amount": round(total_valid, 2),
        "valid_count": valid_count,
        "failed_count": failed_count,
    }

    with open(output_file, mode="w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)


def main():
    args = parse_args()
    reconcile(args.input_path, args.output_path)


if __name__ == "__main__":
    main()
EOF

chmod +x /app/reconcile.py
