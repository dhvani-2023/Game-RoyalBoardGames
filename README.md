# Board Games: Royal Club (iOS)

Native iOS port of the Android game in `/Volumes/Work/Raj/Android/Game-BoardGames-master`.
This folder is a complete, independent Xcode project. It shares nothing with the other games.

| | |
|---|---|
| Bundle ID | `com.ngstudio.royalboardgames` |
| Platform | iPhone, iOS 17+ |
| Status | **Port in progress.** Currently a placeholder screen. |

## Run it
1. Open `RoyalBoardGames.xcodeproj` in Xcode.
2. Pick an iPhone simulator (or your iPhone) and press **Run**.
3. For the App Store: in *Signing & Capabilities*, choose your Team once.

## What's inside
- `RoyalBoardGames/`: app code, art, sounds (`Resources/Audio`, 48 kHz), fonts, icon.
- `RoyalBoardGamesTests/`: unit tests, including "same level as Android" checks.
- `Packages/GameKit/`: this game's own copy of the engine code (sound, haptics, saving, game loop, exact Android random numbers).
- `Reference/Android/`: screenshots of the Android version, used to compare the look.

## Port plan
- **Shell.** "Royal Game Night" look: night, felt, gold and wood tokens; Lilita One + Nunito.
  - Splash: gold ring with orbiting icons. Onboarding: 4 pages, including a live mini pool break.
  - Wooden dock: Home (Spin the Table wheel, Continue cards, Quick Play) | Games | Trophies | Settings.
- **Pool (8-Ball and 9-Ball).** 2–4 players.
  - Physics: dt = 1/960 s with full 3D spin, squirt, throw and english. Every shot is simulated on release, then played back from the recording with slow motion on the last ball.
  - Content: 8 tables, 8 cues. Ghost-ball bot that simulates its candidate shots.
  - Controls: power bar, fine aim wheel, spin ball, call pocket, ball in hand.
  - Balls rendered from per-ball quaternions. **Free rotation** while open.
- **Carrom.** Classic, Pocket Pool, Freestyle modes; ICF rule option.
  - Physics: dt = 1/480 s. Content: 8 boards, 8 strikers. Simulating bot.
  - The board turns to face each shooter. Free rotation while open.
- **Ludo.** 4-arm and 6-arm boards, 2–6 players, 3D tumbling die, 6 themes, heuristic bot.
- **Chess.** Full rules and draw claims, 5 clock options, 4 board styles; negamax bot at depth 1/2/3 with quiescence search; resume by replaying the move list.
- **Snakes & Ladders.** Fixed layout, 10 animated themes.
- **Tic-Tac-Toe.** Best-of matches, minimax bot.
- **Port.**
  - Physics: plain Swift `Double`s in the same operation order; bots and tests reuse the same simulator.
  - Audio: about 6k lines of procedural board art ported to Canvas. A 32-voice synth mixer for the 73 synthesized sounds, plus the 84 bpm lounge loop.
  - Autosave: every game uses its existing `party.<game>.saved.v1` key.
- **Simulator pass.**
  - A full rack of each pool variant (break, foul, ball in hand, call the 8) and a Carrom board in each mode.
  - A 6-player Ludo game, chess mate/stalemate/promotion, a Snakes game, a Tic-Tac-Toe best-of-5.
  - Rotation in Pool and Carrom; resume an autosave after a kill and relaunch.

## Upgrades over Android
- **Fixes:** —
- **New features:** Instant replay of the last Pool and Carrom shot, in slow motion (shots are already recorded). Practice table for Pool and Carrom (free shooting, no turns). Chess: move list, undo against the bot, hint button, copy game as PGN.
