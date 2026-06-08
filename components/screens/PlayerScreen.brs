' Player (TV_APP_SPEC §9) — Phase 1: load/resume/progress + custom transport
' chrome + focus zones + single-tap & hold-to-seek + Netflix pause overlay.
' Markers / pop-ups / QR note / settings / Up-Next arrive in later passes.
'
' The screen Group owns focus, so the native Video node never gets keys and its
' built-in trickplay UI never shows — all chrome here is hand-drawn (§9 "do not
' use the stock player controller UI").

sub init()
    ' Timing constants (§9.1).
    m.SEEK_STEP = 10
    m.WATCHED = 0.95
    m.SEEK_TIERS = [600, 1000, 1400, 1800]   ' ms held → rate 2..5

    m.video = m.top.findNode("video")
    m.chrome = m.top.findNode("chrome")
    m.loading = m.top.findNode("loading")
    m.errorLabel = m.top.findNode("errorLabel")

    m.pauseScrim = m.top.findNode("pauseScrim")
    m.pauseWordmark = m.top.findNode("pauseWordmark")
    m.pauseTitle = m.top.findNode("pauseTitle")

    m.eventTitle = m.top.findNode("eventTitle")
    m.videoTitle = m.top.findNode("videoTitle")
    m.iconRow = m.top.findNode("iconRow")
    m.pills = m.top.findNode("pills")

    m.scrub = m.top.findNode("scrub")
    m.scrubTrack = m.top.findNode("scrubTrack")
    m.scrubPlayed = m.top.findNode("scrubPlayed")
    m.scrubKnob = m.top.findNode("scrubKnob")
    m.timeElapsed = m.top.findNode("timeElapsed")
    m.timeRemaining = m.top.findNode("timeRemaining")

    m.flash = m.top.findNode("flash")
    m.seekIndicator = m.top.findNode("seekIndicator")
    m.seekChevron = m.top.findNode("seekChevron")
    m.seekRate = m.top.findNode("seekRate")

    m.chapterFlash = m.top.findNode("chapterFlash")
    m.chapterFlashTick = m.top.findNode("chapterFlashTick")
    m.chapterFlashBg = m.top.findNode("chapterFlashBg")
    m.chapterFlashLabel = m.top.findNode("chapterFlashLabel")

    m.chaptersModal = m.top.findNode("chaptersModal")
    m.chaptersClip = m.top.findNode("chaptersClip")
    m.chaptersList = m.top.findNode("chaptersList")

    m.markersClip = m.top.findNode("markersClip")
    m.markersRow = m.top.findNode("markersRow")
    m.markersScrollAnim = m.top.findNode("markersScrollAnim")
    m.markersScrollInterp = m.top.findNode("markersScrollInterp")

    m.popup = m.top.findNode("popup")
    m.detailModal = m.top.findNode("detailModal")
    m.detailPanel = m.top.findNode("detailPanel")
    m.imageViewer = m.top.findNode("imageViewer")
    m.viewerImg = m.top.findNode("viewerImg")
    m.viewerCounter = m.top.findNode("viewerCounter")
    m.textReader = m.top.findNode("textReader")
    m.readerTitle = m.top.findNode("readerTitle")
    m.readerBody = m.top.findNode("readerBody")
    m.readerClip = m.top.findNode("readerClip")

    m.fadeIn = m.top.findNode("chromeFadeIn")
    m.fadeOut = m.top.findNode("chromeFadeOut")

    m.hideTimer = m.top.findNode("hideTimer")
    m.hideTimer.observeField("fire", "onHideTimer")
    m.indicatorTimer = m.top.findNode("indicatorTimer")
    m.indicatorTimer.observeField("fire", "onIndicatorTimer")
    m.flashTimer = m.top.findNode("flashTimer")
    m.flashTimer.observeField("fire", "onFlashTimer")
    m.saveTimer = m.top.findNode("saveTimer")
    m.saveTimer.observeField("fire", "onSaveTimer")
    m.chapterFlashTimer = m.top.findNode("chapterFlashTimer")
    m.chapterFlashTimer.observeField("fire", "onChapterFlashTimer")
    m.popupTimer = m.top.findNode("popupTimer")
    m.popupTimer.observeField("fire", "onPopupTimer")
    m.qrTimer = m.top.findNode("qrTimer")
    m.qrTimer.observeField("fire", "onQrTimer")

    ' Video state.
    m.video.notificationInterval = 1
    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onPosition")
    m.video.observeField("duration", "onDuration")

    ' Playback / chrome state.
    m.payload = invalid
    m.loadStarted = false
    m.duration = 0
    m.position = 0
    m.resumed = false
    m.isPlaying = false
    m.completeSaved = false
    m.lastSavedSecond = -1

    m.controlsVisible = false
    m.zone = "pills"        ' icons | scrub | pills
    m.iconIdx = 0
    m.pillIdx = 1
    m.captionsOn = false
    m.overlay = "none"      ' none | chapters (settings/qr/detail land in later passes)

    m.chapters = []
    m.chapSel = 0
    m.chapScrollY = 0
    m.chapRows = []         ' [{ group, bg }]

    m.markers = []          ' merged annotations + notes, sorted by time
    m.markerIdx = 0
    m.markerInit = false    ' seed-to-playhead only once per video
    m.markerChips = []      ' [{ group, border, bg, x, w }]
    m.markerStripW = 0
    m.MARKER_W = 1620       ' visible strip width (matches scrub)

    ' Detail / image / text overlay state.
    m.activeMarker = invalid
    m.detailFocusKey = "close"
    m.detailFocusList = []
    m.detailBtns = {}       ' focusKey -> { bg, glyph?, label? }
    m.viewerIndex = 0
    m.readerScrollY = 0
    m.readerMax = 0
    m.wasPlaying = false
    m.prevPos = 0           ' playhead at previous tick (popup crossing detect)
    m.pendingQr = invalid   ' deferred detail-card QR build
    m.DETAIL_CLAMP = 280

    m.iconKeys = []
    m.pillKeys = []
    m.iconBtns = []         ' [{ key, bg, glyph, tip }]
    m.pillBtns = []         ' [{ bg, glyph, label }]
    m.seekHold = invalid
    m.clock = CreateObject("roTimespan")   ' monotonic ms for hold-to-seek

    m.top.setFocus(true)
end sub

' videoId is set by MainScene after node creation; load is triggered here.
sub onVideoIdSet()
    if m.top.videoId = invalid or m.top.videoId = "" then return
    if m.loadStarted then return
    m.loadStarted = true
    loadData()
end sub

' ── Data load (GET /videos/:id/stream-url) ──────────────────────────────
sub loadData()
    m.loading.visible = true
    m.errorLabel.visible = false
    m.task = CreateObject("roSGNode", "ApiTask")
    m.task.observeField("response", "onStreamResponse")
    m.task.request = ApiReq().streamUrl(m.top.videoId)
    m.task.control = "RUN"
end sub

sub onStreamResponse()
    res = m.task.response
    if res <> invalid and res.status = 401 then
        m.top.signedOut = true
        return
    end if
    if res = invalid or res.ok <> true or res.data = invalid then
        showError("Could not load this video. Check your connection.")
        return
    end if

    data = res.data
    m.payload = data
    m.chapters = arr(data.chapters)
    hls = nz(data.hls_url)
    if hls = "" then
        showError("This video is unavailable (no stream URL).")
        return
    end if

    ' Seed scrub display to the resume position right away (§9.2) so the bar
    ' doesn't sit at 0 until the first post-seek position fires.
    seed = 0
    durSec = numOr(data.duration_seconds, 0)
    progSec = numOr(data.progress_seconds, 0)
    if progSec > 0 and durSec > 0 and progSec < durSec * m.WATCHED then seed = progSec
    m.position = seed
    if durSec > 0 then m.duration = durSec

    titles()
    buildIconRow()
    buildPills()
    renderScrub()

    ' Markers strip: annotations now (from the payload), notes async (§9.6).
    m.markers = buildMarkers(arr(data.annotations), [])
    buildMarkerStrip()
    loadNotes()

    ' Build + attach the HLS content.
    content = CreateObject("roSGNode", "ContentNode")
    content.url = hls
    content.streamFormat = "hls"
    content.title = nz(data.title)
    cap = nz(data.captions_url)
    if cap <> "" then content.SubtitleUrl = cap
    m.video.content = content
    m.video.control = "play"
end sub

sub showError(msg as string)
    m.loading.visible = false
    m.errorLabel.text = msg
    m.errorLabel.visible = true
end sub

