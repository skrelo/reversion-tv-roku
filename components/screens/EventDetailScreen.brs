sub init()
    m.bg = m.top.findNode("bg")
    m.backdrop = m.top.findNode("backdrop")
    m.wordmark = m.top.findNode("wordmark")
    m.titleFallback = m.top.findNode("titleFallback")
    m.leftCol = m.top.findNode("leftCol")
    m.rightCol = m.top.findNode("rightCol")
    m.bandAnim = m.top.findNode("bandAnim")
    m.leftOpac = m.top.findNode("leftOpac")
    m.rightOpac = m.top.findNode("rightOpac")
    m.wmOpac = m.top.findNode("wmOpac")
    m.rail = m.top.findNode("videosRail")
    m.nav = m.top.findNode("nav")
    m.loading = m.top.findNode("loading")
    m.errorLabel = m.top.findNode("errorLabel")
    m.emptyLabel = m.top.findNode("emptyLabel")
    m.toast = m.top.findNode("toast")
    m.toastLabel = m.top.findNode("toastLabel")

    m.descModal = m.top.findNode("descModal")
    m.modalTitle = m.top.findNode("modalTitle")
    m.modalMeta = m.top.findNode("modalMeta")
    m.modalTagline = m.top.findNode("modalTagline")
    m.modalBody = m.top.findNode("modalBody")

    ' Bottom edge the two-column band is anchored to (well above the 700 hero
    ' bottom so the Videos rail header clears it).
    m.BAND_BOTTOM = 660

    ' Focus state. zone: hero | rail | nav.
    m.zone = "hero"
    m.heroIds = []          ' subset of ["watch","mylist","desc"] that exist
    m.heroPos = 0
    m.railCol = 0
    m.descOpen = false

    m.navIds = ["search", "home", "meetups", "livestreams", "continue", "mylist", "settings"]
    m.navIndex = 1
    m.nav.activeId = "home"

    ' Button / block node refs (rebuilt on render).
    m.watchBg = invalid : m.watchIcon = invalid : m.watchLabel = invalid
    m.mylistBg = invalid : m.mylistIcon = invalid
    m.descBg = invalid : m.descLabel = invalid : m.descMore = invalid

    m.layoutTimer = CreateObject("roSGNode", "Timer")
    m.layoutTimer.duration = 0.05
    m.layoutTimer.repeat = false
    m.layoutTimer.observeField("fire", "onBandLayout")

    m.modalTimer = CreateObject("roSGNode", "Timer")
    m.modalTimer.duration = 0.05
    m.modalTimer.repeat = false
    m.modalTimer.observeField("fire", "onModalBodyLayout")
    m.modalScrollY = 0
    m.modalMax = 0

    m.toastTimer = CreateObject("roSGNode", "Timer")
    m.toastTimer.duration = 2.5
    m.toastTimer.repeat = false
    m.toastTimer.observeField("fire", "onToastTimer")

    m.top.setFocus(true)
end sub

' eventId is set by MainScene AFTER the node is created (init already ran), so
' the data load is triggered here rather than in init().
sub onEventIdSet()
    if m.top.eventId = invalid or m.top.eventId = "" then return
    if m.loadStarted = true then return
    m.loadStarted = true
    loadData()
end sub

' ── Data load (GET /events/:id + /library) ──────────────────────────────
sub loadData()
    m.loading.visible = true
    m.evDone = false : m.libDone = false
    m.evRes = invalid : m.libRes = invalid

    m.evTask = CreateObject("roSGNode", "ApiTask")
    m.evTask.observeField("response", "onEventResponse")
    m.evTask.request = ApiReq().event(m.top.eventId)
    m.evTask.control = "RUN"

    m.libTask = CreateObject("roSGNode", "ApiTask")
    m.libTask.observeField("response", "onLibResponse")
    m.libTask.request = ApiReq().library()
    m.libTask.control = "RUN"
end sub

sub onEventResponse()
    m.evRes = m.evTask.response
    m.evDone = true
    maybeReady()
end sub
sub onLibResponse()
    m.libRes = m.libTask.response
    m.libDone = true
    maybeReady()
end sub

