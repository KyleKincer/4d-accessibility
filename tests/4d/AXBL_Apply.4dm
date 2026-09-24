#DECLARE($action : Object) -> $result : Object
var $i : Integer
$result:=New object("status"; "rejected"; "message"; "Unsupported action")
Case of
 : (($action.node="array") & ($action.operation="selectRows"))
  $result:=AXB_ListboxSelect(Form.arrayOptions; $action)
 : (($action.node="collection") & ($action.operation="selectRows"))
  $result:=AXB_ListboxSelect(Form.collectionOptions; $action)
  If (Form.cancelPending=True)
   Form.cancelPending:=False
   Form.scope:=Generate UUID
  End if
 : ($action.operation="press")
  Case of
   : ($action.node="entitylimits")
    Form.rows:=Form.rows.copy().add(Form.rows)
   : ($action.node="entitywrong")
    Form.collectionOptions.selection:=Formula(New collection)
   : ($action.node="entitywrongclass")
    Form.collectionOptions.selection:=Formula(ds.AXBOther.newSelection())
   : ($action.node="entitynull")
    Form.collectionOptions.selection:=Formula(Null)
   : ($action.node="entitynumeric")
    Form.collectionOptions.keyProperty:="number"
    LISTBOX SET COLUMN FORMULA(*; "CollectionID"; "This.number"; Is real)
   : ($action.node="entitycomputed")
    Form.collectionOptions.labelColumns[0].property:="computedName"
    LISTBOX SET COLUMN FORMULA(*; "CollectionName"; "This.computedName"; Is text)
   : ($action.node="entitynulllabel")
    Form.collectionOptions.labelColumns[0].property:="optionalLabel"
    LISTBOX SET COLUMN FORMULA(*; "CollectionName"; "This.optionalLabel"; Is text)
   : ($action.node="filter")
    LISTBOX DELETE ROWS(*; "Array"; 5; 1)
    Form.rows:=Form.rows.query("id # :1"; "C0005")
   : ($action.node="rejectselection")
    Form.rejectSelection:=True
   : ($action.node="scopeselection")
    Form.scopeOnSelection:=True
   : ($action.node="fault")
    Form.failConfirm:=True
   : ($action.node="cancelpending")
    Form.cancelPending:=True
   : ($action.node="casekeys")
    aListID{1}:="case"
    aListID{3}:="CASE"
    aListID{4}:="café"
    aListID{5}:="CAFE"
    Form.keyTest:=AXB_ListboxSelect(Form.arrayOptions; New object("operation"; "selectRows"; "node"; "array"; "value"; New collection("array.CASE")))
   : ($action.node="scope")
    Form.scope:=Uppercase(Form.scope)
   : ($action.node="caselabel")
    aListName{1}:=Lowercase(aListName{1})
   : ($action.node="sort")
    LISTBOX SORT COLUMNS(*; "Array"; 1; <)
    LISTBOX SORT COLUMNS(*; "Collection"; 1; <)
   : ($action.node="bottom")
    OBJECT SET SCROLL POSITION(*; "Array"; 594; 1; *)
    OBJECT SET SCROLL POSITION(*; "Collection"; 594; 1; *)
   : ($action.node="top")
    OBJECT SET SCROLL POSITION(*; "Array"; 1; 1; *)
    OBJECT SET SCROLL POSITION(*; "Collection"; 1; 1; *)
   : ($action.node="hide")
    OBJECT SET VISIBLE(*; "ArrayName"; Not(OBJECT Get visible(*; "ArrayName")))
    OBJECT SET VISIBLE(*; "CollectionName"; Not(OBJECT Get visible(*; "CollectionName")))
   : ($action.node="duplicate")
    aListID{600}:=aListID{1}
    If (Form.entity=True)
     // Ordered entity selections can contain the same record more than once.
     Form.rows:=Form.rows.slice(0; 599).copy().add(Form.rows[0])
    Else
     Form.rows[599].id:=Form.rows[0].id
    End if
    Form.rows:=Form.rows
   : ($action.node="single")
    LISTBOX SET PROPERTY(*; "Array"; lk selection mode; lk single)
    LISTBOX SET PROPERTY(*; "Collection"; lk selection mode; lk single)
   : ($action.node="format")
    OBJECT SET FORMAT(*; "ArrayName"; "&x")
    OBJECT SET FORMAT(*; "CollectionName"; "&x")
   : ($action.node="rebind")
    LISTBOX SET COLUMN FORMULA(*; "CollectionName"; "This.id"; Is text)
   : ($action.node="reset")
    ARRAY TEXT(aListID; 600)
    ARRAY TEXT(aListName; 600)
    ARRAY BOOLEAN(aListSelected; 600)
    ARRAY LONGINT(aListControl; 600)
    For ($i; 1; 600)
     aListID{$i}:="A"+String($i; "0000")
     aListName{$i}:="Array item "+String($i; "0000")
     aListSelected{$i}:=False
     aListControl{$i}:=0
    End for
    aListControl{2}:=lk row is hidden
    aListControl{3}:=lk row is disabled
    aListControl{4}:=lk row is not selectable
    If (Form.entity=True)
     Form.rows:=ds.AXBItem.all().orderBy("id asc")
     Form.selected:=ds.AXBItem.newSelection()
    Else
     Form.rows:=New collection
     For ($i; 1; 600)
      Form.rows.push(New object("id"; "C"+String($i; "0000"); "name"; "Collection item "+String($i; "0000")))
     End for
     Form.rows:=Form.rows
     Form.selected:=New collection
    End if
    LISTBOX SET COLUMN FORMULA(*; "CollectionName"; "This.name"; Is text)
    LISTBOX SET COLUMN FORMULA(*; "CollectionID"; "This.id"; Is text)
    Form.collectionOptions.keyProperty:="id"
    Form.collectionOptions.labelColumns[0].property:="name"
    Form.collectionOptions.selection:=Formula(Form.selected)
    OBJECT SET FORMAT(*; "ArrayName"; "")
    OBJECT SET FORMAT(*; "CollectionName"; "")
    OBJECT SET VISIBLE(*; "ArrayName"; True)
    OBJECT SET VISIBLE(*; "CollectionName"; True)
    LISTBOX SET PROPERTY(*; "Array"; lk selection mode; lk multiple)
    LISTBOX SET PROPERTY(*; "Collection"; lk selection mode; lk multiple)
    OBJECT SET SCROLL POSITION(*; "Array"; 1; 1; *)
    OBJECT SET SCROLL POSITION(*; "Collection"; 1; 1; *)
  End case
  $result:=New object("status"; "completed"; "message"; "Fixture operation completed")
End case
Form.lastResult:=$result