' ── Titles + pause-overlay brand ────────────────────────────────────────
sub titles()
    d = m.payload
    m.eventTitle.text = nz(d.event_title)
    m.videoTitle.text = nz(d.title)

    wm = nz(d.wordmark_url)
    if wm <> "" then
        ' Mid-left (Netflix-style), clear of the lower-left chrome titles. §9.10
        m.pauseWordmark.width = 640 : m.pauseWordmark.height = 240
        m.pauseWordmark.translation = [150, 330]
        m.pauseWordmark.uri = SizedImageH(wm, 240)
    else
        m.pauseTitle.text = nz(d.event_title)
        if m.pauseTitle.text = "" then m.pauseTitle.text = nz(d.title)
    end if
end sub

' ── Icon row: round buttons anchored top-right, focus-only tooltip beneath.
' Add Note · Chapters (if chapters) · CC (if captions) · Settings. §9.3
sub buildIconRow()
    m.iconRow.removeChildren(m.iconRow.getChildren(-1, 0))
    m.iconKeys = ["addnote"]
    if m.chapters.Count() > 0 then m.iconKeys.push("chapters")
    if nz(m.payload.captions_url) <> "" then m.iconKeys.push("cc")
    m.iconKeys.push("settings")

    btnSize = 64
    gap = 22
    n = m.iconKeys.Count()
    totalW = n * btnSize + (n - 1) * gap
    startX = 1770 - totalW
    topY = 60

    m.iconBtns = []
    i = 0
    for each k in m.iconKeys
        x = startX + i * (btnSize + gap)
        g = CreateObject("roSGNode", "Group")
        g.translation = [x, topY]
        ' Circular button (white avatar_circle baked asset). Transparency is via
        ' Poster.opacity (Roku ignores blendColor alpha), tint via blendColor.
        bg = CreateObject("roSGNode", "Poster")
        bg.width = btnSize : bg.height = btnSize
        bg.uri = "pkg:/images/avatar_circle.png"
        bg.blendColor = "0x0A1018FF"
        bg.opacity = 0.5
        g.appendChild(bg)
        ic = "ic_note.png"
        label = "Add note"
        if k = "chapters" then ic = "ic_chapters.png" : label = "Chapters"
        if k = "cc" then ic = "ic_cc.png" : label = "Subtitles"
        if k = "settings" then ic = "ic_settings.png" : label = "Settings"
        gl = glyph(ic, 34, [15, 15], "0xFFFFFFFF")
        g.appendChild(gl)
        tip = makeLabel(label, "SemiBold", 18, "0xE7ECF2FF", 160, 1)
        tip.translation = [Int((btnSize - 160) / 2), btnSize + 8]
        tip.horizAlign = "center"
        tip.opacity = 0
        g.appendChild(tip)
        m.iconRow.appendChild(g)
        m.iconBtns.push({ key: k, bg: bg, glyph: gl, tip: tip })
        i = i + 1
    end for
end sub

' ── Playback pills (Restart · Play/Pause · Next) ────────────────────────
sub buildPills()
    m.pills.removeChildren(m.pills.getChildren(-1, 0))
    m.pillKeys = ["restart", "playpause"]
    if m.payload.next_video <> invalid then m.pillKeys.push("next")

    m.pillBtns = []
    totalW = 0
    for each k in m.pillKeys
        label = "Restart"
        ic = "ic_restart.png"
        if k = "playpause" then
            label = "Pause" : ic = "ic_pause.png"
        else if k = "next" then
            label = "Next video" : ic = "ic_next.png"
        end if
        g = CreateObject("roSGNode", "Group")
        w = labelPillWidth(label)
        bg = roundedBg(w, 64, "0xFFFFFF26")
        g.appendChild(bg)
        gl = glyph(ic, 28, [24, 18], "0xFFFFFFFF")
        g.appendChild(gl)
        lb = makeLabel(label, "Bold", 24, "0xFFFFFFFF", w - 84, 1)
        lb.translation = [64, 0] : lb.height = 64 : lb.vertAlign = "center"
        g.appendChild(lb)
        m.pills.appendChild(g)
        m.pillBtns.push({ bg: bg, glyph: gl, label: lb })
        totalW = totalW + w
    end for
    ' Center the row horizontally (itemSpacings=20 between pills). §9.3
    totalW = totalW + (m.pillKeys.Count() - 1) * 20
    m.pills.translation = [Int((1920 - totalW) / 2), 980]
end sub

' Pill width: room for the glyph (≈64px lead) + the bold 24px label.
function labelPillWidth(label as string) as integer
    return 96 + Len(label) * 15
end function

' ── Video node events ───────────────────────────────────────────────────
sub onVideoState()
    st = m.video.state
    if st = "playing" then
        m.loading.visible = false
        ' A chip seek auto-resumes a paused video on Roku; if a pausing overlay
        ' (detail/image/text) is open, re-pause immediately so it never plays
        ' behind the card. §9.8
        if overlayPausing() then
            m.video.control = "pause"
            return
        end if
        m.isPlaying = true
        ' Resume seek on the first playable transition (§9.2).
        if not m.resumed then
            m.resumed = true
            progSec = numOr(m.payload.progress_seconds, 0)
            if progSec > 0 and m.duration > 0 and progSec < m.duration * m.WATCHED then
                m.video.seek = progSec
            end if
            ' NOTE: Roku has no public arbitrary VOD playback-rate API, so the
            ' saved default playback speed (§10.1) cannot be applied here. This
            ' is a Roku platform gap vs Android/Tizen/tvOS.
        end if
        m.saveTimer.control = "start"
        applyPlayState()
    else if st = "paused" then
        m.isPlaying = false
        applyPlayState()
    else if st = "buffering" then
        m.loading.visible = true
    else if st = "finished" then
        m.isPlaying = false
        markComplete()
        ' Phase 1: no autoplay/Up-Next yet → leave the player.
        pop()
    else if st = "error" then
        showError("Playback error. Please go back and try again.")
    end if
end sub

sub onDuration()
    if m.video.duration > 0 then
        m.duration = m.video.duration
        renderScrub()
    end if
end sub

sub onPosition()
    m.position = m.video.position
    renderScrub()
    maybePopup(m.position)

    ' Progress save at 95% (once), deduped by whole second elsewhere (§9.13).
    if m.duration > 0 and not m.completeSaved and m.position >= m.duration * m.WATCHED then
        m.completeSaved = true
        markComplete()
    end if
end sub

' ── Scrub render ────────────────────────────────────────────────────────
sub renderScrub()
    total = m.duration
    if total <= 0 then total = numOr(m.payload.duration_seconds, 0)
    posSec = m.position
    if posSec < 0 then posSec = 0
    if total > 0 and posSec > total then posSec = total

    trackW = 1620
    frac = 0.0
    if total > 0 then frac = posSec / total
    if frac < 0 then frac = 0
    if frac > 1 then frac = 1
    playedW = Int(trackW * frac)
    m.scrubPlayed.width = playedW
    m.scrubKnob.translation = [playedW - 11, m.scrubKnob.translation[1]]

    m.timeElapsed.text = fmt(posSec)
    remain = total - posSec
    if remain < 0 then remain = 0
    m.timeRemaining.text = "-" + fmt(remain)
end sub

' ── Progress save ───────────────────────────────────────────────────────
sub saveProgress(seconds as integer)
    if seconds < 1 then return
    if seconds = m.lastSavedSecond then return
    m.lastSavedSecond = seconds
    t = CreateObject("roSGNode", "ApiTask")
    t.request = ApiReq().saveProgress(m.top.videoId, seconds)
    t.control = "RUN"
    m.saveTask = t
end sub

sub markComplete()
    ' Write full duration so the video leaves Continue Watching (§9.13).
    if m.duration > 0 then saveProgress(Int(m.duration))
end sub

sub onSaveTimer()
    if m.isPlaying then saveProgress(Int(m.position))
end sub

' ── Play / pause ────────────────────────────────────────────────────────
sub togglePlay()
    if m.video.state = "playing" then
        m.video.control = "pause"
        doFlash("ic_pause.png")
    else
        m.video.control = "resume"
        doFlash("ic_play.png")
    end if
end sub

sub applyPlayState()
    ' Pills play/pause glyph + label.
    for i = 0 to m.pillKeys.Count() - 1
        if m.pillKeys[i] = "playpause" then
            b = m.pillBtns[i]
            if m.isPlaying then
                b.glyph.uri = "pkg:/images/icons/ic_pause.png" : b.label.text = "Pause"
            else
                b.glyph.uri = "pkg:/images/icons/ic_play.png" : b.label.text = "Play"
            end if
        end if
    end for
    ' Pause overlay: shown only while paused with chrome up.
    updatePauseOverlay()
    if m.isPlaying then
        armHide()
    else
        clearHide()
    end if
