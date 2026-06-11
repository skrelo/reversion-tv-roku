' Settings (TV_APP_SPEC §10). 2-pane: section tabs on the left, a detail pane on
' the right rebuilt per section. This screen owns focus explicitly and renders
' highlight from state (§12) — there are no real SceneGraph-focused children.
'
' (Platform — Roku) §10.1 speed chips are intentionally omitted: Roku exposes no
' public arbitrary VOD playback-rate API, so Playback holds only Autoplay Next.

sub init()
    m.bg = m.top.findNode("bg")
    m.tabsGroup = m.top.findNode("tabs")
    m.pane = m.top.findNode("pane")
    m.docReader = m.top.findNode("docReader")
    m.docTitle = m.top.findNode("docTitle")
    m.docBody = m.top.findNode("docBody")
    m.docHint = m.top.findNode("docHint")
    m.docLayoutTimer = m.top.findNode("docLayoutTimer")
    m.docLayoutTimer.observeField("fire", "onDocLayout")
    m.docHint.text = Chr(8593) + " / " + Chr(8595) + " to scroll  ·  BACK to return"

    ' Section tabs, in order (§10.0).
    m.sections = [
        { id: "playback", label: "Playback" },
        { id: "account",  label: "Account" },
        { id: "privacy",  label: "Privacy" },
        { id: "info",     label: "Info" },
        { id: "signout",  label: "Sign Out" }
    ]
    m.privacyDocs = [
        { title: "Privacy & Data Stewardship Notice", doc: "privacy-stewardship-notice" },
        { title: "Private Member Digital Agreement",  doc: "private-member-digital-agreement" }
    ]

    ' Layout. The detail pane is framed by a "window" panel so it reads as a
    ' separate surface from the tab column.
    m.PANE_W = 1130
    m.PANEL_X = -28
    m.PANEL_Y = -28
    m.PANEL_W = m.PANE_W + 56
    m.PANEL_H = 828
    m.DOC_BOX_H = 800           ' iframe box height (matches docBox/docClip in XML)
    m.DOC_PAD = 24              ' inner padding of the iframe box (matches docBody)
    m.TAB_W = 400
    m.TAB_H = 60
    m.TAB_STEP = 76

    ' Colors.
    m.cIdle   = "0x1B2A3AFF"
    m.cActive = "0x23324AFF"
    m.cGold   = "0xC9A84CFF"
    m.cText   = "0xFFFFFFFF"
    m.cMuted  = "0x8C9EB0FF"
    m.cDark   = "0x0F1923FF"
    m.cDanger = "0xC0463CFF"
    m.cPanel  = "0x16222EFF"    ' detail-pane window bg (matches avatar_mask corners)
    m.cInset  = "0x0B131CFF"    ' iframe box bg (inset, darker than the panel)

    ' Playback speed (parity with Android Settings). Roku persists the pref like
    ' the other platforms; see the note in onSpeedSelect about applying it.
    m.speedVals = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    m.speedLabels = ["0.5x", "0.75x", "Normal (1x)", "1.25x", "1.5x", "2x"]
    m.speedWidths = [110, 132, 196, 132, 110, 92]
    m.curSpeed = numOr(RegRead(ReversionConfig().KEY_PLAYBACK_SPEED), 1.0)

    ' State.
    m.tabIdx = 0
    m.section = "playback"
    m.zone = "tabs"            ' "tabs" | "pane"
    m.paneIdx = 0
    m.paneCount = 0            ' focusables in the current pane (0 = display-only)
    m.pbFocus = "chip"         ' playback sub-focus: "chip" | "toggle"
    m.chipIdx = 0
    m.speedChips = []
    m.toggleTrack = invalid
    m.toggleKnob = invalid
    m.toggleFocusBg = invalid
    m.toggleLbl = invalid
    m.user = invalid
    m.docOpen = false
    m.docIdx = 0
    m.docScroll = 0
    m.docMax = 0

    ' Per-section node refs (set during pane builds).
    m.docRows = []
    m.signoutBg = invalid
    m.signoutLbl = invalid

    m.autoplayNext = (RegRead(ReversionConfig().KEY_AUTOPLAY_NEXT) <> "false")

    buildTabs()
    styleTabs()
    buildPane()

    ' Account is loaded lazily from /me.
    m.meTask = CreateObject("roSGNode", "ApiTask")
    m.meTask.observeField("response", "onMeResponse")
    m.meTask.request = ApiReq().me()
    m.meTask.control = "RUN"

    m.top.setFocus(true)
