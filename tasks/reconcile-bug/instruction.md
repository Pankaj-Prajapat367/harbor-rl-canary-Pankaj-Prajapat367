# Payment Transaction Reconciler CLI

Your goal is to inspect and fix the Python CLI tool located at `/app/reconcile.py` so that it accurately processes payment transaction CSV files and writes summary reconciliation reports in JSON format.

## Execution Interface
The script must be executable via the command line with the following argument flags:
```bash
python3 /app/reconcile.py --input <path_to_csv> --output <path_to_json>
```

## Input CSV Specification
The input CSV file contains a header row followed by transaction records with four columns:
```csv
tx_id,timestamp,amount,status
```
- `tx_id` (string): The unique transaction identifier.
- `timestamp` (string): ISO 8601 formatted timestamp representing when the event occurred (e.g., `2026-03-01T14:30:00Z`, `2026-03-01T16:30:00+02:00`).
- `amount` (float): The transaction amount.
- `status` (string): The recorded state of the transaction (e.g., `SUCCESS`, `COMPLETED`, `PENDING`, `FAILED`, `CANCELLED`).

## Reconciliation & Business Rules
1. **Valid Status Filtering**:
   - A transaction is strictly considered valid if its status is either `SUCCESS` or `COMPLETED` (case-insensitive).
   - Any transaction with status `PENDING`, `FAILED`, `CANCELLED`, or unknown statuses must NOT be included in the valid totals.

2. **Deduplication by Precedence**:
   - The same `tx_id` may appear multiple times across the dataset (e.g., retry attempts, state transitions, or updates).
   - When a `tx_id` appears more than once, only the entry with the **latest absolute timestamp** (converted and compared in normalized UTC time) must be kept.
   - If the latest record for a given `tx_id` is `SUCCESS` or `COMPLETED`, that transaction counts as valid.
   - If the latest record for a given `tx_id` is `FAILED` or `PENDING`, that transaction counts towards `failed_count`.
   - Earlier entries for the same `tx_id` must be disregarded and not double-counted.

3. **Output JSON Format**:
   The script must write a valid JSON object to the path specified by `--output` containing exactly these keys:
   ```json
   {
     "total_valid_amount": 1250.50,
     "valid_count": 5,
     "failed_count": 2
   }
   ```
   - `total_valid_amount` (float): The sum of the amounts of all unique valid transactions, rounded to 2 decimal places. If no valid transactions exist, this should be `0.0`.
   - `valid_count` (int): Number of unique valid transactions.
   - `failed_count` (int): Number of unique non-valid transactions (e.g., failed, pending, or cancelled records).

Fix any bugs in `/app/reconcile.py` so that all input files are parsed accurately and output matches the required specification.
