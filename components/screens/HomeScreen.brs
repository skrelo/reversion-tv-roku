sub init()
    m.bg = m.top.findNode("bg")
    m.railsContainer = m.top.findNode("railsContainer")
    m.railsContent = m.top.findNode("railsContent")
    m.hero = m.top.findNode("hero")
    m.nav = m.top.findNode("nav")
    m.loading = m.top.findNode("loading")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn   = m.top.findNode("retryBtn")
    m.retryBg    = m.top.findNode("retryBg")
    m.emptyLabel = m.top.findNode("emptyLabel")
    m.emptyState = m.top.findNode("emptyState")
    m.toast = m.top.findNode("toast")
    m.toastLabel = m.top.findNode("toastLabel")
    m.exitDialog = m.top.findNode("exitDialog")
    m.exitCancelBg = m.top.findNode("exitCancelBg")
    m.exitCancelLabel = m.top.findNode("exitCancelLabel")
    m.exitConfirmBg = m.top.findNode("exitConfirmBg")
    m.exitConfirmLabel = m.top.findNode("exitConfirmLabel")
    m.heroAnim = m.top.findNode("heroAnim")
    m.heroHInterp = m.top.findNode("heroHInterp")
    m.railsYInterp = m.top.findNode("railsYInterp")
    m.railScrollAnim = m.top.findNode("railScrollAnim")
    m.railScrollInterp = m.top.findNode("railScrollInterp")

    ' Layout constants (mirror Tizen Home.css ratios: 0.85 / 0.60 of 1080).
    m.HERO_EXPANDED = 918
    m.HERO_COLLAPSED = 648
    m.railStride = 312       ' title + 16:9 art + below-card text + gap
    m.railTopPad = 24        ' breathing room between hero and the first rail

    ' Focus + routing state (HomeScreen owns all focus; §12).
    m.zone = "hero"          ' hero | rails | nav
    m.prevZone = "hero"
    m.heroBtn = 0            ' 0 watch | 1 mylist | 2 info
    m.railIndex = 0
    m.colByRail = []
    m.railNodes = []
    m.rails = []
    m.navIndex = 1           ' default Home
    m.activeNav = "home"
    m.catalog = ""
    m.exitSel = 0
    m.slideIndex = 0
    m.carousel = []
    m.allEvents = invalid

    ' Nav item id order must match HomeNav.brs.
    m.navIds = ["search", "home", "meetups", "livestreams", "continue", "mylist", "settings"]

    m.autoTimer = CreateObject("roSGNode", "Timer")
    m.autoTimer.duration = 8
    m.autoTimer.repeat = true
    m.autoTimer.observeField("fire", "onAutoAdvance")

    ' Guard: for a short beat after an auto-advance flips the slide, swallow an
    ' OK so a press the user aimed at the PREVIOUS slide doesn't open the
    ' just-flipped one. Any directional press clears it (user is now in control).
    m.justAdvanced = false
    m.advanceGuard = CreateObject("roSGNode", "Timer")
    m.advanceGuard.duration = 0.5
    m.advanceGuard.repeat = false
    m.advanceGuard.observeField("fire", "onAdvanceGuardDone")

    m.toastTimer = CreateObject("roSGNode", "Timer")
    m.toastTimer.duration = 2.5
    m.toastTimer.repeat = false
    m.toastTimer.observeField("fire", "onToastTimer")

    m.top.setFocus(true)
    loadData()
end sub