end sub

' ── Tabs ────────────────────────────────────────────────────────────────────
sub buildTabs()
    clearNode(m.tabsGroup)
    m.tabNodes = []
    for i = 0 to m.sections.Count() - 1
        sec = m.sections[i]
        grp = CreateObject("roSGNode", "Group")
        grp.translation = [0, i * m.TAB_STEP]
        bg = roundedBg(m.TAB_W, m.TAB_H, m.cIdle)
        bg.visible = false
        grp.appendChild(bg)
        lbl = mkLabel(sec.label, "SemiBold", 28, m.cText, m.TAB_W - 48, 1)
        lbl.translation = [24, 0]
        lbl.height = m.TAB_H
        lbl.vertAlign = "center"
        grp.appendChild(lbl)
        m.tabsGroup.appendChild(grp)
        m.tabNodes.push({ bg: bg, label: lbl })
    end for
end sub

sub styleTabs()
    for i = 0 to m.tabNodes.Count() - 1
        t = m.tabNodes[i]
        focused = (m.zone = "tabs" and i = m.tabIdx)
        active = (i = m.tabIdx)
        if focused then
            t.bg.visible = true
            t.bg.blendColor = m.cGold
            t.label.color = m.cDark
        else if active then
            t.bg.visible = true
            t.bg.blendColor = m.cActive
            t.label.color = m.cGold
        else
            t.bg.visible = false
            t.label.color = m.cMuted
        end if
    end for
end sub

sub setTab(idx as integer)
    if idx < 0 then idx = 0
    if idx > m.sections.Count() - 1 then idx = m.sections.Count() - 1
    if idx = m.tabIdx then return
    m.tabIdx = idx
    m.section = m.sections[idx].id
    m.docOpen = false
    buildPane()
    styleTabs()
end sub

' ── Detail pane ───────────────────────────────────────────────────────────────
sub buildPane()
    clearNode(m.pane)
    m.docRows = []
    m.signoutBg = invalid : m.signoutLbl = invalid
    m.speedChips = []
    m.toggleTrack = invalid : m.toggleKnob = invalid
    m.toggleFocusBg = invalid : m.toggleLbl = invalid

    addPanel()

    if m.section = "playback" then
        buildPlaybackPane()
    else if m.section = "account" then
        buildAccountPane()
    else if m.section = "privacy" then
        buildPrivacyPane()
    else if m.section = "info" then
        buildInfoPane()
    else if m.section = "signout" then
        buildSignoutPane()
    end if
    stylePane()
end sub

' The "window" behind the detail content (first child = furthest back).
sub addPanel()
    p = roundedBg(m.PANEL_W, m.PANEL_H, m.cPanel)
    p.translation = [m.PANEL_X, m.PANEL_Y]
    m.pane.appendChild(p)
end sub

sub buildPlaybackPane()
    addHead("Default Playback Speed", 4)
    addSub("Applied when a video starts. You can still change speed during playback.", 52)

    ' Speed chips row.
    m.speedChips = []
    x = 0
    chipY = 120
    for i = 0 to m.speedVals.Count() - 1
        w = m.speedWidths[i]
        grp = CreateObject("roSGNode", "Group")
        grp.translation = [x, chipY]
        bg = roundedBg(w, 64, m.cIdle)
        grp.appendChild(bg)
        lbl = mkLabel(m.speedLabels[i], "SemiBold", 24, m.cText, w, 1)
        lbl.horizAlign = "center" : lbl.height = 64 : lbl.vertAlign = "center"
        grp.appendChild(lbl)
        m.pane.appendChild(grp)
        m.speedChips.push({ bg: bg, label: lbl })
        x = x + w + 14
    end for

    addHead("Autoplay Next", 232)
    addSub("Automatically advance to the next video when nearing the end.", 280)

    ' Switch-style toggle: track + sliding knob + On/Off label.
    tg = CreateObject("roSGNode", "Group")
    tg.translation = [0, 344]
    m.toggleFocusBg = roundedBg(112, 60, m.cGold)
    m.toggleFocusBg.translation = [-6, -6]
    m.toggleFocusBg.visible = false
    tg.appendChild(m.toggleFocusBg)
    m.toggleTrack = roundedBg(100, 48, m.cIdle)
    tg.appendChild(m.toggleTrack)
    m.toggleKnob = CreateObject("roSGNode", "Poster")
    m.toggleKnob.width = 40 : m.toggleKnob.height = 40
    m.toggleKnob.uri = "pkg:/images/avatar_circle.png"
    m.toggleKnob.blendColor = m.cText
    tg.appendChild(m.toggleKnob)
    m.toggleLbl = mkLabel(autoplayText(), "SemiBold", 26, m.cMuted, 120, 1)
    m.toggleLbl.translation = [120, 0] : m.toggleLbl.height = 48 : m.toggleLbl.vertAlign = "center"
    tg.appendChild(m.toggleLbl)
    m.pane.appendChild(tg)

    syncToggle()
