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
function dateParts(key) {
  var date = dateFromKey(key)
  return date ? { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate() } : null
}
function dateLimits(year, month, maximum) {
  var lastDay = new Date(year, month, 0, 12).getDate()
  var lastMonth = year === maximum.year ? maximum.month : 12
  return {
    month: lastMonth,
    day: year === maximum.year && month === lastMonth ? Math.min(lastDay, maximum.day) : lastDay
  }
}
function changeDatePart(key, maximumKey, part, value) {
  var maximum = dateParts(maximumKey)
  var date = dateParts(key) || dateParts(maximumKey)
  if (!maximum || !date || !Number.isInteger(value) || !["day", "month", "year"].includes(part)) return key
  date[part] = value
  date.year = Math.min(maximum.year, Math.max(1900, date.year))
  date.month = Math.min(dateLimits(date.year, date.month, maximum).month, Math.max(1, date.month))
  date.day = Math.min(dateLimits(date.year, date.month, maximum).day, Math.max(1, date.day))
  return date.year + "-" + pad2(date.month) + "-" + pad2(date.day)
}
function enumerateDays(start, end) {
  var days = []
  if (!validKey(start) || !validKey(end)) return days
  for (var key = start; key <= end && days.length < 100000; key = addDays(key, 1)) days.push(key)
  return days
}
function emptyState() {
  return { version: 3, habits: [], entries: {}, automatic: {}, selectedHabitId: "", preferences: { weekStart: 1 } }
}
function weekStartDay(value) {
  return Number.isInteger(value) && value >= 1 && value <= 7 ? value : 1
}
function orderedWeekdays(weekStart) {
  var first = weekStartDay(weekStart)
  return [0, 1, 2, 3, 4, 5, 6].map(function(offset) { return (first - 1 + offset) % 7 + 1 })
}
function weekOffset(date, weekStart) {
  return (date.getDay() + 7 - (weekStartDay(weekStart) % 7)) % 7
}
function findHabit(state, id) {
  var habits = state && state.habits || []
  for (var i = 0; i < habits.length; i++) if (habits[i].id === id) return habits[i]
  return null
}
function isArchived(habit) {
  var periods = habit && habit.pauses || []
  return periods.length > 0 && !periods[periods.length - 1].to
}
function isPaused(habit, day) {
  return (habit.pauses || []).some(function(period) {
    return day >= period.from && (!period.to || day < period.to)
  })
}
function activeHabits(state) {
  return state.habits.filter(function(habit) { return !isArchived(habit) })
}
function throughDate(habit, today) {
  return habit && habit.endDate && habit.endDate < today ? habit.endDate : today
}
function isDue(habit, day) {
  return !!habit && !isArchived(habit) && day >= habit.startDate
    && (!habit.endDate || day <= habit.endDate) && !isPaused(habit, day)
}
function dateMetrics(habit, today) {
  if (!habit || !habit.endDate) return null
  var total = daysBetween(habit.startDate, habit.endDate) + 1
  return {
    total: total,
    elapsed: Math.min(total, Math.max(0, daysBetween(habit.startDate, today))),
    left: Math.max(0, daysBetween(today, habit.endDate)),
    dueToday: today === habit.endDate,
    ended: today > habit.endDate
  }
}
function validCount(value) {
  return Number.isInteger(value) && value >= 0 && value <= 1000000
}
function parseState(raw, fallbackDate) {
  var state = emptyState()
  var parsed
  try { parsed = JSON.parse(raw) } catch (error) { return state }
  if (!parsed || !Array.isArray(parsed.habits)) return state
  state.preferences.weekStart = weekStartDay(parsed.preferences && parsed.preferences.weekStart)
  var known = {}
  for (var i = 0; i < parsed.habits.length && i < 80; i++) {
    var h = parsed.habits[i]
    if (!h || !/^h[A-Za-z0-9]{1,63}$/.test(h.id) || known[h.id]) continue
    var isCount = h.kind === "count" && validCount(h.target) && h.target > 0
    var habit = {
      id: h.id,
      name: String(h.name || "").slice(0, 96),
      kind: isCount ? "count" : h.kind === "bad" ? "bad" : "good",
      startDate: validKey(h.startDate) ? h.startDate : (parsed.startDate || fallbackDate || todayKey()),
      question: String(h.question || "Did this behavior happen?").slice(0, 256),
      message: String(h.message || "").slice(0, 512),
      defaultAnswer: !isCount && (h.defaultAnswer === "yes" || h.defaultAnswer === "no") ? h.defaultAnswer : ""
    }
    if (isCount) {
      habit.target = h.target
      habit.unit = String(h.unit || "").slice(0, 32)
    }
    if (validKey(h.endDate) && h.endDate >= habit.startDate) habit.endDate = h.endDate
    if (Array.isArray(h.pauses)) habit.pauses = h.pauses.filter(function(p) {
      return p && validKey(p.from) && (p.to === "" || validKey(p.to) && p.to > p.from)
    })
    known[h.id] = habit
    state.habits.push(habit)
  }
  if (typeof parsed.selectedHabitId === "string" && known[parsed.selectedHabitId] && !isArchived(known[parsed.selectedHabitId]))
    state.selectedHabitId = parsed.selectedHabitId
  var entries = parsed.entries || {}
  var automatic = parsed.automatic || {}
  for (var day in entries) {
    if (!validKey(day) || !entries[day] || typeof entries[day] !== "object") continue
    for (var id in entries[day]) {
      var value = entries[day][id]
      if (!known[id] || !(known[id].kind === "count" ? validCount(value) : value === "yes" || value === "no")) continue
      if (!state.entries[day]) state.entries[day] = {}
      state.entries[day][id] = value
      if (known[id].kind !== "count" && automatic[day] && automatic[day][id] === true) {
        if (!state.automatic[day]) state.automatic[day] = {}
        state.automatic[day][id] = true
      }
    }
  }
  return state
}
function answerFor(state, day, id) {
  var value = state.entries && state.entries[day] && state.entries[day][id]
  return value === undefined || value === null ? "" : value
}
function successFor(kind, value) {
  return (value === "yes" || value === "no") && (kind === "bad" ? value === "no" : value === "yes")
}
function recordFor(state, habit, day, today) {
  if (!habit || day < habit.startDate) return { value: "", source: "before" }
  if (habit.endDate && day > habit.endDate) return { value: "", source: "after" }
  if (day > today) return { value: "", source: "future" }
  var value = answerFor(state, day, habit.id)
  if (value !== "") return {
    value: value,
    source: state.automatic && state.automatic[day] && state.automatic[day][habit.id] ? "automatic" : "manual"
  }
  if (isPaused(habit, day)) return { value: "", source: "paused" }
  if (day < today && habit.defaultAnswer) return { value: habit.defaultAnswer, source: "automatic" }
  return { value: "", source: "pending" }
}
function outcome(habit, record, day, today) {
  if (record.value === "" || !habit) return record.source
  if (habit.kind === "count") {
    if (record.value >= habit.target) return "success"
    return day === today ? "progress" : "failure"
  }
  return successFor(habit.kind, record.value) ? "success" : "failure"
}
function summaryForDay(state, day, today) {
  var summary = { total: 0, answered: 0, success: 0, failure: 0, progress: 0, pending: 0, perfect: false }
  today = today || todayKey()
  for (var i = 0; i < state.habits.length; i++) {
    var habit = state.habits[i]
    if (!isDue(habit, day) || day > today) continue
    summary.total++
    var record = recordFor(state, habit, day, today)
    if (record.value === "") {
      summary.pending++
      continue
    }
    summary.answered++
    var status = outcome(habit, record, day, today)
    if (status === "success") summary.success++
    else if (status === "failure") summary.failure++
    else if (status === "progress") summary.progress++
  }
  summary.perfect = summary.total > 0 && summary.success === summary.total
  return summary
}
function cellFor(state, habit, key, today) {
  var record = recordFor(state, habit, key, today)
  return {
    date: key, day: Number(key.slice(-2)), today: key === today, value: record.value,
    source: record.source, automatic: record.source === "automatic",
    selectable: key >= habit.startDate && key <= throughDate(habit, today) && !isPaused(habit, key),
    state: outcome(habit, record, key, today)
  }
}
function defaultPreview(state, habitId, start, today, answer, end) {
  if (end && end < today && validKey(end) && end >= start) today = addDays(end, 1)
  if (end && (!validKey(end) || end < start)) return 0
  if (!answer || !validKey(start) || start >= today) return 0
  var habit = findHabit(state, habitId)
  var count = daysBetween(start, today)
  var periods = habit && habit.pauses || []
  for (var i = 0; i < periods.length; i++) {
    var first = periods[i].from > start ? periods[i].from : start
    var stop = periods[i].to && periods[i].to < today ? periods[i].to : today
    if (stop > first) count -= daysBetween(first, stop)
  }
  for (var day in state.entries)
    if (day >= start && day < today && (!habit || !isPaused(habit, day)) && answerFor(state, day, habitId) !== "") count--
  return Math.max(0, count)
}
function monthGrid(habit, state, year, month, today) {
  if (!habit) return []
  return calendarDates(year, month, state.preferences && state.preferences.weekStart).map(function(date) {
    var cell = cellFor(state, habit, date.key, today)
    cell.inMonth = date.inMonth
    return cell
  })
}
function startOfWeek(day, weekStart) {
  return addDays(day, -weekOffset(dateFromKey(day), weekStart))
}
function weekGrid(habit, state, day, today) {
  if (!habit || !validKey(day)) return []
  var first = startOfWeek(day, state.preferences && state.preferences.weekStart)
  return Array.from({ length: 7 }, function(_, i) {
    var cell = cellFor(state, habit, addDays(first, i), today)
    cell.inMonth = true // The weekly view always shows all seven days.
    return cell
  })
}
function summarizeWeek(cells) {
  var summary = { success: 0, failure: 0, pending: 0 }
  cells.forEach(function(cell) {
    if (cell.state === "success") summary.success++
    else if (cell.state === "failure") summary.failure++
    else if (cell.state === "pending" || cell.state === "progress") summary.pending++
  })
  return summary
}
function barStatus(summary) {
  if (summary.perfect) return "success"
  if (summary.failure > 0) return "failure"
  if (summary.success > 0 || summary.progress > 0) return "progress"
  return "pending"
}
function luminance(color) {
  function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}