' ── Data load (parallel GET /home + /library + /me). §6.1 ───────────────
sub loadData()
    m.loading.visible = true
    m.errorLabel.visible = false
    m.retryBtn.visible = false
    m.emptyState.visible = false
    m.homeDone = false : m.libDone = false : m.meDone = false
    m.homeRes = invalid : m.libRes = invalid : m.meRes = invalid

    m.homeTask = CreateObject("roSGNode", "ApiTask")
    m.homeTask.observeField("response", "onHomeResponse")
    m.homeTask.request = ApiReq().home()
    m.homeTask.control = "RUN"

    m.libTask = CreateObject("roSGNode", "ApiTask")
    m.libTask.observeField("response", "onLibResponse")
    m.libTask.request = ApiReq().library()
    m.libTask.control = "RUN"

    m.meTask = CreateObject("roSGNode", "ApiTask")
    m.meTask.observeField("response", "onMeResponse")
    m.meTask.request = ApiReq().me()
    m.meTask.control = "RUN"
end sub

sub onHomeResponse()
    m.homeRes = m.homeTask.response
    m.homeDone = true
    maybeReady()
end sub
sub onLibResponse()
    m.libRes = m.libTask.response
    m.libDone = true
    maybeReady()
end sub
sub onMeResponse()
    m.meRes = m.meTask.response
    m.meDone = true
    maybeReady()
end sub

sub maybeReady()
    if not (m.homeDone and m.libDone and m.meDone) then return
    m.loading.visible = false

    ' A 401 anywhere with a token present → token is dead, back to Pairing. §2
    if (m.homeRes <> invalid and m.homeRes.status = 401) then
        m.top.signedOut = true
        return
    end if
    if m.homeRes = invalid or m.homeRes.ok <> true then
        if m.homeRes = invalid then
            print "[Home] /home FAILED — response is invalid (task never returned)"
        else
            print "[Home] /home FAILED — status="; m.homeRes.status; " error="; m.homeRes.error
            if m.homeRes.data <> invalid then print "[Home] /home body="; FormatJson(m.homeRes.data)
        end if
        m.errorLabel.text = "Could not load content. Check your connection."
        m.errorLabel.visible = true
        m.retryBtn.visible = true
        m.retryBg.color = "0x1B2A3AFF"
        m.top.setFocus(true)
        return
    end if

    h = m.homeRes.data
    lib = {}
    if m.libRes <> invalid and m.libRes.ok = true then lib = m.libRes.data
    user = invalid
    if m.meRes <> invalid and m.meRes.ok = true and m.meRes.data <> invalid then user = m.meRes.data.user

    m.data = {
        heroCarousel: arr(h.hero_carousel)
        continueWatching: arr(h.continue_watching)
        recentEvents: arr(h.recent_events)
        recentLivestreams: arr(h.recent_livestreams)
        bookmarks: arr(lib.bookmarks)
        eventBookmarks: arr(lib.event_bookmarks)
    }

    if user <> invalid then
        nm = firstNonEmpty([user.display_name, user.name])
        if nm = "" then nm = "Account"
        m.nav.userName = nm
        m.nav.userHandle = nz(user.telegram_handle)
        m.nav.userPhoto = nz(user.profile_photo_url)
    end if

    m.carousel = m.data.heroCarousel
    ' Hero fallback: first recent event wrapped as a featured item. §6.1
    if m.carousel.Count() = 0 and m.data.recentEvents.Count() > 0 then
        m.carousel = [m.data.recentEvents[0]]
    end if

    ' Authorized-but-empty: /home succeeded but there is nothing to show (no hero
    ' slide AND no rails). Render a focusable empty state instead of a dead-end
    ' blank screen. This is NOT the error path (handled above) nor loading. §6.1
    homeRails = buildHomeRails()
    if m.carousel.Count() = 0 and homeRails.Count() = 0 then
        showAuthedEmpty()
        return
    end if

    buildRails(homeRails)
    m.nav.activeId = "home"
    ' Start fully expanded without animating in.
    setHeroHeightImmediate(m.HERO_EXPANDED)
    returnToHero()
end sub

' Signed in but no entitled content. Show the empty state with the Refresh button
' focused (the screen must never present nothing focusable). §6.1
sub showAuthedEmpty()
    m.emptyState.visible = true
    m.zone = "empty"
    m.nav.expanded = false
    m.nav.focusedIndex = -1
    m.hero.focusedButton = -1
    m.top.setFocus(true)
