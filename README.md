# bmw_demo

Guys Checkout this Demo BMW Flutter app Created Just for Fun.  [Download APK](https://github.com/hardikvaistra/bmw_demo/blob/main/bmw_demo.apk?raw=true)

## About App
![DEMO](https://raw.githubusercontent.com/hardikvaistra/bmw_demo/main/assets/images/8a9z7t.gif) 


Well Took me 3&Half days to complete this 3 Screens! it was quite fun doing it! Clean Code and Not Responsive Yet!

Buttons & Objects are just played with BoxShadows just Playing with it for the Best Output
Switch is Custom Made just using container and state
Rounded Slider Took inspiration from -[YT-JideGuru](https://www.youtube.com/watch?v=IP0Nn9f2yJs)
Linear Slider is Basically Shadows and Jugaad 😉
Custom Shapes are from -[Flutter Shape Maker]("https://fluttershapemaker.com/")

## Day Counter

A counter for any date, reached from the hourglass button on the home screen.

Each counter runs in **both directions**: while the date is ahead it counts
down `180 / 180 → 1 / 180`, and the moment it passes it turns around and counts
up `1 / 180 → 180 / 180`. The window (the `/ 180`) is yours to pick — 30, 60,
90, 180, 365 days or anything in between — and it drives the ring and the bar
as well as the fraction.

* **Counters list** — every date you track, nearest first, past dates after.
  Swipe a card away to delete it (with undo), long-press to edit.
* **Editor** — the card itself is the live preview; title suggestions, all-day
  or timed, the counting window, and a background picker.
* **Detail** — a big progress ring, the exact remainder down to the second,
  elapsed/left/percent, and *Add to home screen*.
* **Backgrounds** — nine presets, painted from gradients so they stay sharp at
  any size, plus bundled photos. Any asset under `assets/images/` can be used
  as a custom background via `CountEvent.imagePath`.

### Home-screen widget (Android)

*Add to home screen* renders the counter's artwork to a PNG, hands it to the
Android host, and asks the launcher to place the widget. The widget draws its
own numbers from the stored date, recomputing them on every update and at
midnight, so it stays correct even if the app is never opened. Tapping it opens
the app on that counter.

Counters are persisted through the same Android host, so no extra Flutter
package is needed — on other platforms the app runs with in-memory counters.

Package Used in this App

1. Flutter Animate []("https://pub.dev/packages/flutter_animate")
2. SoundPool []("https://pub.dev/packages/soundpool")

Inspiration of Design Credit [Dribble : Berken](https://dribbble.com/shots/13793065-BMW-Smart-App-Design/)
![ALT](https://raw.githubusercontent.com/hardikvaistra/bmw_demo/main/assets/images/inspiration.jpg)