function contrast(a, b) {
  var first = luminance(a)
  var second = luminance(b)
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}
function paletteColor(status, background) {
  var dark = luminance(background) < 0.32
  if (status === "success") return dark ? "#81dda5" : "#12643d"
  if (status === "failure") return dark ? "#ffa0ac" : "#982438"
  if (status === "progress") return dark ? "#f3ca79" : "#794c00"
  if (status === "best") return dark ? "#b4c8ff" : "#304e9b"
  return ""
}
function calendarDates(year, month, weekStart) {
  var first = new Date(year, month, 1, 12)
  var firstCell = addDays(keyForDate(first), -weekOffset(first, weekStart))
  var cells = []
  for (var i = 0; i < 42; i++) {
    var key = addDays(firstCell, i)
    cells.push({ key: key, day: Number(key.slice(-2)), inMonth: dateFromKey(key).getMonth() === month })
  }
  return cells
}
function heatmapWeeks(habit, state, today, count) {
  var date = dateFromKey(today)
  var firstCell = addDays(today, -(count - 1) * 7 - weekOffset(date, state.preferences && state.preferences.weekStart))
  var weeks = []
  for (var w = 0; w < count; w++) {
    var row = []
    for (var d = 0; d < 7; d++) row.push(cellFor(state, habit, addDays(firstCell, w * 7 + d), today))
    weeks.push(row)
  }
  return weeks
}
function yearMonths(habit, state, year, today) {
  if (!habit) return []
  var months = []
  for (var month = 0; month < 12; month++) {
    var first = keyForDate(new Date(year, month, 1, 12))
    var last = keyForDate(new Date(year, month + 1, 0, 12))
    var cells = monthGrid(habit, state, year, month, today)
    var successes = 0
    var recorded = 0
    for (var i = 0; i < cells.length; i++) {
      if (!cells[i].inMonth) continue
      if (cells[i].state === "success") successes++
      if (cells[i].state === "success" || cells[i].state === "failure") recorded++
    }
    months.push({ month: month, first: first, cells: cells, success: successes, recorded: recorded,
      available: first <= throughDate(habit, today) && last >= habit.startDate })
  }
  return months
}
function analyzeHabit(habit, state, today) {
  var through = throughDate(habit, today)
  var days = enumerateDays(habit.startDate, through)
  var stats = {
    id: habit.id, name: habit.name, kind: habit.kind, trackedDays: days.length,
    answered: 0, successCount: 0, failureCount: 0, manualCount: 0, automaticCount: 0,
    currentStreak: 0, bestStreak: 0, recoveries: 0, averageRecoveryDays: 0,
    pendingRecovery: false, recoverySince: "", latestRecovery: null,
    rate: 0, weekRate: 0, weekAnswered: 0, weekSuccess: 0,
    monthRate: 0, monthAnswered: 0, monthSuccess: 0
  }
  var run = 0, episode = "", recoveryDays = 0, weekSuccess = 0, monthSuccess = 0
  var weekStart = addDays(through, -6), monthStart = addDays(through, -29)
  for (var i = 0; i < days.length; i++) {
    var day = days[i]
    var record = recordFor(state, habit, day, today)
    var status = outcome(habit, record, day, today)
    if (status === "paused" || status === "progress") continue
    if (record.value === "") { run = 0; continue }
    stats.answered++
    if (record.source === "automatic") stats.automaticCount++
    else stats.manualCount++
    var success = status === "success"
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
  var end = through
  var current = outcome(habit, recordFor(state, habit, end, today), end, today)
  if (end === today && (current === "pending" || current === "progress")) end = addDays(end, -1)
  for (var key = end; key >= habit.startDate; key = addDays(key, -1)) {
    var dayState = outcome(habit, recordFor(state, habit, key, today), key, today)
    if (dayState === "paused") continue
    if (dayState !== "success") break
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
  addDays: addDays, daysBetween: daysBetween, dateParts: dateParts, dateLimits: dateLimits, changeDatePart: changeDatePart,
  emptyState: emptyState, weekStartDay: weekStartDay, orderedWeekdays: orderedWeekdays, parseState: parseState, findHabit: findHabit,
  answerFor: answerFor, successFor: successFor, recordFor: recordFor, outcome: outcome,
  isArchived: isArchived, isPaused: isPaused, activeHabits: activeHabits, validCount: validCount,
  isDue: isDue, throughDate: throughDate, dateMetrics: dateMetrics,
  summaryForDay: summaryForDay, defaultPreview: defaultPreview, monthGrid: monthGrid, calendarDates: calendarDates,
  heatmapWeeks: heatmapWeeks, yearMonths: yearMonths, startOfWeek: startOfWeek, weekGrid: weekGrid, summarizeWeek: summarizeWeek,
  barStatus: barStatus, luminance: luminance, contrast: contrast, paletteColor: paletteColor,
  analyzeHabit: analyzeHabit, analyze: analyze
}
