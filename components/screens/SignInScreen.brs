' On-device sign-in (Roku on-device authentication). Passwordless email-code
' flow that mirrors the phone app: enter email -> backend emails a 6-char code
' -> enter code -> exchange for a Sanctum token. Everything happens on the TV
' (no QR / rendezvous linking), satisfying Roku cert 2.2 / 4.1.
'
' This is a real full-screen sign-in page, NOT a dialog: a persistent on-screen
' DynamicKeyboard (voice-capable, the cert-sanctioned node for email/code entry,
' cert 4.12) centered on the page with our own branded pill buttons below it.
' The channel min-firmware is 11.5, so DynamicKeyboard always exists — no
' legacy fallback. Focus is explicit: the screen toggles between the keyboard
' and the button row and owns key routing (§12, mirrors Search/Detail).

' y of the keyboard's top edge; rows below are placed from its measured bounds.
function kbTop() as integer
    return 320
end function

sub init()
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.status = m.top.findNode("status")
    m.keyboard = m.top.findNode("keyboard")
    m.buttonRow = m.top.findNode("buttonRow")

    m.layoutTimer = m.top.findNode("layoutTimer")
    m.layoutTimer.observeField("fire", "onLayout")

    m.exitDialog   = m.top.findNode("exitDialog")
    m.exitCancelBg = m.top.findNode("exitCancelBg")
    m.exitCancelLabel = m.top.findNode("exitCancelLabel")
    m.exitConfirmBg = m.top.findNode("exitConfirmBg")
    m.exitConfirmLabel = m.top.findNode("exitConfirmLabel")
    m.exitSel = 0

    m.email = ""
    m.phase = ""            ' email | code
    m.zone = "keyboard"     ' keyboard | buttons
    m.done = false
    m.advanceAfterSend = true

    ' Button state (parallel arrays so we never findNode into the row).
    m.btnBgs = []
    m.btnLabels = []
    m.btnSel = 0
    m.rowWidth = 0
    m.kbBottomY = kbTop() + 470   ' refined once the keyboard is measured

    ' One task to send the code, one to verify it.
    m.sendTask = CreateObject("roSGNode", "ApiTask")
    m.sendTask.observeField("response", "onSendResponse")
    m.verifyTask = CreateObject("roSGNode", "ApiTask")
    m.verifyTask.observeField("response", "onVerifyResponse")

    ' On-device auth (cert RP 2.1/4.1): the ChannelStore "Request for Information"
    ' (getUserData) screen lets the user share their Roku account email with one
    ' click instead of typing it on the remote. We request it once on entry; on
    ' success we prefill the email, on cancel/empty the manual keyboard remains.
    m.channelStore = CreateObject("roSGNode", "ChannelStore")
    m.channelStore.observeField("userData", "onRokuUserData")
    m.rfiTried = false

    switchToEmail()
    requestRokuEmail()
    ' Measure + lay out one frame after first render.
    m.layoutTimer.control = "start"
end sub

' ── Roku account email (Request for Information) ────────────────────────
sub requestRokuEmail()
    if m.rfiTried then return
    m.rfiTried = true
    ' context "signin" tells Roku this RFI is part of a sign-in flow (vs signup).
    info = CreateObject("roSGNode", "ContentNode")
    info.addFields({ context: "signin" })
    m.channelStore.requestedUserDataInfo = info
    m.channelStore.requestedUserData = "email"
    m.channelStore.command = "getUserData"
end sub

sub onRokuUserData()
    ud = m.channelStore.userData
    ' Cancelled RFI → userData invalid; keep manual entry. cert-compliant either way.
    if ud = invalid then
        enterKeyboard()
        return
    end if
    email = ""
    if ud.email <> invalid then email = ud.email
    if email <> "" then
        m.email = lcaseTrim(email)
        m.keyboard.text = m.email
    end if
    enterKeyboard()
end sub

' ── Phase transitions ──────────────────────────────────────────────────
sub switchToEmail()
    m.phase = "email"
    m.title.text = "Sign in"
    m.subtitle.text = "Enter your account email. We'll send a 6-character sign-in code."
    m.keyboard.text = m.email
    setKeyboardVoice("email")
    buildButtons(["Send code", "Exit"])
    showStatusInfo("")
    enterKeyboard()
end sub

sub switchToCode()
    m.phase = "code"
    m.title.text = "Enter your code"
    m.subtitle.text = "We emailed a 6-character code to " + m.email + "."
    m.keyboard.text = ""
    setKeyboardVoice("alphanumeric")
    buildButtons(["Sign in", "Resend code", "Change email"])
    showStatusInfo("")
    enterKeyboard()
end sub

