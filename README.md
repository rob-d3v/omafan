# omafan

Fan control for Omarchy, in the spirit of Acer's NitroSense. A fan icon in the bar
turns red when the machine runs hot; click it (or pick **omafan** in the app launcher,
`Super + Space`) for a panel with every fan's temperature and speed, presets (auto, off, 50 %, 75 %, turbo), and a
manual speed slider. The CPU and GPU fans can be driven together or one at a time.

![omafan panel](preview.png)

Unofficial community plugin. It is a front end for
[NBFC-Linux](https://github.com/nbfc-linux/nbfc-linux), which does the actual fan
control by talking to the laptop's embedded controller.

## Requirements

- Omarchy 4 with the Quickshell bar.
- `nbfc-linux` with a config for your laptop and its service running:

  ```bash
  yay -S nbfc-linux
  sudo nbfc rate-config -a              # find a config that fits this machine
  sudo nbfc config --set "<config name>"
  sudo systemctl enable --now nbfc_service
  ```

  Tested on an Acer Nitro AN515-44 (`Acer Nitro AN515-44` config). Any laptop NBFC
  supports should work; the panel shows whatever fans the config defines.

omafan itself never asks for root. It runs the unprivileged `nbfc` client, which talks
to `nbfc_service` over its socket.

## Install

```bash
omarchy plugin add https://github.com/rob-d3v/omafan --enable
```

To also open it from the app launcher (`Super + Space`):

```bash
~/.config/omarchy/plugins/io.github.rob-d3v.omafan/launcher.sh install
```

This writes `~/.local/share/applications/omafan.desktop` and nothing else.

## Use

| Where | What |
| --- | --- |
| Bar icon, click | Open or close the panel |
| Bar icon, right click | Show or hide the temperature next to the icon |
| `F` | Switch between both fans, the CPU fan, and the GPU fan |
| `A` | Automatic (NBFC's temperature curve) |
| `O` | Off: stop the chosen fan (or both) |
| `T` | Turbo, 100 % |
| `1`–`9`, `0` | Fix the speed at 10–90 %, or 100 % |
| `↑` `↓` | Speed up or down by 5 % |
| `←` `→`, `Enter` | Move between presets and apply one |
| `Esc` | Close |

From a script or a key binding:

```bash
omarchy-shell io.github.rob-d3v.omafan toggle
```

A fixed speed stays after the panel closes, until you choose Auto again. When a fan
goes past the config's critical temperature, NBFC runs it at full speed whatever was
asked, and the panel says so. That also holds for Off: a stopped fan starts again
at full speed once the critical temperature is reached.

## Remove

```bash
~/.config/omarchy/plugins/io.github.rob-d3v.omafan/launcher.sh remove
omarchy plugin remove io.github.rob-d3v.omafan
```

To give fan control back to the BIOS, stop NBFC: `sudo systemctl disable --now nbfc_service`.

## Development

```bash
node --test test/
omarchy plugin validate .
```

`Model.js` holds the parsing and the commands and is tested under node. `Widget.qml`
is the bar icon and panel, built on Omarchy's `Panel`, `KeyboardPanel`, and controls.

## License

MIT. See [LICENSE](LICENSE).
