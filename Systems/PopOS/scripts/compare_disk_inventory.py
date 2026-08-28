#!/usr/bin/env python3
import csv
import sys
from collections import defaultdict

IDENTITY_FIELDS = ["serial", "smart_serial", "wwn", "by_id", "device"]
COMPARE_FIELDS = [
    "unraid_slot",
    "slot_source",
    "device",
    "kernel_name",
    "size_bytes",
    "model",
    "serial",
    "firmware",
    "transport",
    "rota",
    "by_id",
    "smart_model",
    "smart_serial",
]

IMPORTANT_FIELDS = {
    "unraid_slot",
    "size_bytes",
    "model",
    "serial",
    "smart_serial",
    "firmware",
    "transport",
    "rota",
    "by_id",
}

def load_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = []
        for row in reader:
            clean = {}
            for k, v in row.items():
                key = (k or "").strip()
                val = (v or "").strip()
                clean[key] = val
            rows.append(clean)
        return rows

def first_nonempty(row, fields):
    for field in fields:
        val = row.get(field, "").strip()
        if val:
            return field, val
    return None, ""

def make_identity_key(row):
    field, value = first_nonempty(row, IDENTITY_FIELDS)
    if field and value:
        return f"{field}:{value}"
    # fallback
    return "unknown:{}:{}:{}".format(
        row.get("device", ""),
        row.get("model", ""),
        row.get("size_bytes", ""),
    )

def summarize_disk(row):
    ident_field, ident_value = first_nonempty(row, IDENTITY_FIELDS)
    ident = ident_value or "<unknown>"
    slot = row.get("unraid_slot", "") or "unassigned"
    model = row.get("model", "") or row.get("smart_model", "")
    size = row.get("size_bytes", "")
    dev = row.get("device", "")
    return f"slot={slot} | id={ident} | model={model} | size={size} | dev={dev}"

def compare_rows(before, after):
    diffs = []
    for field in COMPARE_FIELDS:
        b = before.get(field, "")
        a = after.get(field, "")
        if b != a:
            diffs.append({
                "field": field,
                "before": b,
                "after": a,
                "important": "YES" if field in IMPORTANT_FIELDS else ""
            })
    return diffs

def build_slot_map(rows):
    slot_map = {}
    duplicates = defaultdict(list)
    for row in rows:
        slot = row.get("unraid_slot", "").strip()
        if not slot or slot == "unassigned":
            continue
        if slot in slot_map:
            duplicates[slot].append(row)
        else:
            slot_map[slot] = row
    return slot_map, duplicates

def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