sub maybeReady()
    if not (m.evDone and m.libDone) then return
    m.loading.visible = false

    if m.evRes <> invalid and m.evRes.status = 401 then
        m.top.signedOut = true
        return
    end if
    if m.evRes = invalid or m.evRes.ok <> true or m.evRes.data = invalid then
        m.errorLabel.text = "Could not load this event. Check your connection."
        m.errorLabel.visible = true
        return
    end if

    m.event = m.evRes.data.event
    if m.event = invalid then m.event = m.evRes.data
    m.videos = arr(m.evRes.data.videos)

    m.inList = false
    if m.libRes <> invalid and m.libRes.ok = true and m.libRes.data <> invalid then
        evbm = arr(m.libRes.data.event_bookmarks)
        eid = toStr(m.event.id)
        for each e in evbm
            if toStr(e.id) = eid then m.inList = true
        end for
    end if

    renderHero()
    buildRail()
    setInitialFocus()
end sub

function arr(v as dynamic) as object
    if v <> invalid and GetInterface(v, "ifArray") <> invalid then return v
    return []
end function

' ── Hero render (top-centre wordmark + two-column bottom band) ──────────
sub renderHero()
    ev = m.event

    backdropUrl = firstNonEmpty([ev.backdrop_url, ev.poster_url, ev.card_poster_url])
    if backdropUrl <> "" then m.backdrop.uri = SizedImage(backdropUrl, 1920)

    ' Watch target (resume > first video). §7
    inProgress = ev.last_in_progress_video
    firstVideo = ev.first_video
    target = inProgress
    if target = invalid then target = firstVideo
    m.playable = (target <> invalid)
    m.targetVideoId = ""
    if target <> invalid then m.targetVideoId = toStr(target.id)
    watchLabel = "Watch"
    if inProgress <> invalid then watchLabel = "Continue"
    targetTitle = ""
    if target <> invalid then targetTitle = nz(target.title)

    tagline = nz(ev.tv_subtitle)
    rawDesc = firstNonEmpty([ev.description, ev.short_description])
    description = StripHtml(rawDesc)
    m.fullDescription = HtmlToText(rawDesc)
    m.hasDesc = (description <> "")

    wordmarkUrl = nz(ev.wordmark_url)
    if wordmarkUrl <> "" then
        wmW = 1100 : wmH = 300
        m.wordmark.width = wmW : m.wordmark.height = wmH
        m.wordmark.translation = [Int((1920 - wmW) / 2), 52]
        m.wordmark.uri = PaddedImage(wordmarkUrl, wmW, wmH)
        m.wordmark.visible = true
        m.titleFallback.visible = false
    else
        m.wordmark.visible = false
        m.titleFallback.text = nz(ev.title)
        m.titleFallback.visible = true
    end if

    ' LEFT column: watch-target one-liner + action row.
    m.leftCol.removeChildren(m.leftCol.getChildren(-1, 0))
    leftSpacings = []
    if m.playable and targetTitle <> "" then
        m.leftCol.appendChild(buildWatchTarget(targetTitle))
        leftSpacings.push(18)
    end if
    m.leftCol.appendChild(buildActions(watchLabel))
    if leftSpacings.Count() = 0 then leftSpacings = [0]
    m.leftCol.itemSpacings = leftSpacings

    ' RIGHT column: tagline -> description -> meta.
    m.rightCol.removeChildren(m.rightCol.getChildren(-1, 0))
    rightSpacings = []
    n = 0
    if tagline <> "" then
        m.rightCol.appendChild(makeLabel(tagline, "Bold", 28, "0xC9A84CFF", 800, 2))
        n = n + 1
    end if
    if m.hasDesc then
        if n > 0 then rightSpacings.push(14)
        m.rightCol.appendChild(buildDescBlock(description))
        n = n + 1
    end if
    metaRow = makeMeta(nz(ev.session_date), intOr(ev.video_count, m.videos.Count()))
    if metaRow <> invalid then
        if n > 0 then rightSpacings.push(16)
        m.rightCol.appendChild(metaRow)
        n = n + 1
    end if
    if rightSpacings.Count() = 0 then rightSpacings = [0]
    m.rightCol.itemSpacings = rightSpacings

    ' Build the focus order from what actually exists.
    m.heroIds = []
    if m.playable then m.heroIds.push("watch")
    m.heroIds.push("mylist")
    if m.hasDesc then m.heroIds.push("desc")

    ' Hide until measured + bottom-anchored, then fade in.
    m.bandAnim.control = "stop"
    m.leftCol.opacity = 0 : m.rightCol.opacity = 0 : m.wordmark.opacity = 0
    m.layoutTimer.control = "stop"
    m.layoutTimer.control = "start"
end sub

