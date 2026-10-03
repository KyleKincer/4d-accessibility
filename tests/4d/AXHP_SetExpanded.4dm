// Explicit application controller in the disposable fixture. It owns one
// targeted native command; the bridge independently observes completion.
#DECLARE($request : Object)
var $row; $level : Integer
$row:=$request.backingRow
$level:=$request.breakLevel
Form.disclosureCalls.push(OB Copy($request))
Case of
 : (Form.disclosureMode="ignore")
  return
 : (Form.disclosureMode="membership")
  AXHP_Key{$row}:=AXHP_Key{$row}+1000
 : (Form.disclosureMode="caption")
  AXHP_Group{$row}:="Changed caption"
 : (Form.disclosureMode="reparent")
  AXHP_Group{$row}:="Moved parent"
 : (Form.disclosureMode="scope")
  Form.scope:=Generate UUID
 : (Form.disclosureMode="loading")
  Form.ready:=False
 : (Form.disclosureMode="replace")
  AXHP_Options.grids.Grouped.setExpanded:=Formula(AXHP_SetExpandedAlternate($1))
 : (Form.disclosureMode="remove")
  OB REMOVE(AXHP_Options.grids.Grouped; "setExpanded")
End case
If ($request.expanded)
 LISTBOX EXPAND(*; $request.objectName; False; lk break row; $row; $level)
Else
 LISTBOX COLLAPSE(*; $request.objectName; False; lk break row; $row; $level)
End if
