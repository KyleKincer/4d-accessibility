"""VoiceOver keyboard navigation guarded by an owned fixture's PID and project."""
import ctypes as c
from pathlib import Path
import subprocess
import time

import mac_ax as ax


class VoiceOver:
    def __init__(self, process, project, title, output, ocr):
        self.process, self.project, self.title = process, Path(project).resolve() if project else None, title
        self.executable = Path(process.args[0]).resolve()
        self.output, self.ocr = Path(output), Path(ocr)
        self.output.mkdir(exist_ok=True)
        self.steps = []
        self.owned = False
        self.changed_caption = False
        self.accepted_quickstart = False
        self.quickstart_pids = set()

    def guard(self):
        assert self.process.poll() is None, "Owned fixture has exited"
        command = subprocess.check_output(["ps", "-p", str(self.process.pid), "-o", "command="], text=True)
        if self.project:
            assert f"--project {self.project}" in command, "Owned fixture identity changed"
        else:
            assert command.startswith(str(self.executable) + " "), "Owned native fixture identity changed"
        app = ax.application(self.process.pid)
        assert app.read("AXFrontmost") is True, "Owned fixture lost foreground"
        assert any(w.read("AXTitle") == self.title for w in app.read("AXWindows") or []), "Owned fixture window missing"

    @staticmethod
    def pids(name):
        return [int(p) for p in subprocess.run(["pgrep", "-x", name], capture_output=True, text=True).stdout.split()]

    def start(self):
        self.guard()
        assert not self.pids("VoiceOver") and not self.pids("VoiceOver Quickstart"), "Existing VoiceOver session belongs to the user"
        subprocess.run(["open", "/System/Library/CoreServices/VoiceOver.app"], check=True)
        self.owned = True
        # VoiceOver can exist before its welcome helper is launched. Its PID
        # alone does not mean the user has reached an active reading session.
        def running():
            quickstart = self.pids("VoiceOver Quickstart")
            self.quickstart_pids.update(quickstart)
            if self.accepted_quickstart:
                return bool(self.pids("VoiceOver"))
            if not quickstart:
                return False
            for pid in quickstart:
                pending = ax.application(pid).read("AXWindows") or []
                while pending:
                    element = pending.pop()
                    if element.read("AXRole") == "AXButton" and element.read("AXTitle") == "Use VoiceOver":
                        element.press()
                        self.accepted_quickstart = True
                        return False
                    pending.extend(e for e in element.read("AXChildren") or [] if isinstance(e, ax.Element))
            return False
        ax.wait_for(running, "VoiceOver did not start", timeout=20)
        app = ax.application(self.process.pid)
        if app.read("AXFrontmost") is not True:
            app.set_boolean("AXFrontmost", True)
        ax.wait_for(lambda: app.read("AXFrontmost") is True, "Fixture did not regain foreground", timeout=10)
        time.sleep(1)
        try:
            ax.capture_window(self.pids("VoiceOver")[0], self.output / "initial-caption.png")
        except RuntimeError:
            self.key("f10", command=True, fn=True, capture=False)
            self.changed_caption = True

    def key(self, name, shift=False, command=False, toggle=False, fn=False, capture=True, voiceover=True):
        self.guard()
        assert self.pids("VoiceOver"), "VoiceOver is not running"
        codes = {"right": 124, "left": 123, "down": 125, "up": 126, "space": 49, "return": 36, "escape": 53, "home": 115, "end": 119, "f5": 96, "f4": 118, "f10": 109}
        graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        create = ax.signature(graphics, "CGEventCreateKeyboardEvent", c.c_void_p, c.c_void_p, c.c_uint16, c.c_bool)
        flags = ax.signature(graphics, "CGEventSetFlags", None, c.c_void_p, c.c_uint64)
        event_type = ax.signature(graphics, "CGEventSetType", None, c.c_void_p, c.c_uint32)
        post = ax.signature(graphics, "CGEventPost", None, c.c_uint32, c.c_void_p)
        modifiers = [(59, 1 << 18), (58, 1 << 19)] if voiceover else []
        if shift:
            modifiers.append((56, 1 << 17))
        if command:
            modifiers.append((55, 1 << 20))
        if fn:
            modifiers.append((63, 1 << 23))
        if toggle:
            modifiers = [(55, 1 << 20), (63, 1 << 23)]
        active = 0
        for code, bit in modifiers:
            active |= bit
            event = create(None, code, True)
            event_type(event, 12)
            flags(event, active)
            post(0, event)
            ax.release(event)
            time.sleep(0.08)
        try:
            self.guard()
            for down in (True, False):
                event = create(None, codes[name], down)
                flags(event, active)
                post(0, event)
                ax.release(event)
                time.sleep(0.1)
        finally:
            for code, bit in reversed(modifiers):
                active &= ~bit
                event = create(None, code, False)
                event_type(event, 12)
                flags(event, active)
                post(0, event)
                ax.release(event)
                time.sleep(0.08)
        time.sleep(0.5)
        if toggle:
            ax.wait_for(lambda: not self.pids("VoiceOver"), "Owned VoiceOver session did not stop", timeout=10)
            self.owned = False
            return "VoiceOver stopped"
        if not capture:
            return ""
        caption = self.read_caption()
        step = {"key": name, "shift": shift, "command": command, "caption": caption}
        if not voiceover:
            step["voiceoverModifier"] = False
        self.steps.append(step)
        print(step, flush=True)
        return caption

    def read_caption(self):
        """Observe speech after an asynchronous action without moving the VO cursor."""
        self.guard()
        pids = self.pids("VoiceOver")
        assert len(pids) == 1, "Owned VoiceOver session is unavailable"
        image = self.output / f"step-{len(self.steps):03}.png"
        ax.capture_window(pids[0], image)
        return " ".join(subprocess.check_output([str(self.ocr), str(image)], text=True).split())

    def stop(self):
        if self.owned and self.pids("VoiceOver"):
            if self.changed_caption:
                self.key("f10", command=True, fn=True, capture=False)
                self.changed_caption = False
            self.key("f5", toggle=True)
        for pid in self.quickstart_pids.intersection(self.pids("VoiceOver Quickstart")):
            app = ax.application(pid)
            for menu_bar in app.read("AXChildren") or []:
                if menu_bar.read("AXRole") != "AXMenuBar":
                    continue
                for item in menu_bar.read("AXChildren") or []:
                    if item.read("AXTitle") != "VoiceOver Quickstart":
                        continue
                    for menu in item.read("AXChildren") or []:
                        for action in menu.read("AXChildren") or []:
                            if action.read("AXTitle") == "Quit VoiceOver Quickstart":
                                action.press()