' DynamicKeyboard bundles a voice text edit box; dictation spells into our field
' (per-domain) instead of falling through to the OS global search. cert 4.12.
'
' The internal VoiceTextEditBox is reached via the documented `textEditBox`
' FIELD (Roku's own sample: `m.keyboard.textEditBox.voiceEnabled = true`), NOT
' findNode — findNode("textEditBox") returns invalid for a DynamicKeyboard, so
' voiceEnabled never gets set and the mic falls through to OS global search.
' Assign to a local + guard so a transient invalid can't throw (&he4).
sub setKeyboardVoice(mode as string)
    m.keyboard.domain = mode
    teb = m.keyboard.textEditBox
    if teb = invalid then teb = m.keyboard.findNode("textEditBox")
    if teb <> invalid then teb.voiceEnabled = true
end sub

' ── Button activation ──────────────────────────────────────────────────
sub activateButton()
    if m.phase = "email" then
        if m.btnSel = 0 then
            submitEmail()
        else
            showExit()
        end if
    else
        if m.btnSel = 0 then
            submitCode()
        else if m.btnSel = 1 then
            doSendCode(false)        ' resend, stay on the code page
        else
            switchToEmail()          ' change email
        end if
    end if
end sub

sub submitEmail()
    email = lcaseTrim(m.keyboard.text)
    if not looksLikeEmail(email) then
        showStatus("Please enter a valid email address.")
        return
    end if
    m.email = email
    doSendCode(true)
end sub

sub submitCode()
    code = UCase(lcaseTrim(m.keyboard.text))
    if Len(code) <> 6 then
        showStatus("Enter the 6-character code from your email.")
        return
    end if
    doVerifyCode(code)
end sub

' ── Send code ──────────────────────────────────────────────────────────
sub doSendCode(advance as boolean)
    m.advanceAfterSend = advance
    showStatusInfo("Sending code…")
    m.sendTask.request = ApiReq().sendLoginCode(m.email)
    m.sendTask.control = "RUN"
end sub

sub onSendResponse()
    resp = m.sendTask.response
    if resp = invalid then
        showStatus("We couldn't reach the server. Please try again.")
        return
    end if

    data = resp.data
    LogBeacon("sendCode", "SignIn", { ok: resp.ok, status: resp.status })
    if resp.ok = true then
        if data <> invalid and data.needs_verification = true then
            showStatus("Your email isn't verified yet. Check your inbox for a verification link, then try again.")
            return
        end if
        if m.advanceAfterSend then
            switchToCode()
        else
            showStatusInfo("A new code is on its way to " + m.email + ".")
        end if
        return
    end if

    showStatus(apiError(resp, "email", "We couldn't send a code to that email."))
end sub

' ── Verify code ────────────────────────────────────────────────────────
sub doVerifyCode(code as string)
    showStatusInfo("Signing in…")
    m.verifyTask.request = ApiReq().verifyLoginCode(m.email, code, ReversionDeviceName())
    m.verifyTask.control = "RUN"
end sub

sub onVerifyResponse()
    resp = m.verifyTask.response
    if resp = invalid then
        showStatus("We couldn't reach the server. Please try again.")
        return
    end if

    data = resp.data
    gotToken = (resp.ok = true and data <> invalid and data.token <> invalid and data.token <> "")
    LogBeacon("verifyCode", "SignIn", { ok: resp.ok, status: resp.status, gotToken: gotToken })
    if gotToken then
        SaveAuthToken(data.token)
        ' Confirm the token is actually readable back from the registry post-Flush
        ' (this is the value the next cold launch / deep-link test will see).
        rb = GetAuthToken()
        LogBeacon("tokenSaved", "SignIn", { persisted: (rb <> invalid and rb <> "") })
        m.done = true
        m.top.authed = true
        return
    end if

    showStatus(apiError(resp, "code", "That code is invalid or expired. Request a new one."))
end sub

' ── Pill buttons (built in BRS so the count can vary per phase) ─────────
sub buildButtons(labels as object)
    m.buttonRow.removeChildren(m.buttonRow.getChildren(-1, 0))
    m.btnBgs = []
    m.btnLabels = []

    x = 0
    spacing = 28
    h = 72
    for each lbl in labels
        w = buttonWidth(lbl)
        g = m.buttonRow.createChild("Group")
        g.translation = [x, 0]

        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/btn_rounded.9.png"
        bg.width = w
        bg.height = h

        t = g.createChild("Label")
        t.width = w
        t.height = h
        t.horizAlign = "center"
        t.vertAlign = "center"
        t.text = lbl
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/Montserrat-Bold.ttf"
        f.size = 28
        t.font = f

        m.btnBgs.push(bg)
        m.btnLabels.push(t)
        x = x + w + spacing
    end for

    m.rowWidth = x - spacing
    m.btnSel = 0
    styleButtons()
    layoutBelowKeyboard()
end sub

function buttonWidth(label as string) as integer
    w = 90 + Len(label) * 17
    if w < 220 then w = 220
    return w
end function

