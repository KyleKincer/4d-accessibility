var $window : Integer
ON ERR CALL("AXB_FixtureError")
$window:=Open form window("Probe"; Plain form window)
SET WINDOW TITLE("4D accessibility probe 2"; $window)
DIALOG("Probe"; New object)
CLOSE WINDOW($window)
