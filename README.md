# APOD Wallpaper

APOD Wallpaper is a native macOS menu bar app that turns NASA's Astronomy Picture of the Day into your desktop wallpaper.

## Features

- Fetch today's APOD or explore a rotating archive.
- Keep a favorites collection and revisit recently shown images.
- Cache downloaded images for offline reapplication.
- Choose wallpaper presentation: fill, fit, center, or stretch.
- Handle video and other non-image APODs according to your preference.
- Update automatically on an hourly, three-hour, six-hour, twelve-hour, or daily schedule.
- Apply the wallpaper across every connected display.
- Optionally launch at login.

## Requirements

- macOS 13 or later.
- Swift 6 or Xcode 16 or later to build from source.
- Network access to the NASA APOD API and the APOD media URL.

The app uses NASA's `DEMO_KEY` by default. NASA documents that key as a low-rate demonstration credential; custom API-key configuration is not exposed in the current settings UI.

## Build from source

```sh
git clone https://github.com/todaymare/apod-wallpaper.git
cd apod-wallpaper
swift test
./Scripts/build-app.sh
open "build/APOD Wallpaper.app"
```

The build script creates an unsigned application bundle at `build/APOD Wallpaper.app`. Version values can be supplied for local or CI builds:

```sh
VERSION=1.0.1 BUILD_NUMBER=42 ./Scripts/build-app.sh
```

Unsigned builds may require approval in **System Settings → Privacy & Security** the first time they are opened.

## Data and privacy

APOD metadata, display history, favorites, and downloaded images are stored locally under:

```text
~/Library/Application Support/APOD Wallpaper/
```

The app sends requests to NASA's APOD API and the image URLs returned by that API. It does not include analytics or a remote account system.

## Development

Run the test suite with:

```sh
swift test
```

GitHub Actions runs the tests and produces an unsigned app bundle for pushes and pull requests.

## License

This project is available under the [MIT License](LICENSE).
