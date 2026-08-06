#import "/src/volt.typ": *

#set page(
  width: 1920pt,
  height: 1080pt,
  fill: rgb("808080"),
  margin: (x: 0pt, y: 0pt),
)

#init-editor()

#view(
  sequence(
    audio("Fox Tale Waltz Part 1.mp3", trim-start-ms: 5000),
    (
      "0": (update: (volume: 1)),
      "+24": (update: (volume: 1.5)),
      "+24#": (update: (volume: 0.5), transition: ease-in-out-expo),
      "50%": (update: (speed: 1.0)),
      "70%": (update: (speed: 3.0)),
    ),
    duration: 9000,
  ),
  start-frame: 0,
)
