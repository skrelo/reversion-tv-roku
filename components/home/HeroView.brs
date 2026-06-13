sub init()
    m.backdropBg = m.top.findNode("backdropBg")
    m.backdropA = m.top.findNode("backdropA")
    m.backdropB = m.top.findNode("backdropB")
    m.darken = m.top.findNode("darken")
    m.scrim = m.top.findNode("scrim")
    m.fade = m.top.findNode("fade")
    m.content = m.top.findNode("content")
    m.dots = m.top.findNode("dots")
    m.fadeAnim = m.top.findNode("fadeAnim")
    m.fadeInInterp = m.top.findNode("fadeInInterp")
    m.contentAnim = m.top.findNode("contentAnim")
    m.contentOpacInterp = m.top.findNode("contentOpacInterp")
    m.wordmarkOpacInterp = m.top.findNode("wordmarkOpacInterp")
    m.slideAnim = m.top.findNode("slideAnim")
    m.contentSlideInterp = m.top.findNode("contentSlideInterp")
    m.wordmarkSlideInterp = m.top.findNode("wordmarkSlideInterp")
    m.wordmark = m.top.findNode("wordmark")
    m.slideDir = 1   ' 1 = forward (right→left), -1 = backward (left→right)
    m.prevSlideIndex = 0

    ' The content column is bottom-anchored: its action row must sit at the same
    ' Y on every slide whether or not a description is present. LayoutGroup grows
    ' downward and Roku only reports boundingRect after a render pass, so we build
    ' the column, then measure + reposition on the next frame and fade it in.
    m.pendingContentBottom = 0
    m.layoutTimer = CreateObject("roSGNode", "Timer")
    m.layoutTimer.duration = 0.05   ' ~3 frames: ensure the column has rendered
    m.layoutTimer.repeat = false
    m.layoutTimer.observeField("fire", "onContentLayout")

    ' Backdrop crossfade state. A = back (previous) layer, B = front (current)
    ' layer. Set synchronously in setBackdrop — no load-status observer.
    m.shownUrl = ""

    ' Button node refs (rebuilt each carousel render).
    m.watchBg = invalid : m.watchIcon = invalid : m.watchLabel = invalid
    m.mylistBg = invalid : m.mylistIcon = invalid
    m.infoBg = invalid : m.infoIcon = invalid

    ' Track last-rendered state to skip re-animation on no-change renders
    ' (e.g. returning from nav to the same slide).
    m.renderedMode = ""
    m.renderedSlideIdx = -1

    onHeightChanged()
end sub

' ── Render ──────────────────────────────────────────────────────────────
sub render()
    newMode = m.top.mode
    newIdx = m.top.slideIndex

    ' If the mode + slide index haven't changed, just update buttons —
    ' don't rebuild content or re-trigger the slide-in animation.
    if newMode = m.renderedMode and newMode = "carousel" and newIdx = m.renderedSlideIdx then
        updateButtons()
        return
    end if

    if newMode = "spotlight" then
        renderSpotlight()
    else
        renderCarousel()
    end if
    m.renderedMode = newMode
    m.renderedSlideIdx = newIdx
    onHeightChanged()
    updateButtons()
end sub