end sub

sub updatePauseOverlay()
    show = (m.controlsVisible and not m.isPlaying and m.overlay = "none")
    m.pauseScrim.visible = show
    if show and nz(m.payload.wordmark_url) <> "" then
        m.pauseWordmark.visible = true : m.pauseTitle.visible = false
    else if show then
        m.pauseTitle.visible = true : m.pauseWordmark.visible = false
    else
        m.pauseWordmark.visible = false : m.pauseTitle.visible = false
    end if
end sub

sub doFlash(icon as string)
    m.flash.uri = "pkg:/images/icons/" + icon
    m.flash.visible = true
    m.flashTimer.control = "stop"
    m.flashTimer.control = "start"
end sub

sub onFlashTimer()
    m.flash.visible = false
end sub

' ── Chrome show / hide ──────────────────────────────────────────────────
sub showControls(zone as string)
    if zone <> "" then m.zone = zone
    if not m.controlsVisible then
        m.controlsVisible = true
        m.fadeOut.control = "stop"
        m.fadeIn.control = "start"
    end if
    styleZones()
    ' Keep the strip forwarded to the playhead chip while it isn't focused.
    ' Instant here (the strip was hidden, so a slide would look wrong). §9.6
    if m.markers.Count() > 0 and m.zone <> "markers" then
        styleMarkers()
        centerMarker(nearestMarkerIndex(m.markers, m.position), true)
    end if
    updatePauseOverlay()
    armHide()
end sub

sub hideControls()
    if not m.controlsVisible then return
    m.controlsVisible = false
    m.fadeIn.control = "stop"
    m.fadeOut.control = "start"
    clearHide()
    updatePauseOverlay()
end sub

sub armHide()
    clearHide()
    ' Auto-hide only while playing and no modal (§9.3). Paused chrome stays.
    if m.isPlaying and m.controlsVisible then
        m.hideTimer.control = "start"
    end if
end sub

sub clearHide()
    m.hideTimer.control = "stop"
end sub

sub onHideTimer()
    if m.isPlaying then hideControls()
end sub

' ── Focus styling ───────────────────────────────────────────────────────
sub styleZones()
    styleIcons()
    for i = 0 to m.pillBtns.Count() - 1
        styleBtn(m.pillBtns[i].bg, m.pillBtns[i].glyph, m.pillBtns[i].label, (m.zone = "pills" and m.pillIdx = i))
    end for
    styleScrub(m.zone = "scrub")
end sub

' Icons: focus = subtle white-wash circle, glyph stays white (no gold fill);
' tooltip shows only on focus; CC glyph goes gold when captions are on. §9.3
sub styleIcons()
    for i = 0 to m.iconBtns.Count() - 1
        b = m.iconBtns[i]
        focused = (m.zone = "icons" and m.iconIdx = i)
        if focused then
            ' Brighter white wash on focus (Tizen ~18% white).
            b.bg.blendColor = "0xFFFFFFFF"
            b.bg.opacity = 0.32
            b.tip.opacity = 1
        else
            ' Constant dark translucent circle so white glyphs read on any frame.
            b.bg.blendColor = "0x0A1018FF"
            b.bg.opacity = 0.5
            b.tip.opacity = 0
        end if
        if b.key = "cc" and m.captionsOn then
            b.glyph.blendColor = "0xC9A84CFF"
        else
            b.glyph.blendColor = "0xFFFFFFFF"
        end if
    end for
end sub

sub styleBtn(bg as object, ic as object, label as object, focused as boolean)
    if bg = invalid then return
    if focused then
        bg.blendColor = "0xC9A84CFF"
        if ic <> invalid then ic.blendColor = "0x0F1923FF"
        if label <> invalid then label.color = "0x0F1923FF"
    else
        bg.blendColor = "0xFFFFFF26"
        if ic <> invalid then ic.blendColor = "0xFFFFFFFF"
        if label <> invalid then label.color = "0xFFFFFFFF"
    end if
end sub

sub styleScrub(focused as boolean)
    if focused then
        m.scrubTrack.height = 14 : m.scrubPlayed.height = 14
        m.scrubTrack.translation = [0, -4] : m.scrubPlayed.translation = [0, -4]
        m.scrubKnob.visible = true
        m.scrubPlayed.color = "0xE0C25EFF"
    else
        m.scrubTrack.height = 6 : m.scrubPlayed.height = 6
        m.scrubTrack.translation = [0, 0] : m.scrubPlayed.translation = [0, 0]
        m.scrubKnob.visible = false
        m.scrubPlayed.color = "0xC9A84CFF"
    end if
end sub

' ── Seeking (single-tap 10s + hold-to-seek tiers) §9.4/§9.5 ─────────────
sub seekBy(delta as integer)
    if m.duration <= 0 then return
    target = m.position + delta
    if target < 0 then target = 0
    if target > m.duration then target = m.duration
    m.video.seek = target
    m.position = target
    renderScrub()
end sub

sub onSeekKey(dir as integer)
    nowMs = nowMillis()
    tier = 1
    if m.seekHold <> invalid and m.seekHold.dir = dir then
        tier = tierForHold(nowMs - m.seekHold.start)
    else
        m.seekHold = { dir: dir, start: nowMs }
    end if
    seekBy(dir * m.SEEK_STEP * tier)
    if tier >= 2 then showSeekIndicator(tier, dir)
    if m.controlsVisible then
        showControls("scrub")
    end if
end sub

function tierForHold(elapsedMs as integer) as integer
    tier = 1
    for i = 0 to m.SEEK_TIERS.Count() - 1
        if elapsedMs >= m.SEEK_TIERS[i] then tier = i + 2
    end for
    return tier
end function

sub showSeekIndicator(tier as integer, dir as integer)
    if dir < 0 then
        m.seekChevron.uri = "pkg:/images/icons/ic_chevron_left.png"
    else
        m.seekChevron.uri = "pkg:/images/icons/ic_chevron_right.png"
    end if
    m.seekRate.text = tier.ToStr() + "x"
    m.seekIndicator.visible = true
    m.indicatorTimer.control = "stop"
    m.indicatorTimer.control = "start"
end sub

sub onIndicatorTimer()
    m.seekIndicator.visible = false
end sub

' ── Activate ────────────────────────────────────────────────────────────
sub activateIcon()
    k = m.iconKeys[m.iconIdx]
    if k = "cc" then
        toggleCaptions()
        armHide()
    else if k = "chapters" then
        openChapters()
    end if
    ' addnote / settings wired in a later pass.
end sub

sub activatePill()
    k = m.pillKeys[m.pillIdx]
    if k = "restart" then
        m.video.seek = 0
        m.position = 0
        m.completeSaved = false
        if m.video.state <> "playing" then m.video.control = "resume"
        showControls("pills")
    else if k = "playpause" then
        togglePlay()
        armHide()
    else if k = "next" then
        ' Phase 1: no in-place swap yet → leave for the later autoplay pass.
        armHide()
    end if
end sub

sub toggleCaptions()
    m.captionsOn = not m.captionsOn
    if m.captionsOn then
        m.video.globalCaptionMode = "On"
    else
        m.video.globalCaptionMode = "Off"
    end if
    styleIcons()
end sub

' ── Notes & Annotations strip (§9.6) ────────────────────────────────────
sub loadNotes()
    m.notesTask = CreateObject("roSGNode", "ApiTask")
    m.notesTask.observeField("response", "onNotesResponse")
    m.notesTask.request = ApiReq().listNotes(m.top.videoId)
    m.notesTask.control = "RUN"
end sub

sub onNotesResponse()
    res = m.notesTask.response
    notes = []
    if res <> invalid and res.ok = true and res.data <> invalid then notes = arr(res.data.notes)
    m.markers = buildMarkers(arr(m.payload.annotations), notes)
    buildMarkerStrip()
    ' Keep the strip forwarded to the playhead chip until the user enters it.
    if m.zone <> "markers" then centerMarker(nearestMarkerIndex(m.markers, m.position), true)
end sub

