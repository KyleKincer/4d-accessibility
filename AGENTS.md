# Working on 4D Accessibility

Read [current status](skills/4d-accessibility/references/STATUS.md) before claiming coverage. For host integration, use [the integration skill](skills/4d-accessibility/SKILL.md); for builds and tests, use [CONTRIBUTING.md](CONTRIBUTING.md).

Edit canonical helpers in `host/Methods` and `host/OptionalMethods`. Refresh host copies with `install_host_methods.py`. Preserve native editors, validation, timers and business handlers. Host array pointers must stay in host adapters because a compiled component cannot dereference pointers into an interpreted host.

Run 4D compiler drivers and graphical fixtures sequentially. A compiler pass does not prove compiled desktop execution or assistive-technology behavior. An AX success response proves request transport, not application completion. Keep unresolved families and failed tests in the status document.
