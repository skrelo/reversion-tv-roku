' Pairing / device-auth flow. TV_APP_SPEC §5.

sub init()
    m.codeLabel = m.top.findNode("code")
    m.countdownLabel = m.top.findNode("countdown")
    m.qr = m.top.findNode("qr")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorMsg = m.top.findNode("errorMsg")
    m.retryBtn = m.top.findNode("retryBtn")
    m.retryBtn.observeField("buttonSelected", "onRetry")

    m.code = ""
    m.expiresIn = 0
    m.pollInterval = 5

    ' One task to mint codes, one to poll. Keeping them separate avoids a
    ' mint response landing in the poll handler (or vice versa).
    m.requestTask = CreateObject("roSGNode", "ApiTask")
    m.requestTask.observeField("response", "onRequestResponse")
    m.pollTask = CreateObject("roSGNode", "ApiTask")
    m.pollTask.observeField("response", "onPollResponse")

    ' 1 s countdown tick. §5
    m.countdownTimer = CreateObject("roSGNode", "Timer")
    m.countdownTimer.duration = 1
    m.countdownTimer.repeat = true
    m.countdownTimer.observeField("fire", "onCountdownTick")

    ' First poll ~1.5 s after a code is minted, then repeat at poll_interval. §5
    m.firstPollTimer = CreateObject("roSGNode", "Timer")
    m.firstPollTimer.duration = 1.5
    m.firstPollTimer.repeat = false
    m.firstPollTimer.observeField("fire", "onFirstPoll")

    m.pollTimer = CreateObject("roSGNode", "Timer")
    m.pollTimer.repeat = true
    m.pollTimer.observeField("fire", "onPollTick")

    mintCode()
end sub

' ── Mint a fresh pairing code ───────────────────────────────────────────
sub mintCode()
    stopTimers()
    m.errorGroup.visible = false
    m.code = ""
    m.codeLabel.text = "Generating code…"
    m.countdownLabel.text = ""
    m.qr.text = ""
    m.requestTask.request = ApiReq().requestPairingCode(ReversionDeviceName())
    m.requestTask.control = "RUN"
end sub

sub onRequestResponse()
    resp = m.requestTask.response
    if resp <> invalid and resp.ok = true and resp.data.code <> invalid then
        m.code = resp.data.code
        m.expiresIn = toInt(resp.data.expires_in, 600)
        m.pollInterval = toInt(resp.data.poll_interval, 5)
        if m.pollInterval < 2 then m.pollInterval = 2

        m.codeLabel.text = formatCode(m.code)
        m.qr.text = m.code
        updateCountdownLabel()

        m.countdownTimer.control = "start"
        m.firstPollTimer.control = "start"
    else
        showError("We couldn't reach the server to get a pairing code.")
    end if
end sub

' ── Polling ─────────────────────────────────────────────────────────────
sub onFirstPoll()
    pollOnce()
    m.pollTimer.duration = m.pollInterval
    m.pollTimer.control = "start"
end sub

sub onPollTick()
    pollOnce()
end sub

sub pollOnce()
    if m.code = "" then return
    m.pollTask.request = ApiReq().pollPairingCode(m.code)
    m.pollTask.control = "RUN"
end sub

sub onPollResponse()
    resp = m.pollTask.response
    if resp = invalid then return

    status = resp.status
    data = resp.data

    if status = 200 and data <> invalid and data.status = "authorized" and data.token <> invalid then
        ' Authorized: persist token, stop everything, hand off to Home. §5
        SaveAuthToken(data.token)
        stopTimers()
        m.top.paired = true
        return
    end if

    if status = 410 or status = 404 then
        ' Code expired/gone → regenerate. §5
        mintCode()
        return
    end if

    ' 202 pending or any transient (status 0 / 5xx) → keep polling. §5
end sub

' ── Countdown ───────────────────────────────────────────────────────────
sub onCountdownTick()
    m.expiresIn = m.expiresIn - 1
    if m.expiresIn <= 0 then
        ' Expired → auto-regenerate. §5
        mintCode()
        return
    end if
    updateCountdownLabel()
end sub

sub updateCountdownLabel()
    m.countdownLabel.text = "Code expires in " + mmss(m.expiresIn)
end sub

' ── Errors ──────────────────────────────────────────────────────────────
sub showError(msg as string)
    stopTimers()
    m.codeLabel.text = ""
    m.countdownLabel.text = ""
    m.qr.text = ""
    m.errorMsg.text = msg
    m.errorGroup.visible = true
    m.retryBtn.setFocus(true)
end sub

sub onRetry()
    mintCode()
end sub

sub stopTimers()
    m.countdownTimer.control = "stop"
    m.firstPollTimer.control = "stop"
    m.pollTimer.control = "stop"
end sub

' ── Helpers ─────────────────────────────────────────────────────────────
' Group the code in 3s with dashes for readability (§5). If it already has a
' dash, trust the server's grouping.
function formatCode(raw as string) as string
    if raw = invalid or raw = "" then return ""
    if Instr(1, raw, "-") > 0 then return raw
    out = ""
    i = 0
    for each ch in raw.Split("")
        if i > 0 and (i mod 3) = 0 then out = out + "-"
        out = out + ch
        i = i + 1
    end for
    return out
end function

function mmss(totalSeconds as integer) as string
    s = totalSeconds
    if s < 0 then s = 0
    mins = s \ 60
    r = s mod 60
    rr = r.ToStr()
    if r < 10 then rr = "0" + rr
    return mins.ToStr() + ":" + rr
end function

function toInt(v as dynamic, fallback as integer) as integer
    if v = invalid then return fallback
    t = type(v)
    if t = "String" or t = "roString" then return v.ToInt()
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return v
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Int(v)
    return fallback
end function
