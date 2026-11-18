
/// Build a date, filling missing fields from `base` and then from today.
///
/// - d (datetime, dictionary): A date, or a dictionary with any of `day`, `month`, `year`.
/// - base (dictionary): Fallback fields used before today's date.
/// -> datetime
#let default-date(d, base: (:)) = {
  if type(d) == datetime {
    return d
  }
  assert(type(d) == dictionary, message: "date must be a datetime or a dictionary")

  let now = datetime.today()
  let day-arg = d.at("day", default: base.at("day", default: now.day()))
  let month-arg = d.at("month", default: base.at("month", default: now.month()))
  let year-arg = d.at("year", default: base.at("year", default: now.year()))

  return datetime(year: year-arg, month: month-arg, day: day-arg)
}

/// Number of days in the month of the given date.
///
/// - date-like (datetime, dictionary): Any date accepted by `default-date`.
/// -> int
#let month-length(date-like) = {
  let date = default-date(date-like)

  let m = date.month()
  let y = date.year()

  // last day of the month = day before the first of the next one
  let next = if m == 12 {
    datetime(year: y + 1, month: 1, day: 1)
  } else {
    datetime(year: y, month: m + 1, day: 1)
  }

  return (next - duration(days: 1)).day()
}

/// Keep the marks and spans of a calendar that match every given condition.
///
/// Spans are kept when they overlap the date range. Dates accept the same
/// dictionaries as `mark`, with missing fields filled from the calendar default.
/// The result is a calendar, sorted by date, usable by any view or filtered again.
///
/// - cal (dictionary): Calendar created by `calendar`.
/// - after (datetime, dictionary, none): Keep events on or after this date.
/// - before (datetime, dictionary, none): Keep events on or before this date.
/// - between (array, none): Pair of dates, both ends inclusive.
/// - kind (str, array, none): Keep events of this kind, or of any of these kinds.
/// - month (int, none): Keep events overlapping this month.
/// - year (int, none): Keep events overlapping this year, or the month's year.
/// - where (function, none): Custom predicate, called as `(event) => bool`.
/// -> dictionary
#let filter-events(
  cal,
  after: none,
  before: none,
  between: none,
  kind: none,
  month: none,
  year: none,
  where: none,
) = {
  assert(between == none or (type(between) == array and between.len() == 2),
    message: "between must be a pair of dates")
  assert(kind == none or type(kind) in (str, array), message: "kind must be a string or an array")
  assert(where == none or type(where) == function, message: "where must be a function or none")

  let base = cal.default-date

  // collect (start, end) windows, either end may be none
  let windows = ()
  if after != none { windows.push((default-date(after, base: base), none)) }
  if before != none { windows.push((none, default-date(before, base: base))) }
  if between != none {
    windows.push((default-date(between.at(0), base: base), default-date(between.at(1), base: base)))
  }
  if month != none or year != none {
    let y = if year != none { year } else { base.at("year", default: datetime.today().year()) }
    if month != none {
      let first = datetime(year: y, month: month, day: 1)
      windows.push((first, datetime(year: y, month: month, day: month-length(first))))
    } else {
      windows.push((datetime(year: y, month: 1, day: 1), datetime(year: y, month: 12, day: 31)))
    }
  }

  // intersect them into a single [lo, hi] window
  let starts = windows.map(w => w.at(0)).filter(d => d != none)
  let ends = windows.map(w => w.at(1)).filter(d => d != none)
  let lo = if starts.len() > 0 { starts.sorted().last() } else { none }
  let hi = if ends.len() > 0 { ends.sorted().first() } else { none }

  let kinds = if type(kind) == str { (kind,) } else { kind }

  let keep(start, end, e) = (
    (lo == none or end >= lo)
      and (hi == none or start <= hi)
      and (kinds == none or e.kind in kinds)
      and (where == none or where(e))
  )

  return (
    ..cal,
    marks: cal.marks.filter(m => keep(m.date, m.date, m)).sorted(key: m => m.date),
    spans: cal.spans.filter(s => keep(s.start, s.end, s)).sorted(key: s => s.start),
  )
}

