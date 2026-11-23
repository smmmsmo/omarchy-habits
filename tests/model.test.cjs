const assert = require("node:assert/strict");
const fs = require("node:fs");
const M = require("../Model.js");
const today = "2026-11-24";
function fixture(kind = "good", defaultAnswer = "") {
  const state = M.emptyState();
  state.habits = [{
    id: "htest", name: "Habit X", kind, startDate: "2026-11-01",
    question: "Did you do this?", message: "One day at a time.", defaultAnswer
  }];
  return state;
}
function enter(state, day, value, automatic = false) {
  state.entries[day] ??= {};
  state.entries[day].htest = value;
  if (automatic) {
    state.automatic[day] ??= {};
    state.automatic[day].htest = true;
  }
  return state;
}
function stats(state) { return M.analyzeHabit(state.habits[0], state, today); }

assert.equal(M.validKey("2026-02-30"), false);
assert.equal(M.validKey("2024-02-29"), true);
const maximum = "2026-11-24";
assert.deepEqual(M.dateParts("2026-11-05"), { day: 5, month: 11, year: 2026 });
assert.deepEqual(M.dateLimits(2026, 11, M.dateParts(maximum)), { month: 11, day: 24 });
assert.deepEqual(M.dateLimits(2024, 2, M.dateParts(maximum)), { month: 12, day: 29 });
assert.equal(M.changeDatePart("2024-01-31", maximum, "month", 2), "2024-02-29");
assert.equal(M.changeDatePart("2024-02-29", maximum, "year", 2025), "2025-02-28");
assert.equal(M.changeDatePart("2025-12-31", maximum, "year", 2026), maximum);
assert.equal(M.changeDatePart(maximum, maximum, "day", 30), maximum);
assert.equal(M.addDays("2026-12-31", 1), "2027-01-01");
assert.equal(M.successFor("bad", "no"), true);
assert.equal(M.successFor("good", "yes"), true);
assert.equal(M.successFor("bad", ""), false);

let state = fixture();
enter(state, "2026-11-01", "yes");
enter(state, "2026-11-03", "yes");
enter(state, "2026-11-04", "yes");
assert.equal(stats(state).bestStreak, 2);
assert.equal(stats(state).currentStreak, 0);
assert.equal(stats(state).rate, 1);
enter(state, "2026-11-23", "yes");
assert.equal(stats(state).currentStreak, 1, "today can remain pending");
enter(state, today, "no");
assert.equal(stats(state).currentStreak, 0);

state = fixture("bad", "no");
assert.equal(stats(state).successCount, 23);
assert.equal(stats(state).automaticCount, 23);
assert.equal(stats(state).currentStreak, 23);
assert.equal(M.recordFor(state, state.habits[0], today, today).value, "");
assert.equal(M.recordFor(state, state.habits[0], "2026-11-25", today).value, "");
assert.equal(M.recordFor(state, state.habits[0], "2026-10-31", today).source, "before");
enter(state, "2026-11-20", "yes");
enter(state, "2026-11-21", "yes");
assert.equal(stats(state).failureCount, 2, "manual overrides beat defaults");
assert.equal(stats(state).recoveries, 1);
assert.equal(stats(state).averageRecoveryDays, 2);
assert.deepEqual(stats(state).latestRecovery, {
  from: "2026-11-20", to: "2026-11-22", days: 2, automatic: true
});
assert.equal(stats(state).weekSuccess, 4);
assert.equal(stats(state).weekAnswered, 6);
assert.equal(stats(state).currentStreak, 2);
assert.equal(stats(state).manualCount, 2);
assert.equal(stats(state).automaticCount, 21);

enter(state, today, "yes");
assert.equal(stats(state).pendingRecovery, true);
assert.equal(stats(state).recoverySince, today);
assert.equal(stats(state).currentStreak, 0);
enter(state, today, "no");
assert.equal(stats(state).pendingRecovery, false);
assert.equal(stats(state).currentStreak, 3);

state = fixture("good", "no");
assert.equal(stats(state).failureCount, 23, "default No for a good habit means missed");
assert.equal(stats(state).rate, 0);
enter(state, "2026-11-20", "yes", true);
assert.equal(M.recordFor(state, state.habits[0], "2026-11-20", today).value, "yes",
  "previously saved automatic values don't change with the setting");
state.habits[0].startDate = "2026-11-21";
assert.equal(stats(state).answered, 3, "each habit owns its analysis window");

const grid = M.monthGrid(state.habits[0], state, 2026, 10, today);
assert.equal(grid.length, 42);
assert.equal(M.dateFromKey(grid[0].date).getDay(), 1);
assert.equal(grid.find(c => c.date === today).state, "pending");
assert.equal(grid.find(c => c.date === "2026-11-23").automatic, true);
assert.equal(grid.find(c => c.date === "2026-11-20").selectable, false);
assert.equal(grid.find(c => c.date === "2026-11-25").state, "future");
const leapMonth = M.calendarDates(2024, 1);
assert.equal(leapMonth.filter(c => c.inMonth).length, 29);
assert.ok(leapMonth.some(c => c.key === "2024-02-29" && c.inMonth));
assert.equal(M.calendarDates(2026, 11).filter(c => c.inMonth).length, 31);
assert.equal(M.defaultPreview(state, "htest", "2026-11-20", today, "yes"), 3);
assert.equal(M.defaultPreview(state, "htest", "2026-11-20", today, ""), 0);

const legacy = M.parseState(JSON.stringify({
  version: 1, startDate: "2026-11-05",
  habits: [{ id: "htest", name: "Habit X", kind: "bad" }],
  entries: { "2026-11-06": { htest: "yes" } }
}));
assert.equal(legacy.habits[0].startDate, "2026-11-05");
assert.equal(legacy.habits[0].defaultAnswer, "", "legacy data gains no guessed answers");
assert.equal(M.recordFor(legacy, legacy.habits[0], "2026-11-06", today).source, "manual");
assert.deepEqual(M.parseState(JSON.stringify(state)), state);

const markup = '<img src="https://example.invalid/tracker">';
state.habits[0].name = markup;
state.habits[0].question = markup;
state.habits[0].message = markup;
const parsed = M.parseState(JSON.stringify(state));
assert.equal(parsed.habits[0].message, markup);
const qml = fs.readFileSync(`${__dirname}/../HabitPanel.qml`, "utf8");
assert.match(qml, /component Label: Text \{\s*textFormat: Text.PlainText/);
assert.doesNotMatch(qml, /PanelToolTip|tooltipText:/, "no untrusted shared tooltip sinks");
assert.match(qml, /"dd MMM yyyy"/);
console.log("Model tests passed: defaults, midnight boundary, manual priority, per-habit dates, calendar, streaks, recovery, migration, plain text.");