end sub

function arr(v as dynamic) as object
    if v <> invalid and GetInterface(v, "ifArray") <> invalid then return v
    return []
end function

' ── Rail building ───────────────────────────────────────────────────────
function buildHomeRails() as object
    rails = []
    if m.data.continueWatching.Count() > 0 then rails.push({ key: "cw", title: "Continue Watching", items: m.data.continueWatching, type: "video" })
    ml = BuildMyList(m.data.eventBookmarks, m.data.bookmarks)
    if ml.Count() > 0 then rails.push({ key: "ml", title: "My List", items: ml, type: "mixed" })
    if m.data.recentEvents.Count() > 0 then rails.push({ key: "events", title: "Meetups", items: m.data.recentEvents, type: "event" })
    if m.data.recentLivestreams.Count() > 0 then rails.push({ key: "ls", title: "Livestreams", items: m.data.recentLivestreams, type: "event" })
    return rails
end function

function buildCatalogRails(catalogType as string) as object
    if catalogType = "meetups" then
        src = m.data.recentEvents
        if m.allEvents <> invalid then src = m.allEvents
        return YearGroupedRails(src, "meetups", "Other")
    else if catalogType = "livestreams" then
        return YearGroupedRails(m.data.recentLivestreams, "livestreams", "Collections")
    else if catalogType = "continue" then
        if m.data.continueWatching.Count() > 0 then return [{ key: "cw", title: "Continue Watching", items: m.data.continueWatching, type: "video" }]
        return []
    else if catalogType = "mylist" then
        ml = BuildMyList(m.data.eventBookmarks, m.data.bookmarks)
        if ml.Count() > 0 then return [{ key: "ml", title: "My List", items: ml, type: "mixed" }]
        return []
    end if
    return []
end function

sub buildRails(rails as object)
    m.railsContent.removeChildren(m.railsContent.getChildren(-1, 0))
    m.railNodes = []
    m.colByRail = []
    m.rails = rails
    i = 0
    for each rail in rails
        node = CreateObject("roSGNode", "Rail")
        node.translation = [0, i * m.railStride]
        node.rail = rail
        m.railsContent.appendChild(node)
        m.railNodes.push(node)
        m.colByRail.push(0)
        i = i + 1
    end for
    m.railScrollAnim.control = "stop"
    m.railsContent.translation = [0, m.railTopPad]
end sub

' ── Hero collapse/expand + rail scroll animations ───────────────────────
sub setHeroHeightImmediate(h as float)
    m.heroAnim.control = "stop"
    m.hero.heroHeight = h
    m.railsContainer.translation = [150, h]
end sub

sub animateHeroTo(targetH as float)
    fromH = m.hero.heroHeight
    if Abs(fromH - targetH) < 1 then
        setHeroHeightImmediate(targetH)
        return
    end if
    curY = m.railsContainer.translation
    m.heroAnim.control = "stop"
    m.heroHInterp.keyValue = [fromH, targetH]
    m.railsYInterp.keyValue = [curY, [150, targetH]]
    m.heroAnim.control = "start"
end sub

sub scrollRailsTo(railIndex as integer)
    targetY = m.railTopPad - railIndex * m.railStride
    cur = m.railsContent.translation
    if Abs(cur[1] - targetY) < 1 then return
    m.railScrollAnim.control = "stop"
    m.railScrollInterp.keyValue = [cur, [0, targetY]]
    m.railScrollAnim.control = "start"
end sub

' ── Hero / rails focus transitions ──────────────────────────────────────
sub returnToHero()
    m.zone = "hero"
    m.activeNav = "home"
    m.nav.activeId = "home"
    clearRailFocus()
    m.heroBtn = 0
    animateHeroTo(m.HERO_EXPANDED)
    renderSlide()
    startAuto()
end sub