' Merge annotations (gold) + notes (blue) into one time-sorted list. Port of
' Tizen markers.js buildMarkers.
function buildMarkers(annotations as object, notes as object) as object
    out = []
    for each a in annotations
        imgs = []
        if nz(a.image_url) <> "" then imgs.push(a.image_url)
        if GetInterface(a.images, "ifArray") <> invalid
            for each u in a.images
                if nz(u) <> "" then imgs.push(u)
            end for
        end if
        for each src in allImages(nz(a.body))
            imgs.push(src)
        end for
        out.push({
            key: "a" + toStr(a.id), type: "annotation",
            id: toStr(a.id), startsAt: Int(numOr(a.starts_at_seconds, 0)),
            title: nz(a.title), body: nz(a.body), bodyText: stripHtmlLine(nz(a.body)),
            images: imgs, isPrivate: false
        })
    end for
    for each n in notes
        out.push({
            key: "n" + toStr(n.id), type: "note",
            id: toStr(n.id), startsAt: Int(numOr(n.seconds, 0)),
            title: nz(n.title), body: nz(n.body), bodyText: stripHtmlLine(nz(n.body)),
            images: allImages(nz(n.body)), isPrivate: true
        })
    end for
    ' Insertion sort by startsAt (lists are short).
    for i = 1 to out.Count() - 1
        j = i
        while j > 0 and out[j].startsAt < out[j - 1].startsAt
            tmp = out[j] : out[j] = out[j - 1] : out[j - 1] = tmp
            j = j - 1
        end while
    end for
    return out
end function

function nearestMarkerIndex(markers as object, t as integer) as integer
    if markers.Count() = 0 then return -1
    best = 0 : bestDist = 2147483647
    for i = 0 to markers.Count() - 1
        d = Abs(markers[i].startsAt - t)
        if d < bestDist then bestDist = d : best = i
    end for
    return best
end function

sub buildMarkerStrip()
    m.markersRow.removeChildren(m.markersRow.getChildren(-1, 0))
    m.markerChips = []
    m.markersClip.visible = (m.markers.Count() > 0)
    if m.markers.Count() = 0 then return

    chipH = 76
    gap = 14
    x = 0
    for i = 0 to m.markers.Count() - 1
        mk = m.markers[i]
        title = mk.title
        if title = "" then
            if mk.type = "note" then title = "Note" else title = "Annotation"
        end if
        ' Content-fit width, capped (uniform height). §9.6
        titleW = Len(title) * 13
        bodyW = Len(mk.bodyText) * 11
        contentW = titleW
        if bodyW > contentW then contentW = bodyW
        chipW = 132 + contentW + 18
        if chipW < 280 then chipW = 280
        if chipW > 460 then chipW = 460

        chip = CreateObject("roSGNode", "Group")
        chip.translation = [x, 0]

        border = roundedBg(chipW, chipH, "0xC9A84CFF")
        border.visible = false
        chip.appendChild(border)
        bg = roundedBg(chipW - 4, chipH - 4, "0x14202EE6")
        bg.translation = [2, 2]
        chip.appendChild(bg)

        ' Vertically center the content block (1 line without a body, 2 with). §9.6
        hasBody = (mk.bodyText <> "")
        rowH = 30
        bodyH = 26
        if hasBody then
            blockH = rowH + 4 + bodyH
            rowY = Int((chipH - blockH) / 2)
            bodyY = rowY + rowH + 4
        else
            rowY = Int((chipH - rowH) / 2)
            bodyY = 0
        end if

        dotColor = "0xC9A84CFF"
        if mk.type = "note" then dotColor = "0x53B7E8FF"
        dot = CreateObject("roSGNode", "Poster")
        dot.width = 14 : dot.height = 14
        dot.uri = "pkg:/images/avatar_circle.png"
        dot.blendColor = dotColor
        dot.translation = [20, rowY + Int((rowH - 14) / 2)]
        chip.appendChild(dot)

        tc = makeLabel(fmt(mk.startsAt), "Bold", 21, "0xCFD8E3FF", 80, 1)
        tc.translation = [42, rowY] : tc.height = rowH : tc.vertAlign = "center"
        chip.appendChild(tc)
        ti = makeLabel(title, "Bold", 23, "0xFFFFFFFF", chipW - 132 - 8, 1)
        ti.translation = [126, rowY] : ti.height = rowH : ti.vertAlign = "center"
        chip.appendChild(ti)
        if hasBody then
            bd = makeLabel(mk.bodyText, "Regular", 20, "0x9FB0C0FF", chipW - 40, 1)
            bd.translation = [20, bodyY] : bd.height = bodyH : bd.vertAlign = "center"
            chip.appendChild(bd)
        end if

        m.markersRow.appendChild(chip)
        m.markerChips.push({ group: chip, border: border, bg: bg, x: x, w: chipW })
        x = x + chipW + gap
    end for
    m.markerStripW = x - gap
    styleMarkers()
end sub

sub styleMarkers()
    for i = 0 to m.markerChips.Count() - 1
        c = m.markerChips[i]
        focused = (m.zone = "markers" and m.markerIdx = i)
        c.border.visible = focused
        if focused then
            c.bg.blendColor = "0x223044F2"
        else
            c.bg.blendColor = "0x14202EE6"
        end if
    end for
end sub

' Center the strip on a chip index within the 1620px clip window. Animated by
' default (smooth, no snap); instant=true for off-screen seeding on chrome open.
sub centerMarker(idx as integer, instant = false as boolean)
    if idx < 0 or idx >= m.markerChips.Count() then return
    c = m.markerChips[idx]
    target = c.x - Int(m.MARKER_W / 2) + Int(c.w / 2)
    maxScroll = m.markerStripW - m.MARKER_W
    if maxScroll < 0 then maxScroll = 0
    if target < 0 then target = 0
    if target > maxScroll then target = maxScroll

    fromXY = m.markersRow.translation
    toXY = [-target, 0]
    if instant or (fromXY[0] = toXY[0]) then
        m.markersScrollAnim.control = "stop"
        m.markersRow.translation = toXY
        return
    end if
    m.markersScrollInterp.keyValue = [fromXY, toXY]
    m.markersScrollAnim.control = "stop"
    m.markersScrollAnim.control = "start"
end sub

sub enterMarkers()
    if m.markers.Count() = 0 then return
    if not m.markerInit then
        idx = nearestMarkerIndex(m.markers, m.position)
        if idx >= 0 then m.markerIdx = idx
        m.markerInit = true
    end if
    m.zone = "markers"
    styleMarkers()
    centerMarker(m.markerIdx)
    ' Icons/scrub also restyle (drop their focus).
    styleIcons()
    styleScrub(false)
end sub

function handleMarkerKeys(key as string) as boolean
    if key = "left" then
        if m.markerIdx > 0 then m.markerIdx = m.markerIdx - 1 : styleMarkers() : centerMarker(m.markerIdx)
        return true
    end if
    if key = "right" then
        if m.markerIdx < m.markers.Count() - 1 then m.markerIdx = m.markerIdx + 1 : styleMarkers() : centerMarker(m.markerIdx)
        return true
    end if
    if key = "up" then m.zone = "icons" : styleMarkers() : styleZones() : return true
    if key = "down" then m.zone = "scrub" : styleMarkers() : styleZones() : return true
    if key = "OK" then
        ' Open the detail card WITHOUT seeking. Jumping to the timecode is an
        ' explicit action on the card's focusable timecode button (§9.8) — an
        ' auto-seek here feels like the video "snaps back" a second.
        mk = m.markers[m.markerIdx]
        if mk <> invalid then openDetail(mk)
        return true
    end if
    return true
end function

' ════════════════════════════════════════════════════════════════════════
'  Marker detail card (§9.8) — centered modal, pauses video.
' ════════════════════════════════════════════════════════════════════════
sub openDetail(mk as object)
    if mk = invalid then return
    m.activeMarker = mk
    ' Capture the real play-state BEFORE the seek (a chip seek auto-resumes a
    ' paused video on Roku). The detail card always pauses while open (§9.8);
    ' on close we restore this state.
    m.wasPlaying = m.isPlaying
    m.overlay = "detail"
    m.video.control = "pause"
    buildDetail(mk)
    m.detailModal.visible = true
    updatePauseOverlay()
    clearHide()
    ' Build the QR one tick later: the QRCode encodes synchronously on the
    ' render thread, so doing it inline would block the card from drawing for
    ' ~1s. Showing the card first then filling the QR feels instant.
    if m.pendingQr <> invalid then m.qrTimer.control = "start"
end sub

' Overlays that force the video to stay paused while open.
function overlayPausing() as boolean
    return (m.overlay = "detail" or m.overlay = "image" or m.overlay = "text")
end function