end sub

sub buildAccountPane()
    m.paneCount = 0
    if m.user = invalid then
        m.pane.appendChild(mkLabel("Loading...", "Regular", 30, m.cMuted, m.PANE_W, 1))
        return
    end if
    u = m.user
    nm = firstNonEmpty([u.display_name, u.name])
    if nm = "" then nm = nz(u.email)
    if nm = "" then nm = "Account"
    initial = "R"
    if Len(nm) > 0 then initial = UCase(Left(nm, 1))
    photo = nz(u.profile_photo_url)

    av = CreateObject("roSGNode", "Group")
    av.translation = [8, 8]
    if photo <> "" then
        ' Real photo, cropped to a circle by the panel-colored frame mask on top.
        ph = CreateObject("roSGNode", "Poster")
        ph.width = 112 : ph.height = 112
        ph.loadDisplayMode = "scaleToZoom"
        ph.uri = SizedImageH(photo, 112)
        av.appendChild(ph)
        msk = CreateObject("roSGNode", "Poster")
        msk.width = 112 : msk.height = 112
        msk.uri = "pkg:/images/avatar_mask.png"
        av.appendChild(msk)
    else
        circle = CreateObject("roSGNode", "Poster")
        circle.width = 112 : circle.height = 112
        circle.uri = "pkg:/images/avatar_circle.png"
        circle.blendColor = m.cGold
        av.appendChild(circle)
        il = mkLabel(initial, "Bold", 52, m.cDark, 112, 1)
        il.horizAlign = "center" : il.height = 112 : il.vertAlign = "center"
        av.appendChild(il)
    end if
    m.pane.appendChild(av)

    nameLbl = mkLabel(nm, "Bold", 40, m.cText, m.PANE_W - 150, 1)
    nameLbl.translation = [148, 22]
    m.pane.appendChild(nameLbl)
    handle = nz(u.telegram_handle)
    if handle <> "" then
        hl = mkLabel(handle, "Regular", 26, m.cMuted, m.PANE_W - 150, 1)
        hl.translation = [148, 76]
        m.pane.appendChild(hl)
    end if

    y = 168
    addKV("Email", firstNonEmpty([u.email]), y) : y = y + 64
    ms = firstNonEmpty([u.member_since, u.created_at_label])
    if ms <> "" then
        addKV("Member since", ms, y) : y = y + 64
    end if
end sub

sub buildPrivacyPane()
    m.paneCount = m.privacyDocs.Count()
    addSub("Read the member documents below.", 0)
    y = 64
    for i = 0 to m.privacyDocs.Count() - 1
        d = m.privacyDocs[i]
        grp = CreateObject("roSGNode", "Group")
        grp.translation = [0, y]
        bg = roundedBg(m.PANE_W, 84, m.cIdle)
        grp.appendChild(bg)
        lbl = mkLabel(d.title, "SemiBold", 28, m.cText, m.PANE_W - 120, 1)
        lbl.translation = [28, 0] : lbl.height = 84 : lbl.vertAlign = "center"
        grp.appendChild(lbl)
        chev = mkLabel(Chr(8250), "Bold", 40, m.cMuted, 40, 1)
        chev.translation = [m.PANE_W - 56, 0] : chev.height = 84 : chev.vertAlign = "center"
        grp.appendChild(chev)
        m.pane.appendChild(grp)
        m.docRows.push({ bg: bg, label: lbl, chev: chev })
        y = y + 100
    end for
end sub