' Move to a specific carousel slide. Focus ALWAYS returns to the primary
' Watch/Continue button (button 0) on any slide change — manual paging or
' auto-advance — regardless of which button was focused before.
sub goToSlide(index as integer)
    m.slideIndex = index
    m.heroBtn = 0
    renderSlide()
    startAuto()
end sub

sub renderSlide()
    if m.carousel.Count() = 0 then return
    if m.slideIndex > m.carousel.Count() - 1 then m.slideIndex = 0
    ev = m.carousel[m.slideIndex]
    ' Set count/index/mylist BEFORE slide — setting slide triggers render() which
    ' calls buildDots(), and buildDots reads slideCount/slideIndex. The old order
    ' set slide first, so dots always rendered with stale values.
    m.hero.slideCount = m.carousel.Count()
    m.hero.slideIndex = m.slideIndex
    m.hero.inMyList = isEventInList(ev)
    m.hero.mode = "carousel"
    if m.zone = "hero" then
        m.hero.focusedButton = m.heroBtn
    else
        m.hero.focusedButton = -1
    end if
    m.hero.slide = HeroSlideModel(ev)
end sub

function isEventInList(ev as object) as boolean
    if ev = invalid then return false
    id = toStr(ev.id)
    for each e in m.data.eventBookmarks
        if toStr(e.id) = id then return true
    end for
    return false
end function

sub enterRailsFromHero()
    if m.rails.Count() = 0 then return
    stopAuto()
    m.zone = "rails"
    m.railIndex = 0
    m.hero.focusedButton = -1
    animateHeroTo(m.HERO_COLLAPSED)
    updateRailFocus()
end sub

sub clearRailFocus()
    for each node in m.railNodes
        node.focusedCol = -1
    end for
end sub

sub updateRailFocus()
    col = m.colByRail[m.railIndex]
    itemCount = m.railNodes[m.railIndex].itemCount
    if col > itemCount - 1 then col = itemCount - 1
    if col < 0 then col = 0
    m.colByRail[m.railIndex] = col

    for i = 0 to m.railNodes.Count() - 1
        if i = m.railIndex then
            m.railNodes[i].focusedCol = col
        else
            m.railNodes[i].focusedCol = -1
        end if
    end for

    scrollRailsTo(m.railIndex)
    updateSpotlight()
end sub

sub updateSpotlight()
    rail = m.rails[m.railIndex]
    col = m.colByRail[m.railIndex]
    if rail = invalid or rail.items = invalid or col > rail.items.Count() - 1 then return
    item = rail.items[col]
    model = CardModel(item, rail.type)
    m.hero.spotlight = model.spotlight
    m.hero.mode = "spotlight"
end sub

' ── Left nav ────────────────────────────────────────────────────────────
sub openNav()
    m.prevZone = m.zone
    m.zone = "nav"
    stopAuto()
    m.navIndex = indexOfNav(m.activeNav)
    if m.navIndex < 0 then m.navIndex = 1
    m.nav.expanded = true
    m.nav.focusedIndex = m.navIndex
    m.hero.focusedButton = -1
end sub

sub closeNavToContent()
    m.nav.expanded = false
    m.nav.focusedIndex = -1
    if m.prevZone = "rails" and m.rails.Count() > 0 then
        m.zone = "rails"
        updateRailFocus()
    else
        m.zone = "hero"
        m.heroBtn = 0
        animateHeroTo(m.HERO_EXPANDED)
        m.hero.focusedButton = m.heroBtn
        startAuto()
    end if
end sub

function indexOfNav(id as string) as integer
    for i = 0 to m.navIds.Count() - 1
        if m.navIds[i] = id then return i
    end for
    return -1
end function

