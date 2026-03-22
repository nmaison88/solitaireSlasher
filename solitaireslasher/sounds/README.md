# Sound Effects for Solitaire Slasher

This directory contains sound effects for the game.

## Required Sound Files

To enable sound effects, add the following audio files to this directory:

1. **card_place.wav** or **card_place.ogg**
   - Played when a card is successfully placed (foundation or tableau)
   - Suggested: Short, satisfying "click" or "snap" sound
   - Duration: ~0.1-0.3 seconds

2. **card_draw.wav** or **card_draw.ogg**
   - Played when drawing cards from the stock pile
   - Suggested: Quick "shuffle" or "flip" sound
   - Duration: ~0.2-0.4 seconds

3. **win.wav** or **win.ogg**
   - Played when the game is won (all cards in foundations)
   - Suggested: Triumphant fanfare or celebration sound
   - Duration: ~1-3 seconds

## Supported Formats

- WAV (uncompressed)
- OGG (compressed, recommended for smaller file size)
- MP3 (supported but OGG is preferred in Godot)

## Free Sound Resources

You can find free sound effects at:
- https://freesound.org/
- https://opengameart.org/
- https://kenney.nl/assets (has card game sounds)

## Current Status

The game is set up to play sounds, but will work silently until audio files are added.
The SoundManager will automatically detect and load sounds when they are placed in this directory.