#let default-weekday-names = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")

/// Draw the weeks of a month as a grid.
///
/// Every option can be preset with `month-weeks.with(..)`.
///
/// - cal (dictionary): Calendar created by `calendar`.
/// - month (int, none): Month to draw, defaults to the calendar default or today.
/// - year (int, none): Year to draw, defaults to the calendar default or today.
/// - week-height (length, auto): Height of each week row. A fixed length keeps
///   rows even regardless of how many marks a day has.
/// - mark-radius (length): Radius of the default mark dot.
/// - mark-fill (color): Fill of the default mark dot.
/// - span-stroke (stroke): Stroke of the bar drawn under days inside a span.
/// - off-month-fill (color): Text color of days outside the month.
/// - max-marks (int, none): Dots shown per day by the default marks renderer;
///   the rest are summarized as `+n`. `none` shows all.
/// - marks-grid-args (dictionary, function): Arguments merged into the grid
///   holding the dots. A function receives the number of dots and returns
///   the dictionary.
/// - render-marks (function, none): Replaces the marks block entirely, called
///   as `(dots, events, args) => content` where `args` are the merged grid
///   arguments. Takes precedence over `max-marks` and `marks-grid-args`.
/// - weekday-names (array): Seven header names, always starting on sunday.
/// - first-weekday (int): Weekday of the first column, 0 is sunday and 1 is monday.
/// - render-header (function, none): Replaces each header cell, called as
///   `(index, name) => content` where index 0 is sunday. When every cell
///   returns `none` the header row is dropped.
/// - grid-args (dictionary): Arguments merged into the outer month grid,
///   e.g. `stroke`, `inset`, `gutter`, `fill`. `columns` is always 7.
/// -> content
#let month-weeks(
  cal,
  month: none,
  year: none,
  week-height: 3.2em,
  mark-radius: 0.1em,
  mark-fill: black,
  span-stroke: 0.15em + black,
  off-month-fill: gray,
  max-marks: 6,
  marks-grid-args: (:),
  render-marks: none,
  weekday-names: default-weekday-names,
  first-weekday: 0,
  render-header: none,
  grid-args: (:),
) = {
  import calc: *

  assert(type(grid-args) == dictionary, message: "grid-args must be a dictionary")
  assert("columns" not in grid-args, message: "grid-args cannot set columns, the month grid always has 7")
  assert(type(marks-grid-args) in (dictionary, function), message: "marks-grid-args must be a dictionary or a function")
  assert(render-marks == none or type(render-marks) == function, message: "render-marks must be a function or none")
  assert(
    type(weekday-names) == array and weekday-names.len() == 7,
    message: "weekday-names must be an array of 7 names, starting on sunday",
  )
  assert(first-weekday in range(7), message: "first-weekday must be an int from 0 (sunday) to 6 (saturday)")
  assert(render-header == none or type(render-header) == function, message: "render-header must be a function or none")

  let date = (:)
  if month != none {
    date.insert("month", month)
  }
  if year != none {
    date.insert("year", year)
  }
  date.insert("day", 1)

  date = default-date(date, base: cal.default-date)

  let n = month-length(date)
  let prev-n = month-length(date - duration(days: 1))

  // weekday() is 1 (mon) .. 7 (sun); shift so the first column is first-weekday
  let week-start = rem(rem(date.weekday(), 7) - first-weekday + 7, 7)

  let this-month = filter-events(cal, month: date.month(), year: date.year())
  let this-annotations = (:)

  // separate annotations by date
  for a in this-month.marks {
    {
      let key = str(a.date.day())

      let existing = this-annotations.at(key, default: ())
      existing.push(a)
      this-annotations.insert(key, existing)
    }
  }

  // spans covering each day of the month
  let this-spans = (:)
  for s in this-month.spans {
    for day in range(1, n + 1) {
      let d = datetime(year: date.year(), month: date.month(), day: day)
      if s.start <= d and d <= s.end {
        let key = str(day)
        let existing = this-spans.at(key, default: ())
        existing.push(s)
        this-spans.insert(key, existing)
      }
    }
  }

  // lay out the dots of one day
  let draw-marks = events => {
    let dots = events.map(e => circle(radius: mark-radius, fill: mark-fill))
    if dots.len() == 0 and render-marks == none {
      return none
    }

    let user-args = if type(marks-grid-args) == function {
      marks-grid-args(dots.len())
    } else {
      marks-grid-args
    }

    let grid-args = (columns: max(1, min(3, dots.len())), gutter: 0.1em)
    if "rows" in user-args and "columns" not in user-args {
      let _ = grid-args.remove("columns")
    }
    grid-args = grid-args + user-args

    if render-marks != none {
      return align(center, render-marks(dots, events, grid-args))
    }

    let shown = dots
    let extra = none
    if max-marks != none and dots.len() > max-marks {
      shown = dots.slice(0, max-marks - 1)
      extra = text(size: 0.5em)[+#(dots.len() - max-marks + 1)]
    }
    if extra != none {
      shown.push(extra)
    }

    align(center, grid(align: left + horizon, ..grid-args, ..shown))
  }

  // draw annotations for a day
  let draw-cell = (annotations, spans) => day => {
    let bars = spans.at(str(day), default: ()).map(s => line(length: 1.2em, stroke: span-stroke))

    stack(dir: ttb, spacing: 0.15em, align(center)[#day], draw-marks(annotations.at(str(day), default: ())), ..bars)
  }

  let in-month-day-cell = content => text(fill: black)[#content]
  let off-month-day-cell = content => text(fill: off-month-fill)[#content]

  let cal-days = ()
  cal-days = cal-days + range(prev-n - week-start + 1, prev-n + 1).map(draw-cell((:), (:))).map(off-month-day-cell)

  cal-days = cal-days + range(1, n + 1).map(draw-cell(this-annotations, this-spans)).map(in-month-day-cell)

  let trailing = rem(7 - rem(week-start + n, 7), 7)
  cal-days = cal-days + range(1, trailing + 1).map(draw-cell((:), (:))).map(off-month-day-cell)

  // get header, rotated to start on first-weekday
  let draw-header = if render-header != none {
    render-header
  } else {
    (i, name) => pad(bottom: 0.6em)[#name]
  }
  let header = range(7).map(k => rem(first-weekday + k, 7)).map(i => draw-header(i, weekday-names.at(i)))

  let header-rows = ()
  if header.any(h => h != none) {
    header-rows = (auto,)
  } else {
    header = ()
  }
  let cal-cells = header + cal-days

  let weeks = int(cal-days.len() / 7)
  let month-grid-args = (
    rows: header-rows + (week-height,) * weeks,
    align: center + top,
    inset: 0.5em,
  ) + grid-args

  grid(columns: 7, ..month-grid-args, ..cal-cells)
}

/// Mark a single day.
///
/// - date (datetime, dictionary): Missing fields come from the calendar default.
/// - label (str): Description of the mark.
/// - kind (str, none): Free category, useful in `render-marks`.
/// -> array
#let mark(date, label: "", kind: none) = (
  (type: "mark", date: date, label: label, kind: kind),
)

/// Mark a span of days, both ends inclusive.
///
/// - start (datetime, dictionary): First day of the span.
/// - end (datetime, dictionary): Last day of the span.
/// - label (str): Description of the span.
/// - kind (str, none): Free category.
/// -> array
#let span(start, end, label: "", kind: none) = (
  (type: "span", start: start, end: end, label: label, kind: kind),
)

/// Create calendar data from entries produced by `mark` and `span`.
///
/// - ..args (arguments): Positional arrays of entries; named `default`
///   (dictionary) fills missing date fields.
/// -> dictionary
#let calendar(..args) = {
  let base = args.named().at("default", default: (:))
  let data = (marks: (), spans: ())

  for entries in args.pos() {
    for e in entries {
      if e.type == "mark" {
        data.marks.push((..e, date: default-date(e.date, base: base)))
      } else if e.type == "span" {
        data.spans.push((
          ..e,
          start: default-date(e.start, base: base),
          end: default-date(e.end, base: base),
        ))
      }
    }
  }

  data.default-date = base

  return data
}
