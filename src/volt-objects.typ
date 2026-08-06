#let normal-rect = rect
#let normal-image = image
#let normal-text = text
#let normal-move = move
#let normal-rotate = rotate
#let normal-place = place
#let normal-scale = scale

#let rect(
  body: none,
  fill: none,
  height: auto,
  inset: 0% + 5pt,
  outset: (:),
  radius: (:),
  stroke: auto,
  width: auto,
  valign: top + left,
  vmove-x: 0pt,
  vmove-y: 0pt,
  vrotate: 0deg,
  vrot-mov-order: "rotate-move",
) = {
  (
    "draw-function": normal-rect,
    "positional-arguments": ("body": body),
    "arguments": (
      "fill": fill,
      "height": height,
      "inset": inset,
      "outset": outset,
      "radius": radius,
      "stroke": stroke,
      "width": width,
    ),
    "valign": valign,
    "vmove-x": vmove-x,
    "vmove-y": vmove-y,
    "vrotate": vrotate,
    "vrot-mov-order": vrot-mov-order,
  )
}

#let image(
  source,
  alt: none,
  fit: "cover",
  format: auto,
  height: auto,
  icc: auto,
  page: 1,
  scaling: auto,
  width: auto,
  valign: top + left,
  vmove-x: 0pt,
  vmove-y: 0pt,
  vrotate: 0deg,
  vrot-mov-order: "rotate-move",
) = {
  (
    "draw-function": normal-image,
    "positional-arguments": ("source": source),
    "arguments": (
      "alt": alt,
      "width": width,
      "height": height,
      "fit": fit,
      "format": format,
      "icc": icc,
      "page": page,
      "scaling": scaling,
    ),
    "valign": valign,
    "vmove-x": vmove-x,
    "vmove-y": vmove-y,
    "vrotate": vrotate,
    "vrot-mov-order": vrot-mov-order,
  )
}

#let progress-text(
  body,
  font: "libertinus serif",
  fallback: true,
  style: "normal",
  weight: "regular",
  stretch: 100%,
  size: 11pt,
  fill: luma(0%),
  stroke: none,
  tracking: 0pt,
  spacing: 100% + 0pt,
  baseline: 0pt,
  overhang: true,
  top-edge: "cap-height",
  bottom-edge: "baseline",
  lang: "en",
  region: none,
  script: auto,
  dir: auto,
  hyphenate: false,
  costs: (
    hyphenation: 100%,
    runt: 100%,
    widow: 100%,
    orphan: 100%,
  ),
  number-type: auto,
  number-width: auto,
  ligatures: true,
  discretionary-ligatures: false,
  historical-ligatures: false,
  stylistic-set: (),
  features: (:),
  fractions: false,
  slashed-zero: false,
  variations: (:),
  kerning: true,
  alternates: 0,
  cjk-latin-spacing: auto,
  progress: 1.0,
) = {
  // FAST PATH: Skip AST traversal if text is fully displayed or empty
  if progress >= 1.0 {
    return normal-text(
      body,
      font: font,
      fallback: fallback,
      style: style,
      weight: weight,
      stretch: stretch,
      size: size,
      fill: fill,
      stroke: stroke,
      tracking: tracking,
      spacing: spacing,
      baseline: baseline,
      overhang: overhang,
      top-edge: top-edge,
      bottom-edge: bottom-edge,
      lang: lang,
      region: region,
      script: script,
      dir: dir,
      hyphenate: hyphenate,
      costs: costs,
      number-type: number-type,
      number-width: number-width,
      ligatures: ligatures,
      discretionary-ligatures: discretionary-ligatures,
      historical-ligatures: historical-ligatures,
      stylistic-set: stylistic-set,
      features: features,
      fractions: fractions,
      slashed-zero: slashed-zero,
      variations: variations,
      kerning: kerning,
      alternates: alternates,
      cjk-latin-spacing: cjk-latin-spacing,
    )
  }
  if progress <= 0.0 { return [] }

  let count-chars(it) = {
    let t = type(it)
    if t == str {
      it.clusters().len()
    } else if t == content {
      if it.has("text") {
        it.text.clusters().len()
      } else if it.has("children") {
        it.children.map(count-chars).sum(default: 0)
      } else if it.has("body") {
        count-chars(it.body)
      } else if it.has("child") {
        count-chars(it.child)
      } else { 0 }
    } else { 0 }
  }

  let rebuild-container(f, fields, new-body) = {
    if f == align {
      let al = fields.remove("alignment", default: left + top)
      align(al, new-body)
    } else if f == place {
      let al = fields.remove("alignment", default: none)
      let dx = fields.remove("dx", default: 0pt)
      let dy = fields.remove("dy", default: 0pt)
      if al != none { place(al, new-body, dx: dx, dy: dy) } else { place(new-body, dx: dx, dy: dy) }
    } else if f == rotate {
      let angle = fields.remove("angle", default: 0deg)
      rotate(angle, new-body, ..fields)
    } else if f == move {
      let dx = fields.remove("dx", default: 0pt)
      let dy = fields.remove("dy", default: 0pt)
      move(dx: dx, dy: dy, new-body)
    } else if f == box {
      box(new-body, ..fields)
    } else {
      f(new-body, ..fields)
    }
  }

  let slice-node(it, rem) = {
    let t = type(it)
    if t == str {
      let chars = it.clusters()
      let take = int(calc.min(chars.len(), rem))
      return (chars.slice(0, take).join(), rem - take)
    } else if t == content {
      if it.has("text") {
        let chars = it.text.clusters()
        let take = int(calc.min(chars.len(), rem))
        return (normal-text(chars.slice(0, take).join()), rem - take)
      } else if it.has("children") {
        let new-children = ()
        let current-rem = rem
        for child in it.children {
          let (res-child, next-rem) = slice-node(child, current-rem)
          new-children.push(res-child)
          current-rem = next-rem
        }
        return (new-children.join(), current-rem)
      } else if it.has("body") {
        let (new-body, next-rem) = slice-node(it.body, rem)
        let f = it.func()
        let fields = it.fields()
        let _ = fields.remove("body")
        return (rebuild-container(f, fields, new-body), next-rem)
      } else if it.has("child") {
        let (new-child, next-rem) = slice-node(it.child, rem)
        let f = it.func()
        let fields = it.fields()
        let _ = fields.remove("child")
        return (f(new-child, ..fields), next-rem)
      }
    }
    return (it, rem)
  }

  let total = count-chars(body)
  if total == 0 { return [] }

  let budget = int(calc.min(total, calc.max(0, calc.round(total * progress))))
  let (modified-body, _) = slice-node(body, budget)

  return normal-text(
    modified-body,
    font: font,
    fallback: fallback,
    style: style,
    weight: weight,
    stretch: stretch,
    size: size,
    fill: fill,
    stroke: stroke,
    tracking: tracking,
    spacing: spacing,
    baseline: baseline,
    overhang: overhang,
    top-edge: top-edge,
    bottom-edge: bottom-edge,
    lang: lang,
    region: region,
    script: script,
    dir: dir,
    hyphenate: hyphenate,
    costs: costs,
    number-type: number-type,
    number-width: number-width,
    ligatures: ligatures,
    discretionary-ligatures: discretionary-ligatures,
    historical-ligatures: historical-ligatures,
    stylistic-set: stylistic-set,
    features: features,
    fractions: fractions,
    slashed-zero: slashed-zero,
    variations: variations,
    kerning: kerning,
    alternates: alternates,
    cjk-latin-spacing: cjk-latin-spacing,
  )
}

