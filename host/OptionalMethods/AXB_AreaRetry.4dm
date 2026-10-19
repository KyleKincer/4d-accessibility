// Runs in its own process: after a pause, start the bridge again in a window whose session failed.
#DECLARE($id : Text; $window : Integer; $delay : Integer)
DELAY PROCESS(Current process; $delay*60)
CALL FORM($window; Formula(AXB_Area("retry"; $1)); $id)
