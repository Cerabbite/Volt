#import "volt-objects.typ": *
#import "volt-animation.typ": *

#let editor-config = state("editor-config", ())
#let duration-state = state("duration-state", 0)
#let media-state = state("media-state", ("audio": (), "video": ()))
#let registered-views = state("registered-views", ())

#let clean-key(k) = {
  let str-k = str(k)
  if "#" in str-k {
    str-k.split("#").at(0)
  } else if "_" in str-k and not str-k.starts-with("_") {
    str-k.split("_").at(0)
  } else {
    str-k
  }
}

#let normalize-timeline(timeline) = {
  let entries = ()
  if type(timeline) == dictionary {
    for (k, v) in timeline.pairs() {
      entries.push((str(k), v))
    }
  } else if type(timeline) == array {
    for item in timeline {
      if type(item) == dictionary {
        for (k, v) in item.pairs() {
          entries.push((str(k), v))
        }
      } else if type(item) == array and item.len() >= 2 {
        entries.push((str(item.at(0)), item.at(1)))
      }
    }
  }
  return entries
}

#let normalize-updates(updates) = {
  if type(updates) != dictionary { return (:) }
  let has-targets = updates.values().any(v => type(v) == dictionary)
  if has-targets {
    return updates
  } else {
    return (default: updates)
  }
}

#let get-easing-for-prop(trans-def, target, prop) = {
  if trans-def == none { return t => t }
  if type(trans-def) == function { return trans-def }
  if type(trans-def) == dictionary {
    let target-trans = trans-def.at(target, default: trans-def.at("all", default: none))
    if type(target-trans) == function { return target-trans }
    if type(target-trans) == dictionary {
      return target-trans.at(prop, default: target-trans.at("all", default: t => t))
    }
    return trans-def.at(prop, default: trans-def.at("all", default: t => t))
  }
  return t => t
}

#let update(it, changes) = {
  if type(changes) != dictionary or type(it) != dictionary {
    return it
  }

  let updated-wrapper = it

  for (key, val) in changes {
    if key in ("vmove-x", "vmove-y", "vrotate", "valign", "vrot-mov-order") {
      updated-wrapper.insert(key, val)
    } else if "positional-arguments" in updated-wrapper and key in updated-wrapper.positional-arguments {
      let positional-arguments = updated-wrapper.at("positional-arguments", default: (:))
      positional-arguments.insert(key, val)
      updated-wrapper.insert("positional-arguments", positional-arguments)
    } else {
      let current-args = updated-wrapper.at("arguments", default: (:))
      current-args.insert(key, val)
      updated-wrapper.insert("arguments", current-args)
    }
  }

  return updated-wrapper
}

#let display-sequence() = {}

#let sequence(
  objects,
  timeline,
  speed: 1.0,
  duration: 0,
  start-frame: 0,
  timeline-mode: "target", // "target" (per-object tracks) or "global" (single cursor)
  vmove-x: 0pt,
  vmove-y: 0pt,
  vrotate: 0deg,
  vrot-mov-order: "rotate-move",
  valign: center + horizon,
) = {
  let normalized-objects = (:)
  let is-element-dict = type(objects) == dictionary and ("draw-function" in objects or "is-sequence" in objects)

  if type(objects) == content or is-element-dict {
    normalized-objects.insert("default", objects)
  } else if type(objects) == dictionary {
    normalized-objects = objects
  } else {
    panic((type: type(objects), objects: objects))
  }

  (
    "draw-function": display-sequence,
    "is-sequence": true,
    "positional-arguments": ("objects": normalized-objects, "timeline": timeline),
    "arguments": (
      "speed": speed,
      "duration": duration,
      "start-frame": start-frame,
      "timeline-mode": timeline-mode,
    ),
    "valign": valign,
    "vmove-x": vmove-x,
    "vmove-y": vmove-y,
    "vrotate": vrotate,
    "vrot-mov-order": vrot-mov-order,
  )
}