sub onNavSelect(id as string)
    if id = "home" then
        if m.catalog <> "" then
            exitCatalog()
        else
            m.nav.expanded = false
            m.nav.focusedIndex = -1
            returnToHero()
        end if
        return
    end if
    if id = "search" then
        m.nav.expanded = false : m.nav.focusedIndex = -1
        m.zone = m.prevZone
        m.top.openSearch = false
        m.top.openSearch = true
        return
    end if
    if id = "settings" then
        m.nav.expanded = false : m.nav.focusedIndex = -1
        m.zone = m.prevZone
        m.top.openSettings = false
        m.top.openSettings = true
        return
    end if
    enterCatalog(id)
end sub

sub enterCatalog(catalogType as string)
    m.catalog = catalogType
    m.activeNav = catalogType
    m.nav.activeId = catalogType
    m.nav.expanded = false
    m.nav.focusedIndex = -1
    m.slideIndex = 0
    animateHeroTo(m.HERO_COLLAPSED)

    ' Meetups lazy-loads the full meetup-only events list once. §6.7
    if catalogType = "meetups" and m.allEvents = invalid then
        m.eventsTask = CreateObject("roSGNode", "ApiTask")
        m.eventsTask.observeField("response", "onEventsResponse")
        m.eventsTask.request = ApiReq().events(1, 50, "meetup")
        m.eventsTask.control = "RUN"
    end if

    rails = buildCatalogRails(catalogType)
    if rails.Count() = 0 then
        buildRails([])
        m.emptyLabel.visible = true
        ' Nothing to focus: keep the nav open.
        m.zone = "nav"
        m.nav.expanded = true
        m.navIndex = indexOfNav(catalogType)
        m.nav.focusedIndex = m.navIndex
        return
    end if
    m.emptyLabel.visible = false
    buildRails(rails)
    m.zone = "rails"
    m.railIndex = 0
    updateRailFocus()
end sub

sub onEventsResponse()
    resp = m.eventsTask.response
    if resp <> invalid and resp.ok = true then
        ev = resp.data.events
        if ev = invalid then ev = resp.data.data
        m.allEvents = arr(ev)
        ' If still viewing Meetups, rebuild with the fuller list.
        if m.catalog = "meetups" then
            rails = buildCatalogRails("meetups")
            if rails.Count() > 0 then
                m.emptyLabel.visible = false
                buildRails(rails)
                if m.zone = "rails" then
                    m.railIndex = 0
                    updateRailFocus()
                end if
            end if
        end if
    end if
end sub

sub exitCatalog()
    m.catalog = ""
    m.activeNav = "home"
    m.nav.activeId = "home"
    m.nav.expanded = false
    m.nav.focusedIndex = -1
    m.emptyLabel.visible = false
    buildRails(buildHomeRails())
    returnToHero()
end sub

' ── Actions (Detail/Player are later passes → toast for now) ─────────────
sub heroActivate()
    if m.carousel.Count() = 0 then return
    ev = m.carousel[m.slideIndex]
    slide = HeroSlideModel(ev)
    if m.heroBtn = 0 then
        if slide.hasTarget then
            openVideo(slide.targetVideoId)
        else
            openEvent(slide.eventId)
        end if
    else if m.heroBtn = 1 then
        toggleHeroMyList(ev)
    else if m.heroBtn = 2 then
        openEvent(slide.eventId)
    end if
end sub

' Signal MainScene to push Event Detail. Reset to "" first so re-selecting the
' same event id still triggers the observer's onChange.
sub openEvent(eventId as string)
    if eventId = "" then return
    m.top.openEventId = ""
    m.top.openEventId = eventId
end sub

' Signal MainScene to push the Player (hero Watch with a target, or a video
' card OK). Reset to "" first so re-selecting the same id re-fires onChange. §9
sub openVideo(videoId as string)
    if videoId = "" then return
    m.top.openVideoId = ""
    m.top.openVideoId = videoId
end sub

