#!/usr/bin/env python3
"""Private, atomic habit storage. Each mutation re-reads under an exclusive lock."""
import csv
import datetime as dt
import fcntl
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import uuid
from copy import deepcopy

MAX_BYTES = 8 * 1024 * 1024
MAX_ANSWERS = 100_000
MAX_COUNT = 1_000_000
MAX_REQUEST = 16 * 1024


def date_key(value):
    if not isinstance(value, str) or len(value) != 10:
        raise ValueError("Use a real date in YYYY-MM-DD form.")
    date = dt.date.fromisoformat(value)
    if date.isoformat() != value or date.year < 1900:
        raise ValueError("Use a date from 1900 onwards.")
    return value


def empty():
    return {"version": 3, "habits": [], "entries": {}, "automatic": {}}


def archived(habit):
    pauses = habit.get("pauses", [])
    return bool(pauses and not pauses[-1]["to"])


def paused(habit, day):
    return any(p["from"] <= day and (not p["to"] or day < p["to"])
               for p in habit.get("pauses", []))


def numeric(value, minimum=0):
    return type(value) is int and minimum <= value <= MAX_COUNT


def valid_answer(habit, value):
    return numeric(value) if habit["kind"] == "count" else value in ("yes", "no")


def end_date(value, start):
    if value == "":
        return ""
    end = date_key(value)
    if end < start:
        raise ValueError("The ending date cannot be before the starting date.")
    return end


def validate(data):
    if not isinstance(data, dict) or data.get("version") not in (1, 2, 3):
        raise ValueError("Unsupported habit data. Restore a backup before editing.")
    if data["version"] == 1:
        date_key(data["startDate"])
    habits, entries = data["habits"], data["entries"]
    if not isinstance(habits, list) or len(habits) > 80 or not isinstance(entries, dict):
        raise ValueError("Invalid habit data. The file has not been changed.")
    by_id = {}
    for habit in habits:
        if not isinstance(habit, dict):
            raise ValueError("Invalid habit.")
        identity = habit["id"]
        if (not isinstance(identity, str) or not identity.startswith("h")
                or not identity.isalnum() or len(identity) > 64 or identity in by_id):
            raise ValueError("Invalid or duplicate habit ID.")
        if (not isinstance(habit["name"], str) or not habit["name"].strip()
                or len(habit["name"]) > 96 or habit["kind"] not in
                (("good", "bad", "count") if data["version"] == 3 else ("good", "bad"))):
            raise ValueError("Invalid habit name or kind.")
        by_id[identity] = habit
        if data["version"] >= 2:
            date_key(habit["startDate"])
            if (not isinstance(habit["question"], str) or not habit["question"].strip()
                    or len(habit["question"]) > 256
                    or not isinstance(habit["message"], str) or len(habit["message"]) > 512
                    or habit["defaultAnswer"] not in ("", "yes", "no")):
                raise ValueError("Invalid habit question, message, or default.")
        if data["version"] == 3:
            end_date(habit.get("endDate", ""), habit["startDate"])
            if habit["kind"] == "count" and (
                    not numeric(habit.get("target"), 1) or habit["defaultAnswer"]
                    or not isinstance(habit.get("unit"), str) or len(habit["unit"]) > 32):
                raise ValueError("Invalid numeric target or unit.")
            pauses = habit.get("pauses", [])
            if not isinstance(pauses, list):
                raise ValueError("Invalid archive history.")
            end = "1900-01-01"
            for index, period in enumerate(pauses):
                start = date_key(period["from"])
                stop = period["to"]
                if (start < end or (stop and date_key(stop) <= start)
                        or (not stop and (stop != "" or index != len(pauses) - 1))):
                    raise ValueError("Invalid archive dates.")
                end = stop
    for day, answers in entries.items():
        date_key(day)
        if not isinstance(answers, dict):
            raise ValueError("Invalid daily answers.")
        if any(key not in by_id or not valid_answer(by_id[key], answer)
               for key, answer in answers.items()):
            raise ValueError("Invalid daily answer.")
    if data["version"] >= 2:
        preferences = data.get("preferences", {})
        if not isinstance(preferences, dict):
            raise ValueError("Invalid app settings.")
        validate_week_start(preferences.get("weekStart", 1))
        selected = data.get("selectedHabitId", "")
        if selected != "" and (not isinstance(selected, str) or selected not in by_id):
            raise ValueError("Invalid selected habit.")
        if not isinstance(data["automatic"], dict):
            raise ValueError("Invalid automatic-answer records.")
        for day, answers in data["automatic"].items():
            date_key(day)
            if not isinstance(answers, dict) or any(
                    identity not in entries.get(day, {}) or flag is not True
                    or by_id[identity]["kind"] == "count"
                    for identity, flag in answers.items()):
                raise ValueError("Invalid automatic-answer record.")
    return data