#let get-sequence-bounds(seq) = {
  let pos-args = seq.positional-arguments
  let seq-args = seq.arguments
  if seq-args.duration != 0 { return seq-args.duration }

  let norm-objs = pos-args.at("objects")
  let raw-timeline = pos-args.at("timeline")
  let seq-speed = seq-args.at("speed", default: 1.0)
  let mode = seq-args.at("timeline-mode", default: "target")
  let entries = normalize-timeline(raw-timeline)

  let max-reach = 0

  for (_, obj) in norm-objs {
    if type(obj) == dictionary {
      let obj-args = obj.at("arguments", default: (:))
      let start-f = obj-args.at("start-frame", default: 0)
      let child-speed = obj-args.at("speed", default: 1.0)

      let child-dur = 0
      if obj.at("is-sequence", default: false) {
        child-dur = int(get-sequence-bounds(obj) / child-speed)
      } else if "duration" in obj-args and obj-args.duration != 0 {
        child-dur = int(obj-args.duration / child-speed)
      }
      max-reach = calc.max(max-reach, start-f + child-dur)
    }
  }

  // Fallback fixed duration if timeline uses percentages but base duration isn't set dynamically yet,
  // or parse percentage keys safely against a default/explicit duration.
  let d-base = if seq-args.duration != 0 { seq-args.duration } else { 100 } // fallback base for % bounds scanning

  if mode == "target" {
    let target-cursors = (:)
    for pair in entries {
      let raw-k = pair.at(0)
      let frame-data = pair.at(1)
      let k = clean-key(raw-k)

      let f-val = 0
      if k.ends-with("%") {
        let pct = float(k.slice(0, -1)) / 100.0
        f-val = int(pct * d-base)
      } else if k.starts-with("-") {
        f-val = calc.max(0, d-base - int(k.slice(1)))
      } else {
        let updates = normalize-updates(frame-data.at("update", default: (:)))
        for target in updates.keys() {
          let prev-f = target-cursors.at(target, default: 0)
          f-val = if k.starts-with("+") {
            prev-f + int(k.slice(1))
          } else {
            int(k)
          }
          target-cursors.insert(target, f-val)
        }
      }
      max-reach = calc.max(max-reach, f-val)
    }
  } else {
    let prev-f = 0
    for pair in entries {
      let raw-k = pair.at(0)
      let k = clean-key(raw-k)
      let f-val = 0
      if k.ends-with("%") {
        let pct = float(k.slice(0, -1)) / 100.0
        f-val = int(pct * d-base)
      } else if k.starts-with("+") {
        prev-f += int(k.slice(1))
        f-val = prev-f
      } else if k.starts-with("-") {
        f-val = calc.max(0, d-base - int(k.slice(1)))
      } else {
        prev-f = int(k)
        f-val = prev-f
      }
      max-reach = calc.max(max-reach, f-val)
    }
  }

  return int(max-reach / seq-speed)
}

#let compile-timeline(timeline, sequence-duration, mode: "target") = {
  let entries = normalize-timeline(timeline)
  let resolved-entries = ()
  let d-base = sequence-duration

  // Pass 2a: End-Relative Keyframes ("-10")
  for pair in entries {
    let raw-k = pair.at(0)
    let frame-data = pair.at(1)
    let k = clean-key(raw-k)
    if k.starts-with("-") {
      let f-val = calc.max(0, d-base - int(k.slice(1)))
      resolved-entries.push((frame: f-val, data: frame-data))
    }
  }

  // Pass 2b: Percentage Keyframes ("50%")
  for pair in entries {
    let raw-k = pair.at(0)
    let frame-data = pair.at(1)
    let k = clean-key(raw-k)
    if k.ends-with("%") {
      let pct = float(k.slice(0, -1)) / 100.0
      let f-val = int(pct * d-base)
      resolved-entries.push((frame: f-val, data: frame-data))
    }
  }

  // Pass 2c: Absolute & Relative Offsets
  if mode == "target" {
    let target-cursors = (:)

    for pair in entries {
      let raw-k = pair.at(0)
      let frame-data = pair.at(1)
      let k = clean-key(raw-k)

      if not (k.starts-with("-") or k.ends-with("%")) {
        let updates = normalize-updates(frame-data.at("update", default: (:)))
        let transitions = frame-data.at("transition", default: none)

        for target in updates.keys() {
          let prev-f = target-cursors.at(target, default: 0)
          let f-val = if k.starts-with("+") {
            prev-f + int(k.slice(1))
          } else {
            int(k)
          }
          target-cursors.insert(target, f-val)

          let single-update = ((target): updates.at(target))
          resolved-entries.push((
            frame: f-val,
            data: (update: single-update, transition: transitions),
          ))
        }
      }
    }
  } else {
    let prev-f = 0
    for pair in entries {
      let raw-k = pair.at(0)
      let frame-data = pair.at(1)
      let k = clean-key(raw-k)

      if not (k.starts-with("-") or k.ends-with("%")) {
        let f-val = if k.starts-with("+") {
          prev-f + int(k.slice(1))
        } else {
          int(k)
        }
        prev-f = f-val
        resolved-entries.push((frame: f-val, data: frame-data))
      }
    }
  }

  // Group into property tracks
  let compiled-tracks = (:)
  for item in resolved-entries {
    let f-val = item.at("frame")
    let frame-data = item.at("data")
    let updates = normalize-updates(frame-data.at("update", default: (:)))
    let transitions = frame-data.at("transition", default: none)

    for (target, props) in updates {
      let target-tracks = compiled-tracks.at(target, default: (:))
      for (prop, val) in props {
        let prop-track = target-tracks.at(prop, default: ())
        let ease-fn = get-easing-for-prop(transitions, target, prop)
        prop-track.push((frame: f-val, value: val, ease: ease-fn))
        target-tracks.insert(prop, prop-track)
      }
      compiled-tracks.insert(target, target-tracks)
    }
  }

  for (target, target-tracks) in compiled-tracks {
    for (prop, keyframes) in target-tracks {
      compiled-tracks.at(target).insert(prop, keyframes.sorted(key: k => k.frame))
    }
  }

  return compiled-tracks
}