sub buildDetail(mk as object)
    m.detailPanel.removeChildren(m.detailPanel.getChildren(-1, 0))
    m.detailBtns = {}
    m.detailFocusList = []

    panelW = 1180 : panelH = 820
    px = Int((1920 - panelW) / 2) : py = Int((1080 - panelH) / 2)
    m.detailPanel.translation = [px, py]
    isNote = (mk.type = "note")
    accent = "0xC9A84CFF"
    if isNote then accent = "0x4C8CC9FF"

    bg = CreateObject("roSGNode", "Rectangle")
    bg.width = panelW : bg.height = panelH : bg.color = "0x10171FFF"
    m.detailPanel.appendChild(bg)
    bar = CreateObject("roSGNode", "Rectangle")
    bar.width = 8 : bar.height = panelH : bar.color = accent
    m.detailPanel.appendChild(bar)

    pad = 56
    ' Header: focusable timecode "Go to HH:MM" button + PRIVATE badge.
    timeBtn = makeActionPillIcon("Go to " + fmt(mk.startsAt), "ic_play.png", pad, 38, 264)
    timeBtn.accent = accent
    m.detailPanel.appendChild(timeBtn.group)
    m.detailBtns["time"] = timeBtn
    m.detailFocusList.push("time")
    if isNote then
        pv = makeLabel("PRIVATE", "SemiBold", 18, "0x9FB0C0FF", 160, 1)
        pv.translation = [pad + 280, 52]
        m.detailPanel.appendChild(pv)
    end if

    ' Action pills (top-right): Delete (notes), Close. Edit arrives with the
    ' QR companion in a later pass.
    rightX = panelW - pad
    closeBtn = makeActionPill("Close", rightX - 150, 40, 150)
    m.detailPanel.appendChild(closeBtn.group)
    m.detailBtns["close"] = closeBtn
    if isNote then
        delBtn = makeActionPill("Delete", rightX - 150 - 16 - 150, 40, 150)
        m.detailPanel.appendChild(delBtn.group)
        m.detailBtns["delete"] = delBtn
    end if

    ' Title.
    ttl = makeLabel(nz2(mk.title, defaultTitle(mk)), "Bold", 40, "0xFFFFFFFF", panelW - pad * 2, 2)
    ttl.translation = [pad, 108]
    m.detailPanel.appendChild(ttl)
    dv = CreateObject("roSGNode", "Rectangle")
    dv.width = panelW - pad * 2 : dv.height = 2 : dv.color = "0x2A3848FF"
    dv.translation = [pad, 220]
    m.detailPanel.appendChild(dv)

    ' Single left-aligned column: image(s) → body → read-more → QR.
    contentY = 256
    bodyW = panelW - pad * 2
    images = mk.images
    if images = invalid then images = []
    full = htmlMultiline(mk.body)
    truncated = (Len(full) > m.DETAIL_CLAMP)
    link = firstLink(mk.body)

    ' Presentation decided by COUNT (§9.8): exactly 1 image → large + centered;
    ' 2+ → thumbnail strip. Both are focusable → open the viewer on OK.
    heroImage = (images.Count() = 1)

    ' "Press OK to enlarge" hint ABOVE the image(s) (both single + strip).
    if images.Count() > 0 then
        hint = makeLabel("Press OK to enlarge", "Regular", 20, "0x8C9EB0FF", panelW - pad * 2, 1)
        if heroImage then
            hint.horizAlign = "center"
        else
            hint.horizAlign = "left"
        end if
        hint.translation = [pad, contentY]
        m.detailPanel.appendChild(hint)
        contentY = contentY + 32
    end if

    if heroImage then
        ' Bounded so the card still fits: bigger when the image is the only
        ' content, smaller when body/link share the card.
        if full = "" and link = "" then
            heroW = 880 : heroH = 495
        else
            heroW = 560 : heroH = 315
        end if
        hx = Int((panelW - heroW) / 2)
        grp = CreateObject("roSGNode", "Group")
        grp.translation = [hx, contentY]
        brd = CreateObject("roSGNode", "Rectangle")
        brd.width = heroW : brd.height = heroH : brd.color = "0x00000000"
        grp.appendChild(brd)
        img = CreateObject("roSGNode", "Poster")
        img.width = heroW - 8 : img.height = heroH - 8 : img.translation = [4, 4]
        img.loadDisplayMode = "scaleToFit" : img.uri = images[0]
        grp.appendChild(img)
        m.detailPanel.appendChild(grp)
        m.detailBtns["thumb0"] = { group: grp, bg: brd, isThumb: true }
        m.detailFocusList.push("thumb0")
        contentY = contentY + heroH + 24
    else if images.Count() > 0 then
        ' Thumbnail strip.
        thumbW = 220 : thumbH = 132 : gap = 20
        n = images.Count()
        if n > 5 then n = 5
        for i = 0 to n - 1
            grp = CreateObject("roSGNode", "Group")
            grp.translation = [pad + i * (thumbW + gap), contentY]
            brd = CreateObject("roSGNode", "Rectangle")
            brd.width = thumbW : brd.height = thumbH : brd.color = "0x00000000"
            grp.appendChild(brd)
            img = CreateObject("roSGNode", "Poster")
            img.width = thumbW - 8 : img.height = thumbH - 8 : img.translation = [4, 4]
            img.loadDisplayMode = "scaleToZoom" : img.uri = images[i]
            grp.appendChild(img)
            m.detailPanel.appendChild(grp)
            key = "thumb" + Stri(i).Trim()
            m.detailBtns[key] = { group: grp, bg: brd, isThumb: true }
            m.detailFocusList.push(key)
        end for
        contentY = contentY + thumbH + 28
    end if

    ' Body (clamped).
    shown = full
    if truncated then shown = Left(full, m.DETAIL_CLAMP) + "…"
    if shown <> "" then
        bd = makeLabel(shown, "Regular", 26, "0xE6ECF2FF", bodyW, 6)
        bd.lineSpacing = 8
        bd.translation = [pad, contentY]
        m.detailPanel.appendChild(bd)
        contentY = contentY + 220
    end if

    ' Read-more (focusable) before the QR.
    if truncated then
        m.detailBtns["readmore"] = makeActionPill("Press OK to read", pad, contentY, 320)
        m.detailPanel.appendChild(m.detailBtns["readmore"].group)
        m.detailFocusList.push("readmore")
        m.readerFull = full
        m.readerTitleText = nz2(mk.title, defaultTitle(mk))
        contentY = contentY + 84
    end if

    ' Link QR, left-aligned with the URL beneath it. Built deferred (see
    ' openDetail) so the QR encode doesn't block the card from showing.
    m.pendingQr = invalid
    if link <> "" then
        qrSize = 300
        maxY = panelH - pad - qrSize - 64
        qy = contentY
        if qy > maxY then qy = maxY
        cardN = CreateObject("roSGNode", "Rectangle")
        cardN.width = qrSize : cardN.height = qrSize : cardN.color = "0xFFFFFFFF"
        cardN.translation = [pad, qy]
        m.detailPanel.appendChild(cardN)
        ' Show the actual URL under the QR so viewers know what they're scanning.
        urlLbl = makeLabel(link, "SemiBold", 22, "0x9FB0C0FF", qrSize, 2)
        urlLbl.translation = [pad, qy + qrSize + 12]
        m.detailPanel.appendChild(urlLbl)
        m.pendingQr = { link: link, x: pad + 12, y: qy + 12, size: qrSize - 24 }
    end if

    if isNote then m.detailFocusList.push("delete")
    m.detailFocusList.push("close")

    ' Land focus on the timecode so a single OK jumps to the marker.
    m.detailFocusKey = "time"
    styleDetail()
end sub

sub onQrTimer()
    if m.pendingQr = invalid then return
    if m.overlay <> "detail" then m.pendingQr = invalid : return
    p = m.pendingQr
    q = makeQrNode(p.link, p.size)
    q.translation = [p.x, p.y]
    m.detailPanel.appendChild(q)
    m.pendingQr = invalid
end sub

function makeActionPill(label as string, x as integer, y as integer, w as integer) as object
    grp = CreateObject("roSGNode", "Group")
    grp.translation = [x, y]
    bg = roundedBg(w, 56, "0x1B2A3AFF")
    grp.appendChild(bg)
    lbl = makeLabel(label, "SemiBold", 24, "0xFFFFFFFF", w, 1)
    lbl.horizAlign = "center" : lbl.height = 56 : lbl.vertAlign = "center"
    grp.appendChild(lbl)
    return { group: grp, bg: bg, label: lbl }
end function