def validate_week_start(value):
    # ISO weekdays, also used by Qt.locale().dayName(): Monday=1, Sunday=7.
    if type(value) is not int or not 1 <= value <= 7:
        raise ValueError("Choose a weekday from Monday through Sunday.")
    return value


def migrate(data):
    """Legacy history stays manual and gains no guessed automatic answers."""
    if data["version"] == 1:
        for habit in data["habits"]:
            habit.update(startDate=data["startDate"], question="Did this behavior happen?",
                         message="", defaultAnswer="")
        data.pop("startDate")
        data.update(automatic={})
    data["version"] = 3
    return data


def fill_defaults(data, today):
    """Close only elapsed local dates. Saved defaults never overwrite an answer."""
    count = sum(len(answers) for answers in data["entries"].values())
    for habit in data["habits"]:
        if not habit["defaultAnswer"]:
            continue
        day = dt.date.fromisoformat(habit["startDate"])
        end = habit.get("endDate")
        through = min(today - dt.timedelta(days=1), dt.date.fromisoformat(end)) if end else today - dt.timedelta(days=1)
        while day <= through:
            key = day.isoformat()
            if not paused(habit, key) and habit["id"] not in data["entries"].get(key, {}):
                if count >= MAX_ANSWERS:
                    raise ValueError("Too many automatic answers. Choose a more recent starting date.")
                data["entries"].setdefault(key, {})[habit["id"]] = habit["defaultAnswer"]
                data["automatic"].setdefault(key, {})[habit["id"]] = True
                count += 1
            day += dt.timedelta(days=1)
    return data


def restore_default(data, habit, day, today):
    identity = habit["id"]
    if data["automatic"].get(day, {}).get(identity):
        return  # The saved default may predate the habit's current setting.
    answers = data["entries"].get(day, {})
    answers.pop(identity, None)
    if not answers:
        data["entries"].pop(day, None)
    if habit["defaultAnswer"] and day < today.isoformat() and not paused(habit, day):
        data["entries"].setdefault(day, {})[identity] = habit["defaultAnswer"]
        data["automatic"].setdefault(day, {})[identity] = True


def habit_fields(operation, default_start, today, default_end=""):
    name = " ".join(str(operation.get("name", "")).split())
    kind = operation.get("kind")
    start = date_key(operation.get("startDate", default_start))
    question = " ".join(str(operation.get("question", "Did this behavior happen?")).split())
    message = str(operation.get("message", "")).strip()
    default = operation.get("defaultAnswer", "")
    if not name or len(name) > 96:
        raise ValueError("Name your habit using 1–96 characters.")
    if kind not in ("good", "bad", "count") or default not in ("", "yes", "no"):
        raise ValueError("Choose the habit type and its Yes/No default.")
    if start > today:
        raise ValueError("The starting date cannot be in the future.")
    if not question or len(question) > 256 or len(message) > 512:
        raise ValueError("Use a question up to 256 characters and a message up to 512.")
    fields = dict(name=name, kind=kind, startDate=start, question=question,
                  message=message, defaultAnswer=default)
    if "endDate" in operation or default_end:
        fields["endDate"] = end_date(operation.get("endDate", default_end), start)
    if kind == "count":
        target = operation.get("target")
        unit = operation.get("unit", "")
        if not numeric(target, 1) or not isinstance(unit, str) or len(unit) > 32:
            raise ValueError("Choose a whole-number target of 1–1,000,000 and a short unit.")
        fields.update(target=target, unit=" ".join(unit.split()), defaultAnswer="")
    return fields


