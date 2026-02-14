# keytape

CLI tool to render the [VHS][1] keystroke log onto the generated
video. VHS does not have the ability to caption keypresses,
so this tool was created to do so. It does, however, require
a small patch to VHS to output a keystroke log.

[Demo](https://github.com/pkazmier/keytape/blob/main/demo-captioned.mp4)

## Prerequisites

1. Patched version of [`vhs`][2] to generate key logs
2. [`ffmpeg`][3] compiled with `--enable-libass`
3. A [Nerd Font][4] for subtitles
4. Neovim for Lua

## Quick Start

1. Generate a VHS video using patched `vhs`:

   ```console
   vhs --keylog keylog.json demo.tape -o demo.mp4
   ```

2. Add the keypresses to the video with `keytape`:

   ```console
   ./keytape.lua keylog.json demo.mp4
   ```

## Usage

### Command syntax

```console
keytape <keylog.json> <video.mp4> [--flag=value ...]
```

- `keylog.json` - key event log produced by VHS
- `video.mp4` - screencast video produced by VHS

Outputs:

- `<video>.ass` - subtitle file
- `<video>-captioned.mp4` - rendered video

### Configuration

All options may be provided as:

- Command line flags: `--option=value`
- Environment variables: `KEYTAPE_OPTION=value`

Command line flags override environment variables.

### Options

| Flag                    | Environment                   | Description                                | Default             |
| ----------------------- | ----------------------------- | ------------------------------------------ | ------------------- |
| `--font`                | `KEYTAPE_FONT`                | Font family used for subtitles             | JetBrainsMonoNL NFM |
| `--font-size`           | `KEYTAPE_FONT_SIZE`           | Font size in points                        | 32                  |
| `--max-keys-onscreen`   | `KEYTAPE_MAX_KEYS_ONSCREEN`   | Maximum keys displayed sliding window      | 10                  |
| `--inactivity-timer-ms` | `KEYTAPE_INACTIVITY_TIMER_MS` | Idle duration before window resets         | 1000                |
| `--highlight-color`     | `KEYTAPE_HIGHLIGHT_COLOR`     | Highlight color in RRGGBB for newest key   | 66CCFF              |
| `--background-opacity`  | `KEYTAPE_BACKGROUND_OPACITY`  | Background opacity of subtitle box 0–1     | 0.5                 |
| `--key-normalization`   | `KEYTAPE_KEY_NORMALIZATION`   | Key rendering style: `vim` or `icon` style | vim                 |
| `--margin-left`         | `KEYTAPE_MARGIN_LEFT`         | Left margin in px                          | 40                  |
| `--margin-right`        | `KEYTAPE_MARGIN_RIGHT`        | Right margin in px                         | 40                  |
| `--margin-vertical`     | `KEYTAPE_MARGIN_VERTICAL`     | Bottom margin in px                        | 40                  |

### Examples

Default usage:

    keytape keylog.json demo.mp4

Custom styling:

    keytape session.json demo.mp4 \
      --font="JetBrainsMonoNL NFM" \
      --font-size=36 \
      --highlight-color=FF6666 \
      --background-opacity=0.4

Using environment variables:

    export KEYTAPE_FONT_SIZE=36
    export KEYTAPE_MAX_KEYS_ONSCREEN=8
    keytape session.json demo.mp4

[1]: https://github.com/charmbracelet/vhs
[2]: https://github.com/pkazmier/vhs/tree/keylogger
[3]: https://ffmpeg.org/
[4]: https://www.nerdfonts.com/
