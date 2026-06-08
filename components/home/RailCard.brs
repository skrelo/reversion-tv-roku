sub init()
    m.scaleHost = m.top.findNode("scaleHost")
    m.ring = m.top.findNode("ring")
    m.image = m.top.findNode("image")
    m.gradient = m.top.findNode("gradient")
    m.wordmark = m.top.findNode("wordmark")
    m.overlay = m.top.findNode("overlay")
    m.cwPlay = m.top.findNode("cwPlay")
    m.badgeBg = m.top.findNode("badgeBg")
    m.badge = m.top.findNode("badge")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressFill = m.top.findNode("progressFill")
    m.belowTitle = m.top.findNode("belowTitle")
    m.belowMeta = m.top.findNode("belowMeta")
    m.scaleAnim = m.top.findNode("scaleAnim")
    m.scaleInterp = m.top.findNode("scaleInterp")
    ' Scale around the art centre so the focus pop grows evenly.
    m.scaleHost.scaleRotateCenter = [150, 84]
end sub

sub render()
    md = m.top.model
    if md = invalid then return

    if md.art <> invalid and md.art <> "" then
        m.image.uri = SizedImage(md.art, 450)
    else
        m.image.uri = ""
    end if

    showWordmark = (md.wordmark <> invalid and md.wordmark <> "" and md.hasBaked <> true)
    m.wordmark.visible = showWordmark
    ' PaddedImage pads the mark onto an exact 456x120 (2x of the 228x60 box)
    ' transparent canvas so the aspect ratio is preserved by the CDN — Roku then
    ' renders it 1:1 with scaleToFit, no stretching (same trick as the hero).
    if showWordmark then m.wordmark.uri = PaddedImage(md.wordmark, 456, 120)

    hasOverlay = (md.overlayTitle <> invalid and md.overlayTitle <> "")
    m.overlay.visible = hasOverlay
    if hasOverlay then m.overlay.text = md.overlayTitle

    m.gradient.visible = (showWordmark or hasOverlay)

    m.cwPlay.visible = (md.isContinue = true)

    hasBadge = (md.badge <> invalid and md.badge <> "")
    m.badgeBg.visible = hasBadge
    if hasBadge then
        m.badge.text = md.badge
        if md.badge = "NEW" then
            m.badgeBg.color = "0xE50914FF"
        else
            m.badgeBg.color = "0x0F1923D9"
        end if
    end if

    frac = 0.0
    if md.progress <> invalid then frac = md.progress
    if frac > 0 then
        m.progressTrack.visible = true
        m.progressFill.width = Int(300 * frac)
    else
        m.progressTrack.visible = false
    end if

    ' Below-card text. Video tiles show title (line 1) + date (line 2); event
    ' tiles show only the date — and it sits on the TOP line so it aligns with
    ' the video tiles' title row (mirrors Tizen's flex column, no empty slot).
    bt = nz(md.belowTitle)
    bm = nz(md.belowMeta)
    if bt <> "" then
        m.belowTitle.visible = true
        m.belowTitle.text = bt
        m.belowTitle.translation = [0, 180]
        m.belowMeta.translation = [0, 210]
    else
        m.belowTitle.visible = false
        m.belowMeta.translation = [0, 180]
    end if
    m.belowMeta.visible = (bm <> "")
    m.belowMeta.text = bm
end sub

sub onFocusChanged()
    f = (m.top.focused = true)
    m.ring.visible = f
    m.scaleAnim.control = "stop"
    if f then
        m.scaleInterp.keyValue = [m.scaleHost.scale, [1.08, 1.08]]
    else
        m.scaleInterp.keyValue = [m.scaleHost.scale, [1.0, 1.0]]
    end if
    m.scaleAnim.control = "start"
end sub
