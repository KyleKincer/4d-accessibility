# Performance and activation

What the bridge costs an application, and how to control where it runs.

## Activation

A 4D process with the bridge starts **dormant**. Lifecycle areas do not start their forms' sessions, forms started by hand do not poll, and the providers for forms without an area and for 4D's own windows do not run. The form behaves as if it had no area.

The process becomes **active** when:
- VoiceOver runs, or Switch Control is on, when 4D starts or later;
- an accessibility client reads the contents of one of its windows: for example Voice Control, Full Keyboard Access, an automation tool or a test.

Window managers and other tools that read only window titles and frames do not wake it. Once active, a process stays active until 4D quits. A dormant form is published about 0.2 seconds after the first read of its window.

Each 4D client decides alone, so only the clients whose users run an assistive technology pay its cost. No application code is needed.

### Choosing the mode on a machine

The `Activation` setting in the `io.github.kylekincer.4d-accessibility` domain chooses the mode for every 4D on that Mac:

| Value | Meaning |
| --- | --- |
| `auto` (default) | Dormant until an assistive technology needs it, as above |
| `on` | Active from the start |
| `off` | Never active: the plugin installs none of its drawing hooks or observers and describes nothing, so the application runs as without the bridge |

```sh
defaults write io.github.kylekincer.4d-accessibility Activation -string off
defaults delete io.github.kylekincer.4d-accessibility Activation   # back to auto
```

A configuration profile can manage the same domain and key. The `AXB_ACTIVATION` environment variable overrides the setting for one 4D process, for tests and diagnosis. Restart 4D after changing the mode.

`AXB Status` ends with the 4D version, whether the plugin observes 4D's drawing, and the mode and state: for example `4D 20.8; hooks not installed; auto; dormant` or `4D 20.8; hooks installed; auto; active; VoiceOver`. `AXB Active` returns 1 when the process is active.

### Observing 4D's drawing

Forms without a bridge area, 4D's standard messages, editors and Progress windows, and list boxes without a grid entry are published from what 4D draws. The plugin observes the text 4D draws into its form-object layers, and the tab and pop-up cells AppKit draws for it. This depends on how 4D renders, which a new 4D version can change. So by default the plugin installs these observations only on 4D versions it was validated on: currently 4D 20, its LTS and R releases. It installs them when 4D loads it, even while dormant, because 4D builds each line of text once and draws it again from its cache: text built before the observation started could never be read. This is the dormant cost measured below. The `off` mode installs nothing.

The `Hooks` setting in the same domain overrides the version check: `on` observes on any 4D version, `off` never observes. The `AXB_HOOKS` environment variable overrides the setting for one process. Without the observations, forms with a bridge area are still published and operated, but forms without one, 4D's standard messages and editors, and list boxes without a grid entry are not.

```sh
defaults write io.github.kylekincer.4d-accessibility Hooks -string off
```

Lifecycle areas also follow `AXB_Configure`'s `enabled` per form, as before.

## Measurements

`measure_cost.py` builds one compiled project per variant and runs the same script in each. The project opens a small dialog five times and a large form three times. It then leaves the large form idle for 30 seconds, and scrolls its list box for 30 seconds. The large form has 600 buttons, a field and a 2,000-row list box. A one-tick timer records how long the form's process waits between ticks. Work on that process, such as polling, delays the next tick and so the user's next keystroke or click. CPU time and memory are read from outside.

4D 20.8, compiled, Apple Silicon, macOS 26, median of two runs. CPU is the share of one core.

| Variant | Idle CPU | Memory | Pauses over 100 ms in 30 s | Longest pause | Scrolling CPU | Large form opens in |
| --- | --- | --- | --- | --- | --- | --- |
| No bridge | 3.0% | 280 MB | 0 | 65 ms | 23% | 196 ms |
| 0.34.1, plugin only, no areas | 5.8% | 313 MB | 0 | 58 ms | 25% | 204 ms |
| 0.34.1, area in every form | 22.6% | 322 MB | 48 | 191 ms | 39% | 226 ms |
| 0.35.0, area in every form, dormant | 3.8% | 309 MB | 0 | 64 ms | 27% | 199 ms |
| 0.35.0, area in every form, active | 24.2% | 323 MB | 47 | 200 ms | 39% | 213 ms |

Dormant, a form with an area costs what the same form costs without the bridge. Two costs remain:
- about 29 MB, the loaded plugin and component;
- 3–4 points of CPU while 4D redraws continuously, here a list box scrolling every tick. The plugin records the text 4D draws from the start, so that a window open when an assistive technology arrives can be described.

Active, the bridge describes the whole form every 0.1–1 second on the form's own process. On this form each description takes about 170 ms, so the user waits up to that long once or twice a second. In a large customer form, about 650 described elements, one description took about 280 ms under Rosetta. This is the cost assistive-technology users pay today, and the next performance work.

The small dialog opens in 40–80 ms in every variant, with no pattern between them.

Records: [0.34.1](validation/cost-0.34.1.json), [0.35.0](validation/cost-0.35.0-development.json); [activation acceptance](validation/activation-development.json); [drawing observation and first clicks](validation/hooks-policy-development.json).

## Reproduce

```sh
python3 measure_cost.py --server /path/to/4D\ Server.app --variant none --variant plugin --variant area --repeat 2
python3 measure_cost.py --server /path/to/4D\ Server.app --variant plugin --variant area --wake
python3 test_activation_fixture.py --server /path/to/4D\ Server.app --voiceover
```

`--wake` reads each window with an accessibility client first, as VoiceOver does when it enters a window. `--intel` runs 4D under Rosetta. The activation test checks that reading only a window's title and frame leaves the process dormant, that reading its contents or starting VoiceOver wakes it, and the `on` and `off` modes.