#let precompile-sequence(seq) = {
  let base-dur = get-sequence-bounds(seq)
  let pos-args = seq.positional-arguments
  let seq-args = seq.arguments
  let objects = pos-args.at("objects")
  let timeline = pos-args.at("timeline")
  let mode = seq-args.at("timeline-mode", default: "target")

  let compiled-tracks = compile-timeline(timeline, base-dur, mode: mode)
  let compiled-objects = (:)

  for (key, obj) in objects {
    if type(obj) == dictionary and obj.at("is-sequence", default: false) {
      compiled-objects.insert(key, precompile-sequence(obj))
    } else {
      compiled-objects.insert(key, obj)
    }
  }

  let updated-seq = seq
  updated-seq.insert("base-duration", base-dur)
  updated-seq.insert("compiled-tracks", compiled-tracks)

  let new-pos-args = updated-seq.positional-arguments
  new-pos-args.insert("objects", compiled-objects)
  updated-seq.insert("positional-arguments", new-pos-args)

  return updated-seq
}

// ==========================================
// 6. Track Interpolator & Rendering Engine
// ==========================================

#let evaluate-tracks(tracks, current-frame) = {
  let evaluated = (:)
  for (prop, keyframes) in tracks {
    let prev-kf = none
    let next-kf = none

    for kf in keyframes {
      if kf.frame <= current-frame {
        prev-kf = kf
      } else if next-kf == none {
        next-kf = kf
      }
    }

    if prev-kf == none {
      evaluated.insert(prop, keyframes.first().value)
    } else if next-kf == none or prev-kf.frame == next-kf.frame {
      evaluated.insert(prop, prev-kf.value)
    } else {
      let t = (current-frame - prev-kf.frame) / (next-kf.frame - prev-kf.frame)
      let ease-fn = next-kf.at("ease", default: t => t)
      let eased-t = ease-fn(t)
      evaluated.insert(prop, interpolation(prev-kf.value, next-kf.value, eased-t))
    }
  }
  return evaluated
}

#let render-single-object(base-obj, tracks, relative-frame) = {
  let evaluated-properties = evaluate-tracks(tracks, relative-frame)
  let obj-dict = update(base-obj, evaluated-properties)

  let draw-fn = obj-dict.at("draw-function")
  let pos-args = obj-dict.at("positional-arguments", default: (:)).values()
  let draw-args = obj-dict.at("arguments", default: (:))

  let body-content = draw-fn(..pos-args, ..draw-args)

  let dx = obj-dict.at("vmove-x", default: 0pt)
  let dy = obj-dict.at("vmove-y", default: 0pt)
  let rot = obj-dict.at("vrotate", default: 0deg)
  let order = obj-dict.at("vrot-mov-order", default: "rotate-move")

  let transformed = body-content
  if order == "rotate-then-move" or order == "rotate-move" {
    transformed = normal-rotate(rot, transformed)
    transformed = normal-move(dx: dx, dy: dy, transformed)
  } else {
    transformed = normal-move(dx: dx, dy: dy, transformed)
    transformed = normal-rotate(rot, transformed)
  }

  return transformed
}