def main():
    if len(sys.argv) < 3:
        print("Usage: compare_unraid_inventory.py before.csv after.csv [detail_report.csv] [slot_report.csv]", file=sys.stderr)
        sys.exit(1)

    before_path = sys.argv[1]
    after_path = sys.argv[2]
    detail_report = sys.argv[3] if len(sys.argv) >= 4 else "unraid_comparison_detail.csv"
    slot_report = sys.argv[4] if len(sys.argv) >= 5 else "unraid_slot_validation.csv"

    before_rows = load_csv(before_path)
    after_rows = load_csv(after_path)

    before_by_id = {}
    after_by_id = {}
    before_dupes = defaultdict(list)
    after_dupes = defaultdict(list)

    for row in before_rows:
        key = make_identity_key(row)
        if key in before_by_id:
            before_dupes[key].append(row)
        else:
            before_by_id[key] = row

    for row in after_rows:
        key = make_identity_key(row)
        if key in after_by_id:
            after_dupes[key].append(row)
        else:
            after_by_id[key] = row

    all_keys = sorted(set(before_by_id.keys()) | set(after_by_id.keys()))
    detail_rows = []

    matched = 0
    unchanged = 0
    changed = 0
    removed = 0
    added = 0

    for key in all_keys:
        b = before_by_id.get(key)
        a = after_by_id.get(key)

        if b and not a:
            removed += 1
            detail_rows.append({
                "status": "REMOVED_AFTER",
                "identity_key": key,
                "field": "",
                "before_value": summarize_disk(b),
                "after_value": "",
                "important_change": "YES",
            })
            continue

        if a and not b:
            added += 1
            detail_rows.append({
                "status": "ADDED_AFTER",
                "identity_key": key,
                "field": "",
                "before_value": "",
                "after_value": summarize_disk(a),
                "important_change": "YES",
            })
            continue

        matched += 1
        diffs = compare_rows(b, a)
        if not diffs:
            unchanged += 1
            detail_rows.append({
                "status": "UNCHANGED",
                "identity_key": key,
                "field": "",
                "before_value": summarize_disk(b),
                "after_value": summarize_disk(a),
                "important_change": "",
            })
        else:
            changed += 1
            for diff in diffs:
                detail_rows.append({
                    "status": "CHANGED",
                    "identity_key": key,
                    "field": diff["field"],
                    "before_value": diff["before"],
                    "after_value": diff["after"],
                    "important_change": diff["important"],
                })

    write_csv(
        detail_report,
        ["status", "identity_key", "field", "before_value", "after_value", "important_change"],
        detail_rows,
    )

    before_slots, before_slot_dupes = build_slot_map(before_rows)
    after_slots, after_slot_dupes = build_slot_map(after_rows)

    all_slots = sorted(set(before_slots.keys()) | set(after_slots.keys()))
    slot_rows = []

    slot_unchanged = 0
    slot_changed = 0
    slot_missing_after = 0
    slot_new_after = 0

    print("")
    print("Slot validation summary")
    print("-----------------------")

    for slot in all_slots:
        b = before_slots.get(slot)
        a = after_slots.get(slot)

        if b and not a:
            slot_missing_after += 1
            slot_rows.append({
                "slot": slot,
                "status": "MISSING_AFTER",
                "before_identity": summarize_disk(b),
                "after_identity": "",
                "before_serial": b.get("serial", ""),
                "after_serial": "",
                "before_device": b.get("device", ""),
                "after_device": "",
                "notes": "Slot existed before but is not assigned after",
            })
            print(f"{slot}: missing after | before was {summarize_disk(b)}")
            continue

        if a and not b:
            slot_new_after += 1
            slot_rows.append({
                "slot": slot,
                "status": "NEW_AFTER",
                "before_identity": "",
                "after_identity": summarize_disk(a),
                "before_serial": "",
                "after_serial": a.get("serial", ""),
                "before_device": "",
                "after_device": a.get("device", ""),
                "notes": "Slot appears after but was not assigned before",
            })
            print(f"{slot}: new after | after is {summarize_disk(a)}")
            continue

        bkey = make_identity_key(b)
        akey = make_identity_key(a)
        if bkey == akey:
            slot_unchanged += 1
            slot_rows.append({
                "slot": slot,
                "status": "UNCHANGED",
                "before_identity": summarize_disk(b),
                "after_identity": summarize_disk(a),
                "before_serial": b.get("serial", ""),
                "after_serial": a.get("serial", ""),
                "before_device": b.get("device", ""),
                "after_device": a.get("device", ""),
                "notes": "Same disk identity remains in this slot",
            })
        else:
            slot_changed += 1
            slot_rows.append({
                "slot": slot,
                "status": "DISK_CHANGED",
                "before_identity": summarize_disk(b),
                "after_identity": summarize_disk(a),
                "before_serial": b.get("serial", ""),
                "after_serial": a.get("serial", ""),
                "before_device": b.get("device", ""),
                "after_device": a.get("device", ""),
                "notes": "Different disk identity is assigned to this slot after change",
            })
            print(f"{slot}: disk changed")
            print(f"  before: {summarize_disk(b)}")
            print(f"  after : {summarize_disk(a)}")

    write_csv(
        slot_report,
        [
            "slot",
            "status",
            "before_identity",
            "after_identity",
            "before_serial",
            "after_serial",
            "before_device",
            "after_device",
            "notes",
        ],
        slot_rows,
    )

    print("")
    print("Inventory comparison complete")
    print(f"Before file:        {before_path}")
    print(f"After file:         {after_path}")
    print(f"Detail report:      {detail_report}")
    print(f"Slot report:        {slot_report}")
    print("")
    print("Identity-based summary")
    print(f"  Matched disks:    {matched}")
    print(f"  Unchanged:        {unchanged}")
    print(f"  Changed:          {changed}")
    print(f"  Added after:      {added}")
    print(f"  Removed after:    {removed}")
    print("")
    print("Slot-based summary")
    print(f"  Unchanged slots:  {slot_unchanged}")
    print(f"  Changed slots:    {slot_changed}")
    print(f"  Missing after:    {slot_missing_after}")
    print(f"  New after:        {slot_new_after}")

    if before_dupes:
        print("")
        print("Warning: duplicate disk identity keys in BEFORE file:")
        for key, rows in before_dupes.items():
            print(f"  {key} ({len(rows) + 1} entries total)")

    if after_dupes:
        print("")
        print("Warning: duplicate disk identity keys in AFTER file:")
        for key, rows in after_dupes.items():
            print(f"  {key} ({len(rows) + 1} entries total)")

    if before_slot_dupes:
        print("")
        print("Warning: duplicate slot assignments in BEFORE file:")
        for key, rows in before_slot_dupes.items():
            print(f"  {key} ({len(rows) + 1} entries total)")

    if after_slot_dupes:
        print("")
        print("Warning: duplicate slot assignments in AFTER file:")
        for key, rows in after_slot_dupes.items():
            print(f"  {key} ({len(rows) + 1} entries total)")

if __name__ == "__main__":
    main()