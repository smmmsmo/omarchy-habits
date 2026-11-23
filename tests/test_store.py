import concurrent.futures
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
        self.assertEqual(data["version"], 2)
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
            subprocess.run(["python3", str(SCRIPT), str(self.path),
                json.dumps(dict(action="add", name=f"Habit {index}", kind="good"))],
                capture_output=True, text=True, check=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(add, range(12)))
        self.assertEqual(len(self.apply(action="read")["habits"]), 12)

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