#let render-view-for-frame(
  alignment: horizon + center,
  sequence,
  start-frame: 0,
  duration: 0,
  frame: 0,
  compound-speed: 1.0,
) = {
  let seq-args = sequence.arguments
  let seq-start = seq-args.at("start-frame", default: 0)

  let effective-start = start-frame + seq-start
  let relative-frame = frame - effective-start

  if relative-frame < 0 { return }

  let base-duration = sequence.at("base-duration")
  let effective-duration = if duration > 0 {
    duration
  } else if duration < 0 {
    base-duration + calc.abs(duration)
  } else {
    base-duration
  }

  if relative-frame > effective-duration { return }

  let pos-args = sequence.positional-arguments
  let objects = pos-args.at("objects")

  let local-speed = seq-args.at("speed", default: 1.0)
  let current-compound-speed = compound-speed * local-speed
  let scaled-local-frame = int(relative-frame * current-compound-speed)

  let object-tracks = sequence.at("compiled-tracks")
  let rendered-elements = ()

  for (key, raw-obj) in objects {
    let tracks = object-tracks.at(key, default: (:))

    if type(raw-obj) == dictionary and raw-obj.at("is-sequence", default: false) {
      let child-start = raw-obj.arguments.at("start-frame", default: 0)
      let child-dur = raw-obj.arguments.at("duration", default: 0)

      let child-rel-frame = scaled-local-frame - child-start
      if child-rel-frame >= 0 {
        let child-rendered = render-view-for-frame(
          alignment: alignment,
          raw-obj,
          start-frame: effective-start,
          duration: if child-dur == 0 { duration } else { child-dur },
          frame: frame,
          compound-speed: current-compound-speed,
        )
        if child-rendered != none {
          rendered-elements.push(child-rendered)
        }
      }
    } else if type(raw-obj) == dictionary and raw-obj.at("is-audio", default: false) {
      continue
    } else {
      let obj-args = if type(raw-obj) == dictionary { raw-obj.at("arguments", default: (:)) } else { (:) }
      let obj-start = obj-args.at("start-frame", default: 0)

      if scaled-local-frame >= obj-start {
        let rendered-obj = render-single-object(raw-obj, tracks, scaled-local-frame)
        let obj-align = if type(raw-obj) == dictionary and "valign" in raw-obj {
          raw-obj.valign
        } else {
          alignment
        }
        rendered-elements.push(normal-place(obj-align, rendered-obj))
      }
    }
  }

  let content = rendered-elements.join()

  let dx = sequence.at("vmove-x", default: 0pt)
  let dy = sequence.at("vmove-y", default: 0pt)
  let rot = sequence.at("vrotate", default: 0deg)
  let order = sequence.at("vrot-mov-order", default: "rotate-move")

  let transformed = box(width: 100%, height: 100%, content)
  if order == "rotate-then-move" or order == "rotate-move" {
    transformed = normal-rotate(rot, origin: sequence.at("valign", default: center + horizon), transformed)
    transformed = normal-move(dx: dx, dy: dy, transformed)
  } else {
    transformed = normal-move(dx: dx, dy: dy, transformed)
    transformed = normal-rotate(rot, origin: sequence.at("valign", default: center + horizon), transformed)
  }

  return normal-place(top + left, transformed)
}

#let view(alignment: center + horizon, sequence, start-frame: 0, duration: 0) = {
  let compiled-sequence = precompile-sequence(sequence)

  let seq-start = compiled-sequence.arguments.at("start-frame", default: 0)

  let total-start = start-frame + seq-start
  let natural-end = total-start + compiled-sequence.at("base-duration")

  let effective-end = if duration > 0 {
    total-start + duration
  } else if duration < 0 {
    natural-end + calc.abs(duration)
  } else {
    natural-end
  }

  duration-state.update(old => calc.max(old, effective-end))

  registered-views.update(views => {
    views.push((
      alignment: alignment,
      sequence: compiled-sequence,
      start-frame: start-frame,
      duration: duration,
    ))
    views
  })
}

#let init-editor(
  fps: 24,
  duration-ms: 0,
) = {
  context {
    let natural-frames = duration-state.final()
    let final-media-state = media-state.final()

    let duration-frames = if duration-ms > 0 {
      int((duration-ms / 1000) * fps)
    } else if duration-ms == 0 {
      natural-frames
    } else {
      natural-frames + int((calc.abs(duration-ms) / 1000) * fps)
    }

    let start-frame = 0
    let end-frame = duration-frames

    if "start-frame" in sys.inputs {
      start-frame = int(sys.inputs.at("start-frame"))
      let end-frame-input = int(sys.inputs.at("end-frame", default: str(duration-frames)))
      end-frame = calc.min(duration-frames, end-frame-input)
    }

    let config = (
      fps: fps,
      duration: duration-frames,
      current-frame: start-frame,
    )

    let all-views = registered-views.final()

    for f in range(start-frame, end-frame + 1) {
      let frame-content = ()
      for v in all-views {
        let rendered = render-view-for-frame(
          alignment: v.alignment,
          v.sequence,
          start-frame: v.start-frame,
          duration: v.duration,
          frame: f,
        )
        if rendered != none {
          frame-content.push(rendered)
        }
      }
      [#frame-content.join()#pagebreak()]
    }

    [#metadata(config)<editor-config>#metadata(final-media-state)<media-state>]
  }
}

#let audio(input, start-frame: 0, cutoff: 0, volume: 1, fade-out: 0) = {
  media-state.update(curr => {
    let audio-list = curr.at("audio", default: ())

    let new-entry = (
      input: input,
      start-frame: start-frame,
      cutoff: cutoff,
      fade-out: fade-out,
      volume: volume,
    )

    audio-list.push(new-entry)
    curr.insert("audio", audio-list)
    curr
  })
}
