// One png per section with only the calendars, for the README:
//   typst compile --input split=true usage.typ docs/usage-{0p}.png --ppi 144
// The sections' code, as json:
//   typst eval 'query(<sample>).map(m => m.value)' --in usage.typ --format json

#import "./calendar.typ": calendar, mark, span, month-weeks, filter-events

#let split = sys.inputs.at("split", default: "false") == "true"

#set page(width: 21cm, height: auto, margin: 1.5cm)

#show raw.where(block: true): it => block(
    width: 100%, fill: luma(245), inset: 0.6em, radius: 3pt,
    text(size: 0.75em, it),
)

// Library functions every snippet can use, as if imported once.
#let library = (
    calendar: calendar,
    mark: mark,
    span: span,
    month-weeks: month-weeks,
    filter-events: filter-events,
)

// Evaluate a snippet `(title, code, ..names)` and return its rendered
// body plus the variables it defines, listed in `names`.
#let run(entry, scope) = {
    let (title, code, ..names) = entry
    let export = "\n#metadata((" + names.map(n => n + ": " + n + ",").join() + "))"
    let body = eval(code.text + export, mode: "markup", scope: scope)

    let find(it) = {
        if type(it) != content { return none }
        if it.func() == metadata { return it.value }
        for child in it.at("children", default: ()) {
            let found = find(child)
            if found != none { return found }
        }
        none
    }
    let defs = if names.len() > 0 { find(body) } else { (:) }

    (body, defs)
}

// Each row shows one feature through two snippets, each rendered above its
// verbatim code. When split, only the rendered calendars are kept.
#let sample(feature, left, right, scope) = {
    let draw(entry) = {
        block(text(size: 0.8em, fill: luma(90), entry.at(0)))
        run(entry, scope).at(0)
    }

    [#metadata((
        feature: feature,
        left: (title: left.at(0), code: left.at(1).text),
        right: (title: right.at(0), code: right.at(1).text),
    )) <sample>]

    block(breakable: false, {
        if not split { text(weight: "bold", feature) }
        grid(columns: (1fr, 1fr), column-gutter: 1cm, row-gutter: 0.6em,
            draw(left), draw(right),
            ..if not split { (left.at(1), right.at(1)) },
        )
    })
    if split {
        pagebreak(weak: true)
    } else {
        line(length: 100%, stroke: 0.5pt + luma(200))
    }
}

// Setup snippets: they define c1 .. c4 and colors for the sections below.

#let marks-and-spans = ("Marks and spans", ```typ
#import "calendar.typ": calendar, mark, span, month-weeks
#let c1 = calendar({
  mark((day: 3), label: "Exam")
  mark((day: 9), label: "Dentist")
  span((day: 25), (day: 28), label: "Trip")
}, default: (year: 2024, month: 4))
#month-weeks(c1)
```, "c1")

#let with-loops = ("Generated with loops", ```typ
#let c2 = calendar({
  for i in range(5) { mark((day: 14), label: "Meeting") }
  for i in range(12) { mark((day: 22), label: "Task") }
  span((day: 8), (day: 10), label: "Sprint")
}, default: (year: 2024, month: 4))
#month-weeks(c2)
```, "c2")

#let with-kinds = ("Kinds, and colors for them", ```typ
#let colors = (school: blue, health: green, work: orange)
#let c3 = calendar({
  mark((day: 3), label: "Exam", kind: "school")
  mark((day: 9), label: "Dentist", kind: "health")
  for _ in range(4) { mark((day: 14), kind: "work") }
  for _ in range(8) { mark((day: 22), kind: "work") }
  mark((day: 22), label: "Checkup", kind: "health")
  span((day: 25), (day: 28), label: "Trip")
}, default: (year: 2024, month: 4))
#month-weeks(c3)
```, "c3", "colors")

#let from-data = ("From a list of data", ```typ
#let birthdays = ((6, "Ana"), (20, "Bruno"))
#let c4 = calendar({
  for (d, who) in birthdays {
    mark((day: d), label: who)
  }
  span((day: 13), (day: 17), label: "Conference")
}, default: (year: 2024, month: 5))
#month-weeks(c4)
```, "c4")

#sample("Creating a calendar", marks-and-spans, with-loops, library)
#sample("Kinds and external data", with-kinds, from-data, library)

#let scope = library
#for entry in (marks-and-spans, with-loops, with-kinds, from-data) {
    scope += run(entry, library).at(1)
}

// Feature sections, using c1 .. c4 from above.

#sample("Presets with .with",
    ("House style", ```typ
