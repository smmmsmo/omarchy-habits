#!/usr/bin/env python3
"""Private, atomic habit storage. Each mutation re-reads under an exclusive lock."""
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile
import uuid
from copy import deepcopy

MAX_BYTES = 8 * 1024 * 1024
MAX_ANSWERS = 100_000


def date_key(value):
    if not isinstance(value, str) or len(value) != 10:
        raise ValueError("Use a real date in YYYY-MM-DD form.")
    date = dt.date.fromisoformat(value)
    if date.isoformat() != value or date.year < 1900:
        raise ValueError("Use a date from 1900 onwards.")
    return value


def empty():
    return {"version": 2, "habits": [], "entries": {}, "automatic": {}}


def validate(data):
    if not isinstance(data, dict) or data.get("version") not in (1, 2):
        raise ValueError("Unsupported habit data. Restore a backup before editing.")
    if data["version"] == 1:
        date_key(data["startDate"])
    habits, entries = data["habits"], data["entries"]
    if not isinstance(habits, list) or len(habits) > 80 or not isinstance(entries, dict):
        raise ValueError("Invalid habit data. The file has not been changed.")
    ids = set()
    for habit in habits:
        if not isinstance(habit, dict):
            raise ValueError("Invalid habit.")
        identity = habit["id"]
        if (not isinstance(identity, str) or not identity.startswith("h")
                or not identity.isalnum() or len(identity) > 64 or identity in ids):
            raise ValueError("Invalid or duplicate habit ID.")
        if (not isinstance(habit["name"], str) or not habit["name"].strip()
                or len(habit["name"]) > 96 or habit["kind"] not in ("good", "bad")):
            raise ValueError("Invalid habit name or kind.")
        ids.add(identity)
        if data["version"] == 2:
            date_key(habit["startDate"])
            if (not isinstance(habit["question"], str) or not habit["question"].strip()
                    or len(habit["question"]) > 256
                    or not isinstance(habit["message"], str) or len(habit["message"]) > 512
                    or habit["defaultAnswer"] not in ("", "yes", "no")):
                raise ValueError("Invalid habit question, message, or default.")
    for day, answers in entries.items():
        date_key(day)
        if not isinstance(answers, dict):
            raise ValueError("Invalid daily answers.")
        if any(key not in ids or answer not in ("yes", "no")
               for key, answer in answers.items()):
            raise ValueError("Invalid daily answer.")
    if data["version"] == 2:
        preferences = data.get("preferences", {})
        if not isinstance(preferences, dict):
            raise ValueError("Invalid app settings.")
        validate_week_start(preferences.get("weekStart", 1))
        selected = data.get("selectedHabitId", "")
        if selected != "" and (not isinstance(selected, str) or selected not in ids):
            raise ValueError("Invalid selected habit.")
        if not isinstance(data["automatic"], dict):
            raise ValueError("Invalid automatic-answer records.")
        for day, answers in data["automatic"].items():
            date_key(day)
            if not isinstance(answers, dict) or any(
                    identity not in entries.get(day, {}) or flag is not True
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
        data.update(version=2, automatic={})
    return data


def fill_defaults(data, today):
    """Close only elapsed local dates. Saved defaults never overwrite an answer."""
    count = sum(len(answers) for answers in data["entries"].values())
    for habit in data["habits"]:
        if not habit["defaultAnswer"]:
            continue
        day = dt.date.fromisoformat(habit["startDate"])
        while day < today:
            key = day.isoformat()
            answers = data["entries"].setdefault(key, {})
            if habit["id"] not in answers:
                if count >= MAX_ANSWERS:
                    raise ValueError("Too many automatic answers. Choose a more recent starting date.")
                answers[habit["id"]] = habit["defaultAnswer"]
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
    if habit["defaultAnswer"] and day < today.isoformat():
        data["entries"].setdefault(day, {})[identity] = habit["defaultAnswer"]
        data["automatic"].setdefault(day, {})[identity] = True


def habit_fields(operation, default_start, today):
    name = " ".join(str(operation.get("name", "")).split())
    kind = operation.get("kind")
    start = date_key(operation.get("startDate", default_start))
    question = " ".join(str(operation.get("question", "Did this behavior happen?")).split())
    message = str(operation.get("message", "")).strip()
    default = operation.get("defaultAnswer", "")
    if not name or len(name) > 96:
        raise ValueError("Name your habit using 1–96 characters.")
    if kind not in ("good", "bad") or default not in ("", "yes", "no"):
        raise ValueError("Choose the habit type and its Yes/No default.")
    if start > today:
        raise ValueError("The starting date cannot be in the future.")
    if not question or len(question) > 256 or len(message) > 512:
        raise ValueError("Use a question up to 256 characters and a message up to 512.")
    return dict(name=name, kind=kind, startDate=start, question=question,
                message=message, defaultAnswer=default)


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


def transact(path, operation):
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
            habit.update(habit_fields(operation, habit["startDate"], today_key))
            data["selectedHabitId"] = habit["id"]
        elif action == "select":
            identity = operation.get("id")
            if any(h["id"] == identity for h in data["habits"]):
                data["selectedHabitId"] = identity
        elif action in ("answer", "delete"):
            identity = operation.get("id")
            if not any(h["id"] == identity for h in data["habits"]):
                raise ValueError("That habit no longer exists.")
            if action == "delete":
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
                habit = next(h for h in data["habits"] if h["id"] == identity)
                if not habit["startDate"] <= day <= today_key:
                    raise ValueError("Choose a day between your starting date and today.")
                value = operation.get("value")
                if value not in ("yes", "no", ""):
                    raise ValueError("Choose Yes, No, or clear.")
                if value:
                    data["entries"].setdefault(day, {})[identity] = value
                    auto = data["automatic"].get(day, {})
                    auto.pop(identity, None)
                    if not auto:
                        data["automatic"].pop(day, None)
                else:
                    restore_default(data, habit, day, today)
        else:
            raise ValueError("Unknown habit operation.")
        if action in ("add", "edit"):
            fill_defaults(data, today)
        validate(data)
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if len(content.encode("utf-8")) > MAX_BYTES:
            raise ValueError("Habit data is too large.")
        if data != original:
            # A read can close elapsed days. Keep a stable pre-v2 migration copy.
            if path.exists():
                previous = path.read_text(encoding="utf-8")
                if original["version"] == 1:
                    migration_backup = Path(str(path) + ".v1.bak")
                    if not migration_backup.exists():
                        atomic_write(migration_backup, previous)
                if any(data.get(key) != original.get(key) for key in ("version", "habits", "entries", "automatic", "preferences")):
                    atomic_write(Path(str(path) + ".bak"), previous)
            atomic_write(path, content)
        return data


if __name__ == "__main__":
    try:
        operation = json.loads(sys.argv[2])
        state = transact(Path(sys.argv[1]), operation)
        identity = state["habits"][-1]["id"] if operation.get("action") == "add" else operation.get("id", "")
        print(json.dumps({"ok": True, "data": state, "habitId": identity}, ensure_ascii=False))
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)
