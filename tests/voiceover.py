"""VoiceOver keyboard navigation guarded by an owned fixture's PID and project."""
import ctypes as c
from pathlib import Path
import subprocess
import os
import signal
import time
import re

import mac_ax as ax


class OwnedApplication:
    """Retain the specific running app, including after its PID is reused."""
    def __init__(self, pid):
        self.pid = pid
        self.identity = self.process_identity()
        self.pointer = None
        if self.identity is None:
            return
        c.CDLL("/System/Library/Frameworks/AppKit.framework/AppKit")
        self.objc = c.CDLL("/usr/lib/libobjc.A.dylib")
        self.selector = ax.signature(self.objc, "sel_registerName", c.c_void_p, c.c_char_p)
        get_class = ax.signature(self.objc, "objc_getClass", c.c_void_p, c.c_char_p)
        pool = self.call(get_class(b"NSAutoreleasePool"), "new")
        try:
            self.pointer = self.call(get_class(b"NSRunningApplication"),
                                     "runningApplicationWithProcessIdentifier:", c.c_void_p, (c.c_int, pid))
            if self.pointer:
                self.call(self.pointer, "retain")
        finally:
            self.call(pool, "drain", None)

    def call(self, receiver, selector, result=c.c_void_p, *arguments):
        function = c.CFUNCTYPE(result, c.c_void_p, c.c_void_p, *(kind for kind, _ in arguments))(
            c.cast(self.objc.objc_msgSend, c.c_void_p).value)
        return function(receiver, self.selector(selector.encode()), *(value for _, value in arguments))

    def stop(self):
        if self.alive():
            if self.pointer:
                assert self.call(self.pointer, "terminate", c.c_bool), "Owned assistive application refused normal quit"
            else:
                # Welcome helpers can exist before LaunchServices exposes a
                # running-app object. Recheck the captured PID/birth/command.
                assert self.process_identity() == self.identity, "Owned assistive process changed"
                os.kill(self.pid, signal.SIGTERM)

    def alive(self):
        return bool(self.identity) and self.process_identity() == self.identity and (not self.pointer or not self.call(self.pointer, "isTerminated", c.c_bool))

    def process_identity(self):
        result = subprocess.run(["ps", "-p", str(self.pid), "-o", "lstart=,comm="], capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None

    def __del__(self):
        if getattr(self, "pointer", None):
            self.call(self.pointer, "release", None)


_READING_ROLES = re.compile(r"\b(button|edit text|email field|checkbox|link|summary|heading level \d+|group|web content|html content|scroll area)\b")


def reading_stop(step, role, *labels):
    """Match one English leaf reading stop, excluding interaction summaries."""
    if step["key"] not in ("right", "left") or step.get("shift") or step.get("command") or not step.get("voiceoverModifier", True):
        return False
    text = " ".join(step["caption"].lower().split()).rstrip(" .")
    roles = _READING_ROLES.findall(text)
    # Entering an HTML area announces its first heading with parent context.
    # A separate left/right stop on that heading has just the heading role.
    ending = role.startswith("heading level ") or role == "link" or text.endswith(", " + role) or (role == "group" and text.endswith(", empty group"))
    return roles == [role] and ending and all(label.lower() in text for label in labels)


def reading_stop_index(steps, role, *labels, after=-1):
    return next((i for i, step in enumerate(steps) if i > after and reading_stop(step, role, *labels)), None)


class VoiceOver:
    def __init__(self, process, project, title, output, ocr):
        self.process, self.project, self.title = process, Path(project).resolve() if project else None, title
        self.executable = Path(process.args[0]).resolve()
        self.output, self.ocr = Path(output), Path(ocr)
        self.output.mkdir(exist_ok=True)
        self.steps = []
        self.owned = False
        self.changed_caption = False
        self.caption_restoration_verified = False
        self.accepted_quickstart = False
        self.quickstart_pids = set()
        self.owned_applications = {}
        self.voiceover_pid = None

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
            voiceover_pids = self.pids("VoiceOver")
            self.quickstart_pids.update(quickstart)
            for pid in quickstart + voiceover_pids:
                if pid not in self.owned_applications:
                    self.owned_applications[pid] = OwnedApplication(pid)
            if voiceover_pids:
                assert len(voiceover_pids) == 1, "Ambiguous started VoiceOver session"
                self.voiceover_pid = voiceover_pids[0]
            if self.accepted_quickstart:
                return bool(voiceover_pids) and self.owned_applications[self.voiceover_pid].alive() and self.pids("VoiceOver") == voiceover_pids
            if not quickstart:
                # Once its welcome has been dismissed, VoiceOver starts without Quickstart.
                if voiceover_pids and self.owned_applications[self.voiceover_pid].alive():
                    self.voiceover_seen = getattr(self, "voiceover_seen", None) or time.monotonic()
                    return time.monotonic() - self.voiceover_seen >= 3 and not self.pids("VoiceOver Quickstart")
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
            self.guard_owned_voiceover()
            ax.capture_window(self.voiceover_pid, self.output / "initial-caption.png")
        except RuntimeError as error:
            if str(error) != "The fixture has no onscreen window to capture":
                raise
            self.key("f10", command=True, fn=True, capture=False)
            self.changed_caption = True

    def key(self, name, shift=False, command=False, toggle=False, fn=False, capture=True, voiceover=True, _cleanup=False):
        guard = self.guard
        if _cleanup:
            caption_shortcut = name == "f10" and command and fn and voiceover and not (shift or toggle or capture)
            stop_shortcut = name == "f5" and toggle and not (shift or command or fn)
            assert caption_shortcut or stop_shortcut, "Invalid owned VoiceOver cleanup shortcut"
            guard = self.guard_owned_voiceover
        guard()
        self.guard_owned_voiceover()
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
            guard()
            self.guard_owned_voiceover()
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
        self.guard_owned_voiceover()
        image = self.output / f"step-{len(self.steps):03}.png"
        ax.capture_window(self.voiceover_pid, image)
        return " ".join(subprocess.check_output([str(self.ocr), str(image)], text=True).split())

    def guard_owned_voiceover(self):
        assert self.owned and self.pids("VoiceOver") == [self.voiceover_pid], "Owned VoiceOver session changed"
        assert self.owned_applications[self.voiceover_pid].alive(), "Owned VoiceOver process has exited"

    def restore_caption(self, *, cleanup=False):
        def hidden():
            self.guard_owned_voiceover()
            try:
                ax.capture_window(self.voiceover_pid, self.output / "caption-restoration.png")
            except RuntimeError as error:
                if str(error) == "The fixture has no onscreen window to capture":
                    return True
                raise
            return False

        # A prior attempt can hide the panel before its verification fails.
        # Observe first so retrying cannot toggle it back into view.
        if not hidden():
            self.key("f10", command=True, fn=True, capture=False, _cleanup=cleanup)
            ax.wait_for(hidden, "Owned caption panel did not return to its hidden baseline", timeout=5)
        self.caption_restoration_verified = True
        self.changed_caption = False

    def stop(self):
        failure = None
        try:
            if self.owned and self.pids("VoiceOver"):
                if self.changed_caption:
                    self.restore_caption()
                self.key("f5", toggle=True)
        except BaseException as caught:
            failure = caught
            # These two shortcuts belong to VoiceOver itself. Only its captured
            # process may receive them; they do not require the fixture window.
            if self.changed_caption:
                try:
                    self.restore_caption(cleanup=True)
                except BaseException as caption_error:
                    failure.add_note("Caption restoration failed: " + repr(caption_error))
            try:
                self.key("f5", toggle=True, _cleanup=True)
            except BaseException as toggle_error:
                failure.add_note("Owned VoiceOver shortcut failed: " + repr(toggle_error))
        # Attempt every captured app even if an earlier one refuses to quit.
        # Retained running-app objects and PID/birth/command guards protect any
        # replacement or preexisting user session. This also verifies Quickstart.
        for application in self.owned_applications.values():
            try:
                application.stop()
            except BaseException as cleanup_error:
                if failure is None:
                    failure = cleanup_error
                else:
                    failure.add_note("Owned assistive application quit failed: " + repr(cleanup_error))
        try:
            ax.wait_for(lambda: not any(app.alive() for app in self.owned_applications.values()),
                        "Owned assistive applications did not stop", timeout=10)
            self.owned = False
        except BaseException as wait_error:
            if failure is None:
                failure = wait_error
            else:
                failure.add_note("Owned assistive cleanup verification failed: " + repr(wait_error))
        if self.changed_caption:
            caption_error = AssertionError("Owned caption setting was not restored")
            if failure is None:
                failure = caption_error
            else:
                failure.add_note(str(caption_error))
        if failure is not None:
            raise failure