' Action pill with a leading raster glyph (e.g. the play icon on "Go to …").
function makeActionPillIcon(label as string, icon as string, x as integer, y as integer, w as integer) as object
    grp = CreateObject("roSGNode", "Group")
    grp.translation = [x, y]
    bg = roundedBg(w, 56, "0x1B2A3AFF")
    grp.appendChild(bg)
    g = glyph(icon, 24, [24, 16], "0xFFFFFFFF")
    grp.appendChild(g)
    lbl = makeLabel(label, "SemiBold", 24, "0xFFFFFFFF", w - 64, 1)
    lbl.translation = [60, 0] : lbl.height = 56 : lbl.vertAlign = "center"
    grp.appendChild(lbl)
    return { group: grp, bg: bg, label: lbl, glyph: g }
end function

sub styleDetail()
    for each key in m.detailBtns
        b = m.detailBtns[key]
        focused = (key = m.detailFocusKey)
        isThumb = (b.isThumb <> invalid and b.isThumb)
        if isThumb then
            b.bg.color = "0x00000000"
            if focused then b.bg.color = "0xC9A84CFF"
        else
            rest = "0xFFFFFFFF"
            if b.accent <> invalid then rest = b.accent
            if focused then
                b.bg.blendColor = "0xC9A84CFF" : b.label.color = "0x0A1018FF"
                if b.glyph <> invalid then b.glyph.blendColor = "0x0A1018FF"
            else
                b.bg.blendColor = "0x1B2A3AFF" : b.label.color = rest
                if b.glyph <> invalid then b.glyph.blendColor = rest
            end if
        end if
    end for
end sub

function detailFocusPos() as integer
    for i = 0 to m.detailFocusList.Count() - 1
        if m.detailFocusList[i] = m.detailFocusKey then return i
    end for
    return 0
end function

function handleDetailKeys(key as string) as boolean
    if key = "back" then closeDetail() : return true
    n = m.detailFocusList.Count()
    if n = 0 then return true
    if key = "left" then
        i = detailFocusPos() - 1
        if i < 0 then i = 0
        m.detailFocusKey = m.detailFocusList[i] : styleDetail() : return true
    end if
    if key = "right" then
        i = detailFocusPos() + 1
        if i > n - 1 then i = n - 1
        m.detailFocusKey = m.detailFocusList[i] : styleDetail() : return true
    end if
    if key = "OK" then
        k = m.detailFocusKey
        if k = "time" then
            seekToMarker()
        else if k = "close" then
            closeDetail()
        else if k = "delete" then
            deleteActiveNote()
        else if k = "readmore" then
            openTextReader()
        else if Left(k, 5) = "thumb" then
            idx = Val(Mid(k, 6))
            openImageViewer(idx)
        end if
        return true
    end if
    return true
end function

' Jump the playhead to the marker's timecode, then close the card. Closing
' restores the captured play state (so a playing video resumes from there).
sub seekToMarker()
    if m.activeMarker = invalid then return
    t = m.activeMarker.startsAt
    if m.duration > 0 and t > m.duration then t = Int(m.duration)
    m.overlay = "none"   ' allow the seek to take effect (not squashed)
    m.video.seek = t
    m.position = t
    m.prevPos = t        ' don't re-fire the popup we just jumped to
    renderScrub()
    closeDetail()
end sub

sub closeDetail()
    m.detailModal.visible = false
    m.activeMarker = invalid
    m.overlay = "none"
    ' Restore: was-playing → resume; was-paused → stay paused.
    if m.wasPlaying then
        m.video.control = "resume"
    else
        m.video.control = "pause"
    end if
    showControls("")
    if m.markers.Count() > 0 then enterMarkers()
end sub

sub deleteActiveNote()
    if m.activeMarker = invalid or m.activeMarker.type <> "note" then return
    noteId = m.activeMarker.id
    t = CreateObject("roSGNode", "ApiTask")
    t.request = ApiReq().deleteNote(m.top.videoId, noteId)
    t.control = "RUN"
    m.deleteTask = t
    ' Optimistically drop it from the strip and close.
    kept = []
    for each mk in m.markers
        if not (mk.type = "note" and mk.id = noteId) then kept.push(mk)
    end for
    m.markers = kept
    buildMarkerStrip()
    if m.markerIdx > m.markers.Count() - 1 then m.markerIdx = m.markers.Count() - 1
    if m.markerIdx < 0 then m.markerIdx = 0
    closeDetail()
end sub

' ════════════════════════════════════════════════════════════════════════
'  Full-screen image viewer (§9.9).
' ════════════════════════════════════════════════════════════════════════
sub openImageViewer(idx as integer)
    if m.activeMarker = invalid then return
    imgs = m.activeMarker.images
    if imgs = invalid or imgs.Count() = 0 then return
    m.viewerImages = imgs
    m.viewerIndex = idx
    renderViewer()
    m.overlay = "image"
    m.imageViewer.visible = true
end sub

sub renderViewer()
    n = m.viewerImages.Count()
    i = m.viewerIndex mod n
    if i < 0 then i = i + n
    m.viewerIndex = i
    m.viewerImg.uri = m.viewerImages[i]
    if n > 1 then
        m.viewerCounter.text = Stri(i + 1).Trim() + " / " + Stri(n).Trim()
        m.viewerCounter.visible = true
    else
        m.viewerCounter.visible = false
    end if
end sub

function handleImageKeys(key as string) as boolean
    if key = "back" or key = "OK" then closeImageViewer() : return true
    n = m.viewerImages.Count()
    if key = "left" and n > 1 then m.viewerIndex = m.viewerIndex - 1 : renderViewer() : return true
    if key = "right" and n > 1 then m.viewerIndex = m.viewerIndex + 1 : renderViewer() : return true
    return true
end function

sub closeImageViewer()
    m.imageViewer.visible = false
    m.overlay = "detail"   ' return to the detail card
end sub

' ════════════════════════════════════════════════════════════════════════
'  Full-screen text reader (§9.8).
' ════════════════════════════════════════════════════════════════════════
sub openTextReader()
    m.readerTitle.text = m.readerTitleText
    m.readerBody.text = m.readerFull
    m.readerBody.translation = [0, 0]
    m.readerScrollY = 0
    rect = m.readerBody.boundingRect()
    h = 0
    if rect <> invalid then h = rect.height
    m.readerMax = h - 720
    if m.readerMax < 0 then m.readerMax = 0
    m.overlay = "text"
    m.textReader.visible = true
end sub

function handleTextKeys(key as string) as boolean
    if key = "back" or key = "OK" then closeTextReader() : return true
    stepPx = 240
    if key = "down" then
        m.readerScrollY = m.readerScrollY + stepPx
        if m.readerScrollY > m.readerMax then m.readerScrollY = m.readerMax
        m.readerBody.translation = [0, -m.readerScrollY] : return true
    end if
    if key = "up" then
        m.readerScrollY = m.readerScrollY - stepPx
        if m.readerScrollY < 0 then m.readerScrollY = 0
        m.readerBody.translation = [0, -m.readerScrollY] : return true
    end if
    return true
end function

sub closeTextReader()
    m.textReader.visible = false
    m.overlay = "detail"
end sub

' ════════════════════════════════════════════════════════════════════════
'  Ambient auto pop-ups (§9.6) — non-focusable, top-left, 6s auto-dismiss.
' ════════════════════════════════════════════════════════════════════════
sub maybePopup(curr as integer)
    if m.markers.Count() = 0 then m.prevPos = curr : return
    if m.overlay <> "none" then m.prevPos = curr : return
    if not m.isPlaying then m.prevPos = curr : return
    ' A jump (seek) shouldn't fire every crossed marker.
    if curr < m.prevPos or (curr - m.prevPos) > 2 then m.prevPos = curr : return
    for each mk in m.markers
        s = mk.startsAt
        if s > m.prevPos and s <= curr then
            showPopup(mk) : exit for
        end if
    end for
    m.prevPos = curr
end sub