sub buildInfoPane()
    m.paneCount = 0
    di = CreateObject("roDeviceInfo")
    ai = CreateObject("roAppInfo")

    osv = ""
    v = di.GetOSVersion()
    if v <> invalid then
        osv = nz(v.major) + "." + nz(v.minor) + "." + nz(v.revision)
    end if
    appV = nz(ai.GetValue("major_version")) + "." + nz(ai.GetValue("minor_version"))
    build = nz(ai.GetValue("build_version"))
    model = di.GetModelDisplayName()
    if model = invalid then model = "Roku"

    y = 0
    addKV("Platform", "TV (Roku)", y) : y = y + 64
    addKV("Device", model, y) : y = y + 64
    addKV("Model", nz(di.GetModel()), y) : y = y + 64
    if osv <> "" then
        addKV("OS version", osv, y) : y = y + 64
    end if
    addKV("App version", appV, y) : y = y + 64
    addKV("Build", build, y) : y = y + 64
    addKV("Copyright", "(C) " + yearStr() + " Scott Krelo", y) : y = y + 64
end sub

sub buildSignoutPane()
    m.paneCount = 1
    addSub("You'll need to pair this TV again to sign back in.", 0)
    grp = CreateObject("roSGNode", "Group")
    grp.translation = [0, 72]
    m.signoutBg = roundedBg(260, 72, m.cIdle)
    grp.appendChild(m.signoutBg)
    m.signoutLbl = mkLabel("Sign out", "Bold", 30, m.cText, 260, 1)
    m.signoutLbl.horizAlign = "center" : m.signoutLbl.height = 72 : m.signoutLbl.vertAlign = "center"
    grp.appendChild(m.signoutLbl)
    m.pane.appendChild(grp)
end sub

' Highlight the focused pane control (only when focus is in the pane).
sub stylePane()
    inPane = (m.zone = "pane")
    if m.section = "playback" then
        for i = 0 to m.speedChips.Count() - 1
            c = m.speedChips[i]
            sel = (Abs(m.speedVals[i] - m.curSpeed) < 0.01)
            foc = (inPane and m.pbFocus = "chip" and m.chipIdx = i)
            if foc then
                c.bg.blendColor = m.cGold : c.label.color = m.cDark
            else if sel then
                c.bg.blendColor = m.cText : c.label.color = m.cDark
            else
                c.bg.blendColor = m.cIdle : c.label.color = m.cText
            end if
        end for
        if m.toggleFocusBg <> invalid then
            m.toggleFocusBg.visible = (inPane and m.pbFocus = "toggle")
        end if
        syncToggle()
    else if m.section = "privacy" then
        for i = 0 to m.docRows.Count() - 1
            r = m.docRows[i]
            if inPane and i = m.paneIdx then
                r.bg.blendColor = m.cGold : r.label.color = m.cDark : r.chev.color = m.cDark
            else
                r.bg.blendColor = m.cIdle : r.label.color = m.cText : r.chev.color = m.cMuted
            end if
        end for
    else if m.section = "signout" and m.signoutBg <> invalid then
        if inPane then
            m.signoutBg.blendColor = m.cDanger : m.signoutLbl.color = m.cText
        else
            m.signoutBg.blendColor = m.cIdle : m.signoutLbl.color = m.cText
        end if
    end if
end sub

sub enterPane()
    if m.section = "account" or m.section = "info" then return   ' display-only
    m.zone = "pane"
    if m.section = "playback" then
        m.pbFocus = "chip"
        m.chipIdx = currentSpeedIdx()
    else
        m.paneIdx = 0
    end if
    styleTabs()
    stylePane()
end sub

function currentSpeedIdx() as integer
    for i = 0 to m.speedVals.Count() - 1
        if Abs(m.speedVals[i] - m.curSpeed) < 0.01 then return i
    end for
    return 2   ' default Normal (1x)
end function

sub backToTab()
    m.zone = "tabs"
    styleTabs()
    stylePane()
end sub

sub setPaneIdx(idx as integer)
    if idx < 0 then idx = 0
    if idx > m.paneCount - 1 then idx = m.paneCount - 1
    if idx = m.paneIdx then return
    m.paneIdx = idx
    stylePane()
end sub

sub toggleAutoplay()
    m.autoplayNext = not m.autoplayNext
    RegWrite(ReversionConfig().KEY_AUTOPLAY_NEXT, boolStr2(m.autoplayNext))
    syncToggle()
