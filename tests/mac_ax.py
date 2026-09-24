"""Small macOS AX client for disposable fixture tests, using the agent host's grant.

No mouse/keyboard injection, AppleScript automation grant, or separately signed
application is required. Tests must identify their own fixture before acting.
"""
import ctypes as c
import subprocess
import re
import tempfile
from pathlib import Path
import time


CF = c.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
AX = c.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")


def signature(lib, name, result, *arguments):
    function = getattr(lib, name)
    function.restype = result
    function.argtypes = arguments
    return function


retain = signature(CF, "CFRetain", c.c_void_p, c.c_void_p)
release = signature(CF, "CFRelease", None, c.c_void_p)
type_id = signature(CF, "CFGetTypeID", c.c_ulong, c.c_void_p)
equal = signature(CF, "CFEqual", c.c_bool, c.c_void_p, c.c_void_p)
make_string = signature(CF, "CFStringCreateWithCString", c.c_void_p, c.c_void_p, c.c_char_p, c.c_uint32)
string_length = signature(CF, "CFStringGetLength", c.c_long, c.c_void_p)
string_bytes = signature(CF, "CFStringGetCString", c.c_bool, c.c_void_p, c.c_void_p, c.c_long, c.c_uint32)
array_count = signature(CF, "CFArrayGetCount", c.c_long, c.c_void_p)
array_value = signature(CF, "CFArrayGetValueAtIndex", c.c_void_p, c.c_void_p, c.c_long)
boolean_value = signature(CF, "CFBooleanGetValue", c.c_bool, c.c_void_p)
number_value = signature(CF, "CFNumberGetValue", c.c_bool, c.c_void_p, c.c_int, c.c_void_p)
copy_attribute = signature(AX, "AXUIElementCopyAttributeValue", c.c_int, c.c_void_p, c.c_void_p, c.POINTER(c.c_void_p))
set_attribute = signature(AX, "AXUIElementSetAttributeValue", c.c_int, c.c_void_p, c.c_void_p, c.c_void_p)
attribute_settable = signature(AX, "AXUIElementIsAttributeSettable", c.c_int, c.c_void_p, c.c_void_p, c.POINTER(c.c_bool))
copy_actions = signature(AX, "AXUIElementCopyActionNames", c.c_int, c.c_void_p, c.POINTER(c.c_void_p))
perform_action = signature(AX, "AXUIElementPerformAction", c.c_int, c.c_void_p, c.c_void_p)
copy_element_at_position = signature(AX, "AXUIElementCopyElementAtPosition", c.c_int,
                                     c.c_void_p, c.c_float, c.c_float, c.POINTER(c.c_void_p))
create_application = signature(AX, "AXUIElementCreateApplication", c.c_void_p, c.c_int)
set_timeout = signature(AX, "AXUIElementSetMessagingTimeout", c.c_int, c.c_void_p, c.c_float)
trusted = signature(AX, "AXIsProcessTrusted", c.c_bool)
TYPE_STRING = signature(CF, "CFStringGetTypeID", c.c_ulong)()
TYPE_ARRAY = signature(CF, "CFArrayGetTypeID", c.c_ulong)()
TYPE_BOOLEAN = signature(CF, "CFBooleanGetTypeID", c.c_ulong)()
TYPE_NUMBER = signature(CF, "CFNumberGetTypeID", c.c_ulong)()
TYPE_ELEMENT = signature(AX, "AXUIElementGetTypeID", c.c_ulong)()
TYPE_AX_VALUE = signature(AX, "AXValueGetTypeID", c.c_ulong)()
ax_value_type = signature(AX, "AXValueGetType", c.c_int, c.c_void_p)
ax_value_get = signature(AX, "AXValueGetValue", c.c_bool, c.c_void_p, c.c_int, c.c_void_p)
UTF8 = 0x08000100