sub showPopup(mk as object)
    m.popup.removeChildren(m.popup.getChildren(-1, 0))
    isNote = (mk.type = "note")
    accent = "0xC9A84CFF"
    if isNote then accent = "0x4C8CC9FF"

    ' Content column. An embedded image → thumbnail on the right; a webpage
    ' link → the URL as text under the body. (No QR here — that's the detail
    ' card.)
    panelW = 620 : pad = 24
    imgs = mk.images
    if imgs = invalid then imgs = []
    hasImage = (imgs.Count() > 0)
    link = firstLink(mk.body)
    hasLink = (link <> "")

    thumbW = 0
    if hasImage then thumbW = 200
    textW = panelW - pad * 2 - thumbW
    if thumbW > 0 then textW = textW - 20

    title = ellip(nz2(mk.title, defaultTitle(mk)), 48)
    body = ellip(stripHtmlLine(mk.body), 120)
    hasBody = (body <> "")
    panelH = 96
    if hasBody then panelH = panelH + 64
    if hasLink then panelH = panelH + 44
    if hasImage and panelH < 150 then panelH = 150

    bg = CreateObject("roSGNode", "Rectangle")
    bg.width = panelW : bg.height = panelH : bg.color = "0x10171FF2"
    m.popup.appendChild(bg)
    bar = CreateObject("roSGNode", "Rectangle")
    bar.width = 6 : bar.height = panelH : bar.color = accent
    m.popup.appendChild(bar)

    dot = CreateObject("roSGNode", "Poster")
    dot.width = 14 : dot.height = 14 : dot.translation = [pad, 30]
    dot.uri = "pkg:/images/avatar_circle.png" : dot.blendColor = accent
    m.popup.appendChild(dot)
    tc = makeLabel(fmt(mk.startsAt), "Bold", 22, accent, 160, 1)
    tc.translation = [pad + 22, 24]
    m.popup.appendChild(tc)
    if isNote then
        pv = makeLabel("PRIVATE", "SemiBold", 16, "0x9FB0C0FF", 120, 1)
        pv.translation = [pad + 128, 27]
        m.popup.appendChild(pv)
    end if

    ttl = makeLabel(title, "Bold", 26, "0xFFFFFFFF", textW, 1)
    ttl.translation = [pad, 60]
    m.popup.appendChild(ttl)
    y = 100
    if hasBody then
        bd = makeLabel(body, "Regular", 20, "0x9FB0C0FF", textW, 2)
        bd.translation = [pad, y]
        m.popup.appendChild(bd)
        y = y + 64
    end if
    if hasLink then
        ln = makeLabel(ellip(link, 64), "SemiBold", 20, accent, textW, 1)
        ln.translation = [pad, y]
        m.popup.appendChild(ln)
    end if

    if hasImage then
        th = CreateObject("roSGNode", "Poster")
        th.width = thumbW : th.height = panelH - 36 : th.translation = [panelW - pad - thumbW, 18]
        th.loadDisplayMode = "scaleToZoom" : th.uri = imgs[0]
        m.popup.appendChild(th)
    end if

    m.popup.visible = true
    m.popupTimer.control = "stop"
    m.popupTimer.control = "start"
end sub

' Truncate to n chars with an ellipsis.
function ellip(s as string, n as integer) as string
    if s = invalid then return ""
    if Len(s) <= n then return s
    return Left(s, n).Trim() + "…"
end function

sub onPopupTimer()
    m.popup.visible = false
end sub

' ── HTML helpers ────────────────────────────────────────────────────────
' All <img src> URLs in an HTML body (TipTap embeds images as <img>).
function allImages(html as string) as object
    out = []
    if html = invalid or html = "" then return out
    rx = CreateObject("roRegex", "<img[^>]+src\s*=\s*[" + Chr(34) + "']([^" + Chr(34) + "']+)[" + Chr(34) + "']", "i")
    matches = rx.MatchAll(html)
    for each mm in matches
        if mm.Count() >= 2 and nz(mm[1]) <> "" then out.push(mm[1])
    end for
    return out
end function

' First webpage link in an HTML body. <img> tags are stripped first so an
' image src never leaks into the bare-URL fallback and gets QR'd.
function firstLink(html as string) as string
    if html = invalid or html = "" then return ""
    html = CreateObject("roRegex", "<img[^>]*>", "i").ReplaceAll(html, "")
    rx = CreateObject("roRegex", "href\s*=\s*[" + Chr(34) + "']([^" + Chr(34) + "']+)[" + Chr(34) + "']", "i")
    mm = rx.Match(html)
    if mm.Count() >= 2 then
        h = mm[1].Trim()
        low = LCase(h)
        if Left(low, 4) = "http" then return h
        if Instr(1, h, ":") = 0 then
            while Left(h, 1) = "/" : h = Mid(h, 2) : end while
            return "https://" + h
        end if
    end if
    rx2 = CreateObject("roRegex", "https?://[^\s<>" + Chr(34) + "')]+", "i")
    m2 = rx2.Match(html)
    if m2.Count() >= 1 then return m2[0]
    rx3 = CreateObject("roRegex", "www\.[^\s<>" + Chr(34) + "')]+", "i")
    m3 = rx3.Match(html)
    if m3.Count() >= 1 then return "https://" + m3[0]
    return ""
end function

' Flatten HTML to multi-line plain text (block tags → newline). Used by the
' detail body + text reader.
function htmlMultiline(html as string) as string
    if html = invalid or html = "" then return ""
    s = html
    s = CreateObject("roRegex", "<br\s*/?>", "i").ReplaceAll(s, Chr(10))
    s = CreateObject("roRegex", "</(p|div|li|h[1-6]|tr|blockquote|ul|ol)>", "i").ReplaceAll(s, Chr(10) + Chr(10))
    s = CreateObject("roRegex", "<[^>]*>", "i").ReplaceAll(s, "")
    s = decodeEntities(s)
    s = CreateObject("roRegex", "[ \t]+", "").ReplaceAll(s, " ")
    s = CreateObject("roRegex", "\n{3,}", "").ReplaceAll(s, Chr(10) + Chr(10))
    return s.Trim()
end function

function decodeEntities(s as string) as string
    s = CreateObject("roRegex", "&nbsp;", "i").ReplaceAll(s, " ")
    s = CreateObject("roRegex", "&amp;", "i").ReplaceAll(s, "&")
    s = CreateObject("roRegex", "&lt;", "i").ReplaceAll(s, "<")
    s = CreateObject("roRegex", "&gt;", "i").ReplaceAll(s, ">")
    s = CreateObject("roRegex", "&quot;", "i").ReplaceAll(s, Chr(34))
    s = CreateObject("roRegex", "&#39;", "i").ReplaceAll(s, "'")
    s = CreateObject("roRegex", "&apos;", "i").ReplaceAll(s, "'")
    return s
end function

function makeQrNode(link as string, size as integer) as object
    q = CreateObject("roSGNode", "QRCode")
    q.ecl = "MEDIUM"
    q.border = 1
    q.pixel = 8
    q.darkColor = "0x131A24FF"
    q.lightColor = "0xFFFFFFFF"
    q.width = size : q.height = size
    q.loadDisplayMode = "scaleToFit"
    q.text = link
    return q
end function

function nz2(s as dynamic, fallback as string) as string
    v = nz(s)
    if v = "" then return fallback
    return v
end function

function defaultTitle(mk as object) as string
    if mk.type = "note" then return "Note"
    return "Annotation"
end function

' ── Chapters pop-up (§9.2) ──────────────────────────────────────────────
sub openChapters()
    if m.chapters.Count() = 0 then return
    if m.chapRows.Count() = 0 then buildChapterRows()
    m.chapSel = currentChapterIndex()
    styleChapterRows()
    m.overlay = "chapters"
    m.chaptersModal.visible = true
    clearHide()
end sub

sub buildChapterRows()
    m.chaptersList.removeChildren(m.chaptersList.getChildren(-1, 0))
    m.chapRows = []
    for each ch in m.chapters
        row = CreateObject("roSGNode", "Group")
        bg = CreateObject("roSGNode", "Rectangle")
        bg.width = 680 : bg.height = 60 : bg.color = "0x00000000"
        row.appendChild(bg)
        tc = makeLabel(fmt(numOr(ch.starts_at_seconds, 0)), "Bold", 24, "0xC9A84CFF", 110, 1)
        tc.translation = [16, 0] : tc.height = 60 : tc.vertAlign = "center"
        row.appendChild(tc)
        ti = makeLabel(nz(ch.title), "SemiBold", 24, "0xFFFFFFFF", 520, 1)
        ti.translation = [136, 0] : ti.height = 60 : ti.vertAlign = "center"
        row.appendChild(ti)
        m.chaptersList.appendChild(row)
        m.chapRows.push({ group: row, bg: bg })
    end for
end sub

' Last chapter whose start ≤ playhead.
function currentChapterIndex() as integer
    idx = 0
    for i = 0 to m.chapters.Count() - 1
        if numOr(m.chapters[i].starts_at_seconds, 0) <= m.position then idx = i
    end for
    return idx
end function