sub toggleHeroMyList(ev as object)
    id = toStr(ev.id)
    if id = "" then return
    inList = isEventInList(ev)
    ' Optimistic local update (reconcile-on-reload comes with the full §6.1
    ' library re-pull in a later polish pass).
    if inList then
        newList = []
        for each e in m.data.eventBookmarks
            if toStr(e.id) <> id then newList.push(e)
        end for
        m.data.eventBookmarks = newList
        t = CreateObject("roSGNode", "ApiTask")
        t.request = ApiReq().removeEventBookmark(id)
        t.control = "RUN"
        m.bookmarkTask = t
    else
        m.data.eventBookmarks.push(ev)
        t = CreateObject("roSGNode", "ApiTask")
        t.request = ApiReq().addEventBookmark(id)
        t.control = "RUN"
        m.bookmarkTask = t
    end if
    renderSlide()
end sub

sub selectCard()
    rail = m.rails[m.railIndex]
    col = m.colByRail[m.railIndex]
    if rail = invalid or col > rail.items.Count() - 1 then return
    model = CardModel(rail.items[col], rail.type)
    if model.videoId <> "" then
        openVideo(model.videoId)
    else if model.eventId <> "" then
        openEvent(model.eventId)
    end if
end sub

' ── Toast ───────────────────────────────────────────────────────────────
sub showToast(msg as string)
    m.toastLabel.text = msg
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub
sub onToastTimer()
    m.toast.visible = false
end sub

' ── Auto-advance (8s, carousel only, >1 slide). §6.2/§6.4 ───────────────
sub startAuto()
    if m.zone = "hero" and m.catalog = "" and m.carousel.Count() > 1 then
        m.autoTimer.control = "stop"
        m.autoTimer.control = "start"
    end if
end sub
sub stopAuto()
    m.autoTimer.control = "stop"
end sub
sub onAutoAdvance()
    if m.zone <> "hero" or m.catalog <> "" then return
    if m.carousel.Count() <= 1 then return
    m.heroBtn = 0
    m.slideIndex = (m.slideIndex + 1) mod m.carousel.Count()
    renderSlide()
    ' Arm the post-advance OK guard so a press aimed at the prior slide doesn't
    ' open the freshly-flipped one.
    m.justAdvanced = true
    m.advanceGuard.control = "stop"
    m.advanceGuard.control = "start"
end sub

sub onAdvanceGuardDone()
    m.justAdvanced = false
end sub

' ── Exit overlay (§6.7) ─────────────────────────────────────────────────
sub showExit()
    m.exitSel = 0
    styleExit()
    m.exitDialog.visible = true
    stopAuto()
end sub
sub hideExit()
    m.exitDialog.visible = false
end sub
sub styleExit()
    if m.exitSel = 0 then
        m.exitCancelBg.blendColor = "0xC9A84CFF" : m.exitCancelLabel.color = "0x0F1923FF"
        m.exitConfirmBg.blendColor = "0x23324AFF" : m.exitConfirmLabel.color = "0xFFFFFFFF"
    else
        m.exitCancelBg.blendColor = "0x23324AFF" : m.exitCancelLabel.color = "0xFFFFFFFF"
        m.exitConfirmBg.blendColor = "0xC9A84CFF" : m.exitConfirmLabel.color = "0x0F1923FF"
    end if
end sub

' ── Key routing (all explicit). §12 ─────────────────────────────────────
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Exit prompt owns all keys while open (may sit over the error/empty states).
    if m.exitDialog.visible then return handleExitKeys(key)

    ' Error state: only OK (retry) and BACK (exit prompt) are meaningful.
    if m.retryBtn.visible then
        if key = "OK" then
            m.errorLabel.visible = false
            m.retryBtn.visible = false
            loadData()
            return true
        end if
        if key = "back" then
            showExit()
            return true
        end if
        return true
    end if

    ' Empty state (authed, no content): OK refreshes, BACK opens the exit prompt.
    if m.emptyState.visible then
        if key = "OK" then
            loadData()
            return true
        end if
        if key = "back" then
            showExit()
            return true
        end if
        return true
    end if

    if m.data = invalid then return false

    if m.zone = "nav" then return handleNavKeys(key)
    if m.zone = "rails" then return handleRailKeys(key)
    return handleHeroKeys(key)
