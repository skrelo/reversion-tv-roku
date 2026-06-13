sub init()
    m.host = m.top.findNode("screenHost")
    ' Screen stack: index 0 is the root (Pairing or Home); Event Detail and other
    ' overlays push on top. Keeping the previous screen mounted underneath
    ' preserves its scroll/focus state when we pop back. §6.7 / §7.
    m.stack = []

    ' Certification performance beacons (cert 3.2). The OS fires AppLaunchInitiate
    ' automatically; we must fire AppLaunchComplete once the Home page is rendered.
    ' Pairing is a login dialog shown before Home, so it gets AppDialog beacons.
    ' Fire each only once for the launch sequence.
    m.launchComplete = false

    ' A deep link captured before auth completes; routed once Home is up. §5
    m.pendingDeepLink = invalid

    ' Auth gate on boot. §2 / §5.
    token = GetAuthToken()
    if token <> invalid and token <> "" then
        showHome()
    else
        showSignIn()
    end if

    ' Deep link on cold launch (cert RP 5.x). Stash it; routeDeepLink runs it now
    ' if we're already Home, or defers until sign-in completes.
    if m.top.launchArgs <> invalid then routeDeepLink(m.top.launchArgs)
end sub

' ── Deep linking (cert RP 5.x) ─────────────────────────────────────────
' roInput delivered a deep link while we're running (main.brs forwards it).
sub onInputArgs()
    if m.top.inputArgs <> invalid then routeDeepLink(m.top.inputArgs)
end sub

' Validate contentId + mediaType (case-insensitive keys) and open the content.
' Videos play directly; events open their detail springboard. Invalid/empty →
' do nothing (we're already on Home or sign-in). If not yet authed, defer until
' Home is shown (onAuthed drains m.pendingDeepLink).
sub routeDeepLink(args as object)
    if args = invalid then return
    contentId = ciGet(args, "contentid")
    mediaType = LCase(ciGet(args, "mediatype"))
    if contentId = "" then return

    token = GetAuthToken()
    if token = invalid or token = "" then
        m.pendingDeepLink = { contentId: contentId, mediaType: mediaType }
        return
    end if

    ' Make sure we're at the Home root before pushing content over it.
    if m.stack.Count() = 0 or m.stack[0].subtype() <> "HomeScreen" then showHome()

    if mediaType = "series" or mediaType = "season" then
        pushEvent(contentId)
    else
        ' movie / episode / shortformvideo / tvspecial / livefeed / sportsevent
        ' (and anything else) → treat the id as a video and play it directly.
        pushPlayer(contentId)
    end if
end sub

' Case-insensitive lookup over an roAssociativeArray (deep link keys vary in
' case: contentId vs contentid, mediaType vs mediatype).
function ciGet(aa as object, lowerKey as string) as string
    if aa = invalid then return ""
    for each k in aa
        if LCase(k) = lowerKey then
            v = aa[k]
            if v <> invalid then return v.ToStr()
        end if
    end for
    return ""
end function

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

sub showSignIn()
    ' Sign-in is a login dialog shown before Home → AppDialog beacons (cert 3.2).
    ' Only the launch-time sign-in counts; a later re-auth (after sign-out) skips it.
    fireDialog = not m.launchComplete
    if fireDialog then m.top.signalBeacon("AppDialogInitiate")
    resetTo("SignInScreen")
    topScreen().observeField("authed", "onAuthed")
    topScreen().observeField("exitApp", "onExitApp")
    if fireDialog then m.top.signalBeacon("AppDialogComplete")
end sub

sub showHome()
    resetTo("HomeScreen")
    home = topScreen()
    home.observeField("signedOut", "onSignedOut")
    home.observeField("exitApp", "onExitApp")
    home.observeField("openEventId", "onOpenEvent")
    home.observeField("openVideoId", "onOpenVideo")
    home.observeField("openSettings", "onOpenSettings")
    home.observeField("openSearch", "onOpenSearch")

    ' Home is the fully-rendered launch UI → AppLaunchComplete (cert 3.2), once.
    if not m.launchComplete then
        m.top.signalBeacon("AppLaunchComplete")
        m.launchComplete = true
    end if
end sub

' Home asked to open Settings (left-nav gear) → push it over Home. §10
sub onOpenSettings()
    home = m.stack[0]
    if home.openSettings <> true then return
    home.openSettings = false
    node = CreateObject("roSGNode", "SettingsScreen")
    node.observeField("popped", "onScreenPopped")
    node.observeField("signedOut", "onSignedOut")
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
end sub

' Home asked to open Search (left-nav search icon). §8
sub onOpenSearch()
    home = m.stack[0]
    if home.openSearch <> true then return
    home.openSearch = false
    node = CreateObject("roSGNode", "SearchScreen")
    node.observeField("popped", "onScreenPopped")
    node.observeField("signedOut", "onSignedOut")
    node.observeField("openEventId", "onChildOpenEvent")
    node.observeField("openVideoId", "onChildOpenVideo")
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
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
    node.observeField("openVideoId", "onChildOpenVideo")
    node.observeField("openEventId", "onChildOpenEvent")
    node.observeField("replaceVideoId",  "onReplaceVideo")
    node.observeField("replaceEventId",  "onReplaceEvent")
    m.host.appendChild(node)
    m.stack.push(node)
    node.setFocus(true)
end sub

' Up-Next Mode A: pop the current player and push the next video. §9.12
sub onReplaceVideo()
    child = topScreen()
    if child = invalid then return
    id = child.replaceVideoId
    if id = invalid or id = "" then return
    child.replaceVideoId = ""
    ' Pop the current player.
    if m.stack.Count() > 1 then
        m.host.removeChild(child)
        m.stack.Pop()
    end if
    ' Push fresh player for next video.
    pushPlayer(id)
end sub

' Up-Next Mode B: pop the current player and open the selected event. §9.12
sub onReplaceEvent()
    child = topScreen()
    if child = invalid then return
    id = child.replaceEventId
    if id = invalid or id = "" then return
    child.replaceEventId = ""
    ' Pop the current player.
    if m.stack.Count() > 1 then
        m.host.removeChild(child)
        m.stack.Pop()
    end if
    ' Push EventDetail.
    pushEvent(id)
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
    s = topScreen()
    if s <> invalid and s.exitApp = true then
        m.top.exitApp = true
    end if
end sub

sub onAuthed()
    p = topScreen()
    if p <> invalid and p.authed = true then
        showHome()
        ' Run any deep link the user arrived with before signing in. §5
        if m.pendingDeepLink <> invalid then
            dl = m.pendingDeepLink
            m.pendingDeepLink = invalid
            if dl.mediaType = "series" or dl.mediaType = "season" then
                pushEvent(dl.contentId)
            else
                pushPlayer(dl.contentId)
            end if
        end if
    end if
end sub

' A 401 anywhere → token dead → tear down everything and go to Sign-in. §2
sub onSignedOut()
    ClearAuthToken()
    showSignIn()
end sub

' Global key routing. Screens handle their own keys first (focus chain);
' anything that bubbles up to the scene lands here.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Let the focused screen own BACK (exit prompt at home root, pop on detail,
    ' etc. — §6.7, §9.10). The scene does not force-exit.
    return false
end function