' Next frame: bottom-anchor both columns to a shared baseline, then reveal.
sub onBandLayout()
    lh = colHeight(m.leftCol)
    rh = colHeight(m.rightCol)
    m.leftCol.translation = [150, m.BAND_BOTTOM - lh]
    m.rightCol.translation = [980, m.BAND_BOTTOM - rh]
    m.bandAnim.control = "stop"
    m.leftOpac.keyValue = [0.0, 1.0]
    m.rightOpac.keyValue = [0.0, 1.0]
    m.wmOpac.keyValue = [0.0, 1.0]
    m.bandAnim.control = "start"
    styleHero()
end sub

function colHeight(col as object) as integer
    r = col.boundingRect()
    if r <> invalid and r.height > 0 then return r.height
    return 120
end function

' ── Element builders ────────────────────────────────────────────────────
function buildWatchTarget(title as string) as object
    row = CreateObject("roSGNode", "LayoutGroup")
    row.layoutDirection = "horiz"
    row.itemSpacings = [8]
    row.vertAlignment = "center"
    cam = CreateObject("roSGNode", "Poster")
    cam.width = 22 : cam.height = 22
    cam.uri = "pkg:/images/icons/ic_play.png"
    cam.blendColor = "0xC9A84CFF"
    row.appendChild(cam)
    row.appendChild(makeLabel(title, "SemiBold", 22, "0xFFFFFFF2", 0, 1))
    return row
end function

function buildActions(watchLabel as string) as object
    row = CreateObject("roSGNode", "LayoutGroup")
    row.layoutDirection = "horiz"
    row.itemSpacings = [18]
    row.vertAlignment = "center"

    if m.playable then
        pillW = 200
        if watchLabel = "Continue" then pillW = 236
        watch = CreateObject("roSGNode", "Group")
        m.watchBg = roundedBg(pillW, 64, "0xFFFFFF26")
        watch.appendChild(m.watchBg)
        m.watchIcon = glyph("ic_play.png", 26, [26, 19], "0xFFFFFFFF")
        watch.appendChild(m.watchIcon)
        m.watchLabel = makeLabel(watchLabel, "Bold", 26, "0xFFFFFFFF", pillW - 70, 1)
        m.watchLabel.translation = [62, 0]
        m.watchLabel.height = 64
        m.watchLabel.vertAlign = "center"
        watch.appendChild(m.watchLabel)
        row.appendChild(watch)
    end if

    mylist = CreateObject("roSGNode", "Group")
    m.mylistBg = roundedBg(64, 64, "0xFFFFFF26")
    mylist.appendChild(m.mylistBg)
    micon = "ic_add.png"
    if m.inList then micon = "ic_check.png"
    m.mylistIcon = glyph(micon, 30, [17, 17], "0xFFFFFFFF")
    mylist.appendChild(m.mylistIcon)
    row.appendChild(mylist)

    return row
end function

' Focusable, clamped description with a "More" affordance (OK -> modal). §7
function buildDescBlock(text as string) as object
    grp = CreateObject("roSGNode", "Group")
    m.descBg = CreateObject("roSGNode", "Rectangle")
    m.descBg.width = 820 : m.descBg.height = 162
    m.descBg.translation = [0, 0]
    m.descBg.color = "0x00000000"
    grp.appendChild(m.descBg)

    m.descLabel = makeLabel(text, "SemiBold", 23, "0xF2F2F2F2", 796, 4)
    m.descLabel.translation = [10, 8]
    m.descLabel.height = 124
    grp.appendChild(m.descLabel)

    m.descMore = makeLabel("More ›", "Bold", 19, "0x9FB0C0FF", 200, 1)
    m.descMore.translation = [10, 134]
    grp.appendChild(m.descMore)
    return grp
end function

function makeLabel(text as string, weight as string, size as integer, color as string, w as integer, maxLines as integer) as object
    lbl = CreateObject("roSGNode", "Label")
    lbl.width = w
    lbl.wrap = (maxLines > 1)
    lbl.maxLines = maxLines
    lbl.color = color
    lbl.text = text
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/Montserrat-" + weight + ".ttf"
    f.size = size
    lbl.font = f
    return lbl
end function