def answer_snapshot(data, identity, day):
    return {"value": data["entries"].get(day, {}).get(identity, ""),
            "automatic": data["automatic"].get(day, {}).get(identity) is True}


def write_answer(data, identity, day, value, automatic=False):
    for field, entry, present in (("entries", value, value != ""), ("automatic", True, automatic)):
        if present:
            data[field].setdefault(day, {})[identity] = entry
        else:
            bucket = data[field].get(day, {})
            bucket.pop(identity, None)
            if not bucket:
                data[field].pop(day, None)


def csv_text(value):
    # A habit name or unit isn't a spreadsheet formula.
    return "'" + value if value.lstrip()[:1] in ("=", "+", "-", "@") or value.startswith(("\t", "\r", "\n")) else value


def export_progress(path, data, content, fmt):
    if fmt not in ("json", "csv"):
        raise ValueError("Choose JSON or CSV export.")
    if fmt == "csv":
        output = io.StringIO(newline="")
        writer = csv.writer(output)
        writer.writerow(("date", "habit_id", "habit", "type", "value", "target", "unit",
                         "source", "archived", "start_date", "end_date"))
        habits = {habit["id"]: habit for habit in data["habits"]}
        for day, answers in sorted(data["entries"].items()):
            for identity, value in sorted(answers.items()):
                habit = habits[identity]
                writer.writerow((day, identity, csv_text(habit["name"]), habit["kind"],
                                 value, habit.get("target", ""), csv_text(habit.get("unit", "")),
                                 "automatic" if data["automatic"].get(day, {}).get(identity) else "manual",
                                 "yes" if archived(habit) else "no",
                                 habit["startDate"], habit.get("endDate", "")))
        content = output.getvalue()
    folder = path.parent / "habits-exports"
    folder.mkdir(mode=0o700, exist_ok=True)
    target = folder / f"habits-{dt.date.today().isoformat()}-{uuid.uuid4().hex[:12]}.{fmt}"
    atomic_write(target, content)
    return str(target)


def read_state(path):
    if not path.exists():
        return empty()
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("Habit data is too large. The file has not been changed.")
    return validate(json.loads(path.read_text(encoding="utf-8")))


def atomic_write(path, content):
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".habits-", delete=False) as stream:
            temp_name = stream.name
            os.fchmod(stream.fileno(), 0o600)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
        temp_name = None
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temp_name is not None:
            os.unlink(temp_name)


