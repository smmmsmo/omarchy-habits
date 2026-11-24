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
assert.equal(M.emptyState().preferences.weekStart, 1);
assert.equal(M.parseState('{"habits":[],"preferences":{"weekStart":6}}').preferences.weekStart, 6);
assert.equal(M.parseState('{"habits":[],"preferences":{"defaultStartDate":"2026-11-01"}}').preferences.weekStart, 1);
assert.equal(M.parseState('{"habits":[],"preferences":{"weekStart":"6"}}').preferences.weekStart, 1);
assert.deepEqual(M.orderedWeekdays(6), [6, 7, 1, 2, 3, 4, 5]);
assert.deepEqual(M.orderedWeekdays(7), [7, 1, 2, 3, 4, 5, 6]);
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
for (let first = 1; first <= 7; first++) {
  const weekdays = M.orderedWeekdays(first);
  for (const [year, month] of [[2026, 10], [2024, 1], [2026, 11], [2027, 0]]) {
    const cells = M.calendarDates(year, month, first);
    assert.equal(cells.length, 42);
    assert.equal(cells.filter(c => c.inMonth).length, new Date(year, month + 1, 0).getDate());
    cells.forEach((cell, index) => {
      assert.equal(M.dateFromKey(cell.key).getDay() || 7, weekdays[index % 7]);
      if (index > 0) assert.equal(cell.key, M.addDays(cells[index - 1].key, 1));
    });
  }
}
const saturdayState = { ...state, preferences: { weekStart: 6 } };
const saturdayGrid = M.monthGrid(state.habits[0], saturdayState, 2026, 10, today);
assert.equal(saturdayGrid[0].date, "2026-10-31");
assert.deepEqual(saturdayGrid.find(cell => cell.date === today), grid.find(cell => cell.date === today));
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

const numeric = fixture("count");
numeric.habits[0].target = 20;
numeric.habits[0].unit = "pages";
enter(numeric, "2026-11-22", 22);
enter(numeric, "2026-11-23", 20);
enter(numeric, today, 0);
const numericRoundTrip = M.parseState(JSON.stringify(numeric));
assert.equal(M.recordFor(numericRoundTrip, numericRoundTrip.habits[0], today, today).value, 0);
assert.equal(M.outcome(numeric.habits[0], M.recordFor(numeric, numeric.habits[0], today, today), today, today), "progress");
assert.equal(stats(numeric).currentStreak, 2, "a partial same-day count does not erase the streak");
assert.equal(stats(numeric).answered, 2);
assert.equal(M.analyzeHabit(numeric.habits[0], numeric, "2026-11-25").failureCount, 1);
enter(numeric, today, 21);
assert.equal(M.summaryForDay(numeric, today).success, 1);
assert.equal(stats(numeric).currentStreak, 3);

const archived = fixture("good", "yes");
enter(archived, "2026-11-19", "yes");
archived.habits[0].pauses = [{ from: "2026-11-20", to: "2026-11-23" }];
assert.equal(M.recordFor(archived, archived.habits[0], "2026-11-21", today).source, "paused");
assert.equal(M.defaultPreview(archived, "htest", "2026-11-19", today, "yes"), 1);
enter(archived, "2026-11-23", "yes");
assert.equal(stats(archived).currentStreak, 20, "archive gaps neither add to nor break a streak");
archived.habits[0].pauses.push({ from: today, to: "" });
assert.equal(M.isArchived(M.parseState(JSON.stringify(archived)).habits[0]), true);
assert.equal(M.summaryForDay(archived, today).total, 0);
assert.equal(stats(archived).currentStreak, 20);
const year = M.yearMonths(archived.habits[0], archived, 2026, today);
assert.equal(year.length, 12);
assert.equal(year[10].available, true);
assert.equal(year[11].available, false);
assert.equal(year[10].cells.filter(cell => cell.inMonth).length, 30);
assert.equal(year[10].cells.find(cell => cell.date === "2026-11-21").state, "paused");
assert.equal(year[10].cells.find(cell => cell.date === "2026-11-23").state, "success");
assert.equal(year[10].recorded, 20);