function makeMeta(dateStr as dynamic, count as integer) as object
    d = nz(dateStr)
    label = CountLabel(count)
    if d = "" and label = "" then return invalid
    row = CreateObject("roSGNode", "LayoutGroup")
    row.layoutDirection = "horiz"
    row.itemSpacings = [10]
    row.vertAlignment = "center"
    if d <> "" then row.appendChild(makeLabel(d, "Bold", 22, "0xC9A84CFF", 0, 1))
    if d <> "" and label <> "" then row.appendChild(makeLabel("·", "Bold", 22, "0x8C9EB0FF", 0, 1))
    if label <> "" then
        cam = CreateObject("roSGNode", "Poster")
        cam.width = 26 : cam.height = 26
        cam.uri = "pkg:/images/icons/ic_videocount.png"
        cam.blendColor = "0xC9A84CFF"
        row.appendChild(cam)
        row.appendChild(makeLabel(label, "Bold", 22, "0xC9A84CFF", 0, 1))
    end if
    return row
end function

function roundedBg(w as integer, h as integer, color as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.width = w : p.height = h
    p.uri = "pkg:/images/btn_rounded.9.png"
    p.blendColor = color
    return p
end function

function glyph(icon as string, size as integer, pos as object, color as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.width = size : p.height = size
    p.translation = pos
    p.uri = "pkg:/images/icons/" + icon
    p.blendColor = color
    return p
end function

' ── Videos rail ─────────────────────────────────────────────────────────
sub buildRail()
    if m.videos.Count() = 0 then
        m.emptyLabel.visible = true
        m.rail.rail = { title: "Videos", items: [], type: "video" }
        return
    end if
    m.emptyLabel.visible = false
    m.rail.rail = { title: "Videos", items: m.videos, type: "video", hideOverlay: true }
    m.railCol = 0
end sub

' ── Focus ───────────────────────────────────────────────────────────────
sub setInitialFocus()
    m.zone = "hero"
    ' Watch when playable, else first available (desc or my list). §7
    m.heroPos = 0
    styleHero()
end sub

function currentHeroId() as string
    if m.heroIds.Count() = 0 then return ""
    if m.heroPos < 0 then m.heroPos = 0
    if m.heroPos > m.heroIds.Count() - 1 then m.heroPos = m.heroIds.Count() - 1
    return m.heroIds[m.heroPos]
end function

sub styleHero()
    inHero = (m.zone = "hero")
    cur = ""
    if inHero then cur = currentHeroId()
    styleButton(m.watchBg, m.watchIcon, m.watchLabel, (cur = "watch"), "0xC9A84CFF")
    styleButton(m.mylistBg, m.mylistIcon, invalid, (cur = "mylist"), "0xFFFFFFFF")
    styleDesc(cur = "desc")
end sub

sub styleButton(bg as object, icon as object, label as object, focused as boolean, focusFill as string)
    if bg = invalid then return
    if focused then
        bg.blendColor = focusFill
        if icon <> invalid then icon.blendColor = "0x0F1923FF"
        if label <> invalid then label.color = "0x0F1923FF"
    else
        bg.blendColor = "0xFFFFFF26"
        if icon <> invalid then icon.blendColor = "0xFFFFFFFF"
        if label <> invalid then label.color = "0xFFFFFFFF"
    end if
end sub

sub styleDesc(focused as boolean)
    if m.descBg = invalid then return
    if focused then
        m.descBg.color = "0xFFFFFF1F"
        m.descMore.color = "0xFFFFFFFF"
    else
        m.descBg.color = "0x00000000"
        m.descMore.color = "0x9FB0C0FF"
    end if
end sub

' ── Rail focus ──────────────────────────────────────────────────────────
sub enterRail()
    if m.videos.Count() = 0 then return
    m.zone = "rail"
    styleHero()
    updateRailFocus()
end sub

sub updateRailFocus()
    if m.railCol < 0 then m.railCol = 0
    if m.railCol > m.videos.Count() - 1 then m.railCol = m.videos.Count() - 1
    m.rail.focusedCol = m.railCol
end sub

sub clearRailFocus()
    m.rail.focusedCol = -1
end sub

' ── Left nav ────────────────────────────────────────────────────────────
sub openNav()
    m.prevZone = m.zone
    m.zone = "nav"
    clearRailFocus()
    styleHero()
    m.navIndex = indexOfNav("home")
    if m.navIndex < 0 then m.navIndex = 1
    m.nav.expanded = true
    m.nav.focusedIndex = m.navIndex
end sub

sub closeNavToContent()
    m.nav.expanded = false
    m.nav.focusedIndex = -1
    if m.prevZone = "rail" and m.videos.Count() > 0 then
        m.zone = "rail"
        updateRailFocus()
    else
        m.zone = "hero"
    end if
    styleHero()
end sub

function indexOfNav(id as string) as integer
    for i = 0 to m.navIds.Count() - 1
        if m.navIds[i] = id then return i
    end for
    return -1
end function

' Selecting any nav item returns Home (§7). Search/Settings aren't built yet.
sub onNavSelect(id as string)
    pop()
end sub

' ── Actions ─────────────────────────────────────────────────────────────
sub heroActivate()
    cur = currentHeroId()
    if cur = "watch" then
        if m.targetVideoId <> "" then
            openVideo(m.targetVideoId)
        else
            showToast("No video to play yet")
        end if
    else if cur = "mylist" then
        toggleMyList()
    else if cur = "desc" then
        openDesc()
    end if
end sub

sub toggleMyList()
    id = toStr(m.event.id)
    if id = "" then return
    nextState = not m.inList
    m.inList = nextState
    if m.mylistIcon <> invalid then
        if nextState then m.mylistIcon.uri = "pkg:/images/icons/ic_check.png" else m.mylistIcon.uri = "pkg:/images/icons/ic_add.png"
    end if
    t = CreateObject("roSGNode", "ApiTask")
    if nextState then
        t.request = ApiReq().addEventBookmark(id)
    else
        t.request = ApiReq().removeEventBookmark(id)
    end if
    t.control = "RUN"
    m.bookmarkTask = t
end sub

' ── Description modal ───────────────────────────────────────────────────
sub openDesc()
    m.modalTitle.text = nz(m.event.title)
    m.modalTagline.text = nz(m.event.tv_subtitle)
    metaBits = []
    if nz(m.event.session_date) <> "" then metaBits.push(nz(m.event.session_date))
    cl = CountLabel(intOr(m.event.video_count, m.videos.Count()))
    if cl <> "" then metaBits.push(cl)
    m.modalMeta.text = joinStr(metaBits, "   ·   ")
    m.modalBody.text = m.fullDescription
    m.modalBody.translation = [0, 0]
    m.modalScrollY = 0
    m.descOpen = true
    m.descModal.visible = true
    m.modalTimer.control = "stop"
    m.modalTimer.control = "start"
end sub

sub onModalBodyLayout()
    r = m.modalBody.boundingRect()
    h = 0
    if r <> invalid then h = r.height
    m.modalMax = h - 660
    if m.modalMax < 0 then m.modalMax = 0
end sub

sub closeDesc()
    m.descOpen = false
    m.descModal.visible = false
    styleHero()
end sub

sub scrollModal(delta as integer)
    m.modalScrollY = m.modalScrollY + delta
    if m.modalScrollY < 0 then m.modalScrollY = 0
    if m.modalScrollY > m.modalMax then m.modalScrollY = m.modalMax
    m.modalBody.translation = [0, -m.modalScrollY]
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

' Close this screen (MainScene observes `popped`).
sub pop()
    m.top.popped = true
end sub

' ── Key routing (explicit; mirrors Home §12) ────────────────────────────
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.event = invalid then
        ' Allow BACK to leave even on an error/loading screen.
        if key = "back" then
            pop()
            return true
        end if
        return false
    end if

    if m.descOpen then return handleModalKeys(key)
    if m.zone = "nav" then return handleNavKeys(key)
    if m.zone = "rail" then return handleRailKeys(key)
    return handleHeroKeys(key)
end function

function handleHeroKeys(key as string) as boolean
    if key = "back" then
        pop()
        return true
    end if
    if key = "OK" then
        heroActivate()
        return true
    end if
    if key = "down" then
        if m.videos.Count() > 0 then enterRail()
        return true
    end if
    if key = "up" then return true
    if key = "left" then
        if m.heroPos > 0 then
            m.heroPos = m.heroPos - 1
            styleHero()
        else
            openNav()
        end if
        return true
    end if
    if key = "right" then
        if m.heroPos < m.heroIds.Count() - 1 then
            m.heroPos = m.heroPos + 1
            styleHero()
        end if
        return true
    end if
    return false
end function

function handleRailKeys(key as string) as boolean
    if key = "back" then
        pop()
        return true
    end if
    if key = "left" then
        if m.railCol > 0 then
            m.railCol = m.railCol - 1
            updateRailFocus()
        else
            openNav()
        end if
        return true
    end if
    if key = "right" then
        if m.railCol < m.videos.Count() - 1 then
            m.railCol = m.railCol + 1
            updateRailFocus()
        end if
        return true
    end if
    if key = "up" then
        clearRailFocus()
        m.zone = "hero"
        styleHero()
        return true
    end if
    if key = "down" then return true
    if key = "OK" then
        vid = ""
        if m.railCol >= 0 and m.railCol < m.videos.Count() then vid = toStr(m.videos[m.railCol].id)
        if vid <> "" then
            openVideo(vid)
        else
            showToast("This video can't be played")
        end if
        return true
    end if
    return false
end function

' Ask MainScene to push the Player. Clear first so re-selecting re-fires onChange.
sub openVideo(videoId as string)
    m.top.openVideoId = ""
    m.top.openVideoId = videoId
end sub

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

function handleModalKeys(key as string) as boolean
    if key = "back" or key = "OK" then
        closeDesc()
        return true
    end if
    if key = "down" then
        scrollModal(200)
        return true
    end if
    if key = "up" then
        scrollModal(-200)
        return true
    end if
    return true
end function

' ── HTML helpers (mirror Tizen lib/html.js, minimal) ─────────────────────
function StripHtml(s as dynamic) as string
    t = nz(s)
    if t = "" then return ""
    out = ""
    inTag = false
    for each ch in t.Split("")
        if ch = "<" then
            inTag = true
        else if ch = ">" then
            inTag = false
        else if not inTag then
            out = out + ch
        end if
    end for
    out = DecodeEntities(out)
    return CollapseWs(out)
end function

' Block tags -> blank lines so paragraphs survive; everything else stripped.
function HtmlToText(s as dynamic) as string
    t = nz(s)
    if t = "" then return ""
    t = ReplaceStr(t, "</p>", Chr(10) + Chr(10))
    t = ReplaceStr(t, "<br>", Chr(10))
    t = ReplaceStr(t, "<br/>", Chr(10))
    t = ReplaceStr(t, "<br />", Chr(10))
    out = ""
    inTag = false
    for each ch in t.Split("")
        if ch = "<" then
            inTag = true
        else if ch = ">" then
            inTag = false
        else if not inTag then
            out = out + ch
        end if
    end for
    out = DecodeEntities(out)
    return TrimBlankRuns(out)
end function

function DecodeEntities(s as string) as string
    o = s
    o = ReplaceStr(o, "&amp;", "&")
    o = ReplaceStr(o, "&nbsp;", " ")
    o = ReplaceStr(o, "&#39;", "'")
    o = ReplaceStr(o, "&rsquo;", "'")
    o = ReplaceStr(o, "&lsquo;", "'")
    o = ReplaceStr(o, "&ldquo;", Chr(34))
    o = ReplaceStr(o, "&rdquo;", Chr(34))
    o = ReplaceStr(o, "&quot;", Chr(34))
    o = ReplaceStr(o, "&mdash;", "—")
    o = ReplaceStr(o, "&ndash;", "–")
    o = ReplaceStr(o, "&lt;", "<")
    o = ReplaceStr(o, "&gt;", ">")
    return o
end function

function CollapseWs(s as string) as string
    o = ReplaceStr(s, Chr(10), " ")
    o = ReplaceStr(o, Chr(9), " ")
    while Instr(1, o, "  ") > 0
        o = ReplaceStr(o, "  ", " ")
    end while
    return TrimStr(o)
end function

function TrimBlankRuns(s as string) as string
    o = s
    while Instr(1, o, Chr(10) + Chr(10) + Chr(10)) > 0
        o = ReplaceStr(o, Chr(10) + Chr(10) + Chr(10), Chr(10) + Chr(10))
    end while
    return TrimStr(o)
end function

function ReplaceStr(s as string, find as string, repl as string) as string
    if find = "" then return s
    out = ""
    rest = s
    idx = Instr(1, rest, find)
    while idx > 0
        out = out + Left(rest, idx - 1) + repl
        rest = Mid(rest, idx + Len(find))
        idx = Instr(1, rest, find)
    end while
    return out + rest
end function

function TrimStr(s as string) as string
    t = s
    while Len(t) > 0 and (Left(t, 1) = " " or Left(t, 1) = Chr(10) or Left(t, 1) = Chr(13))
        t = Mid(t, 2)
    end while
    while Len(t) > 0 and (Right(t, 1) = " " or Right(t, 1) = Chr(10) or Right(t, 1) = Chr(13))
        t = Left(t, Len(t) - 1)
    end while
    return t
end function

function joinStr(items as object, sep as string) as string
    o = ""
    i = 0
    for each it in items
        if i > 0 then o = o + sep
        o = o + it
        i = i + 1
    end for
    return o
end function