' Buttons only show the gold "focused" fill when the button row actually owns
' focus. While the keyboard is focused every button stays neutral, so moving
' focus down to a button is clearly visible (cert focus-clarity + the primary
' button no longer looks permanently selected).
sub styleButtons()
    inButtons = (m.zone = "buttons")
    for i = 0 to m.btnBgs.Count() - 1
        if inButtons and i = m.btnSel then
            m.btnBgs[i].blendColor = "0xC9A84CFF"
            m.btnLabels[i].color = "0x0F1923FF"
        else
            m.btnBgs[i].blendColor = "0x23324AFF"
            m.btnLabels[i].color = "0xFFFFFFFF"
        end if
    end for
end sub

' ── Layout (after the keyboard is realized) ────────────────────────────
sub onLayout()
    r = m.keyboard.boundingRect()
    if r <> invalid and r.width > 0 then
        x = (1920 - r.width) / 2
        if x < 0 then x = 0
        m.keyboard.translation = [x, kbTop()]
        m.kbBottomY = kbTop() + r.height
    end if
    layoutBelowKeyboard()
end sub

sub layoutBelowKeyboard()
    btnY = m.kbBottomY + 36
    bx = (1920 - m.rowWidth) / 2
    if bx < 0 then bx = 0
    m.buttonRow.translation = [bx, btnY]
    m.status.translation = [360, btnY + 96]
end sub

' ── Focus / key routing ────────────────────────────────────────────────
sub enterKeyboard()
    m.zone = "keyboard"
    m.keyboard.setFocus(true)
    styleButtons()   ' clear any gold button fill while the keyboard is focused
end sub

sub enterButtons()
    if m.btnBgs.Count() = 0 then return
    m.zone = "buttons"
    ' Focus the button row (a sibling Group). setFocus on it pulls focus off the
    ' keyboard; unhandled keys still bubble up to this component's onKeyEvent —
    ' setFocus on m.top would be a no-op while the keyboard descendant has focus.
    m.buttonRow.setFocus(true)
    styleButtons()   ' now show the gold focused fill on the selected button
end sub

' ── Exit dialog ────────────────────────────────────────────────────────
sub showExit()
    m.exitSel = 0
    styleExit()
    m.exitDialog.visible = true
    m.exitDialog.setFocus(true)
end sub

sub hideExit()
    m.exitDialog.visible = false
    enterKeyboard()
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

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.exitDialog.visible then
        if key = "left" or key = "right" then
            if m.exitSel = 0 then m.exitSel = 1 else m.exitSel = 0
            styleExit()
            return true
        end if
        if key = "back" then hideExit() : return true
        if key = "OK" then
            if m.exitSel = 0 then hideExit() else m.top.exitApp = true
            return true
        end if
        return false
    end if

    if m.zone = "keyboard" then
        if key = "back" then
            if m.phase = "code" then
                switchToEmail()
            else
                showExit()
            end if
            return true
        end if
        ' The focused DynamicKeyboard handles d-pad nav internally and only lets
        ' a directional key bubble up at its edge — DOWN bubbles at the bottom
        ' row, dropping into the visible button row below.
        if key = "down" then
            enterButtons()
            return true
        end if
        return false
    end if

    ' buttons zone
    if key = "back" then enterKeyboard() : return true
    if key = "up" then enterKeyboard() : return true
    if key = "left" then
        if m.btnSel > 0 then
            m.btnSel = m.btnSel - 1
            styleButtons()
        end if
        return true
    end if
    if key = "right" then
        if m.btnSel < m.btnBgs.Count() - 1 then
            m.btnSel = m.btnSel + 1
            styleButtons()
        end if
        return true
    end if
    if key = "OK" then activateButton() : return true
    return false
end function

' ── Status helpers ─────────────────────────────────────────────────────
sub showStatus(msg as string)
    m.status.color = "0xFF8A8AFF"
    m.status.text = msg
end sub

sub showStatusInfo(msg as string)
    m.status.color = "0x8C9EB0FF"
    m.status.text = msg
end sub

' Pull a Laravel validation message ({ message, errors: { field: [..] } }).
function apiError(resp as object, field as string, fallback as string) as string
    if resp <> invalid and resp.data <> invalid then
        d = resp.data
        if d.errors <> invalid and d.errors[field] <> invalid then
            arr = d.errors[field]
            if GetInterface(arr, "ifArray") <> invalid and arr.Count() > 0 then return arr[0]
        end if
        if d.message <> invalid and d.message <> "" then return d.message
    end if
    return fallback
end function

function lcaseTrim(s as dynamic) as string
    if s = invalid then return ""
    return s.Trim()
end function

function looksLikeEmail(s as string) as boolean
    if s = invalid then return false
    at = Instr(1, s, "@")
    if at < 2 then return false
    dot = Instr(at, s, ".")
    if dot <= at + 1 then return false
    if dot >= Len(s) then return false
    return true
end function