def transact(path, operation, result=None):
    result = {} if result is None else result
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(str(path) + ".lock", "a", encoding="utf-8") as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        data = read_state(path)
        original = deepcopy(data)
        today = dt.date.today()
        today_key = today.isoformat()
        data = fill_defaults(migrate(data), today)
        action = operation.get("action")
        if action == "read":
            pass
        elif action == "export":
            pass
        elif action == "setPreferences":
            week_start = validate_week_start(operation["weekStart"])
            preferences = data.get("preferences", {})
            if preferences.get("weekStart", 1) != week_start or "defaultStartDate" in preferences:
                preferences = data.setdefault("preferences", {})
                preferences["weekStart"] = week_start
                preferences.pop("defaultStartDate", None)
        elif action == "add":
            if len(data["habits"]) >= 80:
                raise ValueError("Up to 80 habits are supported.")
            habit = dict(id="h" + uuid.uuid4().hex, **habit_fields(operation, today_key, today_key))
            data["habits"].append(habit)
            data["selectedHabitId"] = habit["id"]
        elif action == "edit":
            habit = next((h for h in data["habits"] if h["id"] == operation.get("id")), None)
            if habit is None:
                raise ValueError("That habit no longer exists.")
            if archived(habit):
                raise ValueError("Restore this habit before editing it.")
            fields = habit_fields(operation, habit["startDate"], today_key, habit.get("endDate", ""))
            if (fields["kind"] == "count") != (habit["kind"] == "count"):
                raise ValueError("Create a new habit to switch between Yes/No and a numeric target.")
            habit.update(fields)
            data["selectedHabitId"] = habit["id"]
        elif action == "select":
            identity = operation.get("id")
            if any(h["id"] == identity and not archived(h) for h in data["habits"]):
                data["selectedHabitId"] = identity
        elif action in ("answer", "undo", "archive", "restore", "delete"):
            identity = operation.get("id")
            habit = next((h for h in data["habits"] if h["id"] == identity), None)
            if habit is None:
                raise ValueError("That habit no longer exists.")
            if action == "archive":
                if not archived(habit):
                    habit.setdefault("pauses", []).append({"from": today_key, "to": ""})
                if data.get("selectedHabitId") == identity:
                    data["selectedHabitId"] = ""
            elif action == "restore":
                if archived(habit):
                    periods = habit["pauses"]
                    if periods[-1]["from"] == today_key:
                        periods.pop()
                    else:
                        periods[-1]["to"] = today_key
            elif action == "delete":
                data["habits"] = [h for h in data["habits"] if h["id"] != identity]
                for answers in data["entries"].values():
                    answers.pop(identity, None)
                data["entries"] = {day: answers for day, answers in data["entries"].items() if answers}
                for answers in data["automatic"].values():
                    answers.pop(identity, None)
                data["automatic"] = {day: answers for day, answers in data["automatic"].items() if answers}
                if data.get("selectedHabitId") == identity:
                    data["selectedHabitId"] = ""
            else:
                day = date_key(operation.get("date"))
                if archived(habit) or paused(habit, day):
                    raise ValueError("This day is outside active tracking.")
                if not habit["startDate"] <= day <= min(today_key, habit.get("endDate") or today_key):
                    raise ValueError("Choose a day within the habit's tracking dates, up to today.")
                before = answer_snapshot(data, identity, day)
                if action == "undo":
                    if day != today_key or before != operation.get("after"):
                        raise ValueError("That check-in has changed and can no longer be undone.")
                    prior = operation["before"]
                    value = prior["value"]
                    if (type(prior["automatic"]) is not bool or prior["automatic"]
                            or (value != "" and not valid_answer(habit, value))):
                        raise ValueError("Invalid previous check-in.")
                    write_answer(data, identity, day, value)
                else:
                    value = operation.get("value")
                    if value != "" and not valid_answer(habit, value):
                        raise ValueError("Enter a valid check-in for this habit.")
                    if value == "":
                        restore_default(data, habit, day, today)
                    else:
                        write_answer(data, identity, day, value)
                    after = answer_snapshot(data, identity, day)
                    if day == today_key and before != after:
                        result["undo"] = {"id": identity, "date": day, "before": before, "after": after}
        else:
            raise ValueError("Unknown habit operation.")
        if action in ("add", "edit"):
            fill_defaults(data, today)
        validate(data)
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if len(content.encode("utf-8")) > MAX_BYTES:
            raise ValueError("Habit data is too large.")
        if action == "export":
            result["exportPath"] = export_progress(path, data, content, operation.get("format"))
            return data
        if data != original:
            # A read can close elapsed days. Keep a stable pre-migration copy.
            if path.exists():
                previous = path.read_text(encoding="utf-8")
                if original["version"] < data["version"]:
                    migration_backup = Path(str(path) + f".v{original['version']}.bak")
                    if not migration_backup.exists():
                        atomic_write(migration_backup, previous)
                if any(data.get(key) != original.get(key) for key in ("version", "habits", "entries", "automatic", "preferences")):
                    atomic_write(Path(str(path) + ".bak"), previous)
            atomic_write(path, content)
        return data


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Pass the state path and send one operation on standard input.")
        line = sys.stdin.buffer.readline(MAX_REQUEST + 1)
        if len(line) > MAX_REQUEST or not line.endswith(b"\n"):
            raise ValueError("Expected one bounded JSON line.")
        operation = json.loads(line)
        if not isinstance(operation, dict):
            raise ValueError("Expected a JSON operation object.")
        details = {}
        state = transact(Path(sys.argv[1]), operation, details)
        identity = state["habits"][-1]["id"] if operation.get("action") == "add" else operation.get("id", "")
        print(json.dumps({"ok": True, "data": state, "habitId": identity, **details}, ensure_ascii=False))
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)
