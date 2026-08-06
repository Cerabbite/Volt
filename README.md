# What is Volt?
Volt is an animation and video editing library written for Typst and largely in Typst.

# How to use Volt
Start by importing Volt 
```typst
#import "volt.typ": *
```

To compile your project you need ```volt.py``` and run it using [uv](https://docs.astral.sh/uv/)

## Creating an empty video
You define the video size by the page width and height.
```typst
#set page(width: 1920pt, height: 1080pt, margin: (x: 0pt, y: 0pt))
```
And for short form content
```typst
#set page(width: 1080pt, height: 1920pt, margin: (x: 0pt, y: 0pt))
```

You must then initialize the Volt editor which is used for both video and animations.
```typst
#init-editor()
```