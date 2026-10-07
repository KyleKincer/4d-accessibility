"""Owned VoiceOver session for tests: HID-tap key events and VoiceOver's AppleScript `last phrase`.

Requires "Allow VoiceOver to be controlled with AppleScript". Refuses an existing session.
"""
import ctypes as c
import subprocess
import threading
import time

_graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
_foundation = c.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
_graphics.CGEventCreateKeyboardEvent.restype = c.c_void_p
_graphics.CGEventCreateKeyboardEvent.argtypes = (c.c_void_p, c.c_uint16, c.c_bool)
_graphics.CGEventSetFlags.argtypes = (c.c_void_p, c.c_uint64)
_graphics.CGEventSetType.argtypes = (c.c_void_p, c.c_uint32)
_graphics.CGEventPost.argtypes = (c.c_uint32, c.c_void_p)
_graphics.CGEventKeyboardSetUnicodeString.argtypes = (c.c_void_p, c.c_ulong, c.POINTER(c.c_uint16))
_foundation.CFRelease.argtypes = (c.c_void_p,)

CODES = {"right": 124, "left": 123, "down": 125, "up": 126, "space": 49, "return": 36, "escape": 53, "tab": 48, "delete": 51, "backslash": 42,
         "home": 115, "end": 119, "m": 46}
MODIFIERS = {"ctrl": (59, 1 << 18), "option": (58, 1 << 19), "shift": (56, 1 << 17), "cmd": (55, 1 << 20)}
VO = ("ctrl", "option")
_guard = None


def set_guard(check):
    """Run check() before every posted key; it must raise when input could reach another application."""
    global _guard
    _guard = check


def guard_frontmost(pid, ax):
    """A guard that requires the owned process to be the frontmost application."""
    def check():
        if ax.application(pid).read("AXFrontmost") is not True:
            raise RuntimeError("The owned application lost the foreground; refusing to post input")
    return check


def _post(code, down, flags, modifier=False):
    event = _graphics.CGEventCreateKeyboardEvent(None, code, down)
    if modifier:
        _graphics.CGEventSetType(event, 12)
    _graphics.CGEventSetFlags(event, flags)
    _graphics.CGEventPost(0, event)
    _foundation.CFRelease(event)


def key(name, modifiers=()):
    if _guard:
        _guard()
    active = 0
    held = [MODIFIERS[m] for m in modifiers]
    for code, bit in held:
        active |= bit
        _post(code, True, active, True)
        time.sleep(0.06)
    try:
        for down in (True, False):
            _post(CODES[name], down, active)
            time.sleep(0.06)
    finally:
        for code, bit in reversed(held):
            active &= ~bit
            _post(code, False, active, True)
            time.sleep(0.06)
    time.sleep(0.8)


def type_text(text):
    for character in text:
        if _guard:
            _guard()
        units = (c.c_uint16 * 1)(ord(character))
        for down in (True, False):
            event = _graphics.CGEventCreateKeyboardEvent(None, 49 if character == " " else 0, down)
            _graphics.CGEventKeyboardSetUnicodeString(event, 1, units)
            _graphics.CGEventSetFlags(event, 0)
            _graphics.CGEventPost(0, event)
            _foundation.CFRelease(event)
            time.sleep(0.04)
        time.sleep(0.12)


def _osa(script):
    result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def last_phrase():
    return _osa('tell application "VoiceOver" to get content of last phrase')


def running():
    return subprocess.run(["pgrep", "-x", "VoiceOver"], capture_output=True).returncode == 0


def start(timeout=30):
    if running():
        raise RuntimeError("A VoiceOver session is already running; this test only uses its own session")
    subprocess.run(["open", "/System/Library/CoreServices/VoiceOver.app"], check=True)
    limit = time.monotonic() + timeout
    while time.monotonic() < limit:
        try:
            last_phrase()
            return
        except (RuntimeError, subprocess.TimeoutExpired):
            time.sleep(0.5)
    raise TimeoutError("VoiceOver did not accept AppleScript")


def stop(timeout=15):
    if running():
        try:
            _osa('tell application "VoiceOver" to quit')
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
    limit = time.monotonic() + timeout
    while time.monotonic() < limit and running():
        time.sleep(0.3)


class Listener:
    """Continuous record of VoiceOver's last phrase, so speech between checks is not missed."""

    def __init__(self):
        self.heard = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        previous = None
        while not self._stop.is_set():
            try:
                phrase = last_phrase()
            except (RuntimeError, subprocess.TimeoutExpired):
                phrase = None
            if phrase is not None and phrase != previous:
                self.heard.append((time.monotonic(), " ".join(phrase.split())))
                previous = phrase
            time.sleep(0.1)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._thread.join(2)

    def mark(self):
        return len(self.heard)

    def since(self, index):
        return list(self.heard[index:])


class Session:
    """An owned VoiceOver session for one fixture, with the older reader's interface:
    key() returns what VoiceOver says after a VoiceOver command, read_caption() its
    latest phrase. Keys are refused unless the fixture process is frontmost."""

    def __init__(self, pid, ax):
        self.pid, self.ax, self.steps = pid, ax, []
        self.heard = None

    def start(self):
        start()
        self.heard = Listener()
        self.heard.start()
        set_guard(guard_frontmost(self.pid, self.ax))
        app = self.ax.application(self.pid)
        if app.read("AXFrontmost") is not True:
            app.set_boolean("AXFrontmost", True)
        self.ax.wait_for(lambda: app.read("AXFrontmost") is True, "Fixture did not regain foreground", timeout=10)
        time.sleep(2)

    def key(self, name, shift=False, voiceover=True, wait=1.2):
        mark = self.heard.mark()
        key(name, (VO if voiceover else ()) + (("shift",) if shift else ()))
        time.sleep(wait)
        text = " ".join(phrase for _, phrase in self.heard.since(mark))
        self.steps.append({"key": name, "shift": shift, "speech": text})
        return text

    def read_caption(self):
        return last_phrase()

    def stop(self):
        # Stop the listener first: its AppleScript polling would relaunch VoiceOver.
        if self.heard:
            self.heard.stop()
        stop()