def convert(pointer):
    kind = type_id(pointer)
    if kind == TYPE_AX_VALUE:
        value_kind = ax_value_type(pointer)
        # CGPoint and CGSize both contain two CGFloat values on this 64-bit host.
        if value_kind in (1, 2):
            pair = (c.c_double * 2)()
            return tuple(pair) if ax_value_get(pointer, value_kind, c.byref(pair)) else None
        if value_kind == 4:
            pair = (c.c_long * 2)()
            return tuple(pair) if ax_value_get(pointer, value_kind, c.byref(pair)) else None
        return None
    if kind == TYPE_STRING:
        size = string_length(pointer) * 4 + 1
        if size > 4 * 1024 * 1024 + 1:
            raise RuntimeError("Fixture AX text exceeded its bound")
        buffer = c.create_string_buffer(size)
        if not string_bytes(pointer, buffer, size, UTF8):
            raise RuntimeError("Cannot decode fixture AX text")
        return buffer.value.decode("utf-8")
    if kind == TYPE_ELEMENT:
        return Element(retain(pointer))
    if kind == TYPE_ARRAY:
        count = array_count(pointer)
        if count > 2000:
            raise RuntimeError("Fixture AX array exceeded its bound")
        return [convert(array_value(pointer, index)) for index in range(count)]
    if kind == TYPE_BOOLEAN:
        return boolean_value(pointer)
    if kind == TYPE_NUMBER:
        value = c.c_double()
        return value.value if number_value(pointer, 13, c.byref(value)) else None
    return None


class Element:
    def __init__(self, pointer):
        self.pointer = pointer

    def same_as(self, other):
        return isinstance(other, Element) and equal(self.pointer, other.pointer)

    def __del__(self):
        if self.pointer:
            release(self.pointer)

    def read(self, name):
        key = make_string(None, name.encode(), UTF8)
        value = c.c_void_p()
        try:
            if copy_attribute(self.pointer, key, c.byref(value)) != 0:
                return None
            return convert(value.value)
        finally:
            release(key)
            if value.value:
                release(value.value)

    def count(self, name):
        function = signature(AX, "AXUIElementGetAttributeValueCount", c.c_int, c.c_void_p, c.c_void_p, c.POINTER(c.c_long))
        key = make_string(None, name.encode(), UTF8)
        value = c.c_long()
        try:
            error = function(self.pointer, key, c.byref(value))
            if error:
                raise RuntimeError(f"AX array count failed: {name}, {error}")
            return value.value
        finally:
            release(key)

    def slice(self, name, index, maximum):
        if index < 0 or not 0 <= maximum <= 2000:
            raise ValueError("Use nonnegative indexed AX slices of at most 2000 elements")
        function = signature(AX, "AXUIElementCopyAttributeValues", c.c_int, c.c_void_p, c.c_void_p, c.c_long, c.c_long, c.POINTER(c.c_void_p))
        key = make_string(None, name.encode(), UTF8)
        value = c.c_void_p()
        try:
            error = function(self.pointer, key, index, maximum, c.byref(value))
            if error:
                raise RuntimeError(f"AX array slice failed: {name}, {error}")
            return convert(value.value)
        finally:
            release(key)
            if value.value:
                release(value.value)

    def cell(self, column, row):
        function = signature(AX, "AXUIElementCopyParameterizedAttributeValue", c.c_int, c.c_void_p, c.c_void_p, c.c_void_p, c.POINTER(c.c_void_p))
        number = signature(CF, "CFNumberCreate", c.c_void_p, c.c_void_p, c.c_int, c.c_void_p)
        array = signature(CF, "CFArrayCreate", c.c_void_p, c.c_void_p, c.POINTER(c.c_void_p), c.c_long, c.c_void_p)
        column_value, row_value = c.c_long(column), c.c_long(row)
        numbers = [number(None, 14, c.byref(column_value)), number(None, 14, c.byref(row_value))]
        pointers = (c.c_void_p * 2)(*numbers)
        argument = array(None, pointers, 2, None)
        key = make_string(None, b"AXCellForColumnAndRow", UTF8)
        value = c.c_void_p()
        try:
            error = function(self.pointer, key, argument, c.byref(value))
            if error:
                raise RuntimeError(f"AX indexed cell failed: {column}, {row}, {error}")
            return convert(value.value)
        finally:
            release(key)
            release(argument)
            for item in numbers:
                release(item)
            if value.value:
                release(value.value)

    def actions(self):
        value = c.c_void_p()
        error = copy_actions(self.pointer, c.byref(value))
        try:
            return convert(value.value) if error == 0 and value.value else []
        finally:
            if value.value:
                release(value.value)

    def press(self):
        return self.perform("AXPress")

    def perform(self, name):
        action = make_string(None, name.encode(), UTF8)
        try:
            return perform_action(self.pointer, action)
        finally:
            release(action)

    def at_position(self, x, y):
        """Resolve a screen point through this application's public AX API."""
        result = c.c_void_p()
        error = copy_element_at_position(self.pointer, x, y, c.byref(result))
        if error:
            raise RuntimeError(f"Fixture AX position lookup failed: {error}")
        return Element(result.value)

    def set_text(self, text):
        return self.set_string("AXValue", text)

    def set_boolean(self, name, value):
        key = make_string(None, name.encode(), UTF8)
        boolean = c.c_void_p.in_dll(CF, "kCFBooleanTrue" if value else "kCFBooleanFalse").value
        try:
            return set_attribute(self.pointer, key, boolean)
        finally:
            release(key)

    def set_string(self, name, text):
        key = make_string(None, name.encode(), UTF8)
        value = make_string(None, text.encode(), UTF8)
        try:
            return set_attribute(self.pointer, key, value)
        finally:
            release(value)
            release(key)

    def set_range(self, name, location, length):
        create = signature(AX, "AXValueCreate", c.c_void_p, c.c_int, c.c_void_p)
        pair = (c.c_long * 2)(location, length)
        value = create(4, c.byref(pair))
        key = make_string(None, name.encode(), UTF8)
        try:
            return set_attribute(self.pointer, key, value)
        finally:
            release(value)
            release(key)

    def is_settable(self, name):
        key = make_string(None, name.encode(), UTF8)
        value = c.c_bool()
        try:
            code = attribute_settable(self.pointer, key, c.byref(value))
            if code != 0:
                raise RuntimeError(f"Cannot read {name} mutability: {code}")
            return value.value
        finally:
            release(key)

    def set_elements(self, name, elements):
        """Set an AX element-array attribute while keeping its elements alive."""
        create = signature(CF, "CFArrayCreate", c.c_void_p, c.c_void_p, c.POINTER(c.c_void_p), c.c_long, c.c_void_p)
        pointers = (c.c_void_p * len(elements))(*(e.pointer for e in elements))
        key = make_string(None, name.encode(), UTF8)
        value = create(None, pointers, len(elements), None)
        try:
            return set_attribute(self.pointer, key, value)
        finally:
            release(value)
            release(key)

    def find(self, suffix):
        pending = [self]
        for _ in range(2000):
            if not pending:
                return None
            element = pending.pop()
            identifier = element.read("AXIdentifier")
            if isinstance(identifier, str) and identifier.startswith("axb.") and identifier.endswith(suffix):
                return element
            pending.extend(x for x in (element.read("AXChildren") or []) if isinstance(x, Element))
        raise RuntimeError("Fixture AX traversal exceeded its bound")


