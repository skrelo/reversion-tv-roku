sub init()
    m.host = m.top.findNode("screenHost")
    ' Screen stack: index 0 is the root (Pairing or Home); Event Detail and other
    ' overlays push on top. Keeping the previous screen mounted underneath
    ' preserves its scroll/focus state when we pop back. §6.7 / §7.
    m.stack = []

    ' Certification performance beacons (cert 3.2). The OS fires AppLaunchInitiate
    ' automatically; we must fire AppLaunchComplete once the first interactive
    ' screen is rendered. On an unauthenticated launch that screen is Sign In (we
    ' never reach Home until the user signs in), so AppLaunchComplete MUST fire
    ' there too — otherwise Roku's launch-performance test waits 30s for a beacon
    ' that never comes, times out, and fails. Fire it only once per launch.
    m.launchComplete = false
    ' Tracks the launch-time sign-in "dialog" so its AppDialogComplete fires when
    ' the user authenticates (brackets sign-in time out of engagement metrics).
    m.signInDialogOpen = false

    ' A deep link captured before auth completes; routed once Home is up. §5
    m.pendingDeepLink = invalid

    ' TEMP cert diagnostic: shared remote-logging task, reachable from any
    ' component via m.global.debugTask (see LogBeacon in Config.brs). Created
    ' before the auth gate so the very first beacon (launch) is captured.
    m.debugTask = CreateObject("roSGNode", "DebugTask")
    m.global.addFields({ debugTask: m.debugTask })

    ' Auth gate on boot. §2 / §5.
    token = GetAuthToken()
    hasToken = (token <> invalid and token <> "")
    LogBeacon("launch", "", { hasToken: hasToken })
    if hasToken then
        showHome()
    else
        showWelcome()
    end if
    ' NOTE: don't read m.top.launchArgs here — CreateScene runs init()
    ' synchronously BEFORE main.brs sets it. Cold-launch deep links arrive via
    ' the onLaunchArgs observer below.
end sub

' ── Deep linking (cert RP 5.x) ─────────────────────────────────────────
' Cold-launch deep link: main.brs sets launchArgs after the scene is created,
' so this observer (not init) is where we first see it.
sub onLaunchArgs()
    if m.top.launchArgs <> invalid then
        LogBeacon("launchArgs", "", { contentId: ciGet(m.top.launchArgs, "contentid"), mediaType: ciGet(m.top.launchArgs, "mediatype") })
        routeDeepLink(m.top.launchArgs)
    end if
end sub

' roInput delivered a deep link while we're running (main.brs forwards it).
sub onInputArgs()
    if m.top.inputArgs <> invalid then
        LogBeacon("inputArgs", "", { contentId: ciGet(m.top.inputArgs, "contentid"), mediaType: ciGet(m.top.inputArgs, "mediatype") })
        routeDeepLink(m.top.inputArgs)
    end if
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
        LogBeacon("deepLink", "", { contentId: contentId, mediaType: mediaType, authed: false, action: "deferred-signin" })
        return
    end if
    LogBeacon("deepLink", "", { contentId: contentId, mediaType: mediaType, authed: true, action: "route" })

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

' Guest landing for unauthenticated users (§5 Platform note). This is the first
' interactive UI on an unauthenticated launch, so it carries AppLaunchComplete
' (cert 3.2). The whole pre-auth gate (Welcome + Sign In) blocks content, so we
' open the AppDialog span here; it closes when the user signs in (onAuthed),
' bracketing sign-in time out of engagement metrics. A re-show after sign-out is
' not a launch → fires nothing.
sub showWelcome()
    isLaunch = not m.launchComplete
    LogBeacon("screen", "Welcome", { isLaunch: isLaunch })
    resetTo("WelcomeScreen")
    topScreen().observeField("signIn", "onWelcomeSignIn")
    topScreen().observeField("exitApp", "onExitApp")
    if isLaunch then
        m.top.signalBeacon("AppLaunchComplete")
        m.launchComplete = true
        m.top.signalBeacon("AppDialogInitiate")
        m.signInDialogOpen = true
    end if
end sub

' Welcome → user chose Sign In: swap in the on-device sign-in screen. Launch +
' AppDialog beacons already fired on Welcome, so showSignIn no-ops them.
sub onWelcomeSignIn()
    w = topScreen()
    if w <> invalid and w.signIn = true then showSignIn()
end sub

sub showSignIn()
    ' Reached from the Welcome landing (or after sign-out). The launch +
    ' AppDialogInitiate beacons fire on Welcome, so isLaunch is already false here
    ' and this no-ops them; the guard remains so a direct first-screen sign-in
    ' (should the Welcome step ever be removed) still carries the launch beacons.
    isLaunch = not m.launchComplete
    LogBeacon("screen", "SignIn", { isLaunch: isLaunch })
    resetTo("SignInScreen")
    topScreen().observeField("authed", "onAuthed")
    topScreen().observeField("exitApp", "onExitApp")
    if isLaunch then
        m.top.signalBeacon("AppLaunchComplete")
        m.launchComplete = true
        m.top.signalBeacon("AppDialogInitiate")
        m.signInDialogOpen = true
    end if
end sub

sub showHome()
    LogBeacon("screen", "Home", invalid)
    resetTo("HomeScreen")
    home = topScreen()
    home.observeField("signedOut", "onSignedOut")
    home.observeField("exitApp", "onExitApp")
    home.observeField("openEventId", "onOpenEvent")
    home.observeField("openVideoId", "onOpenVideo")
    home.observeField("openSettings", "onOpenSettings")
    home.observeField("openSearch", "onOpenSearch")

    ' If the user was already authed at boot, Home is the first launch UI →
    ' AppLaunchComplete here (cert 3.2). On the sign-in path it already fired.
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
    LogBeacon("screen", "EventDetail", { eventId: eventId })
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
    LogBeacon("screen", "Player", { videoId: videoId })
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
        LogBeacon("authed", "", { hasToken: (GetAuthToken() <> invalid and GetAuthToken() <> "") })
        ' Close the launch-time sign-in dialog span (cert 3.2) before Home.
        if m.signInDialogOpen = true then
            m.top.signalBeacon("AppDialogComplete")
            m.signInDialogOpen = false
        end if
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

' A 401 anywhere → token dead → tear down everything and go to the Welcome
' landing (the unauthenticated root). §2 / §5
sub onSignedOut()
    LogBeacon("signedOut", "", invalid)
    ClearAuthToken()
    showWelcome()
end sub

' Global key routing. Screens handle their own keys first (focus chain);
' anything that bubbles up to the scene lands here.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Let the focused screen own BACK (exit prompt at home root, pop on detail,
    ' etc. — §6.7, §9.10). The scene does not force-exit.
    return false
end function