#let text(
  body,
  font: "libertinus serif",
  fallback: true,
  style: "normal",
  weight: "regular",
  stretch: 100%,
  size: 11pt,
  fill: luma(0%),
  stroke: none,
  tracking: 0pt,
  spacing: 100% + 0pt,
  baseline: 0pt,
  overhang: true,
  top-edge: "cap-height",
  bottom-edge: "baseline",
  lang: "en",
  region: none,
  script: auto,
  dir: auto,
  hyphenate: false,
  costs: (
    hyphenation: 100%,
    runt: 100%,
    widow: 100%,
    orphan: 100%,
  ),
  number-type: auto,
  number-width: auto,
  ligatures: true,
  discretionary-ligatures: false,
  historical-ligatures: false,
  stylistic-set: (),
  features: (:),
  fractions: false,
  slashed-zero: false,
  variations: (:),
  kerning: true,
  alternates: 0,
  cjk-latin-spacing: auto,
  progress: 1.0,
  valign: top + left,
  vmove-x: 0pt,
  vmove-y: 0pt,
  vrotate: 0deg,
  vrot-mov-order: "rotate-move",
) = {
  (
    "draw-function": progress-text,
    "positional-arguments": ("body": body),
    "arguments": (
      "font": font,
      "fallback": fallback,
      "style": style,
      "weight": weight,
      "stretch": stretch,
      "size": size,
      "fill": fill,
      "stroke": stroke,
      "tracking": tracking,
      "spacing": spacing,
      "baseline": baseline,
      "overhang": overhang,
      "top-edge": top-edge,
      "bottom-edge": bottom-edge,
      "lang": lang,
      "region": region,
      "script": script,
      "dir": dir,
      "hyphenate": hyphenate,
      "costs": costs,
      "number-type": number-type,
      "number-width": number-width,
      "ligatures": ligatures,
      "discretionary-ligatures": discretionary-ligatures,
      "historical-ligatures": historical-ligatures,
      "stylistic-set": stylistic-set,
      "features": features,
      "fractions": fractions,
      "slashed-zero": slashed-zero,
      "variations": variations,
      "kerning": kerning,
      "alternates": alternates,
      "cjk-latin-spacing": cjk-latin-spacing,
      "progress": progress,
    ),
    "valign": valign,
    "vmove-x": vmove-x,
    "vmove-y": vmove-y,
    "vrotate": vrotate,
    "vrot-mov-order": vrot-mov-order,
  )
}
