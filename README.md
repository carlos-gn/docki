# docki

A lightning-fast, open-source app workspace manager for macOS. Save and restore your entire app configuration in seconds.

## Why docki?

docki replaces manual app switching with instant workspace presets. 

I built this because I was tired of manually switching between different work contexts. Now I save each setup as a preset and switch instantly with a single command.

Perfect for:
- Switching between different work contexts
- Context-switching between projects
- Keeping your dock clean by only running what you need

## Installation

### From Source

Prerequisites: [Zig 0.15.2+](https://ziglang.org/download/)

```bash
git clone https://github.com/yourusername/docki.git
cd docki
zig build -Doptimize=ReleaseSafe
./zig-out/bin/docki --version
```

### Homebrew (coming soon)

```bash
brew install docki
```

## Usage

### Save a preset

Capture your currently running applications:

```bash
docki save work
docki save creative
docki save focus
```

This saves the names of all running apps to `~/.config/docki/presets/{name}.apps`

### Load a preset

Restore a saved workspace:

```bash
docki load work
```

This will:
- Launch any apps in the preset that aren't running
- Quit any apps that are running but not in the preset (except protected apps)
- Leave protected apps untouched (Finder, Terminal, iTerm2, ghostty, Warp, Alacritty)

### List presets

```bash
docki list
```

Shows all saved presets:

```
work
creative
focus
```

### Help & Version

```bash
docki --help          # Show usage
docki --version       # Show version
```

## Configuration

### Custom protected apps

Create `~/.config/docki/config.json` to prevent certain apps from being quit:

```json
{
  "protected_apps": ["Finder", "Terminal", "iTerm2", "ghostty", "MyCustomApp"]
}
```

Protected apps will never be automatically quit when loading a preset. App names are case-insensitive (you can write them in any case, they'll be matched regardless).

## How it works

docki uses AppleScript (via `osascript`) to:
- Query running foreground applications
- Launch applications by name
- Quit applications gracefully

Presets are stored as simple text files with comma-separated app names.

## Development

Build and test locally:

```bash
zig build run -- save test_preset
zig build run -- list
zig build run -- load test_preset
```

Run tests:

```bash
zig build test
```

## Contributing

Contributions welcome! This is a small, focused tool—keep it that way.

## License

MIT License - see LICENSE file

## Motivation

This is an open-source alternative to [DockFlow](https://dockflow.appitstudio.com/), built with Zig for speed and simplicity.
