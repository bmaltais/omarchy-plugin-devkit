# shellcheck shell=bash
# The example tour of a standalone app: type into its window. Run it with ./tour tours/demo.sh (the result is left in /tmp).
TOUR_OUT=screenshots/demo.avif
TOUR_STEPS=2
TOUR_SIZE=960x600
TOUR_MAX_SECONDS=120

tour_play() {
  cap "The app has a window"
  wait_until "app_window_up" 20
  sleep 1.5
  cap "Type into it"
  click 480 300 0.8
  typed "echo typed by the recorder"
  pressed Return
  sleep 1.5
}