end sub

' Paint the switch to match the current On/Off state.
sub syncToggle()
    if m.toggleTrack = invalid then return
    if m.autoplayNext then
        m.toggleTrack.blendColor = "0x3DBE8BFF"   ' green when on
        m.toggleKnob.translation = [56, 4]
    else
        m.toggleTrack.blendColor = m.cIdle
        m.toggleKnob.translation = [4, 4]
    end if
    m.toggleLbl.text = autoplayText()
    if m.zone = "pane" and m.pbFocus = "toggle" then
        m.toggleLbl.color = m.cGold
    else
        m.toggleLbl.color = m.cMuted
    end if
end sub

function autoplayText() as string
    if m.autoplayNext then return "On"
    return "Off"
end function

sub onSpeedSelect(idx as integer)
    if idx < 0 or idx > m.speedVals.Count() - 1 then return
    m.curSpeed = m.speedVals[idx]
    ' Persist like every other platform. NOTE: Roku exposes no public arbitrary
    ' VOD playback-rate API, so the player can't apply this mid-stream yet (§9.2);
    ' the pref is stored for parity and for if/when a rate API is available.
    RegWrite(ReversionConfig().KEY_PLAYBACK_SPEED, formatSpeed(m.curSpeed))
    stylePane()
end sub

function formatSpeed(v as float) as string
    s = Str(v)
    s = s.Trim()
    return s
end function

' ── Legal reader (JSON path; Roku has no in-app web view) §10.3 ────────────────
sub openDoc(idx as integer)
    if idx < 0 or idx > m.privacyDocs.Count() - 1 then return
    d = m.privacyDocs[idx]
    m.docOpen = true
    m.docIdx = idx
    m.docScroll = 0
    m.docMax = 0

    m.docTitle.text = d.title
    m.docBody.text = "Loading..."
    m.docBody.translation = [m.DOC_PAD, m.DOC_PAD]
    m.docReader.visible = true

    m.docTask = CreateObject("roSGNode", "ApiTask")
    m.docTask.observeField("response", "onDocResponse")
    m.docTask.request = ApiReq().legalDoc(d.doc)
    m.docTask.control = "RUN"
end sub

sub onDocResponse()
    res = m.docTask.response
    if not m.docOpen then return
    if res <> invalid and res.ok = true and res.data <> invalid and res.data.html <> invalid then
        m.docBody.text = stripHtml(res.data.html)
    else
        m.docBody.text = "Couldn't load this document. Press BACK and try again."
    end if
    m.docBody.translation = [m.DOC_PAD, m.DOC_PAD]
    m.docScroll = 0
    ' Measure one frame later (boundingRect is only valid after layout).
    m.docLayoutTimer.control = "stop"
    m.docLayoutTimer.control = "start"
end sub

sub onDocLayout()
    if m.docBody = invalid then return
    h = 0
    r = m.docBody.boundingRect()
    if r <> invalid then h = r.height
    ' Content scrolls until its bottom reaches the box bottom (minus padding).
    m.docMax = h - (m.DOC_BOX_H - m.DOC_PAD * 2)
    if m.docMax < 0 then m.docMax = 0
end sub

sub scrollDoc(delta as integer)
    if m.docBody = invalid then return
    m.docScroll = m.docScroll + delta
    if m.docScroll < 0 then m.docScroll = 0
    if m.docScroll > m.docMax then m.docScroll = m.docMax
    m.docBody.translation = [m.DOC_PAD, m.DOC_PAD - m.docScroll]
end sub

sub closeDoc()
    m.docOpen = false
    m.docReader.visible = false
    m.zone = "pane"
    m.paneIdx = m.docIdx
    styleTabs()
    stylePane()
end sub

' ── /me ───────────────────────────────────────────────────────────────────────
sub onMeResponse()
    res = m.meTask.response
    if res <> invalid and res.status = 401 then
        m.top.signedOut = true
        return
    end if
    if res <> invalid and res.ok = true and res.data <> invalid then
        m.user = res.data.user
    end if
    if m.section = "account" and not m.docOpen then buildPane()
end sub

sub doSignOut()
    m.top.signedOut = true
end sub

