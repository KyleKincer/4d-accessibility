// Reproduce standard 4D dialogs without any plugin, component or host form.
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "confirm")))
CONFIRM("AX confirmation probe"; "Continue"; "Cancel")
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "alert"; "confirmation"; OK)))
ALERT("AX alert probe"; "Close")
File("/RESOURCES/phase.json").setText(JSON Stringify(New object("phase"; "complete")))
QUIT 4D
