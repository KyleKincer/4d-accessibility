// Prepare one generated form instance. Application data and event forwarding
// have separate lifetimes; the hidden binding belongs to the actual form.
// The result always carries the form to open: the prepared copy on success,
// or the caller's original form when preparation fails. A failure is reported
// once through options.onError with phase "prepare", so a bridge error can
// never skip a business dialog. Callers open $result.form either way.
#DECLARE($form : Object; $data : Object; $options : Object; $operation : Text) -> $result : Object
var $prepared; $context; $page : Object
var $events : Collection
var $event : Variant
var $method : Text
$result:=New object("ok"; False; "error"; "invalidDynamicForm"; "form"; $form)
// One pass of validation; break leaves the block with $result.error set.
While (True)
 If (($form=Null) | ($data=Null) | ($options=Null))
  break
 End if
 If (New collection("start"; "register").indexOf($operation)<0)
  $result.error:="invalidDynamicOperation"
  break
 End if
 If ((New collection(4D.Object).indexOf(OB Class($data))#0) || OB Is shared($data))
  $result.error:="unsupportedDynamicData"
  break
 End if
 If ($data.axbDynamic#Null)
  If (Not($data.axbDynamic.closed=True))
   $result.error:="dynamicDataInUse"
   break
  End if
 End if
 If (($data.axbForm#Null) | ($data.axbView#Null))
  $result.error:="dynamicDataInUse"
  break
 End if
 If (OB Is defined($form; "method"))
  If (Value type($form.method)#Is text)
   $result.error:="invalidDynamicMethod"
   break
  End if
  $method:=$form.method
 End if
 If ($method="AXB_DynamicEvent")
  $result.error:="alreadyPreparedDynamicForm"
  break
 End if
 If ((Value type($form.pages)#Is collection) | ($form.pages=Null))
  break
 End if
 For each ($page; $form.pages)
  If ($page#Null)
   If ($page.objects#Null)
    If (OB Is defined($page.objects; "__AXB_DynamicContext"))
     $result.error:="reservedDynamicObject"
    End if
   End if
  End if
 End for each
 If ($result.error="reservedDynamicObject")
  break
 End if
 $events:=New collection
 If (OB Is defined($form; "events"))
  If (Value type($form.events)#Is collection)
   $result.error:="invalidDynamicEvents"
   break
  End if
  $events:=$form.events.copy()
 Else
  If ($method#"")
   $result.error:="missingDynamicEvents"
   break
  End if
 End if
 For each ($event; $events)
  If ((Value type($event)#Is text) & (Value type($event)#Is real) & (Value type($event)#Is longint))
   $result.error:="invalidDynamicEvents"
  End if
 End for each
 If ($result.error="invalidDynamicEvents")
  break
 End if
 $context:=New object("method"; $method; "onLoad"; (($events.indexOf("onLoad")>=0) | ($events.indexOf(On Load)>=0)); "onUnload"; (($events.indexOf("onUnload")>=0) | ($events.indexOf(On Unload)>=0)); "options"; $options; "operation"; $operation; "closed"; False)
 // On Load transfers this preparation context into a form-owned dynamic variable.
 // The data then retains only its ownership/result marker, with no reference cycle.
 $data.axbDynamic:=$context
 If (Not($context.onLoad))
  $events.push("onLoad")
 End if
 If (Not($context.onUnload))
  $events.push("onUnload")
 End if
 $prepared:=OB Copy($form)
 If ($prepared.pages.length=0)
  $prepared.pages.push(Null)
 End if
 If ($prepared.pages[0]=Null)
  $prepared.pages[0]:=New object("objects"; New object)
 End if
 If ($prepared.pages[0].objects=Null)
  $prepared.pages[0].objects:=New object
 End if
 $prepared.pages[0].objects.__AXB_DynamicContext:=New object("type"; "input"; "dataSourceTypeHint"; "object"; "dataSource"; ""; "placeholder"; JSON Stringify(New object("method"; $method; "onLoad"; $context.onLoad; "onUnload"; $context.onUnload)); "left"; 0; "top"; 0; "width"; 1; "height"; 1; "visibility"; "hidden"; "enterable"; False)
 $prepared.method:="AXB_DynamicEvent"
 $prepared.events:=$events
 $result:=New object("ok"; True; "form"; $prepared)
 break
End while
If (Not($result.ok=True))
 AXB_DynamicFailure($result; $options; "prepare")
End if
