var $window : Integer
var $data : Object
ON ERR CALL("DropdownError")
ARRAY REAL(DropdownNumbers; 3)
DropdownNumbers{1}:=1.5
DropdownNumbers{2}:=2.5
DropdownNumbers{3}:=3.5
DropdownNumbers:=1
ARRAY DATE(DropdownDates; 3)
DropdownDates{1}:=!2026-09-24!
DropdownDates{2}:=!2026-09-25!
DropdownDates{3}:=!2026-09-26!
DropdownDates:=1
ARRAY TIME(DropdownTimes; 3)
DropdownTimes{1}:=?09:00:00?
DropdownTimes{2}:=?10:00:00?
DropdownTimes{3}:=?11:00:00?
DropdownTimes:=1
DropdownSublist:=New list
APPEND TO LIST(DropdownSublist; "Small"; 401)
APPEND TO LIST(DropdownSublist; "Large"; 402)
DropdownHierarchy:=New list
APPEND TO LIST(DropdownHierarchy; "Sizes"; 400; DropdownSublist; False)
APPEND TO LIST(DropdownHierarchy; "Default"; 500)
SELECT LIST ITEMS BY REFERENCE(DropdownHierarchy; 500)
ARRAY LONGINT(DropdownIntegers; 3)
DropdownIntegers{1}:=10
DropdownIntegers{2}:=20
DropdownIntegers{3}:=30
DropdownIntegers:=1
DropdownList:=New list
APPEND TO LIST(DropdownList; "Red"; 101)
APPEND TO LIST(DropdownList; "Blue"; 202)
APPEND TO LIST(DropdownList; "Green"; 303)
$data:=New object("sequence"; 0; "events"; New collection; "objectChoice"; New object("values"; New collection("Maple"; "Walnut"; "Ash"); "index"; 0; "private"; "must-not-be-published"); "numberChoice"; New object("values"; New collection(4.5; 5.5; 6.5); "index"; 0); "valueChoice"; "Red"; "referenceChoice"; 101)
$data.placeholder:=New object("values"; New collection("One"; "Two"); "index"; -1; "currentValue"; "Choose one")
$data.disabled:=New object("values"; New collection("Fixed"; "Other"); "index"; 0)
$data.unhandled:=New object("values"; New collection(True; False); "index"; 0)
$data.note:="Ordinary editor"
$window:=Open form window("Root"; Plain form window)
DIALOG("Root"; $data)
CLOSE WINDOW($window)
CLEAR LIST(DropdownList)
CLEAR LIST(DropdownHierarchy; *)
QUIT 4D