' ── Key routing (screen owns focus) §10.6 ─────────────────────────────────────
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Legal reader owns its keys: scroll with UP/DOWN, LEFT/BACK closes it.
    if m.docOpen then
        if key = "back" or key = "left" then
            closeDoc()
            return true
        else if key = "up" then
            scrollDoc(-260)
            return true
        else if key = "down" then
            scrollDoc(260)
            return true
        end if
        return true
    end if

    if m.zone = "tabs" then
        if key = "up" then
            setTab(m.tabIdx - 1)
            return true
        else if key = "down" then
            setTab(m.tabIdx + 1)
            return true
        else if key = "right" or key = "OK" then
            enterPane()
            return true
        else if key = "back" then
            m.top.popped = true
            return true
        else if key = "left" then
            return true
        end if
        return false
    end if

    ' zone = "pane"
    if key = "back" then
        backToTab()
        return true
    end if

    if m.section = "playback" then
        if m.pbFocus = "chip" then
            if key = "left" then
                if m.chipIdx > 0 then
                    m.chipIdx = m.chipIdx - 1 : stylePane()
                else
                    backToTab()
                end if
            else if key = "right" then
                if m.chipIdx < m.speedChips.Count() - 1 then
                    m.chipIdx = m.chipIdx + 1 : stylePane()
                end if
            else if key = "down" then
                m.pbFocus = "toggle" : stylePane()
            else if key = "OK" then
                onSpeedSelect(m.chipIdx)
            end if
        else   ' toggle
            if key = "left" then
                backToTab()
            else if key = "up" then
                m.pbFocus = "chip" : stylePane()
            else if key = "OK" then
                toggleAutoplay()
            end if
        end if
        return true
    end if

    if key = "left" then
        backToTab()
        return true
    end if
    if m.section = "privacy" then
        if key = "up" then
            setPaneIdx(m.paneIdx - 1)
        else if key = "down" then
            setPaneIdx(m.paneIdx + 1)
        else if key = "OK" then
            openDoc(m.paneIdx)
        end if
        return true
    else if m.section = "signout" then
        if key = "OK" then doSignOut()
        return true
    end if
    return true
end function

' ── Pane helpers ──────────────────────────────────────────────────────────────
sub addHead(text as string, y as integer)
    h = mkLabel(text, "Bold", 34, m.cText, m.PANE_W, 1)
    h.translation = [0, y]
    m.pane.appendChild(h)
end sub

sub addSub(text as string, y as integer)
    s = mkLabel(text, "Regular", 24, m.cMuted, m.PANE_W, 2)
    s.translation = [0, y]
    m.pane.appendChild(s)
end sub

sub addKV(k as string, v as string, y as integer)
    val = v
    if val = "" then val = Chr(8212)
    grp = CreateObject("roSGNode", "Group")
    grp.translation = [0, y]
    kl = mkLabel(k, "SemiBold", 26, m.cMuted, 320, 1)
    grp.appendChild(kl)
    vl = mkLabel(val, "Regular", 26, m.cText, m.PANE_W - 340, 1)
    vl.translation = [340, 0]
    grp.appendChild(vl)
    m.pane.appendChild(grp)
end sub

' ── Generic helpers ───────────────────────────────────────────────────────────
sub clearNode(n as object)
    cnt = n.getChildCount()
    if cnt > 0 then n.removeChildrenIndex(cnt, 0)
end sub

function mkLabel(text as string, weight as string, size as integer, color as string, w as integer, maxLines as integer) as object
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

function boolStr2(b as boolean) as string
    if b then return "true"
    return "false"
end function

function yearStr() as string
    d = CreateObject("roDateTime")
    return d.GetYear().ToStr()
end function

