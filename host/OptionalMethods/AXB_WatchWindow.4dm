// Attach an accessibility session to the current form window without %AXB Area.
// Invoked via CALL FORM from AXB_WatcherTick, and re-invoked on in-place form switches.
#DECLARE($window : Integer)
var $previousError; $formName; $label : Text
var $table : Pointer
var $tableNum : Integer
var $context; $meta; $options; $storedOptions; $result : Object
var $configured : Variant
ARRAY TEXT($objects; 0)
ARRAY TEXT($methods; 0)
If (($window=0) | (Current form window#$window))
 return
End if
$previousError:=Method called on error(ek local)
ON ERR CALL("AXB_WatchError"; ek local)
$table:=Current form table
$tableNum:=Choose(Is nil pointer($table); 0; Table($table))
$formName:=Current form name
$context:=AXB_FormContext
If (($context#Null) && ($context.active=True))
 If ($context.watched=True)
  If (($context.watchWindow=$window) & ($context.watchTable=$tableNum) & ($context.watchForm=$formName) & (New collection($context.watchFormObj).indexOf(Form)=0))
   ON ERR CALL($previousError; ek local)
   return
  End if
  AXB_FormStop($context)
 Else
  // An %AXB Area or explicit host AXB_Form("start") already owns this window.
  ON ERR CALL($previousError; ek local)
  return
 End if
End if
If ((Value type(Form)#Is object) || (Form=Null))
 ON ERR CALL($previousError; ek local)
 return
End if
FORM GET OBJECTS($objects; Form all pages)
If (($formName="") & (Size of array($objects)=0))
 ON ERR CALL($previousError; ek local)
 return
End if
$meta:=AXB_FormStored("meta")
If (($meta#Null) && (Value type($meta)=Is object) && ($meta.destination="print"))
 ON ERR CALL($previousError; ek local)
 return
End if
$storedOptions:=AXB_FormStored("options")
$label:=""
If (($storedOptions#Null) && (Value type($storedOptions)=Is object) && (Value type($storedOptions.label)=Is text))
 $label:=$storedOptions.label
End if
If ($label="")
 $label:=Get window title($window)
End if
If ($label="")
 $label:=$formName
End if
If ($label="")
 $label:="Application form"
End if
$options:=New object("label"; $label)
METHOD GET NAMES($methods; "AXB_Configure"; *)
If (Find in array($methods; "AXB_Configure")<=0)
 METHOD GET NAMES($methods; "AXB_Configure")
End if
If (Find in array($methods; "AXB_Configure")>0)
 EXECUTE METHOD("AXB_Configure"; $configured; $formName)
 If (($configured#Null) && (Value type($configured)=Is object))
  $options:=OB Copy($configured)
  If (Not(OB Is defined($options; "label")))
   $options.label:=$label
  End if
 End if
End if
// Mirror AXB_Area.4dm screen key precedence: explicit AXB_Configure automationKey ->
// stored root axb.automationKey -> Current form name.
If (Not(OB Is defined($options; "automationKey")) && ($formName#""))
 $options.automationKey:=$formName
 If (($storedOptions#Null) && (Value type($storedOptions)=Is object) && (Value type($storedOptions.automationKey)=Is text))
  $options.automationKey:=$storedOptions.automationKey
 End if
End if
If (Not(OB Is defined($options; "enabled")) && ($storedOptions#Null) && ($storedOptions.enabled=False))
 $options.enabled:=False
End if
If ($options.enabled=False)
 ON ERR CALL($previousError; ek local)
 return
End if
If (($meta#Null) && (Value type($meta)=Is object) && ($meta.destination="listScreen"))
 $options.listScreen:=True
End if
$result:=AXB_Form("start"; $options)
If (($result#Null) && ($result.ok=True))
 $context:=AXB_FormContext
 If ($context#Null)
  $context.watched:=True
  $context.watchWindow:=$window
  $context.watchTable:=$tableNum
  $context.watchForm:=$formName
  $context.watchFormObj:=Form
 End if
End if
ON ERR CALL($previousError; ek local)
