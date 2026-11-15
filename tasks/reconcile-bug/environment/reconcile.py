#!/usr/bin/env python3
import argparse
import csv
import json
import sys


def parse_args():
    parser = argparse.ArgumentParser(description="Payment Reconciler CLI")
    parser.add_argument("--input", required=True, dest="input_path", help="Path to input CSV")
    parser.add_argument("--output", required=True, dest="output_path", help="Path to output JSON")
    return parser.parse_args()


def reconcile(input_file, output_file):
    # Bug 1 will crash here if called via args.input_file instead of args.input_path
    records = {}

    with open(input_file, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            tx_id = row["tx_id"].strip()
            ts_str = row["timestamp"].strip()
            amount = float(row["amount"].strip())
            status = row["status"].strip().upper()

            # Bug 3 (Hard): Naive lexical string comparison for timestamps.
            # Fails on mixed timezone offsets (e.g., '+02:00' vs 'Z').
            if tx_id not in records:
                records[tx_id] = {"timestamp": ts_str, "amount": amount, "status": status}
            else:
                if ts_str > records[tx_id]["timestamp"]:
                    records[tx_id] = {"timestamp": ts_str, "amount": amount, "status": status}

    total_valid = 0.0
    valid_count = 0
    failed_count = 0

    # Bug 2 (Medium): Erroneously treats 'PENDING' transactions as valid!
    VALID_STATUSES = {"SUCCESS", "COMPLETED", "PENDING"}

    for tx_id, data in records.items():
        if data["status"] in VALID_STATUSES:
            total_valid += data["amount"]
            valid_count += 1
        else:
            failed_count += 1

    summary = {
        "total_valid_amount": total_valid,  # Missing round(total_valid, 2)
        "valid_count": valid_count,
        "failed_count": failed_count,
    }

    with open(output_file, mode="w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)


def main():
    args = parse_args()
    # Bug 1 (Easy / Surface): Accesses non-existent attribute input_file / output_file
    # causing an immediate AttributeError crash on startup.
    reconcile(args.input_file, args.output_file)


if __name__ == "__main__":
    main()