sub styleChapterRows()
    for i = 0 to m.chapRows.Count() - 1
        if i = m.chapSel then
            m.chapRows[i].bg.color = "0xFFFFFF1F"
        else
            m.chapRows[i].bg.color = "0x00000000"
        end if
    end for
    ' Keep the selected row inside the 840px clip window.
    rowH = 66
    clipH = 840
    selTop = m.chapSel * rowH
    if selTop < m.chapScrollY then m.chapScrollY = selTop
    if selTop + 60 > m.chapScrollY + clipH then m.chapScrollY = selTop + 60 - clipH
    listH = m.chapRows.Count() * rowH - 6
    maxScroll = listH - clipH
    if maxScroll < 0 then maxScroll = 0
    if m.chapScrollY > maxScroll then m.chapScrollY = maxScroll
    if m.chapScrollY < 0 then m.chapScrollY = 0
    m.chaptersList.translation = [0, -m.chapScrollY]
end sub

sub selectChapter()
    if m.chapSel < 0 or m.chapSel >= m.chapters.Count() then return
    ch = m.chapters[m.chapSel]
    t = Int(numOr(ch.starts_at_seconds, 0))
    if m.duration > 0 and t > m.duration then t = Int(m.duration)
    m.video.seek = t
    m.position = t
    renderScrub()
    showChapterFlash(t, nz(ch.title))
    closeChapters()
end sub

sub closeChapters()
    m.chaptersModal.visible = false
    m.overlay = "none"
    showControls("icons")
end sub

' Brief timecode+name bubble + tick above the scrub at the chapter position. §9.2
sub showChapterFlash(t as integer, title as string)
    total = m.duration
    if total <= 0 then total = numOr(m.payload.duration_seconds, 0)
    frac = 0.0
    if total > 0 then frac = t / total
    if frac < 0 then frac = 0
    if frac > 1 then frac = 1
    tickX = 150 + Int(1620 * frac)

    text = fmt(t) + "   " + title
    bubbleW = 40 + Len(text) * 13
    if bubbleW > 700 then bubbleW = 700
    bubbleX = tickX - Int(bubbleW / 2)
    if bubbleX < 150 then bubbleX = 150
    if bubbleX + bubbleW > 1770 then bubbleX = 1770 - bubbleW

    m.chapterFlashLabel.text = text
    m.chapterFlashLabel.width = bubbleW - 32
    m.chapterFlashLabel.translation = [bubbleX + 16, 838]
    m.chapterFlashBg.width = bubbleW
    m.chapterFlashBg.translation = [bubbleX, 838]
    m.chapterFlashTick.translation = [tickX - 1, 890]
    m.chapterFlash.visible = true
    m.chapterFlashTimer.control = "stop"
    m.chapterFlashTimer.control = "start"
end sub

sub onChapterFlashTimer()
    m.chapterFlash.visible = false
end sub

function handleChaptersKeys(key as string) as boolean
    if key = "back" then closeChapters() : return true
    if key = "up" then
        if m.chapSel > 0 then m.chapSel = m.chapSel - 1 : styleChapterRows()
        return true
    end if
    if key = "down" then
        if m.chapSel < m.chapters.Count() - 1 then m.chapSel = m.chapSel + 1 : styleChapterRows()
        return true
    end if
    if key = "OK" then selectChapter() : return true
    return true
end function

' ── Exit ────────────────────────────────────────────────────────────────
sub pop()
    saveProgress(Int(m.position))
    m.video.control = "stop"
    m.saveTimer.control = "stop"
    m.top.popped = true
end sub

' ── Key routing (explicit; this screen owns focus) ──────────────────────
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then
        ' Release ends a hold-seek run.
        if key = "left" or key = "right" or key = "rewind" or key = "fastforward" then
            m.seekHold = invalid
        end if
        return false
    end if

    if m.payload = invalid then
        if key = "back" then pop() : return true
        return false
    end if

    ' ── Modal overlay owns keys first (§9.15) ──
    if m.overlay = "chapters" then return handleChaptersKeys(key)
    if m.overlay = "image" then return handleImageKeys(key)
    if m.overlay = "text" then return handleTextKeys(key)
    if m.overlay = "detail" then return handleDetailKeys(key)

    ' ── BACK (Netflix double-back, §9.10) ──
    if key = "back" then
        if not m.isPlaying and m.controlsVisible then
            ' First BACK while paused with chrome up: clear chrome, stay paused.
            hideControls()
            return true
        end if
        ' Playing, or paused with chrome already hidden → exit.
        pop()
        return true
    end if

    ' ── Media transport keys (always) ──
    if key = "play" then togglePlay() : showControls("") : return true
    if key = "fastforward" then onSeekKey(1) : return true
    if key = "rewind" then onSeekKey(-1) : return true

    ' ── Bare player (no chrome) §9.3 ──
    if not m.controlsVisible then
        if key = "OK" then togglePlay() : showControls("pills") : return true
        if key = "left" then onSeekKey(-1) : return true
        if key = "right" then onSeekKey(1) : return true
        if key = "up" then showControls("pills") : return true
        if key = "down" then return true   ' no-op on bare player
        return true
    end if

    ' ── Chrome visible: zone navigation ──
    armHide()
    if m.zone = "icons" then return handleIconKeys(key)
    if m.zone = "markers" then return handleMarkerKeys(key)
    if m.zone = "scrub" then return handleScrubKeys(key)
    return handlePillKeys(key)
end function

function handleIconKeys(key as string) as boolean
    if key = "left" then
        if m.iconIdx > 0 then m.iconIdx = m.iconIdx - 1 : styleZones()
        return true
    end if
    if key = "right" then
        if m.iconIdx < m.iconKeys.Count() - 1 then m.iconIdx = m.iconIdx + 1 : styleZones()
        return true
    end if
    if key = "down" then
        if m.markers.Count() > 0 then enterMarkers() else m.zone = "scrub" : styleZones()
        return true
    end if
    if key = "up" then hideControls() : return true
    if key = "OK" then activateIcon() : return true
    return true
end function

function handleScrubKeys(key as string) as boolean
    if key = "left" then onSeekKey(-1) : return true
    if key = "right" then onSeekKey(1) : return true
    if key = "OK" then togglePlay() : return true
    if key = "down" then m.zone = "pills" : styleZones() : return true
    if key = "up" then
        if m.markers.Count() > 0 then enterMarkers() else m.zone = "icons" : styleZones()
        return true
    end if
    return true
end function

function handlePillKeys(key as string) as boolean
    if key = "left" then
        if m.pillIdx > 0 then m.pillIdx = m.pillIdx - 1 : styleZones()
        return true
    end if
    if key = "right" then
        if m.pillIdx < m.pillKeys.Count() - 1 then m.pillIdx = m.pillIdx + 1 : styleZones()
        return true
    end if
    if key = "OK" then activatePill() : return true
    if key = "up" then m.zone = "scrub" : styleZones() : return true
    if key = "down" then hideControls() : return true
    return true
end function

' ── Helpers (mirror EventDetailScreen) ──────────────────────────────────
function fmt(sec as dynamic) as string
    s = Int(sec)
    if s < 0 then s = 0
    h = s \ 3600
    m2 = (s mod 3600) \ 60
    s2 = s mod 60
    if h > 0 then
        return h.ToStr() + ":" + pad2(m2) + ":" + pad2(s2)
    end if
    return m2.ToStr() + ":" + pad2(s2)
end function

function pad2(n as integer) as string
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
end function

function arr(v as dynamic) as object
    if v <> invalid and GetInterface(v, "ifArray") <> invalid then return v
    return []
end function

' Strip HTML tags + entities to a single collapsed line (chip/body preview). §9.6
function stripHtmlLine(html as string) as string
    if html = "" then return ""
    out = ""
    inTag = false
    for i = 0 to Len(html) - 1
        ch = Mid(html, i + 1, 1)
        if ch = "<" then
            inTag = true
        else if ch = ">" then
            inTag = false
            out = out + " "
        else if not inTag then
            out = out + ch
        end if
    end for
    out = ReplaceAll(out, "&nbsp;", " ")
    out = ReplaceAll(out, "&amp;", "&")
    out = ReplaceAll(out, "&lt;", "<")
    out = ReplaceAll(out, "&gt;", ">")
    out = ReplaceAll(out, "&#39;", "'")
    out = ReplaceAll(out, "&quot;", Chr(34))
    out = ReplaceAll(out, Chr(10), " ")
    out = ReplaceAll(out, Chr(13), " ")
    out = ReplaceAll(out, Chr(9), " ")
    ' Collapse runs of spaces.
    while Instr(1, out, "  ") > 0
        out = ReplaceAll(out, "  ", " ")
    end while
    return TrimStr(out)
end function

function ReplaceAll(s as string, find as string, repl as string) as string
    if find = "" then return s
    return s.Replace(find, repl)
end function

function TrimStr(s as string) as string
    return s.Trim()
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

function nowMillis() as integer
    return m.clock.TotalMilliseconds()
end function