' HTML → plain text for the legal reader (TV can't render rich text/links). §12
function stripHtml(html as string) as string
    if html = invalid or html = "" then return ""
    s = html

    ' Turn anchors into "label (url)".
    s = anchorsToText(s)

    ' Block-level tags → newlines; list items → bullets.
    s = ReplaceAll(s, "</p>", Chr(10) + Chr(10))
    s = ReplaceAll(s, "<br>", Chr(10))
    s = ReplaceAll(s, "<br/>", Chr(10))
    s = ReplaceAll(s, "<br />", Chr(10))
    s = ReplaceAll(s, "</div>", Chr(10))
    s = ReplaceAll(s, "</h1>", Chr(10) + Chr(10))
    s = ReplaceAll(s, "</h2>", Chr(10) + Chr(10))
    s = ReplaceAll(s, "</h3>", Chr(10) + Chr(10))
    s = ReplaceAll(s, "</h4>", Chr(10) + Chr(10))
    s = ReplaceAll(s, "</li>", Chr(10))
    s = ReplaceAll(s, "<li>", Chr(8226) + " ")

    ' Drop every remaining tag.
    s = stripTags(s)

    ' Decode the common entities.
    s = ReplaceAll(s, "&nbsp;", " ")
    s = ReplaceAll(s, "&amp;", "&")
    s = ReplaceAll(s, "&lt;", "<")
    s = ReplaceAll(s, "&gt;", ">")
    s = ReplaceAll(s, "&quot;", Chr(34))
    s = ReplaceAll(s, "&#39;", "'")
    s = ReplaceAll(s, "&rsquo;", "'")
    s = ReplaceAll(s, "&lsquo;", "'")
    s = ReplaceAll(s, "&ldquo;", Chr(34))
    s = ReplaceAll(s, "&rdquo;", Chr(34))
    s = ReplaceAll(s, "&mdash;", Chr(8212))
    s = ReplaceAll(s, "&ndash;", Chr(8211))

    s = collapseBlankLines(s)
    return s
end function

' Replace <a href="url">label</a> with "label (url)".
function anchorsToText(s as string) as string
    out = ""
    rest = s
    loop = true
    while loop
        i = Instr(1, LCase(rest), "<a ")
        if i = 0 then
            out = out + rest
            loop = false
        else
            out = out + Left(rest, i - 1)
            rest = Mid(rest, i)
            close = Instr(1, rest, ">")
            if close = 0 then
                out = out + rest
                loop = false
            else
                openTag = Left(rest, close)
                url = extractHref(openTag)
                rest = Mid(rest, close + 1)
                endA = Instr(1, LCase(rest), "</a>")
                if endA = 0 then
                    out = out + rest
                    loop = false
                else
                    label = stripTags(Left(rest, endA - 1))
                    if url <> "" and url <> label then
                        out = out + label + " (" + url + ")"
                    else
                        out = out + label
                    end if
                    rest = Mid(rest, endA + 4)
                end if
            end if
        end if
    end while
    return out
end function

function extractHref(tag as string) as string
    low = LCase(tag)
    i = Instr(1, low, "href=")
    if i = 0 then return ""
    after = Mid(tag, i + 5)
    if Len(after) = 0 then return ""
    q = Left(after, 1)
    if q = Chr(34) or q = "'" then
        after = Mid(after, 2)
        j = Instr(1, after, q)
        if j = 0 then return ""
        return Left(after, j - 1)
    end if
    ' Unquoted: read to space or >.
    j = Instr(1, after, " ")
    k = Instr(1, after, ">")
    if k > 0 and (j = 0 or k < j) then j = k
    if j = 0 then return after
    return Left(after, j - 1)
end function

function stripTags(s as string) as string
    out = ""
    inside = false
    n = Len(s)
    for i = 1 to n
        ch = Mid(s, i, 1)
        if ch = "<" then
            inside = true
        else if ch = ">" then
            inside = false
        else if not inside then
            out = out + ch
        end if
    end for
    return out
end function

function ReplaceAll(s as string, find as string, repl as string) as string
    if find = "" then return s
    out = ""
    rest = s
    flow = Len(find)
    loop = true
    while loop
        i = Instr(1, rest, find)
        if i = 0 then
            out = out + rest
            loop = false
        else
            out = out + Left(rest, i - 1) + repl
            rest = Mid(rest, i + flow)
        end if
    end while
    return out
end function

' Collapse 3+ consecutive newlines down to a blank-line gap, trim leading space.
function collapseBlankLines(s as string) as string
    three = Chr(10) + Chr(10) + Chr(10)
    two = Chr(10) + Chr(10)
    res = s
    loop = true
    while loop
        before = res
        res = ReplaceAll(res, three, two)
        if res = before then loop = false
    end while
    ' Trim leading newlines/spaces.
    while Len(res) > 0 and (Left(res, 1) = Chr(10) or Left(res, 1) = " " or Left(res, 1) = Chr(13))
        res = Mid(res, 2)
    end while
    return res
end function
