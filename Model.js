// Pure local-date and analysis helpers. ISO keys are storage-only.
var DAY_MS = 86400000
function pad2(n) { return n < 10 ? "0" + n : String(n) }
function keyForDate(date) {
  return date && !isNaN(date.getTime())
    ? date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate()) : ""
}
function dateFromKey(key) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""))
  if (!match) return null
  var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12)
  return keyForDate(date) === key ? date : null
}
function validKey(key) { return dateFromKey(key) !== null }
function todayKey() { return keyForDate(new Date()) }
function addDays(key, count) {
  var date = dateFromKey(key)
  if (!date) return key
  date.setDate(date.getDate() + count)
  return keyForDate(date)
}
function daysBetween(from, to) {
  return Math.round((dateFromKey(to).getTime() - dateFromKey(from).getTime()) / DAY_MS)
}
function parseDisplayDate(text) {
  var value = String(text || "").trim()
  if (validKey(value)) return value
  var match = /^(\d{1,2})\s+([a-z]{3})\s+(\d{4})$/i.exec(value)
  if (!match) return ""
  var months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
  var index = months.indexOf(match[2].toLowerCase())
  var key = match[3] + "-" + pad2(index + 1) + "-" + pad2(Number(match[1]))
  return index >= 0 && validKey(key) ? key : ""
}
function enumerateDays(start, end) {
  var days = []
  if (!validKey(start) || !validKey(end)) return days
  for (var key = start; key <= end && days.length < 100000; key = addDays(key, 1)) days.push(key)
  return days
}
function emptyState() { return { version: 2, habits: [], entries: {}, automatic: {}, selectedHabitId: "" } }
function findHabit(state, id) {
  var habits = state && state.habits || []
  for (var i = 0; i < habits.length; i++) if (habits[i].id === id) return habits[i]
  return null
}
function parseState(raw, fallbackDate) {
  var state = emptyState()
  var parsed
  try { parsed = JSON.parse(raw) } catch (error) { return state }
  if (!parsed || !Array.isArray(parsed.habits)) return state
  var known = {}
  for (var i = 0; i < parsed.habits.length && i < 80; i++) {
    var h = parsed.habits[i]
    if (!h || !/^h[A-Za-z0-9]{1,63}$/.test(h.id) || known[h.id]) continue
    known[h.id] = true
    state.habits.push({
      id: h.id,
      name: String(h.name || "").slice(0, 96),
      kind: h.kind === "bad" ? "bad" : "good",
      startDate: validKey(h.startDate) ? h.startDate : (parsed.startDate || fallbackDate || todayKey()),
      question: String(h.question || "Did this behavior happen?").slice(0, 256),
      message: String(h.message || "").slice(0, 512),
      defaultAnswer: h.defaultAnswer === "yes" || h.defaultAnswer === "no" ? h.defaultAnswer : ""
    })
  }
  if (typeof parsed.selectedHabitId === "string" && known[parsed.selectedHabitId])
    state.selectedHabitId = parsed.selectedHabitId
  var entries = parsed.entries || {}
  var automatic = parsed.automatic || {}
  for (var day in entries) {
    if (!validKey(day) || !entries[day] || typeof entries[day] !== "object") continue
    for (var id in entries[day]) {
      var value = entries[day][id]
      if (!known[id] || (value !== "yes" && value !== "no")) continue
      if (!state.entries[day]) state.entries[day] = {}
      state.entries[day][id] = value
      if (automatic[day] && automatic[day][id] === true) {
        if (!state.automatic[day]) state.automatic[day] = {}
        state.automatic[day][id] = true
      }
    }
  }
  return state
}
function answerFor(state, day, id) {
  return state.entries && state.entries[day] && state.entries[day][id] || ""
}
function successFor(kind, value) {
  return (value === "yes" || value === "no") && (kind === "bad" ? value === "no" : value === "yes")
}
function recordFor(state, habit, day, today) {
  if (!habit || day < habit.startDate) return { value: "", source: "before" }
  if (day > today) return { value: "", source: "future" }
  var value = answerFor(state, day, habit.id)
  if (value) return {
    value: value,
    source: state.automatic && state.automatic[day] && state.automatic[day][habit.id] ? "automatic" : "manual"
  }
  if (day < today && habit.defaultAnswer) return { value: habit.defaultAnswer, source: "automatic" }
  return { value: "", source: "pending" }
}
function summaryForDay(state, day, today) {
  var summary = { total: 0, answered: 0, success: 0, failure: 0, remaining: 0, perfect: false }
  today = today || todayKey()
  for (var i = 0; i < state.habits.length; i++) {
    var habit = state.habits[i]
    if (day < habit.startDate || day > today) continue
    summary.total++
    var record = recordFor(state, habit, day, today)
    if (!record.value) continue
    summary.answered++
    if (successFor(habit.kind, record.value)) summary.success++
    else summary.failure++
  }
  summary.remaining = summary.total - summary.answered
  summary.perfect = summary.total > 0 && summary.success === summary.total
  return summary
}
function cellFor(state, habit, key, today) {
  var record = recordFor(state, habit, key, today)
  return {
    date: key, day: Number(key.slice(-2)), today: key === today, value: record.value,
    source: record.source, automatic: record.source === "automatic",
    selectable: key >= habit.startDate && key <= today,
    state: record.value ? (successFor(habit.kind, record.value) ? "success" : "failure") : record.source
  }
}
function defaultPreview(state, habitId, start, today, answer) {
  if (!answer || !validKey(start) || start >= today) return 0
  var count = daysBetween(start, today)
  for (var day in state.entries)
    if (day >= start && day < today && answerFor(state, day, habitId)) count--
  return Math.max(0, count)
}
function monthGrid(habit, state, year, month, today) {
  if (!habit) return []
  return calendarDates(year, month).map(function(date) {
    var cell = cellFor(state, habit, date.key, today)
    cell.inMonth = date.inMonth
    return cell
  })
}
function calendarDates(year, month) {
  var first = new Date(year, month, 1, 12)
  var monday = addDays(keyForDate(first), -((first.getDay() + 6) % 7))
  var cells = []
  for (var i = 0; i < 42; i++) {
    var key = addDays(monday, i)
    cells.push({ key: key, day: Number(key.slice(-2)), inMonth: dateFromKey(key).getMonth() === month })
  }
  return cells
}
function heatmapWeeks(habit, state, today, count) {
  var date = dateFromKey(today)
  var monday = addDays(today, -(count - 1) * 7 - ((date.getDay() + 6) % 7))
  var weeks = []
  for (var w = 0; w < count; w++) {
    var row = []
    for (var d = 0; d < 7; d++) row.push(cellFor(state, habit, addDays(monday, w * 7 + d), today))
    weeks.push(row)
  }
  return weeks
}
function analyzeHabit(habit, state, today) {
  var days = enumerateDays(habit.startDate, today)
  var stats = {
    id: habit.id, name: habit.name, kind: habit.kind, trackedDays: days.length,
    answered: 0, successCount: 0, failureCount: 0, manualCount: 0, automaticCount: 0,
    currentStreak: 0, bestStreak: 0, recoveries: 0, averageRecoveryDays: 0,
    pendingRecovery: false, recoverySince: "", latestRecovery: null,
    rate: 0, weekRate: 0, weekAnswered: 0, weekSuccess: 0,
    monthRate: 0, monthAnswered: 0, monthSuccess: 0
  }
  var run = 0, episode = "", recoveryDays = 0, weekSuccess = 0, monthSuccess = 0
  var weekStart = addDays(today, -6), monthStart = addDays(today, -29)
  for (var i = 0; i < days.length; i++) {
    var day = days[i]
    var record = recordFor(state, habit, day, today)
    if (!record.value) { run = 0; continue }
    stats.answered++
    if (record.source === "automatic") stats.automaticCount++
    else stats.manualCount++
    var success = successFor(habit.kind, record.value)
    if (day >= weekStart) { stats.weekAnswered++; if (success) weekSuccess++ }
    if (day >= monthStart) { stats.monthAnswered++; if (success) monthSuccess++ }
    if (success) {
      stats.successCount++
      run++
      stats.bestStreak = Math.max(stats.bestStreak, run)
      if (episode) {
        stats.recoveries++
        var elapsed = daysBetween(episode, day)
        recoveryDays += elapsed
        stats.latestRecovery = { from: episode, to: day, days: elapsed, automatic: record.source === "automatic" }
        episode = ""
      }
    } else {
      stats.failureCount++
      run = 0
      if (!episode) episode = day
    }
  }
  var end = today
  if (!recordFor(state, habit, end, today).value) end = addDays(end, -1)
  for (var key = end; key >= habit.startDate; key = addDays(key, -1)) {
    if (!successFor(habit.kind, recordFor(state, habit, key, today).value)) break
    stats.currentStreak++
  }
  stats.pendingRecovery = episode !== ""
  stats.recoverySince = episode
  stats.averageRecoveryDays = stats.recoveries ? recoveryDays / stats.recoveries : 0
  stats.rate = stats.answered ? stats.successCount / stats.answered : 0
  stats.weekRate = stats.weekAnswered ? weekSuccess / stats.weekAnswered : 0
  stats.monthRate = stats.monthAnswered ? monthSuccess / stats.monthAnswered : 0
  stats.weekSuccess = weekSuccess
  stats.monthSuccess = monthSuccess
  return stats
}
function analyze(state, today) {
  today = today || todayKey()
  var result = { habits: [], today: summaryForDay(state, today, today), totals: { answered: 0, success: 0, failure: 0, rate: 0 } }
  for (var i = 0; i < state.habits.length; i++) {
    var stats = analyzeHabit(state.habits[i], state, today)
    result.habits.push(stats)
    result.totals.answered += stats.answered
    result.totals.success += stats.successCount
    result.totals.failure += stats.failureCount
  }
  result.totals.rate = result.totals.answered ? result.totals.success / result.totals.answered : 0
  return result
}
if (typeof module !== "undefined" && module.exports) module.exports = {
  keyForDate: keyForDate, dateFromKey: dateFromKey, validKey: validKey, todayKey: todayKey,
  addDays: addDays, daysBetween: daysBetween, parseDisplayDate: parseDisplayDate,
  emptyState: emptyState, parseState: parseState, findHabit: findHabit,
  answerFor: answerFor, successFor: successFor, recordFor: recordFor,
  summaryForDay: summaryForDay, defaultPreview: defaultPreview, monthGrid: monthGrid, calendarDates: calendarDates, heatmapWeeks: heatmapWeeks,
  analyzeHabit: analyzeHabit, analyze: analyze
}
