#let cubic-bezier(x1, y1, x2, y2) = {
  return t => {
    if t <= 0 { return 0.0 }
    if t >= 1 { return 1.0 }

    let sample-bezier(p1, p2, u) = {
      return 3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u
    }

    let sample-derivative(p1, p2, u) = {
      return 3 * (1 - u) * (1 - u) * p1 + 6 * (1 - u) * u * (p2 - p1) + 3 * u * u * (1 - p2)
    }

    let u = t
    let i = 0
    while i < 8 {
      let current-x = sample-bezier(x1, x2, u) - t
      let slope = sample-derivative(x1, x2, u)

      if calc.abs(slope) < 0.000001 { break }

      u = u - current-x / slope
      i = i + 1
    }

    return sample-bezier(y1, y2, u)
  }
}

#let linear(..points) = {
  let pos-args = points.pos()
  let parsed-points = ()
  let n = pos-args.len()

  for i in range(n) {
    let arg = pos-args.at(i)
    let val = 0.0
    let pct = none

    if type(arg) == array {
      val = float(arg.at(0))
      pct = float(arg.at(1))
    } else {
      val = float(arg)
      if i == 0 { pct = 0.0 }
      if i == n - 1 { pct = 1.0 }
    }

    parsed-points.push((time: pct, value: val))
  }

  for i in range(parsed-points.len()) {
    if parsed-points.at(i).time == none {
      let next-known-idx = i
      while parsed-points.at(next-known-idx).time == none { next-known-idx += 1 }

      let prev-known-idx = i - 1
      while parsed-points.at(prev-known-idx).time == none { prev-known-idx -= 1 }

      let prev-t = parsed-points.at(prev-known-idx).time
      let next-t = parsed-points.at(next-known-idx).time
      let segments = next-known-idx - prev-known-idx

      parsed-points.at(i).time = (
        prev-t + (next-t - prev-t) * ((i - prev-known-idx) / segments)
      )
    }
  }

  return t => {
    if t <= 0 { return parsed-points.first().value }
    if t >= 1 { return parsed-points.last().value }

    let i = 0
    while i < parsed-points.len() - 1 {
      let p-current = parsed-points.at(i)
      let p-next = parsed-points.at(i + 1)

      if t >= p-current.time and t <= p-next.time {
        let local-t = (t - p-current.time) / (p-next.time - p-current.time)
        return p-current.value * (1 - local-t) + p-next.value * local-t
      }
      i += 1
    }
    return parsed-points.last().value
  }
}

#let interpolation(from-value, to-value, t) = {
  let value-type = type(from-value)
  if value-type in (length, ratio, float, int, relative, angle) {
    return from-value * (1 - t) + to-value * t
  } else if value-type == color {
    return color.mix(
      (from-value, (1 - t) * 100%),
      (to-value, t * 100%),
    )
  }

  if t < 1.0 { return from-value } else { return to-value }
}

// Easing functions
#let sudden-start = linear(
  (0.0, 0%),
  (1.0, 0%),
  (1.0, 100%),
)

#let sudden-middle = linear(
  (0.0, 0%),
  (0.0, 50%),
  (1.0, 50%),
  (1.0, 100%),
)

#let sudden-end = linear(
  (0.0, 0%),
  (0.0, 100%),
  (1.0, 100%),
)
#let linear-ease = cubic-bezier(0, 0, 1, 1)
#let ease-in-out = cubic-bezier(0.42, 0, 0.58, 1)
#let ease-in-out-expo = cubic-bezier(0.87, 0, 0.13, 1)
