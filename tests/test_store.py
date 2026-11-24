import concurrent.futures
import csv
import datetime as dt
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "store.py"
spec = importlib.util.spec_from_file_location("habits_store", SCRIPT)
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)
TODAY = dt.date.today()
YESTERDAY = (TODAY - dt.timedelta(days=1)).isoformat()
START = (TODAY - dt.timedelta(days=5)).isoformat()


class StorageTests(unittest.TestCase):
    def setUp(self):
        root = Path("/tmp/opencode")
        self.temp = tempfile.TemporaryDirectory(dir=root if root.is_dir() else None)
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "habits.json"

    def apply(self, **operation):
        return store.transact(self.path, operation)

    def add(self, **values):
        fields = dict(name="Habit X", kind="bad", startDate=START,
                      question="Did you do this?", message="Keep going.", defaultAnswer="no")
        fields.update(values)
        data = self.apply(action="add", **fields)
        return data, data["habits"][-1]["id"]

    def test_elapsed_days_only_and_private_backup(self):
        data, identity = self.add()
        self.assertEqual(len(data["entries"]), 5)
        self.assertNotIn(TODAY.isoformat(), data["entries"])
        self.assertTrue(data["automatic"][YESTERDAY][identity])
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        data = self.apply(action="answer", id=identity, date=YESTERDAY, value="yes")
        self.assertEqual(data["entries"][YESTERDAY][identity], "yes")
        self.assertNotIn(identity, data["automatic"].get(YESTERDAY, {}))
        backup = Path(str(self.path) + ".bak")
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(backup.read_text())["entries"][YESTERDAY][identity], "no")
        self.assertEqual(self.apply(action="read")["entries"][YESTERDAY][identity], "yes")

    def test_clear_restores_default_in_past_but_today_stays_open(self):
        data, identity = self.add()
        self.apply(action="answer", id=identity, date=YESTERDAY, value="yes")
        data = self.apply(action="answer", id=identity, date=YESTERDAY, value="")
        self.assertEqual(data["entries"][YESTERDAY][identity], "no")
        self.assertTrue(data["automatic"][YESTERDAY][identity])
        self.apply(action="answer", id=identity, date=TODAY.isoformat(), value="no")
        data = self.apply(action="answer", id=identity, date=TODAY.isoformat(), value="")
        self.assertNotIn(TODAY.isoformat(), data["entries"])

    def test_defaults_catch_up_after_downtime_and_freeze_existing_values(self):
        data, identity = self.add()
        future = TODAY + dt.timedelta(days=3)
        store.fill_defaults(data, future)
        self.assertIn((future - dt.timedelta(days=1)).isoformat(), data["entries"])
        self.assertNotIn(future.isoformat(), data["entries"])
        fields = dict(data["habits"][0])
        fields["defaultAnswer"] = "yes"
        edited = self.apply(action="edit", **fields)
        self.assertEqual(edited["entries"][YESTERDAY][identity], "no")
        store.fill_defaults(edited, TODAY + dt.timedelta(days=1))
        self.assertEqual(edited["entries"][TODAY.isoformat()][identity], "yes")

    def test_v1_migration_preserves_every_answer_and_creates_stable_backup(self):
        original = dict(version=1, startDate=START, habits=[
            dict(id="hlegacy", name="NPNF", kind="bad")],
            entries={YESTERDAY: {"hlegacy": "yes"}})
        self.path.write_text(json.dumps(original))
        data = self.apply(action="read")
        self.assertEqual(data["version"], 3)
        self.assertEqual(data["entries"], original["entries"])
        self.assertEqual(data["habits"][0]["startDate"], START)
        self.assertEqual(data["habits"][0]["defaultAnswer"], "")
        stable = Path(str(self.path) + ".v1.bak")
        self.assertEqual(json.loads(stable.read_text()), original)
        self.apply(action="answer", id="hlegacy", date=TODAY.isoformat(), value="no")
        self.assertEqual(json.loads(stable.read_text()), original)

    def test_corruption_is_never_overwritten(self):
        self.path.write_text("{broken")
        with self.assertRaises(ValueError):
            self.add()
        self.assertEqual(self.path.read_text(), "{broken")

    def test_v2_migration_preserves_preferences_and_automatic_history(self):
        state, identity = self.add()
        state["version"] = 2
        state["preferences"] = {"weekStart": 7}
        self.path.write_text(json.dumps(state))
        data = self.apply(action="read")
        self.assertEqual(data, {**state, "version": 3})
        self.assertEqual(json.loads(Path(str(self.path) + ".v2.bak").read_text()), state)
        self.assertTrue(data["automatic"][YESTERDAY][identity])

    def test_undo_reverts_latest_answer_without_clobbering_another_write(self):
        _, identity = self.add()
        day = TODAY.isoformat()
        result = {}
        store.transact(self.path, dict(action="answer", id=identity, date=day, value="no"), result)
        self.assertEqual(result["undo"]["before"], {"value": "", "automatic": False})
        self.assertNotIn(day, self.apply(action="undo", **result["undo"])["entries"])
        result.clear()
        store.transact(self.path, dict(action="answer", id=identity, date=day, value="no"), result)
        self.apply(action="answer", id=identity, date=day, value="yes")
        with self.assertRaisesRegex(ValueError, "changed"):
            self.apply(action="undo", **result["undo"])
        self.assertEqual(self.apply(action="read")["entries"][day][identity], "yes")

    def test_count_zero_clear_undo_and_target_change_preserve_history(self):
        _, identity = self.add(kind="count", target=20, unit="pages")
        day = TODAY.isoformat()
        self.apply(action="answer", id=identity, date=day, value=0)
        result = {}
        store.transact(self.path, dict(action="answer", id=identity, date=day, value=22), result)
        data = self.apply(action="undo", **result["undo"])
        self.assertEqual(data["entries"][day][identity], 0)
        self.assertEqual(data["automatic"], {})
        self.assertEqual(data["habits"][0]["defaultAnswer"], "")
        fields = dict(data["habits"][0], target=25)
        self.assertEqual(self.apply(action="edit", **fields)["entries"][day][identity], 0)
        for value in ("20", -1, 1_000_001, 1.5, True):
            with self.assertRaises(ValueError):
                self.apply(action="answer", id=identity, date=day, value=value)
        with self.assertRaises(ValueError):
            self.apply(action="edit", **dict(fields, kind="good"))
        self.assertEqual(self.apply(action="answer", id=identity, date=day, value="")["entries"], {})

    def test_archiving_preserves_answers_and_skips_defaults_during_pause(self):
        _, identity = self.add()
        day = TODAY.isoformat()
        self.apply(action="answer", id=identity, date=day, value="yes")
        frozen = self.apply(action="archive", id=identity)
        self.assertEqual(frozen["entries"][day][identity], "yes")
        self.assertEqual(frozen["selectedHabitId"], "")
        self.assertTrue(store.archived(frozen["habits"][0]))
        with self.assertRaises(ValueError):
            self.apply(action="answer", id=identity, date=day, value="no")
        self.assertFalse(store.archived(self.apply(action="restore", id=identity)["habits"][0]))
        historical_pause = {"from": (TODAY - dt.timedelta(days=3)).isoformat(), "to": YESTERDAY}
        frozen["habits"][0]["pauses"] = [historical_pause]
        del frozen["entries"][historical_pause["from"]]
        del frozen["automatic"][historical_pause["from"]]
        self.path.write_text(json.dumps(frozen))
        data = self.apply(action="read")
        self.assertNotIn(historical_pause["from"], data["entries"])
        self.assertEqual(data["entries"][YESTERDAY][identity], "no")

    def test_exports_are_private_and_do_not_rewrite_tracker_data(self):
        _, identity = self.add(name="=7+8", kind="count", target=4, unit="@units")
        self.apply(action="answer", id=identity, date=TODAY.isoformat(), value=0)
        state = self.apply(action="archive", id=identity)
        before = self.path.read_bytes()
        exports = {}
        for fmt in ("csv", "json"):
            result = {}
            store.transact(self.path, dict(action="export", format=fmt), result)
            dest = Path(result["exportPath"])
            self.assertEqual(dest.parent.name, "habits-exports")
            self.assertEqual(dest.stat().st_mode & 0o777, 0o600)
            exports[fmt] = dest
        row = next(csv.DictReader(exports["csv"].read_text().splitlines()))
        self.assertEqual((row["habit"], row["value"], row["unit"], row["archived"]),
                         ("'=7+8", "0", "'@units", "yes"))
        self.assertEqual(json.loads(exports["json"].read_text()), state)
        self.assertEqual(self.path.read_bytes(), before)

    def test_ending_date_is_inclusive_and_stops_defaults(self):
        cutoff = (TODAY - dt.timedelta(days=2)).isoformat()
        state, identity = self.add(endDate=cutoff)
        self.assertEqual(state["habits"][0]["endDate"], cutoff)
        self.assertIn(identity, state["automatic"][cutoff])
        self.assertNotIn(YESTERDAY, state["entries"])
        with self.assertRaisesRegex(ValueError, "tracking dates"):
            self.apply(action="answer", id=identity, date=YESTERDAY, value="yes")
        state = self.apply(action="answer", id=identity, date=cutoff, value="yes")
        self.assertEqual(state["entries"][cutoff][identity], "yes")
        state = self.apply(action="edit", **dict(state["habits"][0], endDate=""))
        self.assertEqual(state["entries"][cutoff][identity], "yes")
        self.assertEqual(state["entries"][YESTERDAY][identity], "no")

    def test_future_and_one_day_deadlines_and_nondestructive_edits(self):
        future = (TODAY + dt.timedelta(days=6)).isoformat()
        state, identity = self.add(endDate=future, defaultAnswer="")
        self.apply(action="answer", id=identity, date=YESTERDAY, value="yes")
        state = self.apply(action="edit", **dict(state["habits"][0], endDate=START))
        self.assertEqual(state["habits"][0]["endDate"], START)
        self.assertEqual(state["entries"][YESTERDAY][identity], "yes")
        for value in (None, "2026-02-30", (TODAY - dt.timedelta(days=6)).isoformat()):
            with self.assertRaises(ValueError):
                self.apply(action="edit", **dict(state["habits"][0], endDate=value))

    def test_edit_fields_and_independent_start_dates(self):
        first, identity = self.add(defaultAnswer="")
        data, other = self.add(name="Other", startDate=YESTERDAY, defaultAnswer="yes")
        self.assertNotIn(identity, data["entries"][YESTERDAY])
        self.assertEqual(data["entries"][YESTERDAY][other], "yes")
        fields = dict(first["habits"][0])
        fields.update(name="Edited", question="A custom question?", message="A custom message.")
        data = self.apply(action="edit", **fields)
        self.assertEqual(data["habits"][0]["question"], fields["question"])
        self.assertEqual(data["habits"][1]["startDate"], YESTERDAY)
        self.assertEqual(data["habits"][0]["message"], fields["message"])

    def test_deletion_removes_both_answers_and_sources(self):
        data, identity = self.add()
        data = self.apply(action="delete", id=identity)
        self.assertEqual(data["habits"], [])
        self.assertEqual(data["entries"], {})
        self.assertEqual(data["automatic"], {})

    def test_week_start_persists_without_changing_habits_or_history(self):
        data, existing = self.add(defaultAnswer="")
        self.apply(action="answer", id=existing, date=YESTERDAY, value="no")
        before = self.apply(action="read")
        for day in range(7, 0, -1):
            after = self.apply(action="setPreferences", weekStart=day)
            for field in ("habits", "entries", "automatic", "selectedHabitId"):
                self.assertEqual(before[field], after[field])
            self.assertEqual(self.apply(action="read")["preferences"]["weekStart"], day)

    def test_old_default_date_is_ignored_and_replaced(self):
        data, _ = self.add(defaultAnswer="")
        data["preferences"] = {"defaultStartDate": START, "unrelatedPreference": True}
        self.path.write_text(json.dumps(data))
        created = self.apply(action="add", name="Uses today", kind="good")
        self.assertEqual(created["habits"][-1]["startDate"], TODAY.isoformat())
        updated = self.apply(action="setPreferences", weekStart=6)
        self.assertEqual(updated["preferences"], {"weekStart": 6, "unrelatedPreference": True})
        self.assertEqual(updated["habits"], created["habits"])

    def test_week_start_rejects_invalid_values(self):
        self.apply(action="setPreferences", weekStart=6)
        before = self.path.read_bytes()
        for day in (-1, 0, 8, "6", True, 6.5, None):
            with self.assertRaises(ValueError):
                self.apply(action="setPreferences", weekStart=day)
        self.assertEqual(self.path.read_bytes(), before)

    def test_selection_survives_reload_without_replacing_the_data_backup(self):
        _, first = self.add()
        _, second = self.add(name="Other")
        backup = Path(str(self.path) + ".bak")
        previous = backup.read_bytes()
        self.assertEqual(self.apply(action="read")["selectedHabitId"], second)
        self.apply(action="select", id=first)
        self.assertEqual(self.apply(action="read")["selectedHabitId"], first)
        self.assertEqual(backup.read_bytes(), previous)
        self.assertEqual(self.apply(action="delete", id=first)["selectedHabitId"], "")

    def test_concurrent_writes_keep_every_habit(self):
        def add(index):
            subprocess.run(["python3", "-B", str(SCRIPT), str(self.path)],
                input=json.dumps(dict(action="add", name=f"Habit {index}", kind="good")) + "\n",
                capture_output=True, text=True, check=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(add, range(12)))
        self.assertEqual(len(self.apply(action="read")["habits"]), 12)

    def test_helper_rejects_missing_oversize_and_non_object_input(self):
        for request in ("", "{}", "[]\n", "{\n", " " * (store.MAX_REQUEST + 1) + "\n"):
            reply = subprocess.run(["python3", "-B", str(SCRIPT), str(self.path)],
                                   input=request, capture_output=True, text=True)
            self.assertEqual(reply.returncode, 1)
            self.assertFalse(json.loads(reply.stdout)["ok"])
            self.assertFalse(self.path.exists())

    def test_future_invalid_and_outside_window_days_refused(self):
        data, identity = self.add()
        before = self.path.read_bytes()
        for day in ("2026-02-30", "1900-01-01", (TODAY + dt.timedelta(days=1)).isoformat()):
            with self.assertRaises(ValueError):
                self.apply(action="answer", id=identity, date=day, value="yes")
        self.assertEqual(self.path.read_bytes(), before)

    def test_markup_is_only_data(self):
        fields = {k: '<img src="https://example.invalid/tracker"> $(touch NEVER)'
                  for k in ("name", "question", "message")}
        data, _ = self.add(**fields)
        for key in fields:
            self.assertEqual(data["habits"][0][key], fields[key])


if __name__ == "__main__":
    unittest.main()