sub renderCarousel()
    s = m.top.slide
    clearContent()
    m.watchBg = invalid : m.mylistBg = invalid : m.infoBg = invalid
    if s = invalid then
        m.wordmark.visible = false
        buildDots()
        return
    end if

    ' Detect slide direction for horizontal transition.
    idx = m.top.slideIndex
    if idx > m.prevSlideIndex then
        m.slideDir = 1
    else if idx < m.prevSlideIndex then
        m.slideDir = -1
    end if
    m.prevSlideIndex = idx

    setBackdrop(s.backdropUrl)

    ' Wordmark: centered across the hero, pinned near the top (Tizen
    ' .hero-wordmark top:64 / left:50%). The CDN pads it onto an exact
    ' transparent canvas so any aspect / line count lands truly centered.
    ' The bottom-left column then carries meta/tagline/desc/actions.
    items = []
    if nz(s.wordmarkUrl) <> "" then
        ' Match Android's tv_hero_wordmark_max 620dp x 190dp (density 2.0 ->
        ' 1240x380 px in the 1920x1080 space) so the wordmark reads large.
        wmW = 1240 : wmH = 380
        m.wordmark.width = wmW : m.wordmark.height = wmH
        m.wordmark.translation = [Int((1920 - wmW) / 2), 56]
        m.wordmark.uri = PaddedImage(s.wordmarkUrl, wmW, wmH)
        m.wordmark.visible = true
    else
        m.wordmark.visible = false
        items.push({ node: makeLabel(nz(s.title), "Bold", 72, "0xFFFFFFFF", 1000, 2), gap: 0 })
    end if

    meta = makeMeta(s.sessionDate, intOr(s.videoCount, 0))
    if meta <> invalid then items.push({ node: meta, gap: 16 })
    if nz(s.tagline) <> "" then items.push({ node: makeLabel(s.tagline, "Bold", 30, "0xC9A84CFF", 900, 2), gap: 12 })
    if nz(s.description) <> "" then
        g = 14
        if nz(s.tagline) = "" then g = 12
        items.push({ node: makeLabel(s.description, "SemiBold", 26, "0xF5F2ECFF", 900, 2), gap: g })
    end if

    ' Action row [Watch/Continue] [+My List] [Info].
    actions = makeActions(s)
    items.push({ node: actions, gap: 28 })

    layoutColumn(items)
    buildDots()
    ' Anchor the action row's bottom here (well above the 918 hero bottom) so the
    ' meta/description/buttons sit in the lower-middle, not jammed near the rails.
    layoutAndReveal(740)
end sub

sub renderSpotlight()
    sp = m.top.spotlight
    m.dots.visible = false
    ' Spotlight keeps its wordmark LEFT in the bottom content column (Tizen
    ' .spotlight-wordmark object-position:left) — the centered top wordmark is
    ' carousel-only.
    m.wordmark.visible = false
    clearContent()
    m.watchBg = invalid : m.mylistBg = invalid : m.infoBg = invalid
    if sp = invalid then return

    setBackdrop(sp.backdropUrl)

    items = []
    if nz(sp.wordmarkUrl) <> "" then
        items.push({ node: makeWordmark(sp.wordmarkUrl, 560, 120), gap: 0 })
    else
        items.push({ node: makeLabel(nz(sp.title), "Bold", 48, "0xFFFFFFFF", 1000, 2), gap: 0 })
    end if
    if nz(sp.videoTitle) <> "" then items.push({ node: makeLabel(sp.videoTitle, "SemiBold", 26, "0xFFFFFFF2", 900, 1), gap: 8 })

    meta = makeMeta(sp.sessionDate, intOr(sp.videoCount, 0))
    if meta <> invalid then items.push({ node: meta, gap: 14 })
    if nz(sp.tagline) <> "" then items.push({ node: makeLabel(sp.tagline, "Bold", 28, "0xC9A84CFF", 900, 1), gap: 12 })
    if nz(sp.description) <> "" then
        g = 14
        if nz(sp.tagline) = "" then g = 12
        items.push({ node: makeLabel(sp.description, "SemiBold", 24, "0xF5F2ECFF", 900, 2), gap: g })
    end if

    layoutColumn(items)
    ' Collapsed hero is 648; bottom-anchor the spotlight column (Tizen bottom:56).
    layoutAndReveal(592)
end sub

' Build-time: hide the freshly-built column, remember where its BOTTOM should
' land, and defer measurement one frame (boundingRect is only valid post-render).
sub layoutAndReveal(contentBottom as integer)
    m.pendingContentBottom = contentBottom
    m.contentAnim.control = "stop"
    m.content.opacity = 0
    m.wordmark.opacity = 0
    ' Provisional placement near the target so a missed measurement still looks
    ' sane; the timer corrects it before the fade makes it visible.
    m.content.translation = [150, contentBottom - 240]
    m.layoutTimer.control = "stop"
    m.layoutTimer.control = "start"
end sub

' Next frame: measure the column and anchor its bottom, then fade in. Bottom-
' anchoring keeps the action row at a constant Y across slides regardless of
' whether a tagline/description is present.
sub onContentLayout()
    r = m.content.boundingRect()
    h = 0
    if r <> invalid then h = r.height
    targetY = m.pendingContentBottom - h
    if h <= 0 then targetY = m.pendingContentBottom - 240
    targetX = 150
    m.content.translation = [targetX, targetY]

    ' Horizontal slide: content glides in from the direction of navigation.
    slideOffset = 120 * m.slideDir
    startX = targetX + slideOffset
    m.slideAnim.control = "stop"
    m.contentSlideInterp.keyValue = [[startX, targetY], [targetX, targetY]]

    ' Wordmark slides too (if visible).
    wmPos = m.wordmark.translation
    if m.wordmark.visible and wmPos <> invalid then
        wmStartX = wmPos[0] + slideOffset
        m.wordmarkSlideInterp.keyValue = [[wmStartX, wmPos[1]], [wmPos[0], wmPos[1]]]
    else
        m.wordmarkSlideInterp.keyValue = [[0, 0], [0, 0]]
    end if

    ' Fade + slide together.
    m.contentAnim.control = "stop"
    m.contentOpacInterp.keyValue = [0.0, 1.0]
    m.wordmarkOpacInterp.keyValue = [0.0, 1.0]
    m.contentAnim.control = "start"
    m.slideAnim.control = "start"
end sub

' Append the visible column children with per-gap spacings (vertical
' LayoutGroup itemSpacings is the gap BEFORE each child after the first).
sub layoutColumn(items as object)
    spacings = []
    i = 0
    for each it in items
        if i > 0 then spacings.push(it.gap)
        m.content.appendChild(it.node)
        i = i + 1
    end for
    if spacings.Count() = 0 then spacings = [0]
    m.content.itemSpacings = spacings
end sub

sub clearContent()
    m.content.removeChildren(m.content.getChildren(-1, 0))
end sub

' ── Element builders ────────────────────────────────────────────────────
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

function makeWordmark(url as string, w as integer, h as integer) as object
    p = CreateObject("roSGNode", "Poster")
    p.width = w
    p.height = h
    ' scaleToFit scales the bitmap UP or DOWN to fit the box while preserving
    ' aspect ratio (never stretches), anchored top-left — the Roku equivalent of
    ' Tizen's `object-fit: contain` + `object-position: left`. This gives every
    ' slide a consistent, correctly-proportioned wordmark instead of the
    ' down-only `limitSize` that left some marks tiny and others clipped.
    p.loadDisplayMode = "scaleToFit"
    p.uri = SizedImageH(url, h * 2)
    return p
end function

function makeMeta(dateStr as dynamic, count as integer) as object
    d = nz(dateStr)
    label = CountLabel(count)
    if d = "" and label = "" then return invalid

    row = CreateObject("roSGNode", "LayoutGroup")
    row.layoutDirection = "horiz"
    row.itemSpacings = [10]
    row.vertAlignment = "center"

    ' Auto-width labels (width 0) so the LayoutGroup packs them tightly with the
    ' camera glyph — no fixed width pushing the count to the far right.
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

function makeActions(s as object) as object
    row = CreateObject("roSGNode", "LayoutGroup")
    row.id = "actionsRow"
    row.layoutDirection = "horiz"
    row.itemSpacings = [18]
    row.vertAlignment = "center"

    label = nz(s.watchLabel)
    if s.hasTarget = true then
        if label = "" then label = "Watch"
    else
        label = "View"
    end if
    pillW = 200
    if label = "Continue" then pillW = 236
    watch = CreateObject("roSGNode", "Group")
    m.watchBg = roundedBg(pillW, 64, "0xFFFFFF26")
    watch.appendChild(m.watchBg)
    iconName = "ic_play.png"
    if not s.hasTarget then iconName = "ic_info.png"
    m.watchIcon = glyph(iconName, 26, [26, 19], "0xFFFFFFFF")
    watch.appendChild(m.watchIcon)
    m.watchLabel = makeLabel(label, "Bold", 26, "0xFFFFFFFF", pillW - 70, 1)
    m.watchLabel.translation = [62, 0]
    m.watchLabel.height = 64
    m.watchLabel.vertAlign = "center"
    watch.appendChild(m.watchLabel)
    row.appendChild(watch)

    mylist = CreateObject("roSGNode", "Group")
    m.mylistBg = roundedBg(64, 64, "0xFFFFFF26")
    mylist.appendChild(m.mylistBg)
    micon = "ic_add.png"
    if m.top.inMyList = true then micon = "ic_check.png"
    m.mylistIcon = glyph(micon, 30, [17, 17], "0xFFFFFFFF")
    mylist.appendChild(m.mylistIcon)
    row.appendChild(mylist)

    info = CreateObject("roSGNode", "Group")
    m.infoBg = roundedBg(64, 64, "0xFFFFFF26")
    info.appendChild(m.infoBg)
    m.infoIcon = glyph("ic_info.png", 30, [17, 17], "0xFFFFFFFF")
    info.appendChild(m.infoIcon)
    row.appendChild(info)

    return row
end function

function roundedBg(w as integer, h as integer, color as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.width = w : p.height = h
    p.uri = "pkg:/images/btn_rounded.9.png"
    p.blendColor = color
    return p
end function

function glyph(icon as string, size as integer, xy as object, color as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.width = size : p.height = size
    p.translation = xy
    p.uri = "pkg:/images/icons/" + icon
    p.blendColor = color
    return p
end function

' ── Dots (bottom-center) ────────────────────────────────────────────────
sub buildDots()
    m.dots.removeChildren(m.dots.getChildren(-1, 0))
    count = m.top.slideCount
    if count <= 1 or m.top.mode <> "carousel" then
        m.dots.visible = false
        return
    end if
    m.dots.visible = true
    idx = m.top.slideIndex
    for i = 0 to count - 1
        dot = CreateObject("roSGNode", "Rectangle")
        dot.width = 12 : dot.height = 12
        if i = idx then
            dot.color = "0xC9A84CFF"
        else
            dot.color = "0xF0EBE359"
        end if
        m.dots.appendChild(dot)
    end for
    totalW = count * 12 + (count - 1) * 12
    m.dots.translation = [Int((1920 - totalW) / 2), m.dotsY]
end sub

' ── Height tracking (hero collapses/expands; all layers follow) ──────────
sub onHeightChanged()
    h = m.top.heroHeight
    if h <= 0 then h = 918
    m.backdropBg.height = h
    m.backdropA.height = h
    m.backdropB.height = h
    m.darken.height = h
    m.fade.height = h
    ' Scrim + dots anchored to the live hero bottom.
    sy = h - m.scrim.height
    if sy > 0 then sy = 0
    m.scrim.translation = [0, sy]
    m.dotsY = Int(h - 44)
    m.dots.translation = [m.dots.translation[0], m.dotsY]
end sub

' ── Backdrop crossfade (fully synchronous — no async load callback) ───────
' B is the FRONT layer (drawn on top) and ALWAYS holds the current slide's
' image; A is the BACK layer holding the previous image during the fade. Every
' value is set synchronously from this call, so the visible image can NEVER be
' a stale slide's art — the previous design waited on loadStatus and a late
' callback from an earlier slide could repaint the wrong backdrop.
sub setBackdrop(url as dynamic)
    u = nz(url)
    if u <> "" then u = SizedImage(u, 1920)
    if u = m.shownUrl then return

    m.fadeAnim.control = "stop"

    if m.shownUrl = "" or u = "" then
        ' First paint (or clear): show on the front layer with no crossfade.
        m.backdropB.uri = u
        m.backdropB.opacity = 1
        m.backdropA.opacity = 0
        m.shownUrl = u
        return
    end if

    ' Park the CURRENT image on the back layer at full opacity, then fade the
    ' NEW image in on the front layer. B's uri is the value we were just given,
    ' so the front layer is always exactly this slide's backdrop.
    m.backdropA.uri = m.shownUrl
    m.backdropA.opacity = 1
    m.backdropB.uri = u
    m.backdropB.opacity = 0
    m.shownUrl = u
    m.fadeInInterp.keyValue = [0.0, 1.0]
    m.fadeAnim.control = "start"
end sub

' ── Button focus styling ────────────────────────────────────────────────
' Paramount focus pattern (matches Android tv_button_watch_bg /
' tv_button_hero_icon_bg). RESTING (all three): translucent-white fill
' (#26 white) + white foreground so the row reads as one unified group.
' FOCUSED: the primary Watch/Continue button fills SOLID GOLD; the icon
' buttons (My List / Info) fill SOLID WHITE. In either focused fill the
' foreground (icon + label) flips to dark navy for legibility.
sub updateButtons()
    if m.watchBg = invalid then return
    b = m.top.focusedButton
    styleButton(m.watchBg, m.watchIcon, m.watchLabel, (b = 0), "0xC9A84CFF")
    styleButton(m.mylistBg, m.mylistIcon, invalid, (b = 1), "0xFFFFFFFF")
    styleButton(m.infoBg, m.infoIcon, invalid, (b = 2), "0xFFFFFFFF")
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
