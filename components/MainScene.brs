sub init()
    m.host = m.top.findNode("screenHost")
    ' Screen stack: index 0 is the root (Pairing or Home); Event Detail and other
    ' overlays push on top. Keeping the previous screen mounted underneath
    ' preserves its scroll/focus state when we pop back. §6.7 / §7.
    m.stack = []

    ' Auth gate on boot. §2 / §5.
    token = GetAuthToken()
    if token <> invalid and token <> "" then
        showHome()
    else
        showPairing()
    end if
end sub

function topScreen() as object
    if m.stack.Count() = 0 then return invalid
    return m.stack[m.stack.Count() - 1]
end function

' Replace the whole stack with a fresh root screen (Pairing <-> Home).
sub resetTo(nodeName as string)
    for each it in m.stack
        m.host.removeChild(it)
    end for
    m.stack = []
    node = CreateObject("roSGNode", nodeName)
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
end sub

sub showPairing()
    resetTo("PairingScreen")
    topScreen().observeField("paired", "onPaired")
end sub

sub showHome()
    resetTo("HomeScreen")
    home = topScreen()
    home.observeField("signedOut", "onSignedOut")
    home.observeField("exitApp", "onExitApp")
    home.observeField("openEventId", "onOpenEvent")
    home.observeField("openVideoId", "onOpenVideo")
end sub

' Home asked to open an event → push Event Detail over it. §7
sub onOpenEvent()
    home = m.stack[0]
    id = home.openEventId
    if id = invalid or id = "" then return
    pushEvent(id)
    ' Clear so re-selecting the same event later re-fires onChange.
    home.openEventId = ""
end sub

sub pushEvent(eventId as string)
    node = CreateObject("roSGNode", "EventDetailScreen")
    node.eventId = eventId
    node.observeField("popped", "onScreenPopped")
    node.observeField("signedOut", "onSignedOut")
    node.observeField("openEventId", "onChildOpenEvent")
    node.observeField("openVideoId", "onChildOpenVideo")
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
end sub

' Push the Player onto the stack. §9
sub pushPlayer(videoId as string)
    node = CreateObject("roSGNode", "PlayerScreen")
    node.videoId = videoId
    node.observeField("popped", "onScreenPopped")
    node.observeField("signedOut", "onSignedOut")
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
end sub

' Home asked to play a video (hero Watch with a target). §6 / §9
sub onOpenVideo()
    home = m.stack[0]
    id = home.openVideoId
    if id = invalid or id = "" then return
    pushPlayer(id)
    home.openVideoId = ""
end sub

' A pushed detail asked to play a video (Watch / video-card OK). §9
sub onChildOpenVideo()
    child = topScreen()
    if child = invalid then return
    id = child.openVideoId
    if id = invalid or id = "" then return
    pushPlayer(id)
    child.openVideoId = ""
end sub

' A pushed detail can open another event (e.g. a related/event card) — push again.
sub onChildOpenEvent()
    child = topScreen()
    if child = invalid then return
    id = child.openEventId
    if id = invalid or id = "" then return
    pushEvent(id)
    child.openEventId = ""
end sub

' Top overlay requested to close itself (BACK at its root). Pop back one level.
sub onScreenPopped()
    if m.stack.Count() <= 1 then return
    top = topScreen()
    if top.popped <> true then return
    m.host.removeChild(top)
    m.stack.Pop()
    topScreen().setFocus(true)
end sub

sub onExitApp()
    home = topScreen()
    if home <> invalid and home.exitApp = true then
        m.top.exitApp = true
    end if
end sub

sub onPaired()
    p = topScreen()
    if p <> invalid and p.paired = true then
        showHome()
    end if
end sub

' A 401 anywhere → token dead → tear down everything and go to Pairing. §2
sub onSignedOut()
    ClearAuthToken()
    showPairing()
end sub

' Global key routing. Screens handle their own keys first (focus chain);
' anything that bubbles up to the scene lands here.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Let the focused screen own BACK (exit prompt at home root, pop on detail,
    ' etc. — §6.7, §9.10). The scene does not force-exit.
    return false
end function
