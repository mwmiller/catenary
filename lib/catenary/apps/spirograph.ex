defmodule Catenary.Apps.Spirograph do
  @moduledoc """
  The repo's worked example: a spirograph you can tweak with a finger
  and post to your own channel, written in the DSL the playground
  compiles.

  Paste `source/0` into the playground buffer and press Run — the
  server compiles it to wasm with no toolchain of your own — then the
  ⇪ panel releases it as an app. The test suite keeps the promise:
  `Catenary.Apps.SpirographTest` compiles this exact string and hands
  it to Watusi on every run, so the example here cannot drift away
  from the language.

  The design is worth a paragraph of its own, because the DSL hands
  the program no memory between messages: every handler rebuilds what
  it needs. `on init` opens the channel; `on data("feed", …)` paints
  the newest posted pattern (or the first built-in when the channel
  is empty or holds something unreadable); `on ui` reads one gesture
  in full — a swatch tap draws a built-in, a drag turns the touch
  point into wheel and pen distances, the chip asks storage what was
  last drawn and posts it; `on data("keep", …)` answers that ask.
  The channel every installation derives from the app's own name is
  what makes a pattern one person finds worth posting appear the next
  time anyone opens the app.
  """

  @source """
  # Spirograph — a hypotrochoid you can play with, then pass around.
  #
  # A wheel of radius rad rolling inside a ring of radius R leaves a
  # pen point, d away from the wheel's centre, on the curve
  #
  #   x = (R - rad)*cos t + d*cos((R - rad)/rad * t)
  #   y = (R - rad)*sin t - d*sin((R - rad)/rad * t)
  #
  # and sweeping t a few turns paints the rosette. Handlers hold no
  # state between messages — the arena resets every turn — so each
  # one rebuilds what it needs. The bottom strip shows six patterns:
  # tap a cell's top to draw it, its bottom to post those settings
  # outright. Drag above the strip to tweak the pen live; release to
  # keep that look, and the share chip posts it through storage.
  # Every installation reads the same channel back on open, so a
  # pattern worth posting appears the next time anyone opens the app.

  on init:
    print("spirograph: tap a swatch, drag to tweak, share to post")
    want "feed" = channel(limit: 5)

  # The feed answers with a page of rows, newest first; each row's
  # payload is a publish's arguments, CBOR-encoded on the way out.
  # Rows that do not read as one of ours fall back to the first
  # preset, so a stranger's entry paints a picture rather than a
  # hole. The posted colour is deliberately ignored — one malformed
  # string would take the whole draw with it — the adopted curve
  # wears this app's own violet. Posts carry their pattern's name as
  # `title`, the channel's own display key, so one field both labels
  # the rail and names the curve — and it is joined onto "" first:
  # that renders any value as text, so no type can reach the view.
  on data("feed", page):
    let f = decode(get(get(page, 0), "payload"))
    let ok = get(f, "type") == "spiro" and get(f, "R") > 0 and get(f, "r") > 0 and get(f, "d") > 0 and get(f, "laps") > 0
    let R = 105
    let rad = 30
    let pen = 60
    let laps = 2
    let hue = "#38bdf8"
    let nm = "comet"
    if ok:
      R = get(f, "R")
      rad = get(f, "r")
      pen = get(f, "d")
      laps = min(get(f, "laps"), 10)
      hue = "#a78bfa"
      nm = "" + get(f, "title")
      if nm == "null":
        nm = "shared"
    let gap = R - rad
    let k = gap / rad
    let n = 240 * laps
    let s = 84 / (gap + pen)
    let step = pi() / 120
    let pts = []
    repeat 4096 times(j):
      if j < n:
        let th = j * step
        pts = push(pts, [120 + s * (gap * cos(th) + pen * cos(k * th)), 92 + s * (gap * sin(th) - pen * sin(k * th))])
    render(col(text(nm), row(text("drag to tweak"), text("swatch top draws, bottom posts")), canvas(240, 240)))
    draw[
      stroke_path(pts: pts, lw: 1.5, c: hue),
      fill_rect(x: 184, y: 156, w: 52, h: 28, c: "#334155"),
      text(s: "share", x: 189, y: 175, size: 12, c: "#e2e8f0"),
      fill_rect(x: 0, y: 184, w: 240, h: 28, c: "#0f172a"),
      fill_rect(x: 0, y: 184, w: 40, h: 28, c: "#38bdf8"),
      text(s: "comet", x: 4, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 0, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 10, y: 230, size: 8, c: "#e2e8f0"),
      fill_rect(x: 40, y: 184, w: 40, h: 28, c: "#f472b6"),
      text(s: "petal", x: 44, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 40, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 50, y: 230, size: 8, c: "#e2e8f0"),
      fill_rect(x: 80, y: 184, w: 40, h: 28, c: "#facc15"),
      text(s: "sun", x: 84, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 80, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 90, y: 230, size: 8, c: "#e2e8f0"),
      fill_rect(x: 120, y: 184, w: 40, h: 28, c: "#4ade80"),
      text(s: "clover", x: 123, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 120, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 130, y: 230, size: 8, c: "#e2e8f0"),
      fill_rect(x: 160, y: 184, w: 40, h: 28, c: "#c084fc"),
      text(s: "plum", x: 164, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 160, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 170, y: 230, size: 8, c: "#e2e8f0"),
      fill_rect(x: 200, y: 184, w: 40, h: 28, c: "#22d3ee"),
      text(s: "ring", x: 204, y: 202, size: 8, c: "#0f172a"),
      fill_rect(x: 200, y: 212, w: 40, h: 28, c: "#1e293b"),
      text(s: "post", x: 210, y: 230, size: 8, c: "#e2e8f0")
    ]

  # Storage answers under this one label in two shapes: a save replies
  # with the word "stored", a load replies the value itself. Only a
  # value shaped like a preset — three positive numbers leading —
  # earns a publish; the save ack falls silent, so remembering a look
  # never posts it by itself. A chip tap before anything is stored
  # misses storage and arrives on err instead, which is an answer
  # too.
  on data("keep", v):
    let R = get(v, 0)
    if R > 0 and get(v, 1) > 0 and get(v, 2) > 0:
      publish(type: "spiro", R: R, r: get(v, 1), d: get(v, 2), laps: get(v, 3), c: get(v, 4), title: get(v, 5))

  # One handler reads the whole gesture. The chip asks storage what
  # was last drawn; the strip's lower half posts the cell it names
  # outright; its upper half draws that cell and remembers it; and
  # anything above the strip turns the touch point into wheel and pen
  # distances — drag for a live tweak, release to keep the last look
  # for the share chip. The cell colours and names below must match
  # the presets in this list and the swatch drawn by the two draw
  # blocks: the DSL has no functions, so the three copies live
  # together or not at all.
  on ui(e):
    let kind = get(e, "type")
    let x = get(e, "x")
    let y = get(e, "y")
    let slot = min(floor(x / 40), 5)
    let presets = [
      [105, 30, 60, 2, "#38bdf8", "comet"],
      [96, 36, 72, 3, "#f472b6", "petal"],
      [100, 25, 80, 1, "#facc15", "sun"],
      [90, 15, 45, 1, "#4ade80", "clover"],
      [105, 42, 63, 2, "#c084fc", "plum"],
      [104, 13, 52, 1, "#22d3ee", "ring"]
    ]
    let paint = false
    let keep = false
    let R = 0
    let rad = 0
    let pen = 0
    let laps = 0
    let hue = ""
    let nm = ""
    # The four regions never overlap, so each is its own if rather
    # than an else chain: the chip and the curve split y 156..184 by
    # x, the strip splits its cells by y, and a cell's two halves
    # share only the cell column.
    if x >= 184 and x < 236 and y >= 156 and y < 184 and kind == "down":
      want "keep" = storage_get(key: "shown")
    if y >= 212 and kind == "down":
      let p = get(presets, slot)
      publish(type: "spiro", R: get(p, 0), r: get(p, 1), d: get(p, 2), laps: get(p, 3), c: get(p, 4), title: get(p, 5))
    if y >= 184 and y < 212 and kind == "down":
      let p = get(presets, slot)
      R = get(p, 0)
      rad = get(p, 1)
      pen = get(p, 2)
      laps = get(p, 3)
      hue = get(p, 4)
      nm = get(p, 5)
      paint = true
      keep = true
    if (x < 184 or y < 156) and y < 184 and (kind == "down" or kind == "move" or kind == "up"):
      R = 105
      rad = 12 + x * 0.15
      pen = 16 + y * 0.45
      laps = 4
      hue = "#a78bfa"
      nm = "tweak"
      paint = true
      if kind == "up":
        keep = true
    if paint:
      let gap = R - rad
      let k = gap / rad
      let n = 240 * laps
      let s = 84 / (gap + pen)
      let step = pi() / 120
      let pts = []
      repeat 4096 times(j):
        if j < n:
          let th = j * step
          pts = push(pts, [120 + s * (gap * cos(th) + pen * cos(k * th)), 92 + s * (gap * sin(th) - pen * sin(k * th))])
      render(col(text(nm), row(text("drag to tweak"), text("swatch top draws, bottom posts")), canvas(240, 240)))
      draw[
        stroke_path(pts: pts, lw: 1.5, c: hue),
        fill_rect(x: 184, y: 156, w: 52, h: 28, c: "#334155"),
        text(s: "share", x: 189, y: 175, size: 12, c: "#e2e8f0"),
        fill_rect(x: 0, y: 184, w: 240, h: 28, c: "#0f172a"),
        fill_rect(x: 0, y: 184, w: 40, h: 28, c: "#38bdf8"),
        text(s: "comet", x: 4, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 0, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 10, y: 230, size: 8, c: "#e2e8f0"),
        fill_rect(x: 40, y: 184, w: 40, h: 28, c: "#f472b6"),
        text(s: "petal", x: 44, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 40, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 50, y: 230, size: 8, c: "#e2e8f0"),
        fill_rect(x: 80, y: 184, w: 40, h: 28, c: "#facc15"),
        text(s: "sun", x: 84, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 80, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 90, y: 230, size: 8, c: "#e2e8f0"),
        fill_rect(x: 120, y: 184, w: 40, h: 28, c: "#4ade80"),
        text(s: "clover", x: 123, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 120, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 130, y: 230, size: 8, c: "#e2e8f0"),
        fill_rect(x: 160, y: 184, w: 40, h: 28, c: "#c084fc"),
        text(s: "plum", x: 164, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 160, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 170, y: 230, size: 8, c: "#e2e8f0"),
        fill_rect(x: 200, y: 184, w: 40, h: 28, c: "#22d3ee"),
        text(s: "ring", x: 204, y: 202, size: 8, c: "#0f172a"),
        fill_rect(x: 200, y: 212, w: 40, h: 28, c: "#1e293b"),
        text(s: "post", x: 210, y: 230, size: 8, c: "#e2e8f0")
      ]
    if keep:
      want "keep" = storage_set(key: "shown", value: [R, rad, pen, laps, hue, nm])

  on err(m):
    print("host: " + m)
  """

  @doc """
  The DSL source for the spirograph example, ready for the playground
  buffer.
  """
  @spec source() :: String.t()
  def source, do: @source
end