#let view = month-weeks.with(
  mark-fill: purple,
  span-stroke: 0.2em + teal,
)
#view(c3)
```),
    ("Minimal: hide other months", ```typ
#let view = month-weeks.with(
  off-month-fill: white,
  mark-fill: luma(150),
)
#view(c1)
```),
    scope,
)

#sample("week-height",
    ("Rows fit their content", ```typ
#month-weeks(c2, week-height: auto)
```),
    ("Compact rows, fewer dots", ```typ
#month-weeks(c2, week-height: 2.2em, max-marks: 3)
```),
    scope,
)

#sample("marks-grid-args",
    ("Dots in one row", ```typ
#month-weeks(c2, max-marks: 5,
  marks-grid-args: n => (columns: calc.min(n, 5)))
```),
    ("Dots in a column", ```typ
#month-weeks(c2, max-marks: 3,
  marks-grid-args: (columns: 1))
```),
    scope,
)

#sample("render-marks: drawing from event data",
    ("Colored by kind", ```typ
#let dot(e) = circle(
  radius: 0.12em, fill: colors.at(e.kind))
#month-weeks(c3, render-marks: (dots, events, args) => {
  let shown = events.slice(0, calc.min(6, events.len()))
  grid(..args, ..shown.map(dot))
})
```),
    ("First event label", ```typ
#month-weeks(c4, render-marks: (dots, events, args) => {
  if events.len() > 0 {
    text(size: 0.45em, events.first().label)
  }
})
```),
    scope,
)

#sample("render-marks: summarizing a day",
    ("Count badge", ```typ
#month-weeks(c2, render-marks: (dots, events, args) => {
  if events.len() > 0 {
    box(fill: black, inset: 0.15em, radius: 0.5em,
      text(fill: white, size: 0.6em)[#events.len()])
  }
})
```),
    ("Busyness bar", ```typ
#month-weeks(c2, render-marks: (dots, events, args) => {
  let n = calc.min(events.len(), 8)
  rect(width: n * 0.2em, height: 0.2em, fill: orange)
})
```),
    scope,
)

#sample("weekday-names and first-weekday",
    ("Portuguese, monday first", ```typ
#let pt = ("dom", "seg", "ter", "qua",
  "qui", "sex", "sab")
#month-weeks(c1, weekday-names: pt, first-weekday: 1)
```),
    ("Single letters", ```typ
#month-weeks(c1,
  weekday-names: ("S", "M", "T", "W", "T", "F", "S"))
```),
    scope,
)

#sample("render-header",
    ("Red weekends", ```typ
#month-weeks(c1, render-header: (i, name) => {
  let fill = if i in (0, 6) { red } else { black }
  pad(bottom: 0.6em, text(fill: fill, upper(name)))
})
```),
    ("No header", ```typ
#month-weeks(c1, render-header: (i, name) => none)
```),
    scope,
)

#sample("grid-args",
    ("Bordered table", ```typ
#month-weeks(c1, grid-args: (
  stroke: 0.5pt + luma(180),
  fill: (x, y) => if y == 0 { luma(235) },
))
```),
    ("Shaded weekends", ```typ
#month-weeks(c4, grid-args: (
  fill: (x, y) => if x in (0, 6) { luma(240) },
))
```),
    scope,
)

#sample("month and year",
    ("Leap february", ```typ
#month-weeks(c1, month: 2)
```),
    ("Next year's february", ```typ
#month-weeks(c1, month: 2, year: 2025)
```),
    scope,
)

#sample("filter-events",
    ("Only work events", ```typ
#month-weeks(filter-events(c3, kind: "work"))
```),
    ("From the 10th to the 25th", ```typ
#month-weeks(filter-events(c3,
  between: ((day: 10), (day: 25))))
```),
    scope,
)

#sample("Other views from the same data",
    ("Agenda with a loop", ```typ
#let april = filter-events(c3,
  where: e => e.kind != "work")
#for m in april.marks [
  #m.date.display("[day]") #m.label \
]
#for s in april.spans [
  #s.start.display("[day]")–#s.end.display("[day]")
  #s.label \
]
```),
    ("Events per kind", ```typ
#for k in colors.keys() [
  #text(fill: colors.at(k), k):
  #filter-events(c3, kind: k).marks.len() \
]
```),
    scope,
)