end function

function handleHeroKeys(key as string) as boolean
    if key = "back" then
        showExit()
        return true
    end if
    if key = "down" then
        if m.rails.Count() > 0 then enterRailsFromHero()
        return true
    end if
    if key = "up" then return true
    if key = "OK" then
        ' If the slide just auto-flipped, swallow this OK (it was almost
        ' certainly aimed at the previous slide) and clear the guard so the
        ' next OK activates normally.
        if m.justAdvanced then
            m.justAdvanced = false
            m.advanceGuard.control = "stop"
            return true
        end if
        heroActivate()
        return true
    end if
    ' Any directional input means the user is driving — drop the guard.
    m.justAdvanced = false
    if key = "left" then
        if m.heroBtn = 0 then
            if m.slideIndex > 0 then
                goToSlide(m.slideIndex - 1)
            else
                openNav()
            end if
        else
            m.heroBtn = m.heroBtn - 1
            m.hero.focusedButton = m.heroBtn
            startAuto()
        end if
        return true
    end if
    if key = "right" then
        if m.heroBtn >= 2 then
            if m.slideIndex < m.carousel.Count() - 1 then
                goToSlide(m.slideIndex + 1)
            end if
        else
            m.heroBtn = m.heroBtn + 1
            m.hero.focusedButton = m.heroBtn
            startAuto()
        end if
        return true
    end if
    return false
end function

function handleRailKeys(key as string) as boolean
    if key = "back" then
        if m.catalog <> "" then
            exitCatalog()
        else
            showExit()
        end if
        return true
    end if
    col = m.colByRail[m.railIndex]
    if key = "left" then
        if col > 0 then
            m.colByRail[m.railIndex] = col - 1
            updateRailFocus()
        else
            openNav()
        end if
        return true
    end if
    if key = "right" then
        itemCount = m.railNodes[m.railIndex].itemCount
        if col < itemCount - 1 then
            m.colByRail[m.railIndex] = col + 1
            updateRailFocus()
        end if
        return true
    end if
    if key = "down" then
        if m.railIndex < m.railNodes.Count() - 1 then
            m.railIndex = m.railIndex + 1
            updateRailFocus()
        end if
        return true
    end if
    if key = "up" then
        if m.railIndex > 0 then
            m.railIndex = m.railIndex - 1
            updateRailFocus()
        else
            ' First rail UP: catalog → nav; home → back to hero. §6.5
            if m.catalog <> "" then
                openNav()
            else
                returnToHero()
            end if
        end if
        return true
    end if
    if key = "OK" then
        selectCard()
        return true
    end if
    return false
end function

function handleNavKeys(key as string) as boolean
    if key = "back" then
        closeNavToContent()
        return true
    end if
    if key = "up" then
        if m.navIndex > 0 then
            m.navIndex = m.navIndex - 1
            m.nav.focusedIndex = m.navIndex
        end if
        return true
    end if
    if key = "down" then
        if m.navIndex < m.navIds.Count() - 1 then
            m.navIndex = m.navIndex + 1
            m.nav.focusedIndex = m.navIndex
        end if
        return true
    end if
    if key = "right" then
        closeNavToContent()
        return true
    end if
    if key = "left" then return true
    if key = "OK" then
        onNavSelect(m.navIds[m.navIndex])
        return true
    end if
    return false
end function

function handleExitKeys(key as string) as boolean
    if key = "left" or key = "right" then
        if m.exitSel = 0 then m.exitSel = 1 else m.exitSel = 0
        styleExit()
        return true
    end if
    if key = "back" then
        hideExit()
        return true
    end if
    if key = "OK" then
        if m.exitSel = 0 then
            hideExit()
        else
            m.top.exitApp = true
        end if
        return true
    end if
    return false
end function