const timed = fixture("good", "yes");
timed.habits[0].endDate = "2026-11-23";
const finite = timed.habits[0];
enter(timed, today, "no");
assert.deepEqual(M.dateMetrics(finite, "2026-11-20"), { total: 23, elapsed: 19, left: 3, dueToday: false, ended: false });
assert.deepEqual(M.dateMetrics(finite, finite.endDate), { total: 23, elapsed: 22, left: 0, dueToday: true, ended: false });
assert.deepEqual(M.dateMetrics(finite, today), { total: 23, elapsed: 23, left: 0, dueToday: false, ended: true });
assert.equal(M.isDue(finite, finite.endDate), true);
assert.equal(M.summaryForDay(timed, today).total, 0);
assert.equal(M.recordFor(timed, finite, today, today).source, "after");
assert.equal(M.analyzeHabit(finite, timed, "2026-12-10").weekSuccess, 7, "recent stats end at the last tracked day");
assert.equal(stats(timed).trackedDays, 23);
assert.equal(stats(timed).currentStreak, 23);
assert.equal(M.defaultPreview(timed, "htest", "2026-11-20", today, "yes", "2026-11-21"), 2);
assert.deepEqual(M.parseState(JSON.stringify(timed)), timed);
timed.preferences.weekStart = 6;
const week = M.weekGrid(finite, timed, finite.endDate, today);
assert.deepEqual(week.map(c => c.date), ["2026-11-21", "2026-11-22", "2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27"]);
assert.deepEqual(M.summarizeWeek(week), { success: 3, failure: 0, pending: 0 });
assert.equal(week[2].selectable, true);
assert.equal(week[3].selectable, false);

const daily = fixture();
const build = daily.habits[0];
daily.habits.push(
  { ...build, id: "hquit", kind: "bad" },
  { ...build, id: "hpartial", kind: "count", target: 20 },
  { ...build, id: "hpending" },
  { ...build, id: "hended", endDate: "2026-11-23" },
  { ...build, id: "harchived", pauses: [{ from: today, to: "" }] }
);
daily.entries[today] = { htest: "yes", hquit: "yes", hpartial: 0, hended: "yes", harchived: "yes" };
assert.deepEqual(M.summaryForDay(daily, today), {
  total: 4, answered: 3, success: 1, failure: 1, progress: 1, pending: 1, perfect: false
}, "each due habit counts exactly once; expired and archived habits do not count");
daily.entries[today].hquit = "no";
assert.equal(M.summaryForDay(daily, today).success, 2, "No is on track for Quit");
assert.equal(M.barStatus(M.summaryForDay(daily, today)), "progress");
daily.entries[today].hquit = "yes";
assert.equal(M.barStatus(M.summaryForDay(daily, today)), "failure");
assert.equal(M.barStatus(M.summaryForDay(M.emptyState(), today)), "pending");
assert.equal(M.barStatus(M.summaryForDay(enter(fixture(), today, "yes"), today)), "success");
function rgb(hex) {
  const [r, g, b] = hex.slice(1).match(/../g).map(part => Number.parseInt(part, 16) / 255);
  return { r, g, b };
}
for (const background of ["#1e1e2e", "#f6f7fa"].map(rgb)) {
  for (const status of ["success", "progress", "failure", "best"])
    assert.ok(M.contrast(rgb(M.paletteColor(status, background)), background) >= 4.5);
}

const markup = '<img src="https://example.invalid/tracker">';
state.habits[0].name = markup;
state.habits[0].question = markup;
state.habits[0].message = markup;
const parsed = M.parseState(JSON.stringify(state));
assert.equal(parsed.habits[0].message, markup);
const qml = fs.readFileSync(`${__dirname}/../HabitPanel.qml`, "utf8");
assert.match(qml, /component Label: Text \{\s*textFormat: Text.PlainText/);
assert.doesNotMatch(qml, /PanelToolTip/, "no untrusted shared tooltip sinks");
assert.deepEqual([...qml.matchAll(/^\s*tooltipText:\s*(.+)$/gm)].map(match => match[1]),
  ['root.t("appSettings")'], "the sole tooltip uses a fixed translation");
assert.match(qml, /"dd MMM yyyy"/);
console.log("Model tests passed: calendars, defaults, numeric targets, archive gaps, streaks, recovery, migration, plain text.");
