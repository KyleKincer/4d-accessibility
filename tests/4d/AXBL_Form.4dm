var $reply : Object
Case of
 : (Form event code=On Load)
  Form.scope:="fixture"
  Form.hooks:=New object
  Form.nativeEvents:=0
  Form.arrayOptions:=New object("objectName"; "Array"; "id"; "array"; "label"; "Array list"; "kind"; "array"; "keyColumn"; "ArrayID"; "labelColumns"; New collection(New object("objectName"; "ArrayName")))
  Form.collectionOptions:=New object("objectName"; "Collection"; "id"; "collection"; "label"; "Collection list"; "kind"; "collection"; "keyColumn"; "CollectionID"; "keyProperty"; "id"; "selection"; Formula(Form.selected); "labelColumns"; New collection(New object("objectName"; "CollectionName"; "property"; "name")))
  If (Form.entity=True)
   Form.collectionOptions.kind:="entity"
  End if
  Form.arrayOptions.onSelection:=Formula(AXBL_Selection("array"))
  Form.collectionOptions.onSelection:=Formula(AXBL_Selection("collection"))
  $reply:=AXB_Form("start"; New object("label"; "Native list boxes"; "describe"; Formula(AXBL_Describe); "apply"; Formula(AXBL_Apply($1)); "onError"; Formula(AXBL_Failed($1))))
 : (Form event code=On Unload)
  $reply:=AXB_Form("stop"; New object)
End case
