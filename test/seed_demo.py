"""Write fictional history into a new, explicitly supplied state directory."""
import datetime as dt
import json
from pathlib import Path
import sys

today = dt.date.today()
start = today - dt.timedelta(days=112)
state_dir = Path(sys.argv[1]) / "omarchy"
state_dir.mkdir(mode=0o700)


def habit(identity, name, kind, question, **fields):
    return dict(id=identity, name=name, kind=kind, question=question, message="",
                startDate=start.isoformat(), defaultAnswer="", **fields)


habits = [
    habit("hwalk", "Daily walk", "good", "Did you go for a walk?"),
    habit("hreading", "Read 20 pages", "count", "How many pages did you read?",
          target=20, unit="pages", endDate=(today + dt.timedelta(days=21)).isoformat()),
    habit("hscroll", "Evening offline", "bad", "Did you scroll after bedtime?"),
]
habits[0]["message"] = "A short walk counts."
entries = {}
for i in range(113):
    day = (start + dt.timedelta(days=i)).isoformat()
    values = {}
    if i % 9 != 5:
        values["hwalk"] = "no" if i % 11 == 6 else "yes"
    if i % 6 != 3:
        values["hreading"] = 12 if i % 7 == 0 else 22
    if i % 8 != 4:
        values["hscroll"] = "yes" if i % 7 == 1 else "no"
    entries[day] = values
entries[today.isoformat()] = {"hwalk": "yes", "hreading": 12}
state = dict(version=3, habits=habits, entries=entries, automatic={},
             selectedHabitId="hwalk", preferences={"weekStart": 1})
with (state_dir / "habits.json").open("x", encoding="utf-8") as stream:
    json.dump(state, stream)