def application(pid):
    if not trusted():
        raise RuntimeError("The invoking process lacks macOS Accessibility permission")
    element = Element(create_application(pid))
    set_timeout(element.pointer, 2)
    return element


def system():
    """Resolve the actual screen target, including windows from other apps."""
    if not trusted():
        raise RuntimeError("The invoking process lacks macOS Accessibility permission")
    create = signature(AX, "AXUIElementCreateSystemWide", c.c_void_p)
    return Element(create())


def capture_window(pid, destination):
    """Capture only the frontmost onscreen window belonging to the fixture PID."""
    graphics = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    window_list = signature(graphics, "CGWindowListCopyWindowInfo", c.c_void_p, c.c_uint32, c.c_uint32)
    dictionary_value = signature(CF, "CFDictionaryGetValue", c.c_void_p, c.c_void_p, c.c_void_p)
    windows = window_list(1, 0)
    if not windows:
        raise RuntimeError("Cannot enumerate fixture windows; check screen-capture permission")

    def property_value(dictionary, name):
        key = make_string(None, name.encode(), UTF8)
        try:
            value = dictionary_value(dictionary, key)
            return convert(value) if value else None
        finally:
            release(key)

    try:
        for index in range(array_count(windows)):
            window = array_value(windows, index)
            if property_value(window, "kCGWindowOwnerPID") == pid:
                number = int(property_value(window, "kCGWindowNumber"))
                subprocess.run(["/usr/sbin/screencapture", "-x", "-l", str(number), str(destination)], check=True, timeout=10)
                return
    finally:
        release(windows)
    raise RuntimeError("The fixture has no onscreen window to capture")


def wait_for(predicate, message, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.04)
    raise AssertionError(message)


def process_architecture(pid):
    """Read the actual host architecture, including Rosetta translation."""
    with tempfile.TemporaryDirectory(prefix="axb-process-sample-") as directory:
        path = Path(directory) / "sample.txt"
        subprocess.run(["/usr/bin/sample", str(pid), "1", "-file", str(path)],
                       check=True, capture_output=True, timeout=15)
        match = re.search(r"^Code Type:\s+(.+)$", path.read_text(), re.M)
        if match is None:
            raise RuntimeError("Cannot verify fixture process architecture")
        return match[1].strip()
