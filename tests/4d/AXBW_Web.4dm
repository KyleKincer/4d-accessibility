Form.events.push(New object("kind"; "web"; "code"; Form event code))
Case of
 : (Form event code=On Load)
  WA OPEN URL(*; "Web"; File("/RESOURCES/web-url.txt").getText())
 : (Form event code=On End URL Loading)
  Form.webURL:=WA Get current URL(*; "Web")
  Form.webReady:=True
 : (Form event code=On URL Loading Error)
  var $url; $description : Text
  var $code : Integer
  WA GET LAST URL ERROR(*; "Web"; $url; $description; $code)
  Form.webError:=New object("url"; $url; "description"; $description; "code"; $code)
End case
