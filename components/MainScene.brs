sub init()
    m.host = m.top.findNode("screenHost")
    m.current = invalid
    m.currentName = ""

    ' Auth gate on boot. §2 / §5.
    token = GetAuthToken()
    if token <> invalid and token <> "" then
        showHome()
    else
        showPairing()
    end if
end sub

sub showPairing()
    swapScreen("PairingScreen")
    m.current.observeField("paired", "onPaired")
end sub

sub showHome()
    swapScreen("HomeScreen")
    ' HomeScreen will request sign-out / 401 via this event. §2, §10.5
    m.current.observeField("signedOut", "onSignedOut")
end sub

' Tear down the existing screen and mount a new one, focusing it.
sub swapScreen(nodeName as string)
    if m.current <> invalid then
        m.host.removeChild(m.current)
        m.current = invalid
    end if
    m.current = CreateObject("roSGNode", nodeName)
    m.currentName = nodeName
    m.host.appendChild(m.current)
    m.current.setFocus(true)
end sub

sub onPaired()
    if m.current <> invalid and m.current.paired = true then
        showHome()
    end if
end sub

sub onSignedOut()
    if m.current <> invalid and m.current.signedOut = true then
        ClearAuthToken()
        showPairing()
    end if
end sub

' Global key routing. Screens handle their own keys first (focus chain);
' anything that bubbles up to the scene lands here.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Let the focused screen own BACK (exit prompt at home root, pop on detail,
    ' etc. — §6.7, §9.10). The scene does not force-exit.
    return false
end function
